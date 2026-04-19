import 'package:flutter/material.dart';

import 'smart_trip_recommender_v2.dart';

class TripOptionCard extends StatelessWidget {
  const TripOptionCard({
    super.key,
    required this.trip,
    required this.onSelect,
  });

  final RankedTripOption trip;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4EAF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: const Color(0xFFEAF2FF),
                ),
                child: Text(
                  'Rota ${trip.rank}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: const Color(0xFFFFF1EE),
                ),
                child: Text(
                  'Hat ${trip.line.displayRouteCode}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFB63519),
                      ),
                ),
              ),
                if (trip.isTransfer)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: const Color(0xFFFFECD1),
                    ),
                    child: Text(
                      'Aktarma',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFE65100),
                          ),
                    ),
                  ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: const Color(0xFFE8F5E9),
                ),
                child: Text(
                  'Skor: ${trip.score}/100',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2E7D32),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              TripTinyMetric(
                icon: Icons.access_time_filled,
                label: 'Binis ${trip.estimatedBoardingTimeLabel}',
              ),
              TripTinyMetric(
                icon: Icons.directions_walk,
                label: '${trip.walkToStartMinutes.toStringAsFixed(1)} dk yuru',
              ),
              TripTinyMetric(
                icon: Icons.schedule,
                label: '${trip.waitMinutes.toStringAsFixed(1)} dk bekleme',
              ),
              TripTinyMetric(
                icon: Icons.directions_bus,
                label: '${trip.busRideMinutes.toStringAsFixed(1)} dk seyahat',
              ),
              TripTinyMetric(
                icon: Icons.time_to_leave,
                label: '${trip.walkFromEndMinutes.toStringAsFixed(1)} dk inis',
              ),
            ],
          ),
          if (trip.usesLiveBusData && trip.nearestLiveBusMeters != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF7EE),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFCDE8D6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.directions_bus, size: 14, color: Color(0xFF1C7A47)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Canli konum: En yakin arac ~${trip.nearestLiveBusMeters!.round()} m',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: const Color(0xFF1C7A47),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
           if (trip.isTransfer && trip.transferLine != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFFD54F), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.swap_horiz, size: 16, color: const Color(0xFFE65100)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Hat ${trip.transferLine!.displayRouteCode} - ${trip.transferDirection}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Aktarma: ${trip.transferStop?.stopName ?? "?"}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${trip.transferWaitMinutes.toInt()} dk bekleme',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: const Color(0xFFE65100),
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
           const SizedBox(height: 8),
           Row(
            children: [
              Expanded(
                child: Text(
                  '${trip.startStop.stopName} → ${trip.endStop.stopName}',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onSelect,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Aç'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TripTinyMetric extends StatelessWidget {
  const TripTinyMetric({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF666666)),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
