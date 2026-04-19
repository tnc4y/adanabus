import 'package:flutter/material.dart';

import '../../data/models/bus_vehicle.dart';
import 'line_detail_models.dart';

class LineDetailVehicleFloatingCard extends StatelessWidget {
  const LineDetailVehicleFloatingCard({
    super.key,
    required this.bus,
    required this.routeCode,
    required this.direction,
  });

  final BusVehicle bus;
  final String routeCode;
  final String direction;

  @override
  Widget build(BuildContext context) {
    final lat = bus.latitude?.toStringAsFixed(5) ?? '-';
    final lon = bus.longitude?.toStringAsFixed(5) ?? '-';

    return Material(
      elevation: 4,
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_bus, color: Color(0xFF0B5A25)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bus.id.isEmpty ? 'Arac' : 'Arac ${bus.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  direction == '1' ? 'Donus' : 'Gidis',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Hat: $routeCode'),
            if (bus.name.isNotEmpty)
              Text(
                bus.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Text('Konum: $lat, $lon'),
          ],
        ),
      ),
    );
  }
}

class LineDetailVehicleEmptyFloatingCard extends StatelessWidget {
  const LineDetailVehicleEmptyFloatingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(14),
      child: const Center(
        child: Text(
          'Canli arac bilgisi bekleniyor...',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class LineDetailSelectedStopInfoCard extends StatelessWidget {
  const LineDetailSelectedStopInfoCard({
    super.key,
    required this.stop,
    required this.estimate,
    required this.currentRouteCode,
    required this.currentDirection,
    required this.lastRefreshAt,
    required this.onClose,
  });

  final LineStop stop;
  final StopArrivalEstimate? estimate;
  final String currentRouteCode;
  final String currentDirection;
  final DateTime? lastRefreshAt;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final refreshLabel = lastRefreshAt == null
        ? 'Guncellenmedi'
        : '${lastRefreshAt!.hour.toString().padLeft(2, '0')}:${lastRefreshAt!.minute.toString().padLeft(2, '0')}:${lastRefreshAt!.second.toString().padLeft(2, '0')}';
    final routeList = stop.routes.isEmpty
        ? currentRouteCode
        : stop.routes.take(8).join(', ');

    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white.withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stop.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Detayi kapat',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Ne geliyor: Hatlar $routeList',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Ne gidiyor: Hat $currentRouteCode • ${currentDirection == '1' ? 'Donus' : 'Gidis'}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              estimate == null
                  ? 'Tahmin yok • Son: $refreshLabel'
                  : 'En yakin: ${estimate!.nearestEtaMinutes} dk, Sonraki: ${estimate!.nextEtaMinutes ?? '-'} dk',
              style: TextStyle(
                fontSize: 12,
                color: estimate == null
                    ? const Color(0xFF6A6A6A)
                    : const Color(0xFF175E2F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
