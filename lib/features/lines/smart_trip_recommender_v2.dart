import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../../data/models/bus_option.dart';
import '../../data/models/bus_vehicle.dart';
import '../../data/models/transit_stop.dart';
import '../../data/models/trip_destination.dart';
import '../../data/services/adana_api_service.dart';

class RankedTripOption {
  const RankedTripOption({
    required this.line,
    required this.direction,
    required this.startStop,
    required this.endStop,
    required this.walkToStartMeters,
    required this.walkFromEndMeters,
    required this.walkToStartMinutes,
    required this.walkFromEndMinutes,
    required this.busRideMinutes,
    required this.waitMinutes,
    required this.totalMinutes,
    required this.score,
    required this.rank,
    required this.estimatedBoardingTimeLabel,
    this.usesLiveBusData = false,
    this.nearestLiveBusMeters,
    this.isTransfer = false,
    this.transferLine,
    this.transferDirection,
    this.transferStop,
    this.transferWaitMinutes = 0,
  });

  final BusOption line;
  final String direction;
  final TransitStop startStop;
  final TransitStop endStop;
  final double walkToStartMeters;
  final double walkFromEndMeters;
  final double walkToStartMinutes;
  final double walkFromEndMinutes;
  final double busRideMinutes;
  final double waitMinutes;
  final double totalMinutes;
  final int score;
  final int rank;
  final String estimatedBoardingTimeLabel;
  final bool usesLiveBusData;
  final double? nearestLiveBusMeters;

  final bool isTransfer;
  final BusOption? transferLine;
  final String? transferDirection;
  final TransitStop? transferStop;
  final double transferWaitMinutes;
}

class _StopWithScore {
  _StopWithScore(this.stop, this.distance, this.frequencyScore);
  final TransitStop stop;
  final double distance;
  final int frequencyScore;
}

class _WaitEstimate {
  const _WaitEstimate({
    required this.minutes,
    required this.usesLiveData,
    this.nearestLiveBusMeters,
  });

  final double minutes;
  final bool usesLiveData;
  final double? nearestLiveBusMeters;
}

class SmartTripRecommenderV2 {
  static const double _walkingMetersPerMinute = 78;
  static const double _busApproachMetersPerMinute = 260;
  static const double _busSpeedMetersPerMinute = 450;
  static const double _maxWalkDistanceMeters = 1200;
  static const int _maxStartStopsToConsider = 5;
  static const int _maxEndStopsToConsider = 5;
  static const int _maxTotalCombinations = 5000;

  static Future<List<RankedTripOption>> recommendTrips({
    required Position origin,
    required TripDestination destination,
    required List<TransitStop> stops,
    required List<BusOption> lines,
    required List<BusVehicle> liveBuses,
    required AdanaApiService apiService,
    int resultLimit = 3,
  }) async {
    if (stops.isEmpty) {
      throw StateError('Durak verisi bulunamadi.');
    }

    final startStops = _findNearbyStops(
      Position(
        latitude: origin.latitude,
        longitude: origin.longitude,
        timestamp: DateTime.now(),
        accuracy: origin.accuracy,
        altitude: origin.altitude,
        altitudeAccuracy: origin.altitudeAccuracy,
        heading: origin.heading,
        headingAccuracy: origin.headingAccuracy,
        speed: origin.speed,
        speedAccuracy: origin.speedAccuracy,
      ),
      stops,
      _maxWalkDistanceMeters,
      lines,
      liveBuses,
      maxResults: _maxStartStopsToConsider,
    );

    final endStops = _findNearbyStops(
      Position(
        latitude: destination.latitude,
        longitude: destination.longitude,
        timestamp: DateTime.now(),
        accuracy: 50,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      ),
      stops,
      _maxWalkDistanceMeters,
      lines,
      liveBuses,
      maxResults: _maxEndStopsToConsider,
    );

    if (startStops.isEmpty) {
      throw StateError('Baslangic noktasinda durak bulunamadi.');
    }
    if (endStops.isEmpty) {
      throw StateError('Hedef noktasinda durak bulunamadi.');
    }

    final lineByCode = <String, BusOption>{
      for (final line in lines) line.displayRouteCode: line,
    };

    final stopsByRoute = <String, List<TransitStop>>{};
    for (final stop in stops) {
      for (final routeCode in stop.routes) {
        stopsByRoute.putIfAbsent(routeCode, () => <TransitStop>[]).add(stop);
      }
    }

    final routeOrderCache = <String, List<String>>{};
    final candidateRouteCodes = <String>{
      ...startStops.expand((stop) => stop.routes),
      ...endStops.expand((stop) => stop.routes),
    };

    for (final routeCode in candidateRouteCodes) {
      for (final direction in const ['0', '1']) {
        final cacheKey = '$routeCode|$direction';
        try {
          final response = await apiService.fetchKentkartPathInfo(
            displayRouteCode: routeCode,
            direction: direction,
          );
          final payload = response is Map<String, dynamic>
              ? response
              : <String, dynamic>{'data': response};
          routeOrderCache[cacheKey] = _extractOrderedStopIds(payload);
        } catch (_) {
          routeOrderCache[cacheKey] = const <String>[];
        }
      }
    }

    final options = <RankedTripOption>[];
    final now = DateTime.now();
    final nowMinutesOfDay = now.hour * 60 + now.minute;
    final todayDayType = _todayDayType(now);
    final stopsById = <String, TransitStop>{for (final stop in stops) stop.stopId: stop};

    final nextDepartureCache = await _buildNextDepartureCache(
      candidateRouteCodes: candidateRouteCodes,
      liveBuses: liveBuses,
      apiService: apiService,
      nowMinutesOfDay: nowMinutesOfDay,
      todayDayType: todayDayType,
    );

    for (final startStop in startStops) {
      for (final endStop in endStops) {
        if (startStop.stopId == endStop.stopId) {
          continue;
        }

        final walkToStartMeters = _distanceMeters(
          origin.latitude,
          origin.longitude,
          startStop.latitude,
          startStop.longitude,
        );
        final walkFromEndMeters = _distanceMeters(
          endStop.latitude,
          endStop.longitude,
          destination.latitude,
          destination.longitude,
        );
        final walkToStartMinutes = walkToStartMeters / _walkingMetersPerMinute;
        final walkFromEndMinutes = walkFromEndMeters / _walkingMetersPerMinute;

        final commonRoutes = <String>{...startStop.routes}
          ..retainAll(endStop.routes);

        for (final routeCode in commonRoutes) {
          final line = lineByCode[routeCode];
          if (line == null) {
            continue;
          }

          final directions = line.directions.isEmpty
              ? const <String>['0', '1']
              : line.directions;

          for (final direction in directions) {
            final routeOrder = routeOrderCache['$routeCode|$direction'] ??
                const <String>[];
            if (!_isOrderedPair(
              startStop.stopId,
              endStop.stopId,
              routeOrder,
            )) {
              continue;
            }

            final rideDistanceMeters = _distanceMeters(
              startStop.latitude,
              startStop.longitude,
              endStop.latitude,
              endStop.longitude,
            );
            final busRideMinutes =
                rideDistanceMeters / _busSpeedMetersPerMinute;

            final liveWaitEstimate = _estimateLiveWaitForDirection(
              userPosition: origin,
              routeCode: routeCode,
              direction: direction,
              liveBuses: liveBuses,
            );
            final leadToStartMinutes = _estimateLeadMinutesToStop(
              stopId: startStop.stopId,
              routeOrder: routeOrder,
              stopsById: stopsById,
            );
            final scheduleWaitMinutes = _estimateScheduleWaitMinutes(
              nowMinutesOfDay: nowMinutesOfDay,
              terminalToBoardMinutes: leadToStartMinutes,
              nextDepartureMinutesOfDay: nextDepartureCache['$routeCode|$direction'],
            );

            var waitMinutes = liveWaitEstimate.minutes;
            var usesLiveData = liveWaitEstimate.usesLiveData;
            var nearestLiveBusMeters = liveWaitEstimate.nearestLiveBusMeters;
            if (scheduleWaitMinutes != null && scheduleWaitMinutes < waitMinutes) {
              waitMinutes = scheduleWaitMinutes;
              usesLiveData = false;
              nearestLiveBusMeters = null;
            }

            final estimatedBoardingMinutesOfDay =
                (nowMinutesOfDay + walkToStartMinutes + waitMinutes).round() %
                    (24 * 60);

            final totalMinutes = walkToStartMinutes +
                waitMinutes +
                busRideMinutes +
                walkFromEndMinutes;

            final score = _calculateScore(
              walkToStart: walkToStartMinutes,
              wait: waitMinutes,
              busRide: busRideMinutes,
              walkFromEnd: walkFromEndMinutes,
            );

            options.add(
              RankedTripOption(
                line: line,
                direction: direction,
                startStop: startStop,
                endStop: endStop,
                walkToStartMeters: walkToStartMeters,
                walkFromEndMeters: walkFromEndMeters,
                walkToStartMinutes: walkToStartMinutes,
                walkFromEndMinutes: walkFromEndMinutes,
                busRideMinutes: busRideMinutes,
                waitMinutes: waitMinutes,
                totalMinutes: totalMinutes,
                score: score,
                rank: 0,
                estimatedBoardingTimeLabel:
                    _minutesToTimeLabel(estimatedBoardingMinutesOfDay),
                usesLiveBusData: usesLiveData,
                nearestLiveBusMeters: nearestLiveBusMeters,
              ),
            );
          }
        }
      }
    }

    if (options.isEmpty || options.length < resultLimit) {
      _addTransferOptions(
        startStops: startStops,
        endStops: endStops,
        origin: origin,
        destination: destination,
        lines: lines,
        liveBuses: liveBuses,
        options: options,
        lineByCode: lineByCode,
        stopsByRoute: stopsByRoute,
        routeOrderCache: routeOrderCache,
        stopsById: stopsById,
        nextDepartureCache: nextDepartureCache,
        nowMinutesOfDay: nowMinutesOfDay,
      );
    }

    options.sort((a, b) {
      final total = a.totalMinutes.compareTo(b.totalMinutes);
      if (total != 0) {
        return total;
      }
      return b.score.compareTo(a.score);
    });

    for (var i = 0; i < options.length && i < resultLimit; i++) {
      options[i] = RankedTripOption(
        line: options[i].line,
        direction: options[i].direction,
        startStop: options[i].startStop,
        endStop: options[i].endStop,
        walkToStartMeters: options[i].walkToStartMeters,
        walkFromEndMeters: options[i].walkFromEndMeters,
        walkToStartMinutes: options[i].walkToStartMinutes,
        walkFromEndMinutes: options[i].walkFromEndMinutes,
        busRideMinutes: options[i].busRideMinutes,
        waitMinutes: options[i].waitMinutes,
        totalMinutes: options[i].totalMinutes,
        score: options[i].score,
        rank: i + 1,
        estimatedBoardingTimeLabel: options[i].estimatedBoardingTimeLabel,
        usesLiveBusData: options[i].usesLiveBusData,
        nearestLiveBusMeters: options[i].nearestLiveBusMeters,
        isTransfer: options[i].isTransfer,
        transferLine: options[i].transferLine,
        transferDirection: options[i].transferDirection,
        transferStop: options[i].transferStop,
        transferWaitMinutes: options[i].transferWaitMinutes,
      );
    }

    return options.take(resultLimit).toList(growable: false);
  }

  static void _addTransferOptions({
    required List<TransitStop> startStops,
    required List<TransitStop> endStops,
    required Position origin,
    required TripDestination destination,
    required List<BusOption> lines,
    required List<BusVehicle> liveBuses,
    required List<RankedTripOption> options,
    required Map<String, BusOption> lineByCode,
    required Map<String, List<TransitStop>> stopsByRoute,
    required Map<String, List<String>> routeOrderCache,
    required Map<String, TransitStop> stopsById,
    required Map<String, int?> nextDepartureCache,
    required int nowMinutesOfDay,
  }) {
    var totalIterations = 0;

    for (final startStop in startStops) {
      for (final endStop in endStops) {
        if (options.length >= 12) {
          return;
        }

        if (startStop.stopId == endStop.stopId) {
          continue;
        }

        final commonRoutes = <String>{...startStop.routes}
          ..retainAll(endStop.routes);
        if (commonRoutes.isNotEmpty) {
          continue;
        }

        final firstLineRoutes = startStop.routes.toSet();
        final lastLineRoutes = endStop.routes.toSet();

        for (final firstLineCode in firstLineRoutes) {
          final firstLine = lineByCode[firstLineCode];
          if (firstLine == null) continue;

          final firstLineStops = stopsByRoute[firstLineCode] ?? const <TransitStop>[];
          if (firstLineStops.isEmpty) {
            continue;
          }

          for (final firstDirection in (firstLine.directions.isEmpty
              ? const <String>['0', '1']
              : firstLine.directions)) {
            for (final lastLineCode in lastLineRoutes) {
              if (firstLineCode == lastLineCode) continue;

              final lastLine = lineByCode[lastLineCode];
              if (lastLine == null) continue;

              final lastLineStops = stopsByRoute[lastLineCode] ?? const <TransitStop>[];
              if (lastLineStops.isEmpty) {
                continue;
              }

              final lastLineStopIds = <String>{
                for (final stop in lastLineStops) stop.stopId,
              };

              for (final lastDirection in (lastLine.directions.isEmpty
                  ? const <String>['0', '1']
                  : lastLine.directions)) {
                final validIntermediates = <TransitStop>[];
                for (final intermediateStop in firstLineStops) {
                  if (!lastLineStopIds.contains(intermediateStop.stopId)) {
                    continue;
                  }

                  final firstRouteOrder =
                      routeOrderCache['$firstLineCode|$firstDirection'] ??
                          const <String>[];
                  if (!_isOrderedPair(
                    startStop.stopId,
                    intermediateStop.stopId,
                    firstRouteOrder,
                  )) {
                    continue;
                  }

                  final secondRouteOrder =
                      routeOrderCache['$lastLineCode|$lastDirection'] ??
                          const <String>[];
                  if (!_isOrderedPair(
                    intermediateStop.stopId,
                    endStop.stopId,
                    secondRouteOrder,
                  )) {
                    continue;
                  }

                  validIntermediates.add(intermediateStop);
                }

                if (validIntermediates.isEmpty) continue;

                validIntermediates.sort((a, b) {
                  final aKmToEndStop = _distanceMeters(
                    a.latitude,
                    a.longitude,
                    endStop.latitude,
                    endStop.longitude,
                  ) / 1000;
                  final bKmToEndStop = _distanceMeters(
                    b.latitude,
                    b.longitude,
                    endStop.latitude,
                    endStop.longitude,
                  ) / 1000;
                  return aKmToEndStop.compareTo(bKmToEndStop);
                });

                final intermediatesSubset =
                    validIntermediates.take(3).toList(growable: false);

                for (final intermediateStop in intermediatesSubset) {
                  totalIterations++;
                  if (totalIterations > _maxTotalCombinations) {
                    return;
                  }

                  final walkToStartMeters = _distanceMeters(
                    origin.latitude,
                    origin.longitude,
                    startStop.latitude,
                    startStop.longitude,
                  );
                  final walkFromEndMeters = _distanceMeters(
                    endStop.latitude,
                    endStop.longitude,
                    destination.latitude,
                    destination.longitude,
                  );
                  final walkToStartMinutes =
                      walkToStartMeters / _walkingMetersPerMinute;
                  final walkFromEndMinutes =
                      walkFromEndMeters / _walkingMetersPerMinute;
                  const walkBetweenStopsMinutes = 0.0;

                  final firstRideMeters = _distanceMeters(
                    startStop.latitude,
                    startStop.longitude,
                    intermediateStop.latitude,
                    intermediateStop.longitude,
                  );
                  final firstRideMinutes =
                      firstRideMeters / _busSpeedMetersPerMinute;

                  final secondRideMeters = _distanceMeters(
                    intermediateStop.latitude,
                    intermediateStop.longitude,
                    endStop.latitude,
                    endStop.longitude,
                  );
                  final secondRideMinutes =
                      secondRideMeters / _busSpeedMetersPerMinute;

                  final wait1LiveEstimate = _estimateLiveWaitForDirection(
                    userPosition: origin,
                    routeCode: firstLineCode,
                    direction: firstDirection,
                    liveBuses: liveBuses,
                  );
                  final wait2LiveEstimate = _estimateLiveWaitForDirection(
                    userPosition: Position(
                      latitude: intermediateStop.latitude,
                      longitude: intermediateStop.longitude,
                      timestamp: DateTime.now(),
                      accuracy: 0,
                      altitude: 0,
                      altitudeAccuracy: 0,
                      heading: 0,
                      headingAccuracy: 0,
                      speed: 0,
                      speedAccuracy: 0,
                    ),
                    routeCode: lastLineCode,
                    direction: lastDirection,
                    liveBuses: liveBuses,
                  );
                  final firstOrder =
                      routeOrderCache['$firstLineCode|$firstDirection'] ??
                          const <String>[];
                  final secondOrder =
                      routeOrderCache['$lastLineCode|$lastDirection'] ??
                          const <String>[];

                  final wait1Schedule = _estimateScheduleWaitMinutes(
                    nowMinutesOfDay: nowMinutesOfDay,
                    terminalToBoardMinutes: _estimateLeadMinutesToStop(
                      stopId: startStop.stopId,
                      routeOrder: firstOrder,
                      stopsById: stopsById,
                    ),
                    nextDepartureMinutesOfDay:
                        nextDepartureCache['$firstLineCode|$firstDirection'],
                  );
                  final wait2Schedule = _estimateScheduleWaitMinutes(
                    nowMinutesOfDay: nowMinutesOfDay,
                    terminalToBoardMinutes: _estimateLeadMinutesToStop(
                      stopId: intermediateStop.stopId,
                      routeOrder: secondOrder,
                      stopsById: stopsById,
                    ),
                    nextDepartureMinutesOfDay:
                        nextDepartureCache['$lastLineCode|$lastDirection'],
                  );

                  var wait1 = wait1LiveEstimate.minutes;
                  var usesLiveData = wait1LiveEstimate.usesLiveData;
                  var nearestLiveBusMeters = wait1LiveEstimate.nearestLiveBusMeters;
                  if (wait1Schedule != null && wait1Schedule < wait1) {
                    wait1 = wait1Schedule;
                    usesLiveData = false;
                    nearestLiveBusMeters = null;
                  }

                  var wait2 = wait2LiveEstimate.minutes;
                  if (wait2Schedule != null && wait2Schedule < wait2) {
                    wait2 = wait2Schedule;
                  }

                  final estimatedBoardingMinutesOfDay =
                      (nowMinutesOfDay + walkToStartMinutes + wait1).round() %
                          (24 * 60);

                  final totalMinutes = walkToStartMinutes +
                      wait1 +
                      firstRideMinutes +
                      walkBetweenStopsMinutes +
                      wait2 +
                      secondRideMinutes +
                      walkFromEndMinutes;

                  final baseScore = _calculateScore(
                    walkToStart: walkToStartMinutes,
                    wait: wait1 + wait2,
                    busRide: firstRideMinutes + secondRideMinutes,
                    walkFromEnd: walkFromEndMinutes,
                  );
                  const transferPenalty = 15;
                  final score = (baseScore - transferPenalty).clamp(0, 100);

                  options.add(
                    RankedTripOption(
                      line: firstLine,
                      direction: firstDirection,
                      startStop: startStop,
                      endStop: endStop,
                      walkToStartMeters: walkToStartMeters,
                      walkFromEndMeters: walkFromEndMeters,
                      walkToStartMinutes: walkToStartMinutes,
                      walkFromEndMinutes: walkFromEndMinutes,
                      busRideMinutes: firstRideMinutes + secondRideMinutes,
                      waitMinutes: wait1 + wait2,
                      totalMinutes: totalMinutes,
                      score: score,
                      rank: 0,
                      estimatedBoardingTimeLabel:
                          _minutesToTimeLabel(estimatedBoardingMinutesOfDay),
                      usesLiveBusData: usesLiveData,
                      nearestLiveBusMeters: nearestLiveBusMeters,
                      isTransfer: true,
                      transferLine: lastLine,
                      transferDirection: lastDirection,
                      transferStop: intermediateStop,
                      transferWaitMinutes: wait2,
                    ),
                  );

                  if (options.length >= 12) {
                    return;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  static List<TransitStop> _findNearbyStops(
    Position center,
    List<TransitStop> stops,
    double maxDistanceMeters,
    List<BusOption> lines,
    List<BusVehicle> liveBuses, {
    required int maxResults,
  }) {
    final stopFrequencyScore = <String, int>{};
    for (final stop in stops) {
      var frequencyScore = 0;
      for (final routeCode in stop.routes) {
        final busCount = liveBuses
            .where((bus) => bus.displayRouteCode == routeCode && bus.hasLocation)
            .length;
        frequencyScore += (busCount > 0 ? 5 + busCount : 0);
      }
      stopFrequencyScore[stop.stopId] = frequencyScore;
    }

    final nearby = <_StopWithScore>[];
    for (final stop in stops) {
      final distance = _distanceMeters(
        center.latitude,
        center.longitude,
        stop.latitude,
        stop.longitude,
      );
      if (distance <= maxDistanceMeters) {
        final frequencyScore = stopFrequencyScore[stop.stopId] ?? 0;
        nearby.add(_StopWithScore(stop, distance, frequencyScore));
      }
    }

    nearby.sort((a, b) {
      final scoreA = (a.distance / 80) - a.frequencyScore;
      final scoreB = (b.distance / 80) - b.frequencyScore;
      return scoreA.compareTo(scoreB);
    });

    return nearby.take(maxResults).map((x) => x.stop).toList(growable: false);
  }

  static List<String> _extractOrderedStopIds(Map<String, dynamic> payload) {
    final pathList = payload['pathList'];
    if (pathList is! List) {
      return const <String>[];
    }

    final orderedStopIds = <String>[];
    for (final path in pathList) {
      if (path is! Map<String, dynamic>) {
        continue;
      }
      final rawStops = path['busStopList'];
      if (rawStops is! List) {
        continue;
      }
      for (final rawStop in rawStops) {
        if (rawStop is! Map<String, dynamic>) {
          continue;
        }
        final stopId = _readString(rawStop, const ['stopId', 'StopId', 'id']);
        if (stopId.isEmpty) {
          continue;
        }
        if (orderedStopIds.isEmpty || orderedStopIds.last != stopId) {
          orderedStopIds.add(stopId);
        }
      }
      if (orderedStopIds.isNotEmpty) {
        break;
      }
    }
    return orderedStopIds;
  }

  static bool _isOrderedPair(
    String startStopId,
    String endStopId,
    List<String> orderedStopIds,
  ) {
    if (orderedStopIds.isEmpty) {
      return false;
    }

    final startIndex = orderedStopIds.indexOf(startStopId);
    final endIndex = orderedStopIds.indexOf(endStopId);
    return startIndex >= 0 && endIndex >= 0 && startIndex < endIndex;
  }

  static String _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  static _WaitEstimate _estimateLiveWaitForDirection({
    required Position userPosition,
    required String routeCode,
    required String direction,
    required List<BusVehicle> liveBuses,
  }) {
    final candidates = liveBuses
        .where(
          (bus) =>
              bus.displayRouteCode == routeCode &&
              bus.direction == direction &&
              bus.hasLocation,
        )
        .toList(growable: false);

    if (candidates.isEmpty) {
      return const _WaitEstimate(minutes: 9.0, usesLiveData: false);
    }

    var closestBusDistance = double.infinity;
    for (final bus in candidates) {
      final distance = _distanceMeters(
        userPosition.latitude,
        userPosition.longitude,
        bus.latitude!,
        bus.longitude!,
      );
      if (distance < closestBusDistance) {
        closestBusDistance = distance;
      }
    }

    final estimated = closestBusDistance / _busApproachMetersPerMinute;
    return _WaitEstimate(
      minutes: estimated.clamp(2.0, 20.0),
      usesLiveData: true,
      nearestLiveBusMeters: closestBusDistance,
    );
  }

  static int _calculateScore({
    required double walkToStart,
    required double wait,
    required double busRide,
    required double walkFromEnd,
  }) {
    final total = walkToStart + wait + busRide + walkFromEnd;
    final baseScore = (100 - (total * 2.5)).round();

    var penalty = 0;
    if (walkToStart > 10) penalty += 5;
    if (walkFromEnd > 10) penalty += 5;
    if (wait > 12) penalty += 3;

    return (baseScore - penalty).clamp(5, 99);
  }

  static double _estimateLeadMinutesToStop({
    required String stopId,
    required List<String> routeOrder,
    required Map<String, TransitStop> stopsById,
  }) {
    if (routeOrder.length < 2) {
      return 0;
    }

    final targetIndex = routeOrder.indexOf(stopId);
    if (targetIndex <= 0) {
      return 0;
    }

    var meters = 0.0;
    for (var i = 1; i <= targetIndex; i++) {
      final prev = stopsById[routeOrder[i - 1]];
      final next = stopsById[routeOrder[i]];
      if (prev == null || next == null) {
        continue;
      }
      meters += _distanceMeters(
        prev.latitude,
        prev.longitude,
        next.latitude,
        next.longitude,
      );
    }
    return meters / _busSpeedMetersPerMinute;
  }

  static double? _estimateScheduleWaitMinutes({
    required int nowMinutesOfDay,
    required double terminalToBoardMinutes,
    required int? nextDepartureMinutesOfDay,
  }) {
    if (nextDepartureMinutesOfDay == null) {
      return null;
    }

    final arrivalAtStop =
        (nextDepartureMinutesOfDay + terminalToBoardMinutes).round();
    var wait = arrivalAtStop - nowMinutesOfDay;
    if (wait < 0) {
      wait += 24 * 60;
    }

    return wait.clamp(0, 240).toDouble();
  }

  static Future<Map<String, int?>> _buildNextDepartureCache({
    required Set<String> candidateRouteCodes,
    required List<BusVehicle> liveBuses,
    required AdanaApiService apiService,
    required int nowMinutesOfDay,
    required int todayDayType,
  }) async {
    final result = <String, int?>{};

    for (final routeCode in candidateRouteCodes) {
      for (final direction in const ['0', '1']) {
        final key = '$routeCode|$direction';
        result[key] = await _resolveNextDepartureForRouteDirection(
          routeCode: routeCode,
          direction: direction,
          liveBuses: liveBuses,
          apiService: apiService,
          nowMinutesOfDay: nowMinutesOfDay,
          todayDayType: todayDayType,
        );
      }
    }

    return result;
  }

  static Future<int?> _resolveNextDepartureForRouteDirection({
    required String routeCode,
    required String direction,
    required List<BusVehicle> liveBuses,
    required AdanaApiService apiService,
    required int nowMinutesOfDay,
    required int todayDayType,
  }) async {
    final candidateBusIds = <String>[];
    final seen = <String>{};
    for (final bus in liveBuses) {
      final id = bus.id.trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      if (bus.displayRouteCode == routeCode && bus.direction == direction) {
        candidateBusIds.add(id);
      }
    }

    if (candidateBusIds.isEmpty) {
      return null;
    }

    int? best;
    for (final busId in candidateBusIds.take(6)) {
      try {
        final dynamic raw = await apiService.fetchStopBusTimeByBusId(busId);
        final payload = raw is Map<String, dynamic>
            ? raw
            : <String, dynamic>{'data': raw};
        final times = _extractTimesForDayType(payload, todayDayType);

        for (final time in times) {
          final minutes = _timeStringToMinutes(time);
          if (minutes == null) {
            continue;
          }
          var candidate = minutes;
          if (candidate < nowMinutesOfDay) {
            candidate += 24 * 60;
          }
          if (best == null || candidate < best) {
            best = candidate;
          }
        }
      } catch (_) {
        continue;
      }
    }

    if (best == null) {
      return null;
    }
    return best % (24 * 60);
  }

  static List<String> _extractTimesForDayType(Map<String, dynamic> payload, int dayType) {
    final found = <String>{};
    final timePattern = RegExp(r'\b(?:[01]?\d|2[0-3]):[0-5]\d\b');
    final dateLikePattern = RegExp(r'\b\d{4}[-/.]\d{1,2}[-/.]\d{1,2}\b');

    bool isScheduleKey(String? key) {
      final k = (key ?? '').toLowerCase().replaceAll('_', '');
      return k.contains('saat') ||
          k.contains('time') ||
          k.contains('hour') ||
          k.contains('kalkis') ||
          k.contains('departure') ||
          k.contains('sefer');
    }

    bool isNoiseKey(String? key) {
      final k = (key ?? '').toLowerCase().replaceAll('_', '');
      return k.contains('update') ||
          k.contains('timestamp') ||
          k.contains('created') ||
          k.contains('modified') ||
          k.contains('date') ||
          k.contains('guncel') ||
          k.contains('refresh') ||
          k.contains('last');
    }

    int? parseDayTypeFromMap(Map map, int? inherited) {
      var resolved = inherited;
      for (final entry in map.entries) {
        final key = entry.key.toString().toLowerCase().replaceAll('_', '');
        if (key == 'daytype' || key == 'day') {
          final parsed = int.tryParse(entry.value.toString().trim());
          if (parsed != null) {
            resolved = parsed;
            break;
          }
        }
      }
      return resolved;
    }

    void walk(dynamic node, int? inheritedDayType, String? keyHint) {
      if (node is Map) {
        final resolvedDayType = parseDayTypeFromMap(node, inheritedDayType);
        for (final entry in node.entries) {
          walk(entry.value, resolvedDayType, entry.key.toString());
        }
        return;
      }

      if (node is List) {
        for (final item in node) {
          walk(item, inheritedDayType, keyHint);
        }
        return;
      }

      if (node == null || inheritedDayType != dayType) {
        return;
      }

      final text = node.toString();
      if (text.trim().isEmpty ||
          dateLikePattern.hasMatch(text) ||
          isNoiseKey(keyHint) ||
          !timePattern.hasMatch(text)) {
        return;
      }

      if (!isScheduleKey(keyHint) && text.length > 64) {
        return;
      }

      for (final match in timePattern.allMatches(text)) {
        final value = match.group(0);
        if (value != null) {
          found.add(value);
        }
      }
    }

    walk(payload, null, null);
    final sorted = found.toList(growable: false);
    sorted.sort((a, b) => (_timeStringToMinutes(a) ?? 0).compareTo(_timeStringToMinutes(b) ?? 0));
    return sorted;
  }

  static int _todayDayType(DateTime now) {
    if (now.weekday == DateTime.saturday) {
      return 6;
    }
    if (now.weekday == DateTime.sunday) {
      return 7;
    }
    return 0;
  }

  static int? _timeStringToMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return (hour * 60) + minute;
  }

  static String _minutesToTimeLabel(int minutesOfDay) {
    final normalized = ((minutesOfDay % (24 * 60)) + (24 * 60)) % (24 * 60);
    final hour = (normalized ~/ 60).toString().padLeft(2, '0');
    final minute = (normalized % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _toRadians(double value) => value * (math.pi / 180.0);
}
