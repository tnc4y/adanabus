import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'smart_trip_recommender_v2.dart';

class TripRouteSegment {
  const TripRouteSegment({
    required this.points,
    required this.color,
    required this.label,
  });

  final List<LatLng> points;
  final Color color;
  final String label;
}

class TripMapIconPin extends StatelessWidget {
  const TripMapIconPin({
    super.key,
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            offset: Offset(0, 2),
            color: Color(0x33000000),
          ),
        ],
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}

class TripRouteHeaderChips extends StatelessWidget {
  const TripRouteHeaderChips({super.key, required this.trip});

  final RankedTripOption trip;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      TripRouteChip(
        color: const Color(0xFF164B9D),
        label: 'Hat ${trip.line.displayRouteCode}',
        subtitle: trip.direction == '1' ? 'Dönüş' : 'Gidiş',
      ),
      if (trip.isTransfer && trip.transferLine != null)
        TripRouteChip(
          color: const Color(0xFFE65100),
          label: 'Hat ${trip.transferLine!.displayRouteCode}',
          subtitle: trip.transferDirection == '1' ? 'Dönüş' : 'Gidiş',
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: chips),
    );
  }
}

class TripRouteChip extends StatelessWidget {
  const TripRouteChip({
    super.key,
    required this.color,
    required this.label,
    required this.subtitle,
  });

  final Color color;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            offset: Offset(0, 2),
            color: Color(0x22000000),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TripLineBadge extends StatelessWidget {
  const TripLineBadge({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              blurRadius: 10,
              offset: Offset(0, 2),
              color: Color(0x33000000),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class TripRouteTimelineData {
  const TripRouteTimelineData({
    required this.now,
    required this.terminalDeparture,
    required this.startStopArrival,
    required this.firstBoarding,
    required this.transferArrival,
    required this.secondBoarding,
    required this.endStopArrival,
    required this.destinationArrival,
    required this.leadFromTerminalMinutes,
    required this.firstWaitMinutes,
    required this.transferWaitMinutes,
  });

  final DateTime now;
  final DateTime terminalDeparture;
  final DateTime startStopArrival;
  final DateTime firstBoarding;
  final DateTime? transferArrival;
  final DateTime? secondBoarding;
  final DateTime endStopArrival;
  final DateTime destinationArrival;
  final int leadFromTerminalMinutes;
  final int firstWaitMinutes;
  final int transferWaitMinutes;
}

class TripLineLiveStatus {
  const TripLineLiveStatus({
    required this.routeCode,
    required this.direction,
    required this.totalBusCount,
    required this.locatedBusCount,
    required this.nearestMetersToReferenceStop,
    required this.sampleVehicles,
  });

  final String routeCode;
  final String direction;
  final int totalBusCount;
  final int locatedBusCount;
  final double? nearestMetersToReferenceStop;
  final List<String> sampleVehicles;
}

class TripRouteLegend extends StatelessWidget {
  const TripRouteLegend({
    super.key,
    required this.trip,
    required this.timeline,
    required this.primaryLiveStatus,
    required this.transferLiveStatus,
  });

  final RankedTripOption trip;
  final TripRouteTimelineData timeline;
  final TripLineLiveStatus? primaryLiveStatus;
  final TripLineLiveStatus? transferLiveStatus;

  @override
  Widget build(BuildContext context) {
    final primary = primaryLiveStatus;
    final transfer = transferLiveStatus;

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white.withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${trip.startStop.stopName} → ${trip.endStop.stopName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (primary != null)
                  TripMiniDotChip(
                    color: const Color(0xFF164B9D),
                    label: '${primary.locatedBusCount}/${primary.totalBusCount}',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TripMiniInfoChip(
                    icon: Icons.access_time,
                    label: 'Çıkış ${_fmtClock(timeline.terminalDeparture)}',
                  ),
                  const SizedBox(width: 8),
                  TripMiniInfoChip(
                    icon: Icons.directions_bus,
                    label: 'Biniş ${_fmtClock(timeline.firstBoarding)}',
                  ),
                  const SizedBox(width: 8),
                  TripMiniInfoChip(
                    icon: Icons.flag,
                    label: 'Varış ${_fmtClock(timeline.destinationArrival)}',
                  ),
                  if (trip.isTransfer && trip.transferLine != null) ...[
                    const SizedBox(width: 8),
                    TripMiniInfoChip(
                      icon: Icons.swap_horiz,
                      label: 'Aktarma ${trip.transferLine!.displayRouteCode}',
                    ),
                  ],
                  if (primary != null) ...[
                    const SizedBox(width: 8),
                    TripMiniInfoChip(
                      icon: Icons.my_location,
                      label: primary.nearestMetersToReferenceStop == null
                          ? 'Canlı araç var'
                          : 'Canlı ~${primary.nearestMetersToReferenceStop!.round()}m',
                    ),
                  ],
                  if (transfer != null) ...[
                    const SizedBox(width: 8),
                    TripMiniInfoChip(
                      icon: Icons.alt_route,
                      label: 'Aktarma canlı ${transfer.locatedBusCount}',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtClock(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class TripMiniInfoChip extends StatelessWidget {
  const TripMiniInfoChip({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E7F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF5E6B82)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class TripMiniDotChip extends StatelessWidget {
  const TripMiniDotChip({
    super.key,
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
