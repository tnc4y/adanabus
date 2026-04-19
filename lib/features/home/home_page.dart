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
import 'home_widgets.dart';

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
  Map<String, List<HomeApproachingBus>> _routeAwareApproachingByStopId =
      const <String, List<HomeApproachingBus>>{};
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

  List<HomeApproachingBus> _buildFallbackApproachingForStop(FavoriteStopItem stop) {
    final list = <HomeApproachingBus>[];
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
        HomeApproachingBus(
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
          _routeAwareApproachingByStopId = const <String, List<HomeApproachingBus>>{};
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

      final result = <String, List<HomeApproachingBus>>{};
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

  Future<List<HomeApproachingBus>> _loadRouteAwareApproachingForStop(
    FavoriteStopItem stop,
  ) async {
    final routeCodes = _resolveRouteCodesForFavoriteStop(stop);
    if (routeCodes.isEmpty) {
      return const <HomeApproachingBus>[];
    }

    final rawApproaching = <HomeApproachingBus>[];
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
                HomeApproachingBus(
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
            decoration: Theme.of(context).brightness == Brightness.dark
                ? BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor)
                : const BoxDecoration(
                    gradient: LinearGradient(
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
                      HomeEmptyFavoritesHero(
                        onOpenLines: widget.onOpenLines,
                        onOpenFavorites: widget.onOpenFavorites,
                      )
                    else if (_editMode)
                      Column(
                        children: [
                          HomeReorderFavoritesList(
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
                                    child: HomeCarouselManageCard(
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
                                  child: HomeFavoriteMiniCarouselCard(
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
                                        : const <HomeApproachingBus>[],
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
                    HomeQuickActionsRow(
                      onOpenPlanner: _openPlanner,
                      onOpenStops: _openStopPicker,
                      onOpenFavorites: widget.onOpenFavorites,
                      onRefreshGps: _requestPosition,
                    ),
                    const SizedBox(height: 20),
                    if (_nearestStop != null)
                      HomeNearestStopCard(
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
                      HomeInlineErrorCard(message: _error!),
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
