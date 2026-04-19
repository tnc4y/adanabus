class FavoriteRouteItem {
  const FavoriteRouteItem({
    required this.startStopId,
    required this.startStopName,
    required this.startLatitude,
    required this.startLongitude,
    required this.startRoutes,
    required this.endStopId,
    required this.endStopName,
    required this.endLatitude,
    required this.endLongitude,
    required this.endRoutes,
  });

  final String startStopId;
  final String startStopName;
  final double startLatitude;
  final double startLongitude;
  final List<String> startRoutes;

  final String endStopId;
  final String endStopName;
  final double endLatitude;
  final double endLongitude;
  final List<String> endRoutes;

  String get key => '$startStopId->$endStopId';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'startStopId': startStopId,
      'startStopName': startStopName,
      'startLatitude': startLatitude,
      'startLongitude': startLongitude,
      'startRoutes': startRoutes,
      'endStopId': endStopId,
      'endStopName': endStopName,
      'endLatitude': endLatitude,
      'endLongitude': endLongitude,
      'endRoutes': endRoutes,
    };
  }

  factory FavoriteRouteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteRouteItem(
      startStopId: (json['startStopId'] ?? '').toString(),
      startStopName: (json['startStopName'] ?? '').toString(),
      startLatitude: _toDouble(json['startLatitude']) ?? 0,
      startLongitude: _toDouble(json['startLongitude']) ?? 0,
      startRoutes: _toStringList(json['startRoutes']),
      endStopId: (json['endStopId'] ?? '').toString(),
      endStopName: (json['endStopName'] ?? '').toString(),
      endLatitude: _toDouble(json['endLatitude']) ?? 0,
      endLongitude: _toDouble(json['endLongitude']) ?? 0,
      endRoutes: _toStringList(json['endRoutes']),
    );
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
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
