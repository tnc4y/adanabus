import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme_utils.dart';
import '../../data/models/bus_vehicle.dart';
import '../../data/models/transit_stop.dart';
import '../../data/services/adana_api_service.dart';
import '../shared/geo_math_utils.dart';
import '../shared/kentkart_path_utils.dart';
import '../shared/app_map_tile_layer.dart';
import '../favorites/favorite_stop_item.dart';

class StopDetailPage extends StatefulWidget {
  const StopDetailPage({
    super.key,
    required this.favoriteStop,
  });

  final FavoriteStopItem favoriteStop;

  @override
  State<StopDetailPage> createState() => _StopDetailPageState();
}

class _StopDetailPageState extends State<StopDetailPage> {
  final AdanaApiService _apiService = AdanaApiService();
  final MapController _mapController = MapController();
  final PageController _trackPageController =
      PageController(viewportFraction: 0.9);

  static const double _clusterRadiusMeters = 300;

  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdatedAt;
  TransitStop? _selectedStop;
  List<TransitStop> _clusterStops = <TransitStop>[];
  List<_RouteTrackInfo> _tracks = <_RouteTrackInfo>[];
  String? _selectedTrackKey;
  int _focusedTrackPage = 0;
  Timer? _refreshTimer;
  Timer? _warmupRetryTimer;
  int _warmupRetryCount = 0;

  static const double _etaMetersPerMinute = 320;
  static const List<Color> _palette = <Color>[
    Color(0xFF0057D9),
    Color(0xFF009E73),
    Color(0xFFF0A202),
    Color(0xFF7B1FA2),
    Color(0xFF00ACC1),
    Color(0xFF8D6E63),
    Color(0xFF3949AB),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFF6D4C41),
    Color(0xFF1E88E5),
    Color(0xFF5E35B1),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _loadStopDetail();
      _scheduleWarmupRetryIfNeeded();
    });
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _warmupRetryTimer?.cancel();
    _trackPageController.dispose();
    super.dispose();
  }

  void _scheduleWarmupRetryIfNeeded() {
    if (_warmupRetryCount >= 3) {
      return;
    }
    _warmupRetryTimer?.cancel();
    final delaySeconds = 2 + _warmupRetryCount;
    _warmupRetryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted || _isLoading) {
        return;
      }
      if (_tracks.isNotEmpty) {
        return;
      }
      _warmupRetryCount++;
      _loadStopDetail();
      _scheduleWarmupRetryIfNeeded();
    });
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) {
        if (!mounted) {
          return;
        }
        if (!_isLoading) {
          _loadStopDetail();
        }
      },
    );
  }

  Future<void> _loadStopDetail() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final allStops = await _apiService.fetchAllStopsCatalog();
      final match =
          allStops.where((stop) => stop.stopId == widget.favoriteStop.stopId);
      final selected = match.isNotEmpty
          ? match.first
          : TransitStop(
              stopId: widget.favoriteStop.stopId,
              stopName: widget.favoriteStop.stopName,
              latitude: widget.favoriteStop.latitude,
              longitude: widget.favoriteStop.longitude,
              routes: const <String>[],
            );

      final clusterStops = _buildNearbyStopCluster(allStops, selected);

      final routeCodes = _collectClusterRouteCodes(clusterStops);
      final tracks = <_RouteTrackInfo>[];
      var paletteIndex = 0;

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

            final parsed = _parseTrack(
              payload: payload,
              routeCode: routeCode,
              direction: direction,
              color: _palette[paletteIndex % _palette.length],
              selectedStops: clusterStops,
            );
            paletteIndex++;

            if (parsed != null) {
              tracks.add(parsed);
            }
          } catch (_) {
            continue;
          }
        }
      }

      if (!mounted) {
        return;
      }

      tracks.sort((a, b) {
        final distanceCompare = a.approachMeters.compareTo(b.approachMeters);
        if (distanceCompare != 0) {
          return distanceCompare;
        }
        return a.routeCode.compareTo(b.routeCode);
      });

      setState(() {
        _selectedStop = selected;
        _clusterStops = clusterStops;
        _tracks = tracks;
        if (tracks.isEmpty) {
          _selectedTrackKey = null;
          _focusedTrackPage = 0;
        } else {
          final keepCurrent = tracks.any((item) => item.key == _selectedTrackKey);
          _selectedTrackKey = keepCurrent ? _selectedTrackKey : tracks.first.key;
          _focusedTrackPage = tracks.indexWhere((item) => item.key == _selectedTrackKey);
          if (_focusedTrackPage < 0) {
            _focusedTrackPage = 0;
          }
        }
        _lastUpdatedAt = DateTime.now();
      });

      if (tracks.isEmpty) {
        _scheduleWarmupRetryIfNeeded();
      } else {
        _warmupRetryCount = 0;
        _warmupRetryTimer?.cancel();
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (_trackPageController.hasClients) {
          _trackPageController.jumpToPage(_focusedTrackPage);
        }
        _fitMap();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  _RouteTrackInfo? _parseTrack({
    required Map<String, dynamic> payload,
    required String routeCode,
    required String direction,
    required Color color,
    required List<TransitStop> selectedStops,
  }) {
    final pathList = KentkartPathUtils.asList(payload['pathList']);
    if (pathList.isEmpty) {
      return null;
    }

    for (final path in pathList) {
      if (path is! Map<String, dynamic>) {
        continue;
      }

      final points = KentkartPathUtils.extractPathPoints(path);
      if (points.length < 2) {
        continue;
      }

      final busStopList = KentkartPathUtils.asList(path['busStopList']);
      final matchedStop = _matchClusterStop(busStopList, selectedStops);
      if (matchedStop == null) {
        // Ters direction karismasini engelle: secili durak bu yonde yoksa ele.
        continue;
      }
      final stopPointIndex = GeoMathUtils.nearestPointIndex(
        points,
        matchedStop.stop.latitude,
        matchedStop.stop.longitude,
      );
      if (stopPointIndex < 0 || stopPointIndex >= points.length - 1) {
        continue;
      }
      final selectedStopIdx = matchedStop.index;
      final fromStopName = selectedStopIdx > 0
          ? KentkartPathUtils.readString(
              busStopList[selectedStopIdx - 1] as Map<String, dynamic>,
              const ['stopName', 'StopName'],
            )
          : '';
      final toStopName = busStopList.isNotEmpty
          ? KentkartPathUtils.readString(
              busStopList.last is Map<String, dynamic>
                  ? busStopList.last as Map<String, dynamic>
                  : const <String, dynamic>{},
              const ['stopName', 'StopName'],
            )
          : '';

      final buses = KentkartPathUtils.extractBuses(path, routeCode, direction);
      final upcomingBuses = _filterUpcomingBuses(
        buses: buses,
        points: points,
        stopPointIndex: stopPointIndex,
      );
      if (upcomingBuses.isEmpty) {
        // Canli arac olmayan hatlari cizme.
        continue;
      }
      final primaryBus = _selectPrimaryBus(
        buses: upcomingBuses,
        points: points,
        stopPointIndex: stopPointIndex,
      );

      final approachPoints = _buildApproachPoints(
        points: points,
        bus: primaryBus,
        stopPointIndex: stopPointIndex,
      );
      final afterStopPoints = points.sublist(stopPointIndex);
      final approachMeters = GeoMathUtils.polylineMeters(approachPoints);
      final eta = _estimateEtaForStop(
        buses: upcomingBuses,
        stopLat: matchedStop.stop.latitude,
        stopLon: matchedStop.stop.longitude,
      );

      return _RouteTrackInfo(
        routeCode: routeCode,
        direction: direction,
        color: color,
        approachPoints: approachPoints,
        afterStopPoints: afterStopPoints,
        remainingPoints: afterStopPoints,
        approachMeters: approachMeters,
        fromStopName: fromStopName,
        toStopName: toStopName,
        nearestEtaMinutes: eta.$1,
        nextEtaMinutes: eta.$2,
        liveBusCount: upcomingBuses.length,
        buses: upcomingBuses,
        primaryBus: primaryBus,
      );
    }

    return null;
  }

  List<TransitStop> _buildNearbyStopCluster(
    List<TransitStop> allStops,
    TransitStop anchor,
  ) {
    final cluster = allStops
        .where(
          (stop) => _distanceMeters(
                anchor.latitude,
                anchor.longitude,
                stop.latitude,
                stop.longitude,
              ) <=
              _clusterRadiusMeters,
        )
        .toList(growable: false);

    if (cluster.isEmpty) {
      return <TransitStop>[anchor];
    }

    cluster.sort((a, b) {
      final distanceCompare = _distanceMeters(
        anchor.latitude,
        anchor.longitude,
        a.latitude,
        a.longitude,
      ).compareTo(
        _distanceMeters(
          anchor.latitude,
          anchor.longitude,
          b.latitude,
          b.longitude,
        ),
      );
      if (distanceCompare != 0) {
        return distanceCompare;
      }
      return a.stopName.compareTo(b.stopName);
    });

    return cluster;
  }

  List<String> _collectClusterRouteCodes(List<TransitStop> clusterStops) {
    final routeCodes = <String>[];
    for (final stop in clusterStops) {
      for (final route in stop.routes) {
        final normalized = route.trim();
        if (normalized.isEmpty || routeCodes.contains(normalized)) {
          continue;
        }
        routeCodes.add(normalized);
      }
    }
    return routeCodes.take(10).toList(growable: false);
  }

  ({TransitStop stop, int index})? _matchClusterStop(
    List<dynamic> busStopList,
    List<TransitStop> clusterStops,
  ) {
    for (final stop in clusterStops) {
      final index = KentkartPathUtils.findStopIndex(busStopList, stop.stopId);
      if (index >= 0) {
        return (stop: stop, index: index);
      }
    }
    return null;
  }

  BusVehicle? _selectPrimaryBus({
    required List<BusVehicle> buses,
    required List<LatLng> points,
    required int stopPointIndex,
  }) {
    final orderedCandidates = <({BusVehicle bus, int pointIndex, double distance})>[];

    for (final bus in buses) {
      if (!bus.hasLocation) {
        continue;
      }
      final pointIndex = GeoMathUtils.nearestPointIndex(
        points,
        bus.latitude!,
        bus.longitude!,
      );
      if (pointIndex < 0) {
        continue;
      }
      final distance = GeoMathUtils.distanceMeters(
        bus.latitude!,
        bus.longitude!,
        points[pointIndex].latitude,
        points[pointIndex].longitude,
      );
      orderedCandidates.add((bus: bus, pointIndex: pointIndex, distance: distance));
    }

    if (orderedCandidates.isEmpty) {
      return null;
    }

    orderedCandidates.sort((a, b) {
      final pointComparison = b.pointIndex.compareTo(a.pointIndex);
      if (pointComparison != 0) {
        return pointComparison;
      }
      return a.distance.compareTo(b.distance);
    });

    return orderedCandidates.first.bus;
  }

  List<BusVehicle> _filterUpcomingBuses({
    required List<BusVehicle> buses,
    required List<LatLng> points,
    required int stopPointIndex,
  }) {
    final upcoming = <BusVehicle>[];
    for (final bus in buses) {
      if (!bus.hasLocation) {
        continue;
      }
      final pointIndex = GeoMathUtils.nearestPointIndex(
        points,
        bus.latitude!,
        bus.longitude!,
      );
      if (pointIndex < 0 || pointIndex > stopPointIndex) {
        continue;
      }
      upcoming.add(bus);
    }
    return upcoming;
  }

  List<LatLng> _buildApproachPoints({
    required List<LatLng> points,
    required BusVehicle? bus,
    required int stopPointIndex,
  }) {
    if (bus == null || !bus.hasLocation) {
      return const <LatLng>[];
    }

    final busPointIndex = GeoMathUtils.nearestPointIndex(
      points,
      bus.latitude!,
      bus.longitude!,
    );
    if (busPointIndex < 0 || busPointIndex > stopPointIndex) {
      return const <LatLng>[];
    }

    final approach = <LatLng>[
      LatLng(bus.latitude!, bus.longitude!),
      ...points.sublist(busPointIndex, stopPointIndex + 1),
    ];

    return approach;
  }

  (int?, int?) _estimateEtaForStop({
    required List<BusVehicle> buses,
    required double stopLat,
    required double stopLon,
  }) {
    if (buses.isEmpty) {
      return (null, null);
    }

    final etaList = <int>[];
    for (final bus in buses) {
      if (!bus.hasLocation) {
        continue;
      }
      final meters = _distanceMeters(
        bus.latitude!,
        bus.longitude!,
        stopLat,
        stopLon,
      );
      etaList.add((meters / _etaMetersPerMinute).clamp(1, 180).round());
    }

    if (etaList.isEmpty) {
      return (null, null);
    }

    etaList.sort();
    return (etaList.first, etaList.length > 1 ? etaList[1] : null);
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return GeoMathUtils.distanceMeters(lat1, lon1, lat2, lon2);
  }

  void _fitMap() {
    if (_selectedStop == null) {
      return;
    }

    final stopPoint = LatLng(_selectedStop!.latitude, _selectedStop!.longitude);
    final allPoints = _clusterStops.isEmpty
        ? <LatLng>[stopPoint]
        : _clusterStops
            .map((stop) => LatLng(stop.latitude, stop.longitude))
            .toList(growable: true);
    final selectedTrack = _tracks.isEmpty
        ? null
        : _tracks.firstWhere(
            (item) => item.key == _selectedTrackKey,
            orElse: () => _tracks.first,
          );
    if (selectedTrack != null) {
      allPoints.addAll(selectedTrack.approachPoints.take(120));
      allPoints.addAll(selectedTrack.afterStopPoints.take(120));
    }

    if (allPoints.length < 2) {
      _mapController.move(stopPoint, 14.5);
      return;
    }

    final bounds = GeoMathUtils.boundsForPoints(allPoints);
    if (bounds == null) {
      return;
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stop = _selectedStop;
    final clusterStops = _clusterStops.isEmpty && stop != null
        ? <TransitStop>[stop]
        : _clusterStops;
    final sortedTracks = List<_RouteTrackInfo>.from(_tracks)
      ..sort((a, b) {
        final distanceCompare = a.approachMeters.compareTo(b.approachMeters);
        if (distanceCompare != 0) {
          return distanceCompare;
        }
        return a.routeCode.compareTo(b.routeCode);
      });
    final selectedTrack = sortedTracks.isEmpty
        ? null
        : sortedTracks.firstWhere(
            (item) => item.key == _selectedTrackKey,
            orElse: () => sortedTracks.first,
          );
    final visibleTracks = selectedTrack == null
        ? const <_RouteTrackInfo>[]
        : <_RouteTrackInfo>[selectedTrack];
    final visibleRouteCodes = visibleTracks.map((track) => track.routeCode).toSet();
    final remainingRoutes = clusterStops
      .expand((item) => item.routes)
        .where((route) => route.trim().isNotEmpty && !visibleRouteCodes.contains(route))
      .toSet()
      .toList(growable: false);
    final center = stop == null
        ? LatLng(widget.favoriteStop.latitude, widget.favoriteStop.longitude)
        : LatLng(stop.latitude, stop.longitude);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green = AppThemeUtils.getAccentColor(context, 'green');
    final blue = AppThemeUtils.getAccentColor(context, 'blue');
    final orange = AppThemeUtils.getAccentColor(context, 'orange');

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF0F1722).withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A2535) : const Color(0xFFF3F6FB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back_rounded, size: 20),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.favoriteStop.stopName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppThemeUtils.getTextColor(context),
              ),
            ),
            Text(
              'Durak #${widget.favoriteStop.stopId}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppThemeUtils.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
        actions: [
          if (_tracks.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: green.withValues(alpha: isDark ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_bus_rounded, size: 12, color: green),
                  const SizedBox(width: 4),
                  Text(
                    '${_tracks.length} hat',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: green,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _isLoading ? null : _loadStopDetail,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A2535) : const Color(0xFFF3F6FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: _isLoading
                      ? AppThemeUtils.getSecondaryTextColor(context)
                      : AppThemeUtils.getTextColor(context),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ───────────────────────────────────────────────────────
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: center, initialZoom: 14),
              children: [
                buildAppMapTileLayer(context),
                // Route polylines
                PolylineLayer(
                  polylines: visibleTracks.expand((t) {
                    final list = <Polyline>[];
                    if (t.approachPoints.length > 1) {
                      list.add(Polyline(
                        points: t.approachPoints,
                        color: const Color(0xFFE53935),
                        strokeWidth: 5,
                        borderColor: const Color(0xFFE53935).withValues(alpha: 0.2),
                        borderStrokeWidth: 9,
                      ));
                    }
                    if (t.afterStopPoints.length > 1) {
                      list.add(Polyline(
                        points: t.afterStopPoints,
                        color: t.color.withValues(alpha: 0.85),
                        strokeWidth: 4,
                        borderColor: t.color.withValues(alpha: 0.15),
                        borderStrokeWidth: 8,
                      ));
                    }
                    return list;
                  }).toList(growable: false),
                ),
                // Stop markers
                if (stop != null)
                  MarkerLayer(
                    markers: clusterStops.map((item) {
                      final isPrimary = item.stopId == stop.stopId;
                      return Marker(
                        point: LatLng(item.latitude, item.longitude),
                        width: isPrimary ? 40 : 24,
                        height: isPrimary ? 40 : 24,
                        child: Container(
                          decoration: BoxDecoration(
                            color: isPrimary ? orange : green,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: isPrimary ? 2.5 : 2),
                            boxShadow: [
                              BoxShadow(
                                color: (isPrimary ? orange : green).withValues(alpha: 0.4),
                                blurRadius: isPrimary ? 10 : 4,
                              ),
                            ],
                          ),
                          child: isPrimary
                              ? const Icon(Icons.place_rounded, color: Colors.white, size: 20)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                // Bus markers
                MarkerLayer(
                  markers: visibleTracks
                      .expand((t) => t.buses)
                      .where((bus) => bus.hasLocation)
                      .map((bus) => Marker(
                            point: LatLng(bus.latitude!, bus.longitude!),
                            width: 50,
                            height: 50,
                            child: Container(
                              decoration: BoxDecoration(
                                color: blue,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: blue.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.directions_bus_rounded,
                                      color: Colors.white, size: 16),
                                  if (bus.id.isNotEmpty)
                                    Text(
                                      bus.id,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 8,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ))
                      .toList(growable: false),
                ),
              ],
            ),
          ),

          // ── Loading overlay ─────────────────────────────────────────
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppThemeUtils.getCardColor(context),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const CircularProgressIndicator(),
                ),
              ),
            ),

          // ── Error banner ────────────────────────────────────────────
          if (_error != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1EE),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD0C8)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFFB63519), size: 17),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7A2010),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _error = null),
                      icon: const Icon(Icons.close_rounded,
                          size: 16, color: Color(0xFFB63519)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ),

          // ── Nearby stops top card ───────────────────────────────────
          if (clusterStops.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 68,
              left: 12,
              right: 12,
              child: _NearbyStopsFloatingCard(
                anchorName: stop?.stopName ?? widget.favoriteStop.stopName,
                clusterStops: clusterStops,
                isDark: isDark,
              ),
            ),

          // ── Track cards (bottom) ────────────────────────────────────
          if (sortedTracks.isNotEmpty || remainingRoutes.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: SizedBox(
                height: 152,
                child: PageView.builder(
                  controller: _trackPageController,
                  itemCount: sortedTracks.length + (remainingRoutes.isNotEmpty ? 1 : 0),
                  onPageChanged: (index) {
                    setState(() {
                      _focusedTrackPage = index;
                      if (index < sortedTracks.length) {
                        _selectedTrackKey = sortedTracks[index].key;
                      }
                    });
                    if (index < sortedTracks.length) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _fitMap();
                      });
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index < sortedTracks.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _TrackFloatingCard(
                          track: sortedTracks[index],
                          stopName: stop?.stopName ?? widget.favoriteStop.stopName,
                          updatedAt: _lastUpdatedAt,
                          isSelected: sortedTracks[index].key == selectedTrack?.key,
                          totalPages: sortedTracks.length + (remainingRoutes.isNotEmpty ? 1 : 0),
                          currentPage: index,
                          isDark: isDark,
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _MissingRoutesPageCard(
                        routes: remainingRoutes,
                        isDark: isDark,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NearbyStopsFloatingCard extends StatelessWidget {
  const _NearbyStopsFloatingCard({
    required this.anchorName,
    required this.clusterStops,
    required this.isDark,
  });

  final String anchorName;
  final List<TransitStop> clusterStops;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final orange = AppThemeUtils.getAccentColor(context, 'orange');

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      color: isDark
          ? const Color(0xFF1A2535).withValues(alpha: 0.97)
          : Colors.white.withValues(alpha: 0.97),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: orange.withValues(alpha: isDark ? 0.25 : 0.2),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.merge_rounded, color: orange, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${clusterStops.length} yakın durak birleştirildi',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: AppThemeUtils.getTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: clusterStops
                          .map(
                            (stop) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppThemeUtils.getSubtleBackgroundColor(context),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: AppThemeUtils.getBorderColor(context),
                                  ),
                                ),
                                child: Text(
                                  stop.stopName,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppThemeUtils.getSecondaryTextColor(context),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackFloatingCard extends StatelessWidget {
  const _TrackFloatingCard({
    required this.track,
    required this.stopName,
    required this.updatedAt,
    required this.isSelected,
    required this.totalPages,
    required this.currentPage,
    required this.isDark,
  });

  final _RouteTrackInfo track;
  final String stopName;
  final DateTime? updatedAt;
  final bool isSelected;
  final int totalPages;
  final int currentPage;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final blue = AppThemeUtils.getAccentColor(context, 'blue');
    final green = AppThemeUtils.getAccentColor(context, 'green');
    final updated = updatedAt == null
        ? '-'
        : '${updatedAt!.hour.toString().padLeft(2, '0')}:${updatedAt!.minute.toString().padLeft(2, '0')}';
    final hasEta = track.nearestEtaMinutes != null;

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      color: isDark
          ? const Color(0xFF1A2535).withValues(alpha: 0.97)
          : Colors.white.withValues(alpha: 0.97),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? blue.withValues(alpha: isDark ? 0.4 : 0.3)
                : AppThemeUtils.getBorderColor(context),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: track.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: track.color.withValues(alpha: 0.4),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    track.routeCode,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: blue,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    track.direction == '1' ? 'Dönüş' : 'Gidiş',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppThemeUtils.getTextColor(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Seçili',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: blue,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // ETA row
            Row(
              children: [
                if (hasEta) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.directions_bus_rounded, size: 12, color: green),
                        const SizedBox(width: 4),
                        Text(
                          '${track.nearestEtaMinutes} dk',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: green,
                          ),
                        ),
                        if (track.nextEtaMinutes != null) ...[
                          Text(
                            ' · ${track.nextEtaMinutes} dk',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: green.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppThemeUtils.getSubtleBackgroundColor(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Yaklaşan yok',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppThemeUtils.getSecondaryTextColor(context),
                      ),
                    ),
                  ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppThemeUtils.getSubtleBackgroundColor(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${track.liveBusCount} araç',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppThemeUtils.getSecondaryTextColor(context),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Footer row
            Row(
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: 11,
                  color: AppThemeUtils.getSecondaryTextColor(context),
                ),
                const SizedBox(width: 4),
                Text(
                  updated,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppThemeUtils.getSecondaryTextColor(context),
                  ),
                ),
                const Spacer(),
                // Page dots
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(totalPages, (i) {
                    final active = i == currentPage;
                    return Container(
                      width: active ? 14 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: active
                            ? blue
                            : AppThemeUtils.getBorderColor(context),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingRoutesPageCard extends StatelessWidget {
  const _MissingRoutesPageCard({
    required this.routes,
    required this.isDark,
  });

  final List<String> routes;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final blue = AppThemeUtils.getAccentColor(context, 'blue');

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      color: isDark
          ? const Color(0xFF1A2535).withValues(alpha: 0.97)
          : Colors.white.withValues(alpha: 0.97),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppThemeUtils.getBorderColor(context)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.route_rounded, size: 14, color: blue),
                ),
                const SizedBox(width: 8),
                Text(
                  'Bu durağa uğrayan diğer hatlar',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppThemeUtils.getTextColor(context),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppThemeUtils.getSubtleBackgroundColor(context),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${routes.length} hat',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppThemeUtils.getSecondaryTextColor(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: routes
                      .take(24)
                      .map(
                        (route) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: blue.withValues(alpha: isDark ? 0.15 : 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: blue.withValues(alpha: isDark ? 0.25 : 0.15),
                            ),
                          ),
                          child: Text(
                            route,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: blue,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteTrackInfo {
  const _RouteTrackInfo({
    required this.routeCode,
    required this.direction,
    required this.color,
    required this.approachPoints,
    required this.afterStopPoints,
    required this.remainingPoints,
    required this.approachMeters,
    required this.fromStopName,
    required this.toStopName,
    required this.nearestEtaMinutes,
    required this.nextEtaMinutes,
    required this.liveBusCount,
    required this.buses,
    required this.primaryBus,
  });

  final String routeCode;
  final String direction;
  final Color color;
  final List<LatLng> approachPoints;
  final List<LatLng> afterStopPoints;
  final List<LatLng> remainingPoints;
  final double approachMeters;
  final String fromStopName;
  final String toStopName;
  final int? nearestEtaMinutes;
  final int? nextEtaMinutes;
  final int liveBusCount;
  final List<BusVehicle> buses;
  final BusVehicle? primaryBus;

  String get key => '$routeCode|$direction|$toStopName';
}
