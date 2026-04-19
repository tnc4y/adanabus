import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/theme_utils.dart';
import '../../data/models/bus_vehicle.dart';
import '../../data/models/transit_stop.dart';
import '../../data/services/adana_api_service.dart';
import '../favorites/favorite_home_entry.dart';
import '../favorites/favorite_route_detail_page.dart';
import '../favorites/favorite_stop_item.dart';
import '../favorites/favorites_controller.dart';
import '../lines/line_detail_page.dart';
import '../lines/trip_planner_page.dart';
import '../shared/geo_math_utils.dart';
import '../shared/kentkart_path_utils.dart';
import '../shared/stop_live_summary_service.dart';
import '../stops/stop_detail_page.dart';
import '../stops/stop_picker_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.favoritesController,
    required this.onOpenLines,
    required this.onOpenFavorites,
  });

  final FavoritesController favoritesController;
  final VoidCallback onOpenLines;
  final VoidCallback onOpenFavorites;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AdanaApiService _apiService = AdanaApiService();
  static const double _etaMetersPerMinute = 320;

  bool _editMode = false;
  String? _error;
  Timer? _refreshTimer;
  Timer? _warmupRetryTimer;
  int _warmupRetryCount = 0;

  List<BusVehicle> _liveBuses = <BusVehicle>[];
  List<TransitStop> _allStops = <TransitStop>[];
  final Map<String, TransitStop> _catalogByStopId = <String, TransitStop>{};
  Map<String, List<_HomeApproachingBus>> _routeAwareApproachingByStopId =
      const <String, List<_HomeApproachingBus>>{};
  bool _isLoadingRouteAwareApproaching = false;
  String _homeStopEntrySignature = '';
  Position? _position;
  TransitStop? _nearestStop;
  StopLiveSummary? _nearestSummary;
  DateTime? _lastRefreshed;

  @override
  void initState() {
    super.initState();
    final isWidgetTest = const bool.fromEnvironment('FLUTTER_TEST');
    if (!isWidgetTest) {
      _refreshDashboard();
      _requestPosition();
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 35),
        (_) {
          _refreshDashboard(silent: true);
          _refreshHomeApproachingForVisibleStops(silent: true);
        },
      );
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _warmupRetryTimer?.cancel();
    super.dispose();
  }

  void _scheduleWarmupRetryIfNeeded() {
    if (_warmupRetryCount >= 3) return;
    if (_liveBuses.isNotEmpty) {
      _warmupRetryCount = 0;
      _warmupRetryTimer?.cancel();
      return;
    }
    _warmupRetryTimer?.cancel();
    final delaySeconds = 2 + _warmupRetryCount;
    _warmupRetryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted) return;
      if (_liveBuses.isNotEmpty) return;
      _warmupRetryCount++;
      _refreshDashboard(silent: true);
      _scheduleWarmupRetryIfNeeded();
    });
  }

  Future<void> _refreshDashboard({bool silent = false}) async {
    if (!silent) {
      setState(() => _error = null);
    }

    List<BusVehicle>? buses;
    List<TransitStop>? stops;
    String? busesError;
    String? stopsError;

    try {
      buses = await _apiService.fetchBuses();
    } catch (error) {
      busesError = error.toString();
    }

    try {
      stops = await _apiService.fetchAllStopsCatalog();
    } catch (error) {
      stopsError = error.toString();
    }

    if (!mounted) return;

    setState(() {
      if (buses != null) _liveBuses = buses;
      if (stops != null) {
        _allStops = stops;
        _catalogByStopId
          ..clear()
          ..addEntries(stops.map((s) => MapEntry(s.stopId, s)));
      }
      _rebuildNearestStop();
      _lastRefreshed = DateTime.now();

      if (busesError == null && stopsError == null) {
        _error = null;
      } else if (busesError != null && stopsError != null) {
        _error = 'Canlı veri alınamadı: $busesError';
      } else if (busesError != null && _liveBuses.isEmpty) {
        _error = 'Canlı veri alınamadı: $busesError';
      } else if (stopsError != null && _allStops.isEmpty) {
        _error = 'Durak kataloğu alınamadı: $stopsError';
      }
    });

    _scheduleWarmupRetryIfNeeded();
    _refreshHomeApproachingForVisibleStops(silent: true);
  }

  Future<void> _requestPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (!mounted) return;
      setState(() {
        _position = position;
        _rebuildNearestStop();
      });
    } catch (_) {}
  }

  void _rebuildNearestStop() {
    if (_position == null || _allStops.isEmpty) {
      _nearestStop = null;
      _nearestSummary = null;
      return;
    }
    final nearest = StopLiveSummaryService.findNearestStop(_position!, _allStops);
    if (nearest == null) {
      _nearestStop = null;
      _nearestSummary = null;
      return;
    }
    _nearestStop = nearest;
    _nearestSummary = StopLiveSummaryService.summarizeStop(nearest, _liveBuses);
  }

  Future<void> _addNearestStopToFavorites() async {
    final nearest = _nearestStop;
    if (nearest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yakın durak bulunamadı.')),
      );
      return;
    }
    final added = widget.favoritesController.toggleFavoriteStop(
      FavoriteStopItem(
        stopId: nearest.stopId,
        stopName: nearest.stopName,
        latitude: nearest.latitude,
        longitude: nearest.longitude,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'En yakın durak favorilere eklendi' : 'Durak favorilerden çıkarıldı',
        ),
      ),
    );
  }

  void _openStopPicker() => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const StopPickerPage(selectedStopIds: <String>{}),
        ),
      );

  void _openPlanner() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TripPlannerPage()),
      );

  List<_HomeApproachingBus> _buildFallbackApproachingForStop(FavoriteStopItem stop) {
    final list = <_HomeApproachingBus>[];
    for (final bus in _liveBuses) {
      if (!bus.hasLocation) continue;
      final etaMinutes = (GeoMathUtils.distanceMeters(
                    bus.latitude!, bus.longitude!, stop.latitude, stop.longitude,
                  ) /
                  _etaMetersPerMinute)
              .clamp(1, 180)
              .round();
      final routeCode = bus.displayRouteCode.isNotEmpty
          ? bus.displayRouteCode
          : (bus.routeCode.isNotEmpty ? bus.routeCode : '?');
      final vehicle = bus.id.isNotEmpty ? bus.id : (bus.name.isNotEmpty ? bus.name : '-');
      final direction = bus.direction == '1' ? 'Dönüş' : 'Gidiş';
      list.add(_HomeApproachingBus(
        routeCode: routeCode,
        direction: direction,
        etaMinutes: etaMinutes,
        vehicle: vehicle,
      ));
    }
    list.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
    return list.take(3).toList(growable: false);
  }

  Future<void> _refreshHomeApproachingForVisibleStops({bool silent = false}) async {
    final stops = widget.favoritesController.homeEntries
        .where((entry) => entry.kind == FavoriteHomeEntryKind.stop)
        .map((entry) => entry.stop)
        .whereType<FavoriteStopItem>()
        .toList(growable: false);

    if (stops.isEmpty) {
      if (mounted) {
        setState(() {
          _routeAwareApproachingByStopId = const {};
          _isLoadingRouteAwareApproaching = false;
        });
      }
      return;
    }

    if (!silent && mounted) setState(() => _isLoadingRouteAwareApproaching = true);

    try {
      if (_catalogByStopId.isEmpty) {
        final catalog = await _apiService.fetchAllStopsCatalog();
        _catalogByStopId
          ..clear()
          ..addEntries(catalog.map((s) => MapEntry(s.stopId, s)));
      }

      final result = <String, List<_HomeApproachingBus>>{};
      for (final stop in stops) {
        final routeAware = await _loadRouteAwareApproachingForStop(stop);
        if (routeAware.isNotEmpty) {
          result[stop.stopId] = routeAware;
        } else {
          final existing = _routeAwareApproachingByStopId[stop.stopId];
          if (existing != null && existing.isNotEmpty) {
            result[stop.stopId] = existing;
          } else {
            result[stop.stopId] = _buildFallbackApproachingForStop(stop);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _routeAwareApproachingByStopId = result;
        _isLoadingRouteAwareApproaching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingRouteAwareApproaching = false);
    }
  }

  Future<List<_HomeApproachingBus>> _loadRouteAwareApproachingForStop(
    FavoriteStopItem stop,
  ) async {
    final routeCodes = _resolveRouteCodesForFavoriteStop(stop);
    if (routeCodes.isEmpty) return const [];

    final rawApproaching = <_HomeApproachingBus>[];
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
              final busPointIndex =
                  GeoMathUtils.nearestPointIndex(points, bus.latitude!, bus.longitude!);
              if (busPointIndex < 0 || busPointIndex > stopPointIndex) continue;

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
              final vehicleCode = bus.id.isNotEmpty ? bus.id : (bus.name.isNotEmpty ? bus.name : '-');
              final dedupe = '$routeLabel|$directionLabel|$vehicleCode';
              if (!dedupeKeys.add(dedupe)) continue;

              rawApproaching.add(_HomeApproachingBus(
                routeCode: routeLabel,
                direction: directionLabel,
                etaMinutes: etaMinutes,
                vehicle: vehicleCode,
              ));
            }
          }
        } catch (_) {
          continue;
        }
      }
    }

    rawApproaching.sort((a, b) {
      final etaCompare = a.etaMinutes.compareTo(b.etaMinutes);
      if (etaCompare != 0) return etaCompare;
      final routeCompare = a.routeCode.compareTo(b.routeCode);
      if (routeCompare != 0) return routeCompare;
      return a.vehicle.compareTo(b.vehicle);
    });

    return rawApproaching.take(3).toList(growable: false);
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
        stop.latitude, stop.longitude, candidate.latitude, candidate.longitude,
      );
      if (meters < nearestMeters) {
        nearest = candidate;
        nearestMeters = meters;
      }
    }

    if (nearest == null || nearestMeters > 180) return const [];
    return nearest.routes.where((r) => r.trim().isNotEmpty).take(8).toList(growable: false);
  }

  void _openFavoriteEntry(FavoriteHomeEntry entry) {
    switch (entry.kind) {
      case FavoriteHomeEntryKind.line:
        final line = entry.line;
        if (line == null) {
          widget.onOpenLines();
          break;
        }
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => LineDetailPage(
            routeCode: line.routeCode,
            routeName: line.routeName,
            direction: '0',
          ),
        ));
        break;
      case FavoriteHomeEntryKind.stop:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => StopDetailPage(favoriteStop: entry.stop!),
        ));
        break;
      case FavoriteHomeEntryKind.route:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FavoriteRouteDetailPage(item: entry.route!),
        ));
        break;
    }
  }

  String _greetingText() {
    final hour = DateTime.now().hour;
    if (hour < 6) return 'İyi geceler';
    if (hour < 12) return 'Günaydın';
    if (hour < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.favoritesController,
      builder: (context, _) {
        final entries = widget.favoritesController.homeEntries;
        final stopSignature = entries
            .where((e) => e.kind == FavoriteHomeEntryKind.stop)
            .map((e) => e.stop?.stopId ?? '')
            .join('|');
        if (stopSignature != _homeStopEntrySignature) {
          _homeStopEntrySignature = stopSignature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _refreshHomeApproachingForVisibleStops(silent: true);
          });
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primaryBlue = AppThemeUtils.getAccentColor(context, 'blue');

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: RefreshIndicator(
            onRefresh: () async {
              await _refreshDashboard();
              await _requestPosition();
            },
            child: CustomScrollView(
              slivers: [
                // ── Hero Header ──────────────────────────────────────────
                SliverToBoxAdapter(
                  child: _HeroHeader(
                    greeting: _greetingText(),
                    liveBusCount: _liveBuses.length,
                    lastRefreshed: _lastRefreshed,
                    isDark: isDark,
                    primaryBlue: primaryBlue,
                  ),
                ),

                // ── Quick Actions ────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _QuickActionsGrid(
                      onOpenPlanner: _openPlanner,
                      onOpenStops: _openStopPicker,
                      onOpenFavorites: widget.onOpenFavorites,
                      onRefreshGps: _requestPosition,
                    ),
                  ),
                ),

                // ── Favoriler ────────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: _SectionHeader(
                      title: 'Favorilerim',
                      trailing: entries.isEmpty
                          ? null
                          : _editMode
                              ? TextButton.icon(
                                  onPressed: () => setState(() => _editMode = false),
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('Bitti'),
                                )
                              : TextButton.icon(
                                  onPressed: () => setState(() => _editMode = true),
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('Düzenle'),
                                ),
                    ),
                  ),
                ),

                if (entries.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _EmptyFavoritesCard(
                        onOpenLines: widget.onOpenLines,
                        onOpenFavorites: widget.onOpenFavorites,
                      ),
                    ),
                  )
                else if (_editMode)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _ReorderFavoritesList(
                        entries: entries,
                        onReorder: widget.favoritesController.reorderHomeEntry,
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        if (_isLoadingRouteAwareApproaching)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final cardW =
                                (constraints.maxWidth / 2.1).clamp(160.0, 230.0);
                            return SizedBox(
                              height: 200,
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                scrollDirection: Axis.horizontal,
                                itemCount: entries.length + 1,
                                separatorBuilder: (_, __) => const SizedBox(width: 10),
                                itemBuilder: (ctx, i) {
                                  if (i == entries.length) {
                                    return SizedBox(
                                      width: cardW * 0.7,
                                      child: _AddMoreCard(
                                        onTap: () => setState(() => _editMode = true),
                                      ),
                                    );
                                  }
                                  final entry = entries[i];
                                  return SizedBox(
                                    width: cardW,
                                    child: _FavoriteCard(
                                      entry: entry,
                                      approachingBuses: entry.kind ==
                                              FavoriteHomeEntryKind.stop
                                          ? (_routeAwareApproachingByStopId[
                                                  entry.stop!.stopId] ??
                                              _buildFallbackApproachingForStop(
                                                  entry.stop!))
                                          : const [],
                                      onTap: () => _openFavoriteEntry(entry),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                // ── En Yakın Durak ───────────────────────────────────────
                if (_nearestStop != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          const _SectionHeader(title: 'En Yakın Durak'),
                          const SizedBox(height: 10),
                          _NearestStopCard(
                            stop: _nearestStop!,
                            summary: _nearestSummary,
                            onAdd: _addNearestStopToFavorites,
                            onOpenStop: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => StopDetailPage(
                                  favoriteStop: FavoriteStopItem(
                                    stopId: _nearestStop!.stopId,
                                    stopName: _nearestStop!.stopName,
                                    latitude: _nearestStop!.latitude,
                                    longitude: _nearestStop!.longitude,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Error ────────────────────────────────────────────────
                if (_error != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: _ErrorBanner(
                        message: _error!,
                        onDismiss: () => setState(() => _error = null),
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Header
// ─────────────────────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.greeting,
    required this.liveBusCount,
    required this.lastRefreshed,
    required this.isDark,
    required this.primaryBlue,
  });

  final String greeting;
  final int liveBusCount;
  final DateTime? lastRefreshed;
  final bool isDark;
  final Color primaryBlue;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(20, topPad + 16, 20, 24),
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
                colors: [const Color(0xFF0D1B2E), const Color(0xFF0C1118)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: [const Color(0xFF164B9D), const Color(0xFF1E6DD5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Logo/brand
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              const Text(
                'AdanaBus',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              // Live badge
              if (liveBusCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4ADE80),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$liveBusCount araç',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            greeting,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Nereye gitmek\nistiyorsunuz?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
              letterSpacing: -0.5,
            ),
          ),
          if (lastRefreshed != null) ...[
            const SizedBox(height: 10),
            Text(
              'Son güncelleme: ${_formatTime(lastRefreshed!)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Actions Grid (2×2)
// ─────────────────────────────────────────────────────────────────────────────

class _QuickActionsGrid extends StatelessWidget {
  const _QuickActionsGrid({
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
    final actions = [
      _ActionDef(
        icon: Icons.alt_route_rounded,
        label: 'Rota Planla',
        color: const Color(0xFF164B9D),
        bgColor: const Color(0xFFEBF2FF),
        darkBgColor: const Color(0xFF1A2A40),
        onTap: onOpenPlanner,
      ),
      _ActionDef(
        icon: Icons.place_rounded,
        label: 'Duraklar',
        color: const Color(0xFF0B5A25),
        bgColor: const Color(0xFFE8F5EE),
        darkBgColor: const Color(0xFF102018),
        onTap: onOpenStops,
      ),
      _ActionDef(
        icon: Icons.star_rounded,
        label: 'Favoriler',
        color: const Color(0xFFB63519),
        bgColor: const Color(0xFFFFF0EC),
        darkBgColor: const Color(0xFF2A1510),
        onTap: onOpenFavorites,
      ),
      _ActionDef(
        icon: Icons.my_location_rounded,
        label: 'Konumum',
        color: const Color(0xFF7B5EA7),
        bgColor: const Color(0xFFF3EEFF),
        darkBgColor: const Color(0xFF1E1530),
        onTap: () => onRefreshGps(),
      ),
    ];

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.85,
      children: actions.map((a) {
        final bg = isDark ? a.darkBgColor : a.bgColor;
        return Material(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: a.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: a.color.withValues(alpha: isDark ? 0.2 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(a.icon, color: a.color, size: 20),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    a.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppThemeUtils.getTextColor(context)
                          : const Color(0xFF1A2840),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ActionDef {
  const _ActionDef({
    required this.icon,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.darkBgColor,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final Color bgColor;
  final Color darkBgColor;
  final VoidCallback onTap;
}

// ─────────────────────────────────────────────────────────────────────────────
// Favorite Card
// ─────────────────────────────────────────────────────────────────────────────

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({
    required this.entry,
    required this.approachingBuses,
    required this.onTap,
  });

  final FavoriteHomeEntry entry;
  final List<_HomeApproachingBus> approachingBuses;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isStop = entry.kind == FavoriteHomeEntryKind.stop;
    final isLine = entry.kind == FavoriteHomeEntryKind.line;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color accent = isStop
        ? AppThemeUtils.getAccentColor(context, 'green')
        : isLine
            ? AppThemeUtils.getAccentColor(context, 'blue')
            : AppThemeUtils.getAccentColor(context, 'orange');

    final IconData icon = isStop
        ? Icons.directions_bus_rounded
        : isLine
            ? Icons.route_rounded
            : Icons.map_rounded;

    final String typeLabel = isStop ? 'Durak' : isLine ? 'Hat' : 'Rota';
    final String title = isLine ? (entry.line?.routeCode ?? entry.title) : entry.title;
    final String subtitle = isLine ? (entry.line?.routeName ?? entry.subtitle) : entry.subtitle;

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
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.25 : 0.18),
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type badge row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: accent, size: 16),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      typeLabel,
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Title
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppThemeUtils.getSecondaryTextColor(context),
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
              ),
              const Spacer(),
              // ETA chips for stops
              if (isStop)
                _EtaChipRow(buses: approachingBuses, accent: accent)
              else
                Row(
                  children: [
                    Icon(Icons.arrow_forward_rounded, size: 13, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      isLine ? 'Detaya git' : 'Rotayı gör',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
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

class _EtaChipRow extends StatelessWidget {
  const _EtaChipRow({required this.buses, required this.accent});
  final List<_HomeApproachingBus> buses;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (buses.isEmpty) {
      return Text(
        'Araç bekleniyor…',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppThemeUtils.getSecondaryTextColor(context),
        ),
      );
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: buses.take(3).map((bus) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${bus.routeCode} · ${bus.etaMinutes}dk',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add More Card
// ─────────────────────────────────────────────────────────────────────────────

class _AddMoreCard extends StatelessWidget {
  const _AddMoreCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppThemeUtils.getAccentColor(context, 'blue');
    return Material(
      color: AppThemeUtils.getSubtleBackgroundColor(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accent.withValues(alpha: 0.15),
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add_rounded, color: accent, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                'Düzenle',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Nearest Stop Card
// ─────────────────────────────────────────────────────────────────────────────

class _NearestStopCard extends StatelessWidget {
  const _NearestStopCard({
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
    final green = AppThemeUtils.getAccentColor(context, 'green');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: AppThemeUtils.getCardColor(context),
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      child: InkWell(
        onTap: onOpenStop,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: green.withValues(alpha: isDark ? 0.25 : 0.2),
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.near_me_rounded, color: green, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop.stopName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          'Durak #${stop.stopId}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppThemeUtils.getSecondaryTextColor(context),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (summary != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions_bus_rounded, size: 13, color: green),
                          const SizedBox(width: 4),
                          Text(
                            '${summary!.liveBusCount}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: green,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (stop.routes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: stop.routes.take(6).map((r) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppThemeUtils.getSubtleBackgroundColor(context),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppThemeUtils.getBorderColor(context)),
                    ),
                    child: Text(
                      r,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  )).toList(),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onAdd,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: green,
                        side: BorderSide(color: green.withValues(alpha: 0.4)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.star_outline_rounded, size: 16),
                      label: const Text(
                        'Favorile',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onOpenStop,
                      style: FilledButton.styleFrom(
                        backgroundColor: green,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text(
                        'Detay',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Empty Favorites Card
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyFavoritesCard extends StatelessWidget {
  const _EmptyFavoritesCard({
    required this.onOpenLines,
    required this.onOpenFavorites,
  });
  final VoidCallback onOpenLines;
  final VoidCallback onOpenFavorites;

  @override
  Widget build(BuildContext context) {
    final accent = AppThemeUtils.getAccentColor(context, 'blue');
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppThemeUtils.getCardColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppThemeUtils.getBorderColor(context)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.star_outline_rounded, size: 32, color: accent),
          ),
          const SizedBox(height: 14),
          Text(
            'Henüz favori eklenmedi',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Sık kullandığın durakları, hatları\nve rotaları buraya ekleyebilirsin.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppThemeUtils.getSecondaryTextColor(context),
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpenFavorites,
                  icon: const Icon(Icons.star_outline_rounded, size: 16),
                  label: const Text('Favoriler'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpenLines,
                  icon: const Icon(Icons.route_rounded, size: 16),
                  label: const Text('Hatlara git'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reorder Favorites List
// ─────────────────────────────────────────────────────────────────────────────

class _ReorderFavoritesList extends StatelessWidget {
  const _ReorderFavoritesList({required this.entries, required this.onReorder});
  final List<FavoriteHomeEntry> entries;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: (entries.length * 72.0).clamp(200.0, 500.0),
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: entries.length,
        onReorder: onReorder,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final isStop = entry.kind == FavoriteHomeEntryKind.stop;
          final isLine = entry.kind == FavoriteHomeEntryKind.line;
          final accent = isStop
              ? AppThemeUtils.getAccentColor(context, 'green')
              : isLine
                  ? AppThemeUtils.getAccentColor(context, 'blue')
                  : AppThemeUtils.getAccentColor(context, 'orange');
          return Container(
            key: ValueKey(entry.key),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppThemeUtils.getCardColor(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppThemeUtils.getBorderColor(context)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isStop ? Icons.place_rounded : isLine ? Icons.route_rounded : Icons.map_rounded,
                  color: accent,
                  size: 16,
                ),
              ),
              title: Text(
                entry.title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              subtitle: Text(
                entry.subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: AppThemeUtils.getSecondaryTextColor(context),
                ),
              ),
              trailing: ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_indicator_rounded,
                  color: AppThemeUtils.getSecondaryTextColor(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error Banner
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1EE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD0C8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB63519), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7A2010),
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFFB63519)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data class
// ─────────────────────────────────────────────────────────────────────────────

class _HomeApproachingBus {
  const _HomeApproachingBus({
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
