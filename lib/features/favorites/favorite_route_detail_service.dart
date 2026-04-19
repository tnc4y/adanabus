import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/bus_vehicle.dart';
import '../../data/services/adana_api_service.dart';
import '../shared/geo_math_utils.dart';
import '../shared/kentkart_path_utils.dart';
import 'favorite_route_item.dart';

class FavoriteRouteCandidate {
  const FavoriteRouteCandidate({
    required this.key,
    required this.routeCode,
    required this.direction,
    required this.color,
    required this.remainingPoints,
    required this.remainingMeters,
    required this.fromStopName,
    required this.toStopName,
    required this.nearestEtaMinutes,
    required this.nextEtaMinutes,
    required this.buses,
  });

  final String key;
  final String routeCode;
  final String direction;
  final Color color;
  final List<LatLng> remainingPoints;
  final double remainingMeters;
  final String fromStopName;
  final String toStopName;
  final int? nearestEtaMinutes;
  final int? nextEtaMinutes;
  final List<BusVehicle> buses;
}

class FavoriteRouteDetailService {
  const FavoriteRouteDetailService();

  static const double _etaMetersPerMinute = 320;

  Future<List<FavoriteRouteCandidate>> loadCandidates({
    required AdanaApiService apiService,
    required FavoriteRouteItem item,
    required List<Color> palette,
  }) async {
    final routeIntersection = <String>{...item.startRoutes}
      ..retainAll(item.endRoutes);
    final routeCodes = routeIntersection.isNotEmpty
        ? routeIntersection.toList(growable: false)
        : item.startRoutes.take(8).toList(growable: false);

    final parsed = <FavoriteRouteCandidate>[];
    var colorIndex = 0;

    for (final routeCode in routeCodes) {
      for (final direction in const <String>['0', '1']) {
        try {
          final response = await apiService.fetchKentkartPathInfo(
            displayRouteCode: routeCode,
            direction: direction,
          );
          final payload = response is Map<String, dynamic>
              ? response
              : <String, dynamic>{'data': response};
          final candidate = _parseCandidate(
            payload: payload,
            routeCode: routeCode,
            direction: direction,
            color: palette[colorIndex % palette.length],
            item: item,
          );
          colorIndex++;
          if (candidate != null) {
            parsed.add(candidate);
          }
        } catch (_) {
          continue;
        }
      }
    }

    return parsed;
  }

  FavoriteRouteCandidate? _parseCandidate({
    required Map<String, dynamic> payload,
    required String routeCode,
    required String direction,
    required Color color,
    required FavoriteRouteItem item,
  }) {
    for (final rawPath in KentkartPathUtils.asList(payload['pathList'])) {
      if (rawPath is! Map<String, dynamic>) {
        continue;
      }

      final rawStops = KentkartPathUtils.asList(rawPath['busStopList']);
      final startIdx = KentkartPathUtils.findStopIndex(rawStops, item.startStopId);
      final endIdx = KentkartPathUtils.findStopIndex(rawStops, item.endStopId);
      if (startIdx < 0 || endIdx < 0 || startIdx >= endIdx) {
        continue;
      }

      final points = KentkartPathUtils.extractPathPoints(rawPath);
      if (points.length < 2) {
        continue;
      }

      final startPointIdx = GeoMathUtils.nearestPointIndex(
        points,
        item.startLatitude,
        item.startLongitude,
      );
      final endPointIdx = GeoMathUtils.nearestPointIndex(
        points,
        item.endLatitude,
        item.endLongitude,
      );
      if (startPointIdx < 0 || endPointIdx < 0 || startPointIdx >= endPointIdx) {
        continue;
      }

      final remaining = points.sublist(startPointIdx, endPointIdx + 1);
      final meters = GeoMathUtils.polylineMeters(remaining);
      final buses = KentkartPathUtils.extractBuses(rawPath, routeCode, direction);
      final eta = _estimateEta(
        buses: buses,
        targetLat: item.startLatitude,
        targetLon: item.startLongitude,
      );

      final fromStopName = startIdx > 0
          ? KentkartPathUtils.readString(
              rawStops[startIdx - 1] as Map<String, dynamic>,
              const ['stopName', 'StopName'],
            )
          : '';
      final toStopName = KentkartPathUtils.readString(
        rawStops[endIdx] as Map<String, dynamic>,
        const ['stopName', 'StopName'],
      );

      return FavoriteRouteCandidate(
        key: '$routeCode|$direction|$startIdx|$endIdx',
        routeCode: routeCode,
        direction: direction,
        color: color,
        remainingPoints: remaining,
        remainingMeters: meters,
        fromStopName: fromStopName,
        toStopName: toStopName,
        nearestEtaMinutes: eta.$1,
        nextEtaMinutes: eta.$2,
        buses: buses,
      );
    }

    return null;
  }

  (int?, int?) _estimateEta({
    required List<BusVehicle> buses,
    required double targetLat,
    required double targetLon,
  }) {
    if (buses.isEmpty) {
      return (null, null);
    }

    final etaList = <int>[];
    for (final bus in buses) {
      if (!bus.hasLocation) {
        continue;
      }
      final meters = GeoMathUtils.distanceMeters(
        bus.latitude!,
        bus.longitude!,
        targetLat,
        targetLon,
      );
      etaList.add((meters / _etaMetersPerMinute).clamp(1, 180).round());
    }

    if (etaList.isEmpty) {
      return (null, null);
    }

    etaList.sort();
    return (etaList.first, etaList.length > 1 ? etaList[1] : null);
  }
}
