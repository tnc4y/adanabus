import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme_utils.dart';
import '../../data/models/bus_vehicle.dart';
import '../../data/models/transit_stop.dart';
import '../../data/services/adana_api_service.dart';
import '../shared/geo_math_utils.dart';
import '../shared/kentkart_path_utils.dart';
import 'favorite_line_item.dart';
import 'favorite_route_detail_page.dart';
import 'favorite_route_item.dart';
import '../stops/stop_detail_page.dart';
import '../stops/stop_picker_page.dart';
import 'favorites_controller.dart';
import 'favorite_stop_item.dart';
import 'favorites_widgets.dart';

class FavoritesPage extends StatefulWidget {
  const FavoritesPage({
    super.key,
    required this.favoritesController,
    required this.onToggleTheme,
    required this.isDarkMode,
  });

  final FavoritesController favoritesController;
  final Future<void> Function() onToggleTheme;
  final bool isDarkMode;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage>
    with SingleTickerProviderStateMixin {
  final AdanaApiService _apiService = AdanaApiService();
  static const double _etaMetersPerMinute = 320;
  final Map<String, TransitStop> _catalogByStopId = <String, TransitStop>{};
  Map<String, List<FavApproachingBusInfo>> _approachingByStopId =
      const <String, List<FavApproachingBusInfo>>{};
  bool _isLoadingApproaching = false;
  String _stopSignature = '';
  Timer? _refreshTimer;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshApproachingData();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _refreshApproachingData(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshApproachingData({bool silent = false}) async {
    final stops = widget.favoritesController.favoriteStops;
    if (stops.isEmpty) {
      if (mounted) {
        setState(() {
          _approachingByStopId = const {};
          _isLoadingApproaching = false;
        });
      }
      return;
    }

    if (!silent && mounted) setState(() => _isLoadingApproaching = true);

    try {
      final globalBuses = await _apiService.fetchBuses();
      final catalog = await _apiService.fetchAllStopsCatalog();
      _catalogByStopId
        ..clear()
        ..addEntries(catalog.map((s) => MapEntry(s.stopId, s)));

      final fallback = <String, List<FavApproachingBusInfo>>{};
      for (final stop in stops) {
        fallback[stop.stopId] =
            _buildFallbackApproachingFromGlobal(stop: stop, buses: globalBuses);
      }

      if (mounted) setState(() => _approachingByStopId = fallback);

      final result = <String, List<FavApproachingBusInfo>>{};
      for (final stop in stops) {
        final routeAware = await _loadApproachingForStop(stop);
        result[stop.stopId] = routeAware.isNotEmpty
            ? routeAware
            : (fallback[stop.stopId] ?? const []);
      }

      if (!mounted) return;
      setState(() {
        _approachingByStopId = result;
        _isLoadingApproaching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingApproaching = false);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Favori duraklar için canlı veri alınamadı.')),
        );
      }
    }
  }

  Future<List<FavApproachingBusInfo>> _loadApproachingForStop(
    FavoriteStopItem stop,
  ) async {
    final routeCodes = _resolveRouteCodesForFavoriteStop(stop);
    if (routeCodes.isEmpty) return const [];

    final rawApproaching = <FavApproachingBusInfo>[];
    final dedupeKeys = <String>{};

    for (final routeCode in routeCodes) {
      for (final direction in const <String>['0', '1']) {
        try {
          final response = await _apiService.fetchKentkartPathInfo(
            displayRouteCode: routeCode,
            direction: direction,
          );
          final payload = response is Map<String, dynamic>
              ? response
              : <String, dynamic>{'data': response};

          for (final path in KentkartPathUtils.asList(payload['pathList'])) {
            if (path is! Map<String, dynamic>) continue;
            final points = KentkartPathUtils.extractPathPoints(path);
            if (points.length < 2) continue;

            final stopPointIndex =
                GeoMathUtils.nearestPointIndex(points, stop.latitude, stop.longitude);
            if (stopPointIndex < 0 || stopPointIndex >= points.length - 1) continue;

            final busStopList = KentkartPathUtils.asList(path['busStopList']);
            final selectedStopIdx =
                KentkartPathUtils.findStopIndex(busStopList, stop.stopId);
            if (selectedStopIdx < 0) continue;

            final buses = KentkartPathUtils.extractBuses(path, routeCode, direction);
            for (final bus in buses) {
              if (!bus.hasLocation) continue;
              final busPointIndex = GeoMathUtils.nearestPointIndex(
                  points, bus.latitude!, bus.longitude!);
              if (busPointIndex < 0 || busPointIndex > stopPointIndex) continue;

              final etaMinutes = (GeoMathUtils.distanceMeters(
                            bus.latitude!, bus.longitude!, stop.latitude, stop.longitude,
                          ) /
                          _etaMetersPerMinute)
                      .clamp(1, 180)
                      .round();

              final routeLabel = bus.displayRouteCode.isNotEmpty
                  ? bus.displayRouteCode
                  : bus.routeCode;
              final vehicleCode =
                  bus.id.isNotEmpty ? bus.id : (bus.name.isNotEmpty ? bus.name : '-');
              final directionLabel = bus.direction == '1' ? 'Dönüş' : 'Gidiş';
              final dedupe = '$routeLabel|$directionLabel|$vehicleCode';
              if (!dedupeKeys.add(dedupe)) continue;

              rawApproaching.add(FavApproachingBusInfo(
                etaMinutes: etaMinutes,
                routeCode: routeLabel.isEmpty ? '?' : routeLabel,
                vehicleCode: vehicleCode,
                direction: directionLabel,
              ));
            }
          }
        } catch (_) {
          continue;
        }
      }
    }

    rawApproaching.sort((a, b) {
      final e = a.etaMinutes.compareTo(b.etaMinutes);
      if (e != 0) return e;
      final r = a.routeCode.compareTo(b.routeCode);
      if (r != 0) return r;
      return a.vehicleCode.compareTo(b.vehicleCode);
    });

    return rawApproaching.take(3).toList(growable: false);
  }

  List<FavApproachingBusInfo> _buildFallbackApproachingFromGlobal({
    required FavoriteStopItem stop,
    required List<BusVehicle> buses,
  }) {
    final list = <FavApproachingBusInfo>[];
    for (final bus in buses) {
      if (!bus.hasLocation) continue;
      final etaMinutes = (GeoMathUtils.distanceMeters(
                    bus.latitude!, bus.longitude!, stop.latitude, stop.longitude,
                  ) /
                  _etaMetersPerMinute)
              .clamp(1, 180)
              .round();
      final routeLabel = bus.displayRouteCode.isNotEmpty
          ? bus.displayRouteCode
          : (bus.routeCode.isNotEmpty ? bus.routeCode : '?');
      final directionLabel = bus.direction == '1' ? 'Dönüş' : 'Gidiş';
      final vehicleCode =
          bus.id.isNotEmpty ? bus.id : (bus.name.isNotEmpty ? bus.name : '-');
      list.add(FavApproachingBusInfo(
        etaMinutes: etaMinutes,
        routeCode: routeLabel,
        vehicleCode: vehicleCode,
        direction: directionLabel,
      ));
    }
    list.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
    return list.take(3).toList(growable: false);
  }

  List<String> _resolveRouteCodesForFavoriteStop(FavoriteStopItem stop) {
    final exact = (_catalogByStopId[stop.stopId]?.routes ?? const <String>[])
        .where((r) => r.trim().isNotEmpty)
        .toList(growable: false);
    if (exact.isNotEmpty) return exact.take(8).toList(growable: false);

    TransitStop? nearest;
    var nearestMeters = double.infinity;
    for (final candidate in _catalogByStopId.values) {
      final meters = GeoMathUtils.distanceMeters(
          stop.latitude, stop.longitude, candidate.latitude, candidate.longitude);
      if (meters < nearestMeters) {
        nearest = candidate;
        nearestMeters = meters;
      }
    }
    if (nearest == null || nearestMeters > 180) return const [];
    return nearest.routes.where((r) => r.trim().isNotEmpty).take(8).toList(growable: false);
  }

  Future<void> _addRoute() async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final startStop = await nav.push<TransitStop>(
      MaterialPageRoute(
        builder: (_) => const StopPickerPage(selectedStopIds: <String>{}),
      ),
    );
    if (startStop == null || !mounted) return;

    final endStop = await nav.push<TransitStop>(
      MaterialPageRoute(
        builder: (_) => StopPickerPage(selectedStopIds: {startStop.stopId}),
      ),
    );
    if (endStop == null || !mounted) return;

    if (startStop.stopId == endStop.stopId) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Başlangıç ve varış aynı olamaz.')),
      );
      return;
    }

    final added = widget.favoritesController.toggleFavoriteRoute(
      FavoriteRouteItem(
        startStopId: startStop.stopId,
        startStopName: startStop.stopName,
        startLatitude: startStop.latitude,
        startLongitude: startStop.longitude,
        startRoutes: startStop.routes,
        endStopId: endStop.stopId,
        endStopName: endStop.stopName,
        endLatitude: endStop.latitude,
        endLongitude: endStop.longitude,
        endRoutes: endStop.routes,
      ),
    );

    messenger.showSnackBar(
      SnackBar(
        content: Text(added ? 'Kayıtlı rota eklendi' : 'Kayıtlı rota kaldırıldı'),
        duration: const Duration(milliseconds: 1100),
      ),
    );
  }

  Future<void> _addStop() async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final stops = widget.favoritesController.favoriteStops;
    final selectedStop = await nav.push<TransitStop>(
      MaterialPageRoute(
        builder: (_) =>
            StopPickerPage(selectedStopIds: stops.map((s) => s.stopId).toSet()),
      ),
    );
    if (selectedStop == null || !mounted) return;

    final added = widget.favoritesController.toggleFavoriteStop(
      FavoriteStopItem(
        stopId: selectedStop.stopId,
        stopName: selectedStop.stopName,
        latitude: selectedStop.latitude,
        longitude: selectedStop.longitude,
      ),
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(added ? 'Durak favorilere eklendi' : 'Durak kaldırıldı'),
        duration: const Duration(milliseconds: 1000),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.favoritesController,
      builder: (context, _) {
        final lines = widget.favoritesController.favoriteLines;
        final stops = widget.favoritesController.favoriteStops;
        final routes = widget.favoritesController.favoriteRoutes;

        final currentSignature = stops.map((s) => s.stopId).join('|');
        if (currentSignature != _stopSignature) {
          _stopSignature = currentSignature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _refreshApproachingData(silent: true);
          });
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;

        if (!widget.favoritesController.isReady) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverAppBar(
                floating: true,
                snap: true,
                pinned: false,
                backgroundColor: isDark ? const Color(0xFF0F1722) : Colors.white,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                titleSpacing: 20,
                title: const Text(
                  'Favoriler',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                actions: [
                  // Refresh
                  _AppBarIconBtn(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Yenile',
                    onTap: _refreshApproachingData,
                  ),
                  // Theme toggle
                  _AppBarIconBtn(
                    icon: widget.isDarkMode
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                    tooltip: widget.isDarkMode ? 'Aydınlık mod' : 'Karanlık mod',
                    onTap: () => widget.onToggleTheme(),
                  ),
                  const SizedBox(width: 8),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(46),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: isDark
                              ? const Color(0xFF1F2937)
                              : const Color(0xFFE8EDF5),
                        ),
                      ),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      labelStyle: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13),
                      unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      indicatorWeight: 3,
                      indicatorSize: TabBarIndicatorSize.label,
                      tabs: [
                        Tab(
                          child: _TabLabel(
                            label: 'Rotalar',
                            count: routes.length,
                            color: AppThemeUtils.getAccentColor(context, 'orange'),
                          ),
                        ),
                        Tab(
                          child: _TabLabel(
                            label: 'Duraklar',
                            count: stops.length,
                            color: AppThemeUtils.getAccentColor(context, 'green'),
                          ),
                        ),
                        Tab(
                          child: _TabLabel(
                            label: 'Hatlar',
                            count: lines.length,
                            color: AppThemeUtils.getAccentColor(context, 'blue'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            body: TabBarView(
              controller: _tabController,
              children: [
                // ── Rotalar ──
                _RoutesTab(
                  routes: routes,
                  onAdd: _addRoute,
                  onRemove: (key) =>
                      widget.favoritesController.removeFavoriteRoute(key),
                  onTap: (item) => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => FavoriteRouteDetailPage(item: item)),
                  ),
                ),
                // ── Duraklar ──
                _StopsTab(
                  stops: stops,
                  approachingByStopId: _approachingByStopId,
                  isLoadingApproaching: _isLoadingApproaching,
                  onAdd: _addStop,
                  onRemove: (id) =>
                      widget.favoritesController.removeFavoriteStop(id),
                  onTap: (item) => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => StopDetailPage(favoriteStop: item)),
                  ),
                ),
                // ── Hatlar ──
                _LinesTab(
                  lines: lines,
                  onRemove: (code) =>
                      widget.favoritesController.removeFavoriteLine(code),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Tab Widgets ─────────────────────────────────────────────────────────────

class _AppBarIconBtn extends StatelessWidget {
  const _AppBarIconBtn(
      {required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 22),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.label, required this.count, required this.color});
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (count > 0) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Routes Tab ──────────────────────────────────────────────────────────────

class _RoutesTab extends StatelessWidget {
  const _RoutesTab({
    required this.routes,
    required this.onAdd,
    required this.onRemove,
    required this.onTap,
  });
  final List<FavoriteRouteItem> routes;
  final VoidCallback onAdd;
  final void Function(String key) onRemove;
  final void Function(FavoriteRouteItem) onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppThemeUtils.getAccentColor(context, 'orange');
    return routes.isEmpty
        ? _EmptyTab(
            icon: Icons.alt_route_rounded,
            title: 'Kayıtlı rota yok',
            subtitle: 'İki durak arasında rota kaydederek\nhızla planlama yapabilirsin.',
            buttonLabel: 'Rota Ekle',
            accent: accent,
            onAdd: onAdd,
          )
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: routes.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AddButton(
                      label: 'Rota Ekle', accent: accent, onTap: onAdd),
                );
              }
              final item = routes[i - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FavoritePairRouteCard(
                  item: item,
                  onRemove: () => onRemove(item.key),
                  onTap: () => onTap(item),
                ),
              );
            },
          );
  }
}

// ─── Stops Tab ───────────────────────────────────────────────────────────────

class _StopsTab extends StatelessWidget {
  const _StopsTab({
    required this.stops,
    required this.approachingByStopId,
    required this.isLoadingApproaching,
    required this.onAdd,
    required this.onRemove,
    required this.onTap,
  });
  final List<FavoriteStopItem> stops;
  final Map<String, List<FavApproachingBusInfo>> approachingByStopId;
  final bool isLoadingApproaching;
  final VoidCallback onAdd;
  final void Function(String id) onRemove;
  final void Function(FavoriteStopItem) onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppThemeUtils.getAccentColor(context, 'green');
    return stops.isEmpty
        ? _EmptyTab(
            icon: Icons.place_rounded,
            title: 'Favori durak yok',
            subtitle: 'Sık kullandığın duraklara\nhızla erişmek için ekle.',
            buttonLabel: 'Durak Ekle',
            accent: accent,
            onAdd: onAdd,
          )
        : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: stops.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) {
                return Column(
                  children: [
                    _AddButton(label: 'Durak Ekle', accent: accent, onTap: onAdd),
                    if (isLoadingApproaching)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    const SizedBox(height: 12),
                  ],
                );
              }
              final item = stops[i - 1];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: FavoriteStopCard(
                  item: item,
                  approachingBuses: approachingByStopId[item.stopId] ?? const [],
                  onRemove: () => onRemove(item.stopId),
                  onTap: () => onTap(item),
                ),
              );
            },
          );
  }
}

// ─── Lines Tab ───────────────────────────────────────────────────────────────

class _LinesTab extends StatelessWidget {
  const _LinesTab({required this.lines, required this.onRemove});
  final List<FavoriteLineItem> lines;
  final void Function(String code) onRemove;

  @override
  Widget build(BuildContext context) {
    final accent = AppThemeUtils.getAccentColor(context, 'blue');
    if (lines.isEmpty) {
      return _EmptyTab(
        icon: Icons.route_rounded,
        title: 'Favori hat yok',
        subtitle: 'Hatlar sekmesinden favorine\nekleyebilirsin.',
        buttonLabel: null,
        accent: accent,
        onAdd: null,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: lines.length,
      itemBuilder: (ctx, i) {
        final item = lines[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FavoriteLineCard(
            routeCode: item.routeCode,
            routeName: item.routeName,
            onRemove: () => onRemove(item.routeCode),
          ),
        );
      },
    );
  }
}

// ─── Shared Helpers ──────────────────────────────────────────────────────────

class _AddButton extends StatelessWidget {
  const _AddButton(
      {required this.label, required this.accent, required this.onTap});
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.accent,
    required this.onAdd,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? buttonLabel;
  final Color accent;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: accent),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppThemeUtils.getSecondaryTextColor(context),
                    height: 1.5,
                  ),
            ),
            if (buttonLabel != null && onAdd != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  buttonLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
