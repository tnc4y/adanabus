import 'package:flutter/material.dart';

import '../../core/theme_utils.dart';
import '../../data/models/transit_stop.dart';
import '../favorites/favorite_home_entry.dart';
import '../shared/stop_live_summary_service.dart';

class HomeApproachingBus {
  const HomeApproachingBus({
    required this.routeCode,
    required this.direction,
    required this.etaMinutes,
    required this.vehicle,
  });

  final String routeCode;
  final String direction;
  final int etaMinutes;
  final String vehicle;
}

class HomeQuickActionsRow extends StatelessWidget {
  const HomeQuickActionsRow({
    super.key,
    required this.onOpenPlanner,
    required this.onOpenStops,
    required this.onOpenFavorites,
    required this.onRefreshGps,
  });

  final VoidCallback onOpenPlanner;
  final VoidCallback onOpenStops;
  final VoidCallback onOpenFavorites;
  final Future<void> Function() onRefreshGps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: HomeActionButton(
            icon: Icons.route,
            label: 'Rota Belirle',
            onTap: onOpenPlanner,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: HomeActionButton(
            icon: Icons.place_outlined,
            label: 'Duraklar',
            onTap: onOpenStops,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: HomeActionButton(
            icon: Icons.star,
            label: 'Favoriler',
            onTap: onOpenFavorites,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: HomeActionButton(
            icon: Icons.gps_fixed,
            label: 'GPS',
            onTap: () => onRefreshGps(),
          ),
        ),
      ],
    );
  }
}

class HomeNearestStopCard extends StatelessWidget {
  const HomeNearestStopCard({
    super.key,
    required this.stop,
    required this.summary,
    required this.onAdd,
    required this.onOpenStop,
  });

  final TransitStop stop;
  final StopLiveSummary? summary;
  final VoidCallback onAdd;
  final VoidCallback onOpenStop;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppThemeUtils.getRouteMapBackgroundColor(context),
      borderRadius: BorderRadius.circular(18),
      elevation: 1,
      child: InkWell(
        onTap: onOpenStop,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.near_me, color: AppThemeUtils.getStatusColor(context, 'arrived')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'En yakın durak',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: onAdd,
                    child: const Text('Favorilere ekle'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                stop.stopName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text('Durak ID: ${stop.stopId}'),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeFavoriteMiniCarouselCard extends StatelessWidget {
  const HomeFavoriteMiniCarouselCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.liveSummary,
    required this.approachingBuses,
  });

  final FavoriteHomeEntry entry;
  final VoidCallback onTap;
  final StopLiveSummary? liveSummary;
  final List<HomeApproachingBus> approachingBuses;

  @override
  Widget build(BuildContext context) {
    final isStop = entry.kind == FavoriteHomeEntryKind.stop;
    final isLine = entry.kind == FavoriteHomeEntryKind.line;
    final accent = isStop
        ? AppThemeUtils.getAccentColor(context, 'green')
        : isLine
            ? AppThemeUtils.getAccentColor(context, 'blue')
            : AppThemeUtils.getAccentColor(context, 'orange');
    final icon = isStop
        ? Icons.location_on_rounded
        : isLine
            ? Icons.route
            : Icons.map_rounded;
    final tag = isStop
        ? 'Durak'
        : isLine
            ? 'Hat'
            : 'Rota';
    final primaryText = isLine ? (entry.line?.routeCode ?? entry.title) : entry.title;
    final subtitleText = isLine ? (entry.line?.routeName ?? entry.subtitle) : entry.subtitle;
    final firstEta = approachingBuses.isNotEmpty ? approachingBuses.first.etaMinutes : null;

    return Material(
      color: AppThemeUtils.getCardColor(context),
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.15), width: 1.5),
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.12), AppThemeUtils.getCardColor(context)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppThemeUtils.getOverlayColor(context, 0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accent, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        tag,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Stack(
                  children: [
                    Positioned(
                      right: -6,
                      bottom: -10,
                      child: Icon(
                        icon,
                        size: 58,
                        color: accent.withValues(alpha: 0.08),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          primaryText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.2,
                                height: 1.15,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitleText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppThemeUtils.getSecondaryTextColor(context),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppThemeUtils.getOverlayColor(context, 0.88),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isStop ? Icons.access_time_filled_rounded : Icons.info_rounded,
                      size: 15,
                      color: accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isStop
                            ? (firstEta == null
                                ? 'Yaklasan arac bekleniyor'
                                : 'En yakin arac: $firstEta dk')
                            : isLine
                                ? 'Hat detayina git'
                                : 'Rota detayina git',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppThemeUtils.getTextColor(context),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isStop && liveSummary != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Canli arac: ${liveSummary!.liveBusCount}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppThemeUtils.getSecondaryTextColor(context),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeReorderFavoritesList extends StatelessWidget {
  const HomeReorderFavoritesList({
    super.key,
    required this.entries,
    required this.onReorder,
  });

  final List<FavoriteHomeEntry> entries;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: mathMax(300, entries.length * 92.0),
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: entries.length,
        onReorder: onReorder,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return Container(
            key: ValueKey(entry.key),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: AppThemeUtils.getCardColor(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppThemeUtils.getBorderColor(context)),
            ),
            child: ListTile(
              leading: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_indicator),
              ),
              title: Text(entry.title),
              subtitle: Text(entry.subtitle),
              trailing: HomeKindBadge(kind: entry.kind),
            ),
          );
        },
      ),
    );
  }
}

class HomeEmptyFavoritesHero extends StatelessWidget {
  const HomeEmptyFavoritesHero({
    super.key,
    required this.onOpenLines,
    required this.onOpenFavorites,
  });

  final VoidCallback onOpenLines;
  final VoidCallback onOpenFavorites;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeUtils.getCardColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppThemeUtils.getBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Henüz favori yok',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          const Text('Henüz favori eklenmedi.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onOpenLines,
                icon: const Icon(Icons.route),
                label: const Text('Hatlara git'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenFavorites,
                icon: const Icon(Icons.star_outline),
                label: const Text('Favorileri aç'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class HomeKindBadge extends StatelessWidget {
  const HomeKindBadge({super.key, required this.kind});

  final FavoriteHomeEntryKind kind;

  @override
  Widget build(BuildContext context) {
    final text = switch (kind) {
      FavoriteHomeEntryKind.line => 'Hat',
      FavoriteHomeEntryKind.stop => 'Durak',
      FavoriteHomeEntryKind.route => 'Rota',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppThemeUtils.getDisabledColor(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text),
    );
  }
}

class HomeActionButton extends StatelessWidget {
  const HomeActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: AppThemeUtils.getCardColor(context),
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          constraints: const BoxConstraints(minHeight: 92),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppThemeUtils.getBorderColor(context),
              width: 1.2,
            ),
            gradient: isDark
                ? null
                : const LinearGradient(
                    colors: [
                      Color(0xFFFFFFFF),
                      Color(0xFFFAFBFC),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppThemeUtils.getAccentColor(context, 'blue').withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: AppThemeUtils.getAccentColor(context, 'blue'),
                  size: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: AppThemeUtils.getTextColor(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeCarouselManageCard extends StatelessWidget {
  const HomeCarouselManageCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppThemeUtils.getAccentColor(context, 'blue');
    return Material(
      color: AppThemeUtils.getCardColor(context),
      borderRadius: BorderRadius.circular(24),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.15),
              width: 1.5,
            ),
            gradient: isDark
                ? null
                : LinearGradient(
                    colors: [
                      accentColor.withValues(alpha: 0.06),
                      AppThemeUtils.getCardColor(context),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.edit_rounded,
                  size: 28,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Favorileri\nDüzenle',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeInlineErrorCard extends StatelessWidget {
  const HomeInlineErrorCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppThemeUtils.getDisabledColor(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message),
    );
  }
}

double mathMax(double a, double b) => a > b ? a : b;
