import 'package:flutter/material.dart';

import '../../core/theme_utils.dart';
import 'favorite_route_item.dart';
import 'favorite_stop_item.dart';

class FavApproachingBusInfo {
  const FavApproachingBusInfo({
    required this.etaMinutes,
    required this.routeCode,
    required this.vehicleCode,
    required this.direction,
  });

  final int etaMinutes;
  final String routeCode;
  final String vehicleCode;
  final String direction;
}

class FavoriteLineCard extends StatelessWidget {
  const FavoriteLineCard({
    super.key,
    required this.routeCode,
    required this.routeName,
    required this.onRemove,
  });

  final String routeCode;
  final String routeName;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final accentBlue = AppThemeUtils.getAccentColor(context, 'blue');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppThemeUtils.getCardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeUtils.getBorderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: accentBlue.withValues(alpha: 0.12),
            ),
            child: Text(
              routeCode,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: accentBlue,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              routeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Favoriden kaldir',
          ),
        ],
      ),
    );
  }
}

class FavoriteStopCard extends StatelessWidget {
  const FavoriteStopCard({
    super.key,
    required this.item,
    required this.approachingBuses,
    required this.onRemove,
    required this.onTap,
  });

  final FavoriteStopItem item;
  final List<FavApproachingBusInfo> approachingBuses;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppThemeUtils.getCardColor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeUtils.getBorderColor(context)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  color: AppThemeUtils.getAccentColor(context, 'blue'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.stopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Favoriden kaldir',
                ),
              ],
            ),
            Text(
              'Durak ID: ${item.stopId}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (approachingBuses.isEmpty)
              Text(
                'Yaklasan arac bilgisi yok',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppThemeUtils.getSecondaryTextColor(context),
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              Column(
                children: approachingBuses
                    .map((bus) => FavoriteApproachingBusRow(bus: bus))
                    .toList(growable: false),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Detay'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FavoriteApproachingBusRow extends StatelessWidget {
  const FavoriteApproachingBusRow({super.key, required this.bus});

  final FavApproachingBusInfo bus;

  @override
  Widget build(BuildContext context) {
    final accentBlue = AppThemeUtils.getAccentColor(context, 'blue');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppThemeUtils.getSubtleBackgroundColor(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accentBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              bus.routeCode,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: accentBlue,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${bus.direction} • Arac ${bus.vehicleCode}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accentBlue,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${bus.etaMinutes} dk',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppThemeUtils.getAccentColor(context, 'green'),
            ),
          ),
        ],
      ),
    );
  }
}

class FavoritePairRouteCard extends StatelessWidget {
  const FavoritePairRouteCard({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onTap,
  });

  final FavoriteRouteItem item;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppThemeUtils.getCardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppThemeUtils.getBorderColor(context)),
        ),
        child: Row(
          children: [
            const Icon(Icons.alt_route_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.startStopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.endStopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: ${item.startStopId} -> ${item.endStopId}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Favoriden kaldir',
            ),
          ],
        ),
      ),
    );
  }
}

class FavSectionEmpty extends StatelessWidget {
  const FavSectionEmpty({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppThemeUtils.getCardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppThemeUtils.getBorderColor(context)),
      ),
      child: Text(text),
    );
  }
}

class FavEmptyState extends StatelessWidget {
  const FavEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_border, size: 44),
          const SizedBox(height: 6),
          Text(
            'Henuz favori yok',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text('Hat, durak veya iki durakli rota ekleyebilirsin.'),
        ],
      ),
    );
  }
}
