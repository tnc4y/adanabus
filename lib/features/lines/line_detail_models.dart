class LineStop {
  const LineStop({
    required this.stopId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.routes,
  });

  final String stopId;
  final String name;
  final double latitude;
  final double longitude;
  final List<String> routes;

  String get key =>
      stopId.isNotEmpty ? stopId : '${latitude.toStringAsFixed(6)}|${longitude.toStringAsFixed(6)}';
}

class StopArrivalEstimate {
  const StopArrivalEstimate({
    required this.nearestEtaMinutes,
    required this.nearestBusId,
    required this.nextEtaMinutes,
    required this.nextBusId,
  });

  final int nearestEtaMinutes;
  final String nearestBusId;
  final int? nextEtaMinutes;
  final String? nextBusId;
}

class BusEtaCandidate {
  const BusEtaCandidate({
    required this.busId,
    required this.etaMinutes,
  });

  final String busId;
  final int etaMinutes;
}

class VehicleRouteProgress {
  const VehicleRouteProgress({
    required this.progress,
    required this.remainingStops,
    required this.startStopName,
    required this.nextStopName,
    required this.endStopName,
  });

  final double progress;
  final int remainingStops;
  final String startStopName;
  final String nextStopName;
  final String endStopName;
}
