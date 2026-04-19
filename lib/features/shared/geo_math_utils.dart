import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class GeoMathUtils {
  const GeoMathUtils._();

  static double distanceMeters(
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

  static double polylineMeters(List<LatLng> points) {
    if (points.length < 2) {
      return 0;
    }
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      total += distanceMeters(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }
    return total;
  }

  static int nearestPointIndex(List<LatLng> points, double lat, double lon) {
    var bestIdx = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final dist = distanceMeters(lat, lon, p.latitude, p.longitude);
      if (dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  static LatLngBounds? boundsForPoints(Iterable<LatLng> points) {
    final iterator = points.iterator;
    if (!iterator.moveNext()) {
      return null;
    }

    var minLat = iterator.current.latitude;
    var maxLat = iterator.current.latitude;
    var minLng = iterator.current.longitude;
    var maxLng = iterator.current.longitude;

    while (iterator.moveNext()) {
      final point = iterator.current;
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }

  static double _toRadians(double value) => value * (math.pi / 180.0);
}
