import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/bus_vehicle.dart';
import '../../data/models/transit_stop.dart';
import '../../data/services/adana_api_service.dart';
import '../shared/geo_math_utils.dart';
import '../shared/kentkart_path_utils.dart';
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

  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdatedAt;
  TransitStop? _selectedStop;
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

      final routeCodes = selected.routes.take(6).toList(growable: false);
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
              selectedStop: selected,
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
    required TransitStop selectedStop,
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

      final stopPointIndex = GeoMathUtils.nearestPointIndex(
        points,
        selectedStop.latitude,
        selectedStop.longitude,
      );
      if (stopPointIndex < 0 || stopPointIndex >= points.length - 1) {
        continue;
      }

      final busStopList = KentkartPathUtils.asList(path['busStopList']);
      final selectedStopIdx =
          KentkartPathUtils.findStopIndex(busStopList, selectedStop.stopId);
      if (selectedStopIdx < 0) {
        // Ters direction karismasini engelle: secili durak bu yonde yoksa ele.
        continue;
      }
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
        stopLat: selectedStop.latitude,
        stopLon: selectedStop.longitude,
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
    final allPoints = <LatLng>[stopPoint];
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
    final remainingRoutes = (stop?.routes ?? const <String>[])
        .where((route) => route.trim().isNotEmpty && !visibleRouteCodes.contains(route))
        .toList(growable: false);
    final center = stop == null
        ? LatLng(widget.favoriteStop.latitude, widget.favoriteStop.longitude)
        : LatLng(stop.latitude, stop.longitude);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.favoriteStop.stopName),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadStopDetail,
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.adanabus',
                ),
                PolylineLayer(
                  polylines: visibleTracks
                      .expand((t) {
                        final polylines = <Polyline>[];
                        if (t.approachPoints.length > 1) {
                          polylines.add(
                            Polyline(
                              points: t.approachPoints,
                              color: const Color(0xFFD32F2F),
                              strokeWidth: 5,
                            ),
                          );
                        }
                        if (t.afterStopPoints.length > 1) {
                          polylines.add(
                            Polyline(
                              points: t.afterStopPoints,
                              color: t.color.withValues(alpha: 0.9),
                              strokeWidth: 4,
                            ),
                          );
                        }
                        return polylines;
                      })
                      .toList(growable: false),
                ),
                if (stop != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(stop.latitude, stop.longitude),
                        width: 44,
                        height: 44,
                        child: const Icon(
                          Icons.place,
                          color: Color(0xFFB63519),
                          size: 34,
                        ),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: visibleTracks
                      .expand((track) => track.buses)
                      .where((bus) => bus.hasLocation)
                      .map(
                        (bus) => Marker(
                          point: LatLng(bus.latitude!, bus.longitude!),
                          width: 44,
                          height: 44,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF164B9D),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  bus.id.isEmpty ? 'Bus' : bus.id,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.directions_bus,
                                size: 22,
                                color: Color(0xFF0B5A25),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.white.withValues(alpha: 0.35),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              ),
            ),
          if (_error != null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1EE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(_error!),
                ),
              ),
            ),
          if (sortedTracks.isNotEmpty || remainingRoutes.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SizedBox(
                height: 146,
                child: PageView.builder(
                  controller: _trackPageController,
                  itemCount:
                      sortedTracks.length + (remainingRoutes.isNotEmpty ? 1 : 0),
                  onPageChanged: (index) {
                    setState(() {
                      _focusedTrackPage = index;
                      if (index < sortedTracks.length) {
                        _selectedTrackKey = sortedTracks[index].key;
                      }
                    });
                    if (index < sortedTracks.length) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          _fitMap();
                        }
                      });
                    }
                  },
                  itemBuilder: (context, index) {
                    if (index < sortedTracks.length) {
                      final track = sortedTracks[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _TrackFloatingCard(
                          track: track,
                          stopName: widget.favoriteStop.stopName,
                          updatedAt: _lastUpdatedAt,
                          isSelected: track.key == selectedTrack?.key,
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _MissingRoutesPageCard(routes: remainingRoutes),
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

class _TrackFloatingCard extends StatelessWidget {
  const _TrackFloatingCard({
    required this.track,
    required this.stopName,
    required this.updatedAt,
    required this.isSelected,
  });

  final _RouteTrackInfo track;
  final String stopName;
  final DateTime? updatedAt;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final updated = updatedAt == null
        ? '-'
        : '${updatedAt!.hour.toString().padLeft(2, '0')}:${updatedAt!.minute.toString().padLeft(2, '0')}';
    final etaText = track.nearestEtaMinutes == null
        ? 'ETA yok'
        : '${track.nearestEtaMinutes} dk${track.nextEtaMinutes == null ? '' : ' • ${track.nextEtaMinutes} dk'}';

    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white.withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: track.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hat ${track.routeCode} • ${track.direction == '1' ? 'Donus' : 'Gidis'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.radio_button_checked, size: 16, color: Color(0xFF164B9D)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$stopName • ${(track.approachMeters / 1000).toStringAsFixed(1)} km',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Yaklasan: $etaText • Canli: ${track.liveBusCount}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF175E2F),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            Text(
              'Son guncelleme: $updated',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingRoutesPageCard extends StatelessWidget {
  const _MissingRoutesPageCard({required this.routes});

  final List<String> routes;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white.withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Buradan gecer (yaklasmayanlar)',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: routes
                      .take(24)
                      .map(
                        (route) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF5F7FA),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFE2E7F0)),
                          ),
                          child: Text(
                            route,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
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
