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

            final waitMinutes = _estimateWaitForDirection(
              userPosition: origin,
              routeCode: routeCode,
              direction: direction,
              liveBuses: liveBuses,
            );

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
      );
    }

    options.sort((a, b) => b.score.compareTo(a.score));

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

                  final wait1 = _estimateWaitForDirection(
                    userPosition: origin,
                    routeCode: firstLineCode,
                    direction: firstDirection,
                    liveBuses: liveBuses,
                  );
                  final wait2 = _estimateWaitForDirection(
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

  static double _estimateWaitForDirection({
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
      return 9.0;
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
    return estimated.clamp(2.0, 20.0);
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
