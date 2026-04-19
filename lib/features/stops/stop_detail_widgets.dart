import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme_utils.dart';
import '../../data/models/bus_vehicle.dart';
import '../../data/models/transit_stop.dart';

class StopRouteTrackInfo {
  const StopRouteTrackInfo({
    required this.routeCode,
    required this.direction,
    required this.color,
    required this.approachPoints,
    required this.afterStopPoints,
    required this.remainingPoints,
    required this.approachMeters,
    required this.fromStopName,
    required this.toStopName,
    required this.nearestEtaMinutes,
    required this.nextEtaMinutes,
    required this.liveBusCount,
    required this.buses,
    required this.primaryBus,
  });

  final String routeCode;
  final String direction;
  final Color color;
  final List<LatLng> approachPoints;
  final List<LatLng> afterStopPoints;
  final List<LatLng> remainingPoints;
  final double approachMeters;
  final String fromStopName;
  final String toStopName;
  final int? nearestEtaMinutes;
  final int? nextEtaMinutes;
  final int liveBusCount;
  final List<BusVehicle> buses;
  final BusVehicle? primaryBus;

  String get key => '$routeCode|$direction|$toStopName';
}

class StopNearbyStopsCard extends StatelessWidget {
  const StopNearbyStopsCard({
    super.key,
    required this.anchorName,
    required this.clusterStops,
  });

  final String anchorName;
  final List<TransitStop> clusterStops;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: AppThemeUtils.getCardColor(context).withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${clusterStops.length} durak birlestirildi',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              anchorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppThemeUtils.getTextColor(context),
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: clusterStops
                    .map(
                      (stop) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppThemeUtils.getSubtleBackgroundColor(context),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppThemeUtils.getBorderColor(context),
                            ),
                          ),
                          child: Text(
                            stop.stopName,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StopTrackCard extends StatelessWidget {
  const StopTrackCard({
    super.key,
    required this.track,
    required this.stopName,
    required this.updatedAt,
    required this.isSelected,
  });

  final StopRouteTrackInfo track;
  final String stopName;
  final DateTime? updatedAt;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final updated = updatedAt == null
        ? '-'
        : '${updatedAt!.hour.toString().padLeft(2, '0')}:${updatedAt!.minute.toString().padLeft(2, '0')}';
    final etaText = track.nearestEtaMinutes == null
        ? 'ETA yok'
        : '${track.nearestEtaMinutes} dk${track.nextEtaMinutes == null ? '' : ' • ${track.nextEtaMinutes} dk'}';

    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: AppThemeUtils.getCardColor(context).withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: track.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hat ${track.routeCode} • ${track.direction == '1' ? 'Donus' : 'Gidis'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.radio_button_checked,
                    size: 16,
                    color: AppThemeUtils.getAccentColor(context, 'blue'),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$stopName • ${(track.approachMeters / 1000).toStringAsFixed(1)} km',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Yaklasan: $etaText • Canli: ${track.liveBusCount}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppThemeUtils.getAccentColor(context, 'green'),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            Text(
              'Son guncelleme: $updated',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class StopMissingRoutesCard extends StatelessWidget {
  const StopMissingRoutesCard({super.key, required this.routes});

  final List<String> routes;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: AppThemeUtils.getCardColor(context).withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Buradan gecer (yaklasmayanlar)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: routes
                      .take(24)
                      .map(
                        (route) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppThemeUtils.getSubtleBackgroundColor(context),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppThemeUtils.getBorderColor(context),
                            ),
                          ),
                          child: Text(
                            route,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
