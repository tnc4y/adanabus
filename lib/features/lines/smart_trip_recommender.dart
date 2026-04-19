import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../../data/models/bus_option.dart';
import '../../data/models/bus_vehicle.dart';
import '../../data/models/transit_stop.dart';

class SmartTripRecommendation {
  const SmartTripRecommendation({
    required this.nearestStop,
    required this.recommendedLine,
    required this.suggestedDirection,
    required this.walkDistanceMeters,
    required this.walkMinutes,
    required this.waitMinutes,
    required this.totalMinutes,
    required this.score,
  });

  final TransitStop nearestStop;
  final BusOption recommendedLine;
  final String suggestedDirection;
  final double walkDistanceMeters;
  final double walkMinutes;
  final double waitMinutes;
  final double totalMinutes;
  final int score;
}

class SmartTripRecommender {
  static const double _walkingMetersPerMinute = 78;
  static const double _busApproachMetersPerMinute = 260;

  static SmartTripRecommendation recommend({
    required Position userPosition,
    required List<TransitStop> stops,
    required List<BusOption> lines,
    required List<BusVehicle> liveBuses,
  }) {
    if (stops.isEmpty) {
      throw StateError('Durak verisi bulunamadi.');
    }

    final nearestStop = _findNearestStop(userPosition, stops);
    final walkDistanceMeters = _distanceMeters(
      userPosition.latitude,
      userPosition.longitude,
      nearestStop.latitude,
      nearestStop.longitude,
    );
    final walkMinutes = walkDistanceMeters / _walkingMetersPerMinute;

    final lineByCode = <String, BusOption>{
      for (final line in lines) line.displayRouteCode: line,
    };

    final candidates = nearestStop.routes
        .map((routeCode) => lineByCode[routeCode])
        .whereType<BusOption>()
        .toList(growable: false);

    final fallback = lines.isNotEmpty ? lines.first : null;
    final recommendedLine = candidates.isNotEmpty ? candidates.first : fallback;

    if (recommendedLine == null) {
      throw StateError('Hat verisi bulunamadi.');
    }

    var bestDirection = '0';
    var bestWaitMinutes = 9.0;
    var bestTotalMinutes = walkMinutes + bestWaitMinutes;

    final directions = recommendedLine.directions.isEmpty
        ? const <String>['0', '1']
        : recommendedLine.directions;

    for (final direction in directions) {
      final waitMinutes = _estimateWaitForDirection(
        userPosition: userPosition,
        routeCode: recommendedLine.displayRouteCode,
        direction: direction,
        liveBuses: liveBuses,
      );
      final totalMinutes = walkMinutes + waitMinutes;
      if (totalMinutes < bestTotalMinutes) {
        bestTotalMinutes = totalMinutes;
        bestWaitMinutes = waitMinutes;
        bestDirection = direction;
      }
    }

    final score = (100 - (bestTotalMinutes * 4)).round().clamp(5, 99);

    return SmartTripRecommendation(
      nearestStop: nearestStop,
      recommendedLine: recommendedLine,
      suggestedDirection: bestDirection,
      walkDistanceMeters: walkDistanceMeters,
      walkMinutes: walkMinutes,
      waitMinutes: bestWaitMinutes,
      totalMinutes: bestTotalMinutes,
      score: score,
    );
  }

  static TransitStop _findNearestStop(
      Position userPosition, List<TransitStop> stops) {
    TransitStop nearest = stops.first;
    var nearestDistance = _distanceMeters(
      userPosition.latitude,
      userPosition.longitude,
      nearest.latitude,
      nearest.longitude,
    );

    for (var i = 1; i < stops.length; i++) {
      final stop = stops[i];
      final distance = _distanceMeters(
        userPosition.latitude,
        userPosition.longitude,
        stop.latitude,
        stop.longitude,
      );
      if (distance < nearestDistance) {
        nearest = stop;
        nearestDistance = distance;
      }
    }

    return nearest;
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
