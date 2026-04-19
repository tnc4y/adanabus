class FavoriteStopItem {
  const FavoriteStopItem({
    required this.stopId,
    required this.stopName,
    required this.latitude,
    required this.longitude,
  });

  final String stopId;
  final String stopName;
  final double latitude;
  final double longitude;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'stopId': stopId,
      'stopName': stopName,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory FavoriteStopItem.fromJson(Map<String, dynamic> json) {
    return FavoriteStopItem(
      stopId: (json['stopId'] ?? '').toString(),
      stopName: (json['stopName'] ?? '').toString(),
      latitude: _toDouble(json['latitude']) ?? 0,
      longitude: _toDouble(json['longitude']) ?? 0,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString());
  }
}
