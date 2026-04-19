class TransitStop {
  const TransitStop({
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
    required this.routes,
  });

  final String stopId;
  final String stopName;
  final double latitude;
  final double longitude;
  final List<String> routes;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'stopId': stopId,
      'stopName': stopName,
      'latitude': latitude,
      'longitude': longitude,
      'routes': routes,
    };
  }

  factory TransitStop.fromJson(Map<String, dynamic> json) {
    return TransitStop(
      stopId: (json['stopId'] ?? '').toString(),
      stopName: (json['stopName'] ?? '').toString(),
      latitude: _toDouble(json['latitude']) ?? 0,
      longitude: _toDouble(json['longitude']) ?? 0,
      routes: (json['routes'] is List)
          ? (json['routes'] as List)
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
          : const <String>[],
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }
}
