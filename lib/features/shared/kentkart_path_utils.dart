import 'package:latlong2/latlong.dart';

import '../../data/models/bus_vehicle.dart';

class KentkartPathUtils {
  const KentkartPathUtils._();

  static List<dynamic> asList(dynamic value) {
    if (value is List<dynamic>) {
      return value;
    }
    return const <dynamic>[];
  }

  static String readString(Map<String, dynamic> map, List<String> keys) {
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

  static double? readDouble(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final parsed = toDouble(map[key]);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static double? toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.'));
    }
    return null;
  }

  static List<LatLng> extractPathPoints(Map<String, dynamic> path) {
    final points = <LatLng>[];
    for (final raw in asList(path['pointList'])) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final lat = readDouble(raw, const ['lat', 'latitude', 'y']);
      final lon = readDouble(raw, const ['lng', 'lon', 'longitude', 'x']);
      if (lat == null || lon == null) {
        continue;
      }
      points.add(LatLng(lat, lon));
    }
    return points;
  }

  static int findStopIndex(List<dynamic> rawStops, String stopId) {
    for (var i = 0; i < rawStops.length; i++) {
      final raw = rawStops[i];
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final id = readString(raw, const ['stopId', 'StopId', 'id']);
      if (id == stopId) {
        return i;
      }
    }
    return -1;
  }

  static List<BusVehicle> extractBuses(
    Map<String, dynamic> path,
    String routeCode,
    String direction,
  ) {
    final result = <BusVehicle>[];
    for (final raw in asList(path['busList'])) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final lat = readDouble(raw, const ['lat', 'latitude', 'y']);
      final lon = readDouble(raw, const ['lng', 'lon', 'longitude', 'x']);
      if (lat == null || lon == null) {
        continue;
      }
      final busId = readString(raw, const ['busId', 'BusId', 'id', 'Id']);
      final name = readString(raw, const ['name', 'Name', 'RouteName']);
      result.add(
        BusVehicle(
          id: busId,
          displayRouteCode: routeCode,
          routeCode: routeCode,
          name: name,
          direction: direction,
          latitude: lat,
          longitude: lon,
          raw: raw,
        ),
      );
    }
    return result;
  }
}
