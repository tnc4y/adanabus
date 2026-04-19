import 'package:geolocator/geolocator.dart';

import '../../data/models/bus_vehicle.dart';
import '../../data/models/transit_stop.dart';
import 'geo_math_utils.dart';

class StopLiveSummary {
  const StopLiveSummary({
    required this.nearestEtaMinutes,
    required this.nearestBusId,
    required this.nextEtaMinutes,
    required this.nextBusId,
    required this.liveBusCount,
  });

  final int? nearestEtaMinutes;
  final String? nearestBusId;
  final int? nextEtaMinutes;
  final String? nextBusId;
  final int liveBusCount;

  bool get hasEstimate => nearestEtaMinutes != null;
}

class StopLiveSummaryService {
  const StopLiveSummaryService._();

  static const double _etaMetersPerMinute = 320;

  static StopLiveSummary summarizeStop(
    TransitStop stop,
    List<BusVehicle> buses,
  ) {
    final etaValues = <({int eta, String busId})>[];

    for (final bus in buses) {
      if (!bus.hasLocation) {
        continue;
      }
      final meters = GeoMathUtils.distanceMeters(
        bus.latitude!,
        bus.longitude!,
        stop.latitude,
        stop.longitude,
      );
      etaValues.add((eta: (meters / _etaMetersPerMinute).clamp(1, 180).round(), busId: bus.id));
    }

    etaValues.sort((a, b) => a.eta.compareTo(b.eta));
    return StopLiveSummary(
      nearestEtaMinutes: etaValues.isEmpty ? null : etaValues.first.eta,
      nearestBusId: etaValues.isEmpty ? null : etaValues.first.busId,
      nextEtaMinutes: etaValues.length > 1 ? etaValues[1].eta : null,
      nextBusId: etaValues.length > 1 ? etaValues[1].busId : null,
      liveBusCount: etaValues.length,
    );
  }

  static TransitStop? findNearestStop(
    Position position,
    List<TransitStop> stops,
  ) {
    if (stops.isEmpty) {
      return null;
    }

    TransitStop nearest = stops.first;
    var nearestDistance = GeoMathUtils.distanceMeters(
      position.latitude,
      position.longitude,
      nearest.latitude,
      nearest.longitude,
    );

    for (var i = 1; i < stops.length; i++) {
      final stop = stops[i];
      final distance = GeoMathUtils.distanceMeters(
        position.latitude,
        position.longitude,
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

  static List<TransitStop> sortByProximity(
    Position position,
    List<TransitStop> stops,
  ) {
    final sorted = stops.toList(growable: false);
    sorted.sort(
      (a, b) {
        final da = GeoMathUtils.distanceMeters(
          position.latitude,
          position.longitude,
          a.latitude,
          a.longitude,
        );
        final db = GeoMathUtils.distanceMeters(
          position.latitude,
          position.longitude,
          b.latitude,
          b.longitude,
        );
        return da.compareTo(db);
      },
    );
    return sorted;
  }
}
