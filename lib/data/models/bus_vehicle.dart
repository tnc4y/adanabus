class BusVehicle {
  const BusVehicle({
    required this.id,
    required this.displayRouteCode,
    required this.routeCode,
    required this.name,
    required this.direction,
    required this.latitude,
    required this.longitude,
    required this.raw,
  });

  final String id;
  final String displayRouteCode;
  final String routeCode;
  final String name;
  final String direction;
  final double? latitude;
  final double? longitude;
  final Map<String, dynamic> raw;

  bool get hasLocation => latitude != null && longitude != null;

  factory BusVehicle.fromJson(Map<String, dynamic> json) {
    return BusVehicle(
      id: _readAsString(json, ['BusId', 'busId', 'Id', 'id']),
      displayRouteCode: _readAsString(
        json,
        ['DisplayRouteCode', 'displayRouteCode', 'lineCode'],
      ),
      routeCode: _readAsString(json, ['RouteCode', 'routeCode']),
      name: _readAsString(json, ['Name', 'name', 'RouteName']),
      direction: _readAsString(json, ['Direction', 'direction']),
      latitude: _readAsDouble(json, ['Lat', 'Latitude', 'lat', 'enlem']),
      longitude: _readAsDouble(json, ['Lon', 'Longitude', 'lon', 'boylam']),
      raw: json,
    );
  }

  static String _readAsString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) {
        continue;
      }
      final normalized = value.toString().trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  static double? _readAsDouble(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      final asDouble = _toDouble(value);
      if (asDouble != null) {
        return asDouble;
      }
    }
    return null;
  }

  static double? _toDouble(dynamic value) {
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
}
