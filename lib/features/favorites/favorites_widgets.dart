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

// ─── Favorite Line Card ───────────────────────────────────────────────────────

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
    final blue = AppThemeUtils.getAccentColor(context, 'blue');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppThemeUtils.getCardColor(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppThemeUtils.getBorderColor(context)),
      ),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: blue.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              routeCode,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: blue,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              routeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppThemeUtils.getTextColor(context),
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(
              Icons.remove_circle_outline_rounded,
              size: 20,
              color: AppThemeUtils.getSecondaryTextColor(context),
            ),
            tooltip: 'Favoriden kaldır',
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ─── Favorite Stop Card ───────────────────────────────────────────────────────

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
    final green = AppThemeUtils.getAccentColor(context, 'green');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: AppThemeUtils.getCardColor(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: green.withValues(alpha: isDark ? 0.25 : 0.2),
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.place_rounded, color: green, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.stopName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppThemeUtils.getTextColor(context),
                          ),
                        ),
                        Text(
                          'Durak #${item.stopId}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppThemeUtils.getSecondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onRemove,
                    icon: Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 20,
                      color: AppThemeUtils.getSecondaryTextColor(context),
                    ),
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    tooltip: 'Favoriden kaldır',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Approaching buses
              if (approachingBuses.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppThemeUtils.getSubtleBackgroundColor(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 14,
                          color: AppThemeUtils.getSecondaryTextColor(context)),
                      const SizedBox(width: 6),
                      Text(
                        'Yaklaşan araç bilgisi bekleniyor…',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppThemeUtils.getSecondaryTextColor(context),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: approachingBuses
                      .map((bus) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: FavoriteApproachingBusRow(bus: bus),
                          ))
                      .toList(),
                ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Detayı gör',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: green,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: green),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Approaching Bus Row ─────────────────────────────────────────────────────

class FavoriteApproachingBusRow extends StatelessWidget {
  const FavoriteApproachingBusRow({super.key, required this.bus});
  final FavApproachingBusInfo bus;

  @override
  Widget build(BuildContext context) {
    final blue = AppThemeUtils.getAccentColor(context, 'blue');
    final green = AppThemeUtils.getAccentColor(context, 'green');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131E2C) : const Color(0xFFF4F8FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: blue.withValues(alpha: isDark ? 0.15 : 0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 38),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: blue.withValues(alpha: isDark ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              bus.routeCode,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: blue,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${bus.direction} · ${bus.vehicleCode}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppThemeUtils.getSecondaryTextColor(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${bus.etaMinutes} dk',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: green,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Favorite Pair Route Card ─────────────────────────────────────────────────

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
    final orange = AppThemeUtils.getAccentColor(context, 'orange');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: AppThemeUtils.getCardColor(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: orange.withValues(alpha: isDark ? 0.25 : 0.18),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.alt_route_rounded, color: orange, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // From
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: AppThemeUtils.getAccentColor(context, 'green'),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.startStopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppThemeUtils.getTextColor(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Container(
                        width: 1,
                        height: 10,
                        color: AppThemeUtils.getBorderColor(context),
                        margin: const EdgeInsets.symmetric(vertical: 2),
                      ),
                    ),
                    // To
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.endStopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppThemeUtils.getTextColor(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Icon(Icons.chevron_right_rounded,
                      size: 20,
                      color: AppThemeUtils.getSecondaryTextColor(context)),
                  const SizedBox(height: 4),
                  IconButton(
                    onPressed: onRemove,
                    icon: Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 18,
                      color: AppThemeUtils.getSecondaryTextColor(context),
                    ),
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    tooltip: 'Kaldır',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
