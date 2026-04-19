class TripDestination {
  const TripDestination({
    required this.latitude,
    required this.longitude,
    required this.name,
  });

  final double latitude;
  final double longitude;
  final String name;

  @override
  String toString() => '$name ($latitude, $longitude)';
}
