import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/bus_vehicle.dart';
import '../../data/models/transit_stop.dart';
import '../../data/services/adana_api_service.dart';
import '../shared/geo_math_utils.dart';
import '../shared/kentkart_path_utils.dart';
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
  });

  final FavoritesController favoritesController;

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final AdanaApiService _apiService = AdanaApiService();
  static const double _etaMetersPerMinute = 320;
  final Map<String, TransitStop> _catalogByStopId = <String, TransitStop>{};
  Map<String, List<FavApproachingBusInfo>> _approachingByStopId =
      const <String, List<FavApproachingBusInfo>>{};
  bool _isLoadingApproaching = false;
  String _stopSignature = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshApproachingData();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _refreshApproachingData(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshApproachingData({bool silent = false}) async {
    final stops = widget.favoritesController.favoriteStops;
    if (stops.isEmpty) {
      if (mounted) {
        setState(() {
          _approachingByStopId = const <String, List<FavApproachingBusInfo>>{};
          _isLoadingApproaching = false;
        });
      }
      return;
    }

    if (!silent && mounted) {
      setState(() {
        _isLoadingApproaching = true;
      });
    }

    try {
      final globalBuses = await _apiService.fetchBuses();
      final catalog = await _apiService.fetchAllStopsCatalog();
      _catalogByStopId
        ..clear()
        ..addEntries(catalog.map((stop) => MapEntry(stop.stopId, stop)));

      final fallback = <String, List<FavApproachingBusInfo>>{};
      for (final stop in stops) {
        fallback[stop.stopId] = _buildFallbackApproachingFromGlobal(
          stop: stop,
          buses: globalBuses,
        );
      }

      if (mounted) {
        // Show fallback quickly while route-aware pathInfo details load.
        setState(() {
          _approachingByStopId = fallback;
        });
      }

      final result = <String, List<FavApproachingBusInfo>>{};
      for (final stop in stops) {
        final routeAware = await _loadApproachingForStop(stop);
        result[stop.stopId] = routeAware.isNotEmpty
            ? routeAware
            : (fallback[stop.stopId] ?? const <FavApproachingBusInfo>[]);
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _approachingByStopId = result;
        _isLoadingApproaching = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingApproaching = false;
      });
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Favori duraklar icin canli veri alinamadi.')),
        );
      }
    }
  }

  Future<List<FavApproachingBusInfo>> _loadApproachingForStop(
    FavoriteStopItem stop,
  ) async {
    final routeCodes = _resolveRouteCodesForFavoriteStop(stop);

    if (routeCodes.isEmpty) {
      return const <FavApproachingBusInfo>[];
    }

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
              // This direction does not pass selected stop.
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
                // Ignore buses that already passed the stop.
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
                  : bus.routeCode;
              final vehicleCode = bus.id.isNotEmpty
                  ? bus.id
                  : (bus.name.isNotEmpty ? bus.name : '-');
              final directionLabel = bus.direction == '1' ? 'Donus' : 'Gidis';

              final dedupe = '$routeLabel|$directionLabel|$vehicleCode';
              if (!dedupeKeys.add(dedupe)) {
                continue;
              }

              rawApproaching.add(
                FavApproachingBusInfo(
                  etaMinutes: etaMinutes,
                  routeCode: routeLabel.isEmpty ? '?' : routeLabel,
                  vehicleCode: vehicleCode,
                  direction: directionLabel,
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
      final routeLabel = bus.displayRouteCode.isNotEmpty
          ? bus.displayRouteCode
          : (bus.routeCode.isNotEmpty ? bus.routeCode : '?');
      final directionLabel = bus.direction == '1' ? 'Donus' : 'Gidis';
      final vehicleCode = bus.id.isNotEmpty
          ? bus.id
          : (bus.name.isNotEmpty ? bus.name : '-');
      list.add(
        FavApproachingBusInfo(
          etaMinutes: etaMinutes,
          routeCode: routeLabel,
          vehicleCode: vehicleCode,
          direction: directionLabel,
        ),
      );
    }

    list.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
    return list.take(3).toList(growable: false);
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

  List<FavApproachingBusInfo> _buildApproachingBuses(FavoriteStopItem stop) {
    return _approachingByStopId[stop.stopId] ?? const <FavApproachingBusInfo>[];
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.favoritesController,
      builder: (context, _) {
        final lines = widget.favoritesController.favoriteLines;
        final stops = widget.favoritesController.favoriteStops;
        final routes = widget.favoritesController.favoriteRoutes;
        final currentSignature = stops.map((stop) => stop.stopId).join('|');
        if (currentSignature != _stopSignature) {
          _stopSignature = currentSignature;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _refreshApproachingData(silent: true);
            }
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Favoriler'),
            actions: [
              IconButton(
                onPressed: _refreshApproachingData,
                icon: const Icon(Icons.refresh),
                tooltip: 'Canli veriyi yenile',
              ),
              if (lines.isNotEmpty)
                IconButton(
                  onPressed: widget.favoritesController.clearFavoriteLines,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Tumunu temizle',
                ),
              if (stops.isNotEmpty)
                IconButton(
                  onPressed: widget.favoritesController.clearFavoriteStops,
                  icon: const Icon(Icons.location_off_outlined),
                  tooltip: 'Tum durak favorilerini temizle',
                ),
              if (routes.isNotEmpty)
                IconButton(
                  onPressed: widget.favoritesController.clearFavoriteRoutes,
                  icon: const Icon(Icons.alt_route_outlined),
                  tooltip: 'Tum kayitli rotalari temizle',
                ),
            ],
          ),
          body: !widget.favoritesController.isReady
              ? const Center(child: CircularProgressIndicator())
              : lines.isEmpty && stops.isEmpty && routes.isEmpty
                  ? const FavEmptyState()
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Kayitli Rotalar',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final startStop =
                                    await Navigator.of(context).push<TransitStop>(
                                  MaterialPageRoute(
                                    builder: (_) => const StopPickerPage(
                                      selectedStopIds: <String>{},
                                    ),
                                  ),
                                );
                                if (startStop == null || !context.mounted) {
                                  return;
                                }

                                final endStop =
                                    await Navigator.of(context).push<TransitStop>(
                                  MaterialPageRoute(
                                    builder: (_) => StopPickerPage(
                                      selectedStopIds: <String>{
                                        startStop.stopId,
                                      },
                                    ),
                                  ),
                                );
                                if (endStop == null || !context.mounted) {
                                  return;
                                }

                                if (startStop.stopId == endStop.stopId) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Baslangic ve varis ayni olamaz.'),
                                    ),
                                  );
                                  return;
                                }

                                final added = widget.favoritesController
                                    .toggleFavoriteRoute(
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

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      added
                                          ? 'Kayitli rota eklendi'
                                          : 'Kayitli rota favorilerden cikarildi',
                                    ),
                                    duration:
                                        const Duration(milliseconds: 1100),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.alt_route_outlined),
                              label: const Text('Rota Ekle'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (routes.isEmpty)
                          const FavSectionEmpty(
                            text: 'Henuz kayitli iki-durak rota yok.',
                          )
                        else
                          ...routes.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: FavoritePairRouteCard(
                                item: item,
                                onRemove: () => widget.favoritesController
                                    .removeFavoriteRoute(item.key),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => FavoriteRouteDetailPage(
                                        item: item,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Favori Duraklar',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final selectedStop = await Navigator.of(context)
                                    .push<TransitStop>(
                                  MaterialPageRoute(
                                    builder: (_) => StopPickerPage(
                                      selectedStopIds: stops
                                          .map((item) => item.stopId)
                                          .toSet(),
                                    ),
                                  ),
                                );
                                if (selectedStop != null) {
                                  final added =
                                      widget.favoritesController.toggleFavoriteStop(
                                    FavoriteStopItem(
                                      stopId: selectedStop.stopId,
                                      stopName: selectedStop.stopName,
                                      latitude: selectedStop.latitude,
                                      longitude: selectedStop.longitude,
                                    ),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          added
                                              ? 'Durak favorilere eklendi'
                                              : 'Durak favorilerden cikarildi',
                                        ),
                                        duration:
                                            const Duration(milliseconds: 1000),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.add_location_alt_outlined),
                              label: const Text('Durak Ekle'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (stops.isEmpty)
                          const FavSectionEmpty(text: 'Henuz favori durak yok.')
                        else
                          ...stops.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: FavoriteStopCard(
                                item: item,
                                approachingBuses: _buildApproachingBuses(item),
                                onRemove: () => widget.favoritesController
                                    .removeFavoriteStop(item.stopId),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => StopDetailPage(
                                        favoriteStop: item,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        if (_isLoadingApproaching)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        const SizedBox(height: 14),
                        Text(
                          'Favori Hatlar',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (lines.isEmpty)
                          const FavSectionEmpty(text: 'Henuz favori hat yok.')
                        else
                          ...lines.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: FavoriteLineCard(
                                routeCode: item.routeCode,
                                routeName: item.routeName,
                                onRemove: () => widget.favoritesController
                                    .removeFavoriteLine(item.routeCode),
                              ),
                            ),
                          ),
                      ],
                    ),
        );
      },
    );
  }
}
