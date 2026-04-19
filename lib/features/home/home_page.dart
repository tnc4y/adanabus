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

  @override
  void initState() {
    super.initState();
    // In widget tests this environment variable is true; in normal app/debug it is false.
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
    if (_warmupRetryCount >= 3) {
      return;
    }
    if (_liveBuses.isNotEmpty) {
      _warmupRetryCount = 0;
      _warmupRetryTimer?.cancel();
      return;
    }

    _warmupRetryTimer?.cancel();
    final delaySeconds = 2 + _warmupRetryCount;
    _warmupRetryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted) {
        return;
      }
      if (_liveBuses.isNotEmpty) {
        return;
      }
      _warmupRetryCount++;
      _refreshDashboard(silent: true);
      _scheduleWarmupRetryIfNeeded();
    });
  }

  Future<void> _refreshDashboard({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _error = null;
      });
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

    if (!mounted) {
      return;
    }

    setState(() {
      if (buses != null) {
        _liveBuses = buses;
      }
      if (stops != null) {
        _allStops = stops;
        _catalogByStopId
          ..clear()
          ..addEntries(stops.map((stop) => MapEntry(stop.stopId, stop)));
      }
      _rebuildNearestStop();

      if (busesError == null && stopsError == null) {
        _error = null;
      } else if (busesError != null && stopsError != null) {
        _error = 'Canli veri alinamadi: $busesError';
      } else if (busesError != null && _liveBuses.isEmpty) {
        _error = 'Canli veri alinamadi: $busesError';
      } else if (stopsError != null && _allStops.isEmpty) {
        _error = 'Durak katalogu alinamadi: $stopsError';
      }
    });

    _scheduleWarmupRetryIfNeeded();
    _refreshHomeApproachingForVisibleStops(silent: true);
  }

  Future<void> _requestPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _position = position;
        _rebuildNearestStop();
      });
    } catch (_) {
      // GPS is optional in the dashboard; keep the page usable without it.
    }
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
    _nearestSummary = StopLiveSummaryService.summarizeStop(
      nearest,
      _liveBuses,
    );
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

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'En yakın durak favorilere eklendi' : 'Durak favorilerden çıkarıldı',
        ),
      ),
    );
  }

  void _openStopPicker() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const StopPickerPage(selectedStopIds: <String>{}),
      ),
    );
  }

  void _openPlanner() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TripPlannerPage()),
    );
  }

  List<_HomeApproachingBus> _buildFallbackApproachingForStop(FavoriteStopItem stop) {
    final list = <_HomeApproachingBus>[];
    for (final bus in _liveBuses) {
      if (!bus.hasLocation) {
        continue;
      }
      final etaMinutes = (GeoMathUtils.distanceMeters(
                bus.latitude!,
                bus.longitude!,
                stop.latitude,
                stop.longitude,
              ) /
              _etaMetersPerMinute)
          .clamp(1, 180)
          .round();
      final routeCode = bus.displayRouteCode.isNotEmpty
          ? bus.displayRouteCode
          : (bus.routeCode.isNotEmpty ? bus.routeCode : '?');
      final vehicle = bus.id.isNotEmpty
          ? bus.id
          : (bus.name.isNotEmpty ? bus.name : '-');
      final direction = bus.direction == '1' ? 'Donus' : 'Gidis';

      list.add(
        _HomeApproachingBus(
          routeCode: routeCode,
          direction: direction,
          etaMinutes: etaMinutes,
          vehicle: vehicle,
        ),
      );
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
          _routeAwareApproachingByStopId = const <String, List<_HomeApproachingBus>>{};
          _isLoadingRouteAwareApproaching = false;
        });
      }
      return;
    }

    if (!silent && mounted) {
      setState(() {
        _isLoadingRouteAwareApproaching = true;
      });
    }

    try {
      if (_catalogByStopId.isEmpty) {
        final catalog = await _apiService.fetchAllStopsCatalog();
        _catalogByStopId
          ..clear()
          ..addEntries(catalog.map((stop) => MapEntry(stop.stopId, stop)));
      }

      final result = <String, List<_HomeApproachingBus>>{};
      for (final stop in stops) {
        final routeAware = await _loadRouteAwareApproachingForStop(stop);
        if (routeAware.isNotEmpty) {
          result[stop.stopId] = routeAware;
        } else {
          // Eğer yeni veri yoksa, eski veriyi tut (null olmayan değerleri)
          final existing = _routeAwareApproachingByStopId[stop.stopId];
          if (existing != null && existing.isNotEmpty) {
            result[stop.stopId] = existing;
          } else {
            // Eğer eski veri de yoksa, fallback'i kullan
            result[stop.stopId] = _buildFallbackApproachingForStop(stop);
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _routeAwareApproachingByStopId = result;
        _isLoadingRouteAwareApproaching = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingRouteAwareApproaching = false;
      });
    }
  }

  Future<List<_HomeApproachingBus>> _loadRouteAwareApproachingForStop(
    FavoriteStopItem stop,
  ) async {
    final routeCodes = _resolveRouteCodesForFavoriteStop(stop);
    if (routeCodes.isEmpty) {
      return const <_HomeApproachingBus>[];
    }

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
            if (path is! Map<String, dynamic>) {
              continue;
            }

            final points = KentkartPathUtils.extractPathPoints(path);
            if (points.length < 2) {
              continue;
            }

            final stopPointIndex = GeoMathUtils.nearestPointIndex(
              points,
              stop.latitude,
              stop.longitude,
            );
            if (stopPointIndex < 0 || stopPointIndex >= points.length - 1) {
              continue;
            }

            final busStopList = KentkartPathUtils.asList(path['busStopList']);
            final selectedStopIdx =
                KentkartPathUtils.findStopIndex(busStopList, stop.stopId);
            if (selectedStopIdx < 0) {
              continue;
            }

            final buses = KentkartPathUtils.extractBuses(path, routeCode, direction);
            for (final bus in buses) {
              if (!bus.hasLocation) {
                continue;
              }

              final busPointIndex = GeoMathUtils.nearestPointIndex(
                points,
                bus.latitude!,
                bus.longitude!,
              );
              if (busPointIndex < 0 || busPointIndex > stopPointIndex) {
                continue;
              }

              final etaMinutes = (GeoMathUtils.distanceMeters(
                        bus.latitude!,
                        bus.longitude!,
                        stop.latitude,
                        stop.longitude,
                      ) /
                      _etaMetersPerMinute)
                  .clamp(1, 180)
                  .round();

              final routeLabel = bus.displayRouteCode.isNotEmpty
                  ? bus.displayRouteCode
                  : (bus.routeCode.isNotEmpty ? bus.routeCode : '?');
              final directionLabel = bus.direction == '1' ? 'Donus' : 'Gidis';
              final vehicleCode = bus.id.isNotEmpty
                  ? bus.id
                  : (bus.name.isNotEmpty ? bus.name : '-');

              final dedupe = '$routeLabel|$directionLabel|$vehicleCode';
              if (!dedupeKeys.add(dedupe)) {
                continue;
              }

              rawApproaching.add(
                _HomeApproachingBus(
                  routeCode: routeLabel,
                  direction: directionLabel,
                  etaMinutes: etaMinutes,
                  vehicle: vehicleCode,
                ),
              );
            }
          }
        } catch (_) {
          continue;
        }
      }
    }

    rawApproaching.sort((a, b) {
      final etaCompare = a.etaMinutes.compareTo(b.etaMinutes);
      if (etaCompare != 0) {
        return etaCompare;
      }
      final routeCompare = a.routeCode.compareTo(b.routeCode);
      if (routeCompare != 0) {
        return routeCompare;
      }
      return a.vehicle.compareTo(b.vehicle);
    });

    return rawApproaching.take(3).toList(growable: false);
  }

  List<String> _resolveRouteCodesForFavoriteStop(FavoriteStopItem stop) {
    final exact = (_catalogByStopId[stop.stopId]?.routes ?? const <String>[])
        .where((route) => route.trim().isNotEmpty)
        .toList(growable: false);
    if (exact.isNotEmpty) {
      return exact.take(8).toList(growable: false);
    }

    TransitStop? nearest;
    var nearestMeters = double.infinity;
    for (final candidate in _catalogByStopId.values) {
      final meters = GeoMathUtils.distanceMeters(
        stop.latitude,
        stop.longitude,
        candidate.latitude,
        candidate.longitude,
      );
      if (meters < nearestMeters) {
        nearest = candidate;
        nearestMeters = meters;
      }
    }

    if (nearest == null || nearestMeters > 180) {
      return const <String>[];
    }

    return nearest.routes
        .where((route) => route.trim().isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.favoritesController,
      builder: (context, _) {
        final entries = widget.favoritesController.homeEntries;
        final stopSignature = entries
            .where((entry) => entry.kind == FavoriteHomeEntryKind.stop)
            .map((entry) => entry.stop?.stopId ?? '')
            .join('|');
        if (stopSignature != _homeStopEntrySignature) {
          _homeStopEntrySignature = stopSignature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _refreshHomeApproachingForVisibleStops(silent: true);
            }
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('AdanaBus'),
          ),
          body: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              gradient: Theme.of(context).brightness == Brightness.dark
                  ? null
                  : const LinearGradient(
                      colors: [Color(0xFFF3F8FF), Color(0xFFE7F0FF), Color(0xFFF8FBFF)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
            ),
            child: SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  await _refreshDashboard();
                  await _requestPosition();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  children: [
                    Row(
                      children: [
                        Text(
                          'Favoriler',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          '${entries.length}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppThemeUtils.getSecondaryTextColor(context),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (entries.isEmpty)
                      _EmptyFavoritesHero(
                        onOpenLines: widget.onOpenLines,
                        onOpenFavorites: widget.onOpenFavorites,
                      )
                    else if (_editMode)
                      Column(
                        children: [
                          _ReorderFavoritesList(
                            entries: entries,
                            onReorder: widget.favoritesController.reorderHomeEntry,
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _editMode = false;
                                });
                              },
                              icon: const Icon(Icons.check),
                              label: const Text('Bitti'),
                            ),
                          ),
                        ],
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final cardWidth = (constraints.maxWidth / 2.2).clamp(150.0, 220.0);
                          final cardHeight = 206.0;
                          return SizedBox(
                            height: cardHeight,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: entries.length + 1,
                              separatorBuilder: (_, __) => const SizedBox(width: 10),
                              itemBuilder: (context, index) {
                                if (index == entries.length) {
                                  return SizedBox(
                                    width: cardWidth,
                                    child: _CarouselManageCard(
                                      onTap: () {
                                        setState(() {
                                          _editMode = true;
                                        });
                                      },
                                    ),
                                  );
                                }
                                final entry = entries[index];
                                return SizedBox(
                                  width: cardWidth,
                                  child: _FavoriteMiniCarouselCard(
                                    entry: entry,
                                    liveSummary: entry.kind == FavoriteHomeEntryKind.stop
                                        ? StopLiveSummaryService.summarizeStop(
                                            _favoriteStopToTransitStop(entry.stop!),
                                            _liveBuses,
                                          )
                                        : null,
                                    approachingBuses: entry.kind == FavoriteHomeEntryKind.stop
                                        ? (_routeAwareApproachingByStopId[entry.stop!.stopId] ??
                                            _buildFallbackApproachingForStop(entry.stop!))
                                        : const <_HomeApproachingBus>[],
                                    onTap: () => _openFavoriteEntry(entry),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    if (_isLoadingRouteAwareApproaching)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    const SizedBox(height: 18),
                    _QuickActionsRow(
                      onOpenPlanner: _openPlanner,
                      onOpenStops: _openStopPicker,
                      onOpenFavorites: widget.onOpenFavorites,
                      onRefreshGps: _requestPosition,
                    ),
                    const SizedBox(height: 20),
                    if (_nearestStop != null)
                      _NearestStopCard(
                        stop: _nearestStop!,
                        summary: _nearestSummary,
                        onAdd: _addNearestStopToFavorites,
                        onOpenStop: () {
                          Navigator.of(context).push(
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
                          );
                        },
                      ),
                    const SizedBox(height: 14),
                    if (_error != null)
                      _InlineErrorCard(message: _error!),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openFavoriteEntry(FavoriteHomeEntry entry) {
    switch (entry.kind) {
      case FavoriteHomeEntryKind.line:
        final line = entry.line;
        if (line == null) {
          widget.onOpenLines();
          break;
        }
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => LineDetailPage(
              routeCode: line.routeCode,
              routeName: line.routeName,
              direction: '0',
            ),
          ),
        );
        break;
      case FavoriteHomeEntryKind.stop:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StopDetailPage(
              favoriteStop: entry.stop!,
            ),
          ),
        );
        break;
      case FavoriteHomeEntryKind.route:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FavoriteRouteDetailPage(item: entry.route!),
          ),
        );
        break;
    }
  }

  TransitStop _favoriteStopToTransitStop(FavoriteStopItem stop) {
    return TransitStop(
      stopId: stop.stopId,
      stopName: stop.stopName,
      latitude: stop.latitude,
      longitude: stop.longitude,
      routes: const <String>[],
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
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
          child: _ActionButton(
            icon: Icons.route,
            label: 'Rota Belirle',
            onTap: onOpenPlanner,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.place_outlined,
            label: 'Duraklar',
            onTap: onOpenStops,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.star,
            label: 'Favoriler',
            onTap: onOpenFavorites,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.gps_fixed,
            label: 'GPS',
            onTap: () => onRefreshGps(),
          ),
        ),
      ],
    );
  }
}

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

class _FavoriteMiniCarouselCard extends StatelessWidget {
  const _FavoriteMiniCarouselCard({
    required this.entry,
    required this.onTap,
    required this.liveSummary,
    required this.approachingBuses,
  });

  final FavoriteHomeEntry entry;
  final VoidCallback onTap;
  final StopLiveSummary? liveSummary;
  final List<_HomeApproachingBus> approachingBuses;

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

class _ReorderFavoritesList extends StatelessWidget {
  const _ReorderFavoritesList({
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
              trailing: _KindBadge(kind: entry.kind),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyFavoritesHero extends StatelessWidget {
  const _EmptyFavoritesHero({
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

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

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

class _ActionButton extends StatelessWidget {
  const _ActionButton({
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

class _CarouselManageCard extends StatelessWidget {
  const _CarouselManageCard({required this.onTap});

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
              const Text(
                'Favorileri\nDüzenle',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: Color(0xFF0A4FB5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineErrorCard extends StatelessWidget {
  const _InlineErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1EE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message),
    );
  }
}

double mathMax(double a, double b) => a > b ? a : b;
