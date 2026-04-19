import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/services/adana_api_service.dart';
import '../../data/models/bus_vehicle.dart';
import 'line_timetable_page.dart';

class LineDetailPage extends StatefulWidget {
  const LineDetailPage({
    super.key,
    required this.routeCode,
    required this.routeName,
    required this.direction,
  });

  final String routeCode;
  final String routeName;
  final String direction;

  @override
  State<LineDetailPage> createState() => _LineDetailPageState();
}

class _LineDetailPageState extends State<LineDetailPage> {
  final AdanaApiService _apiService = AdanaApiService();
  final MapController _mapController = MapController();
  final PageController _vehiclePageController = PageController(viewportFraction: 0.9);

  bool _isLoading = false;
  String? _error;
  String _currentDirection = '0';
  List<LineStop> _stops = <LineStop>[];
  List<LatLng> _pathPoints = <LatLng>[];
  List<BusVehicle> _liveRouteBuses = <BusVehicle>[];
  Map<String, StopArrivalEstimate> _arrivalByStopKey =
      <String, StopArrivalEstimate>{};
  LineStop? _selectedStop;
  int _focusedBusIndex = 0;
  Timer? _liveBusTimer;
  Timer? _mapFocusTimer;
  DateTime? _lastBusRefreshAt;
  LatLng? _lastMapCenter;
  double _lastMapZoom = 13.2;
  static const double _etaMetersPerMinute = 320;

  @override
  void initState() {
    super.initState();
    _currentDirection = widget.direction == '1' ? '1' : '0';
    _loadDetail();
    _startLiveBusTracking();
  }

  @override
  void dispose() {
    _liveBusTimer?.cancel();
    _mapFocusTimer?.cancel();
    _vehiclePageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LineDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final normalizedDirection = widget.direction == '1' ? '1' : '0';
    if (oldWidget.direction != widget.direction &&
        normalizedDirection != _currentDirection) {
      _currentDirection = normalizedDirection;
      _loadDetail();
    }
  }

  Future<void> _loadDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dynamic pathResponse = await _apiService.fetchKentkartPathInfo(
        displayRouteCode: widget.routeCode,
        direction: _currentDirection,
      );

      final pathPayload = pathResponse is Map<String, dynamic>
          ? pathResponse
          : <String, dynamic>{'data': pathResponse};
        final liveBusesFromPath = _extractLiveBusesFromPathPayload(pathPayload);

      final routeBuses = await _apiService.fetchBuses();
      final liveRouteBuses = routeBuses
          .where(
              (bus) =>
                  bus.displayRouteCode == widget.routeCode &&
                  bus.direction == _currentDirection &&
                  bus.hasLocation,
          )
          .toList(growable: false);

      final stops = _extractStops(pathPayload);
      final points = _extractPathPoints(pathPayload, stops);
      final resolvedLiveBuses = liveBusesFromPath.isNotEmpty
          ? liveBusesFromPath
          : liveRouteBuses;
      final arrivals = _buildStopArrivalEstimates(stops, resolvedLiveBuses);
      final nextFocusedBusIndex = _syncFocusedBusIndex(
        previousBuses: _liveRouteBuses,
        nextBuses: resolvedLiveBuses,
        previousIndex: _focusedBusIndex,
      );

      setState(() {
        _stops = stops;
        _pathPoints = points;
        _liveRouteBuses = resolvedLiveBuses;
        _arrivalByStopKey = arrivals;
        _selectedStop = _resolveSelectedStop(stops, _selectedStop);
        _focusedBusIndex = nextFocusedBusIndex;
        _lastBusRefreshAt = DateTime.now();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _fitMapToRoute();
        _alignVehiclePageToFocused();
        _focusSelectedVehicle(animate: false);
      });
    } catch (error) {
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

  void _startLiveBusTracking() {
    _liveBusTimer?.cancel();
    _liveBusTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshLiveBuses(),
    );
  }

  Future<void> _refreshLiveBuses() async {
    if (!mounted || _isLoading) {
      return;
    }

    try {
      final dynamic pathResponse = await _apiService.fetchKentkartPathInfo(
        displayRouteCode: widget.routeCode,
        direction: _currentDirection,
      );
      final pathPayload = pathResponse is Map<String, dynamic>
          ? pathResponse
          : <String, dynamic>{'data': pathResponse};
      final liveBusesFromPath = _extractLiveBusesFromPathPayload(pathPayload);

      final buses = await _apiService.fetchBuses();
      final filteredFromBuses = buses
          .where(
            (bus) =>
                bus.displayRouteCode == widget.routeCode &&
                bus.direction == _currentDirection &&
                bus.hasLocation,
          )
          .toList(growable: false);
      final resolved = liveBusesFromPath.isNotEmpty
          ? liveBusesFromPath
          : filteredFromBuses;
      final arrivals = _buildStopArrivalEstimates(_stops, resolved);
      final nextFocusedBusIndex = _syncFocusedBusIndex(
        previousBuses: _liveRouteBuses,
        nextBuses: resolved,
        previousIndex: _focusedBusIndex,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _liveRouteBuses = resolved;
        _arrivalByStopKey = arrivals;
        _focusedBusIndex = nextFocusedBusIndex;
        _lastBusRefreshAt = DateTime.now();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _alignVehiclePageToFocused();
        _focusSelectedVehicle();
      });
    } catch (_) {
      // Live tracking should not break the route page if one refresh fails.
    }
  }

  List<LineStop> _extractStops(Map<String, dynamic> payload) {
    final pathList = _asList(payload['pathList']);
    final dedupe = <String>{};
    final result = <LineStop>[];

    void addStop(LineStop stop) {
      final key =
          '${stop.latitude.toStringAsFixed(6)}|${stop.longitude.toStringAsFixed(6)}|${stop.name}';
      if (dedupe.add(key)) {
        result.add(stop);
      }
    }

    for (final item in pathList) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      for (final key in const [
        'busStopList',
        'stopList',
        'stationList',
        'stops',
        'durakList'
      ]) {
        final rawStops = _asList(item[key]);
        for (final rawStop in rawStops) {
          if (rawStop is! Map<String, dynamic>) {
            continue;
          }

          final lat = _readDouble(rawStop, const [
            'lat',
            'latitude',
            'y',
          ]);
          final lon = _readDouble(rawStop, const [
            'lon',
            'lng',
            'longitude',
            'x',
          ]);

          if (lat == null || lon == null) {
            continue;
          }

          final name = _readString(rawStop, const [
            'stopName',
            'stationName',
            'name',
            'durakAdi',
          ]);

          addStop(
            LineStop(
              stopId: _readString(rawStop, const ['stopId', 'StopId', 'id']),
              name: name.isEmpty ? 'Durak ${result.length + 1}' : name,
              latitude: lat,
              longitude: lon,
              routes: _readString(rawStop, const ['routes'])
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList(growable: false),
            ),
          );
        }
      }
    }

    if (result.isNotEmpty) {
      return result;
    }

    // Fallback: durak verisi gelmezse rotadan noktalari durak gibi goster.
    final fallbackPoints = _extractPathPoints(payload, const <LineStop>[]);
    for (var i = 0; i < fallbackPoints.length; i++) {
      final point = fallbackPoints[i];
      addStop(
        LineStop(
          stopId: 'fallback_${i + 1}',
          name: 'Durak ${i + 1}',
          latitude: point.latitude,
          longitude: point.longitude,
          routes: const <String>[],
        ),
      );
    }

    return result;
  }

  List<LatLng> _extractPathPoints(
      Map<String, dynamic> payload, List<LineStop> stops) {
    final pathList = _asList(payload['pathList']);
    final points = <LatLng>[];

    void addPoint(double lat, double lon) {
      points.add(LatLng(lat, lon));
    }

    for (final item in pathList) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      for (final key in const ['pointList', 'path', 'shape', 'coordinates']) {
        final raw = _asList(item[key]);
        for (final entry in raw) {
          if (entry is Map<String, dynamic>) {
            final lat = _readDouble(entry, const ['lat', 'latitude', 'y']);
            final lon =
                _readDouble(entry, const ['lon', 'lng', 'longitude', 'x']);
            if (lat != null && lon != null) {
              addPoint(lat, lon);
            }
          } else if (entry is List && entry.length >= 2) {
            final lon = _toDouble(entry[0]);
            final lat = _toDouble(entry[1]);
            if (lat != null && lon != null) {
              addPoint(lat, lon);
            }
          }
        }
      }
    }

    if (points.isNotEmpty) {
      return points;
    }

    if (stops.isNotEmpty) {
      return stops
          .map((stop) => LatLng(stop.latitude, stop.longitude))
          .toList();
    }

    return const <LatLng>[];
  }

  int _syncFocusedBusIndex({
    required List<BusVehicle> previousBuses,
    required List<BusVehicle> nextBuses,
    required int previousIndex,
  }) {
    if (nextBuses.isEmpty) {
      return 0;
    }

    if (previousBuses.isNotEmpty && previousIndex >= 0 && previousIndex < previousBuses.length) {
      final previousBus = previousBuses[previousIndex];
      final matchById = nextBuses.indexWhere((bus) =>
          bus.id.isNotEmpty && previousBus.id.isNotEmpty && bus.id == previousBus.id);
      if (matchById >= 0) {
        return matchById;
      }
    }

    return math.min(previousIndex, nextBuses.length - 1);
  }

  void _alignVehiclePageToFocused() {
    if (!_vehiclePageController.hasClients || _liveRouteBuses.isEmpty) {
      return;
    }
    final safeIndex = math.max(0, math.min(_focusedBusIndex, _liveRouteBuses.length - 1));
    _vehiclePageController.jumpToPage(safeIndex);
  }

  void _focusSelectedVehicle({bool animate = true}) {
    if (_liveRouteBuses.isEmpty) {
      return;
    }
    final safeIndex = math.max(0, math.min(_focusedBusIndex, _liveRouteBuses.length - 1));
    final bus = _liveRouteBuses[safeIndex];
    if (!bus.hasLocation) {
      return;
    }
    final target = LatLng(bus.latitude!, bus.longitude!);
    _animateMapTo(target, targetZoom: 15.6, animate: animate);
  }

  void _animateMapTo(LatLng target, {double targetZoom = 15.2, bool animate = true}) {
    _mapFocusTimer?.cancel();

    final fromCenter = _lastMapCenter ?? _resolveRouteCenter();
    final fromZoom = _lastMapZoom;

    if (!animate) {
      _mapController.move(target, targetZoom);
      _lastMapCenter = target;
      _lastMapZoom = targetZoom;
      return;
    }

    const totalSteps = 10;
    var currentStep = 0;

    _mapFocusTimer = Timer.periodic(const Duration(milliseconds: 28), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      currentStep++;
      final t = currentStep / totalSteps;
      final eased = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
      final lat = fromCenter.latitude + ((target.latitude - fromCenter.latitude) * eased);
      final lng = fromCenter.longitude + ((target.longitude - fromCenter.longitude) * eased);
      final zoom = fromZoom + ((targetZoom - fromZoom) * eased);
      _mapController.move(LatLng(lat, lng), zoom);

      if (currentStep >= totalSteps) {
        timer.cancel();
        _lastMapCenter = target;
        _lastMapZoom = targetZoom;
      }
    });
  }

  void _toggleDirection() {
    if (_isLoading) {
      return;
    }
    setState(() {
      _currentDirection = _currentDirection == '1' ? '0' : '1';
      _selectedStop = null;
    });
    _loadDetail();
  }

  void _openTimetablePage() {
    final fromStop = _stops.isNotEmpty ? _stops.first.name : 'Baslangic duragi';
    final toStop = _stops.isNotEmpty ? _stops.last.name : 'Bitis duragi';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LineTimetablePage(
          routeCode: widget.routeCode,
          routeName: widget.routeName,
          direction: _currentDirection,
          fromStopName: fromStop,
          toStopName: toStop,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _resolveRouteCenter();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.routeName} (${widget.routeCode})',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _toggleDirection,
            icon: const Icon(Icons.swap_horiz),
            tooltip: _currentDirection == '1' ? 'Gidise gec' : 'Donuse gec',
          ),
          IconButton(
            onPressed: _openTimetablePage,
            icon: const Icon(Icons.schedule),
            tooltip: 'Cikis saatleri',
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 12.8,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.adanabus',
                maxZoom: 19,
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _pathPoints,
                    color: const Color(0xFF164B9D),
                    strokeWidth: 4,
                  ),
                ],
              ),
              MarkerLayer(
                markers: _stops
                    .map(
                      (stop) {
                        final isSelected = _selectedStop?.key == stop.key;
                        return Marker(
                          point: LatLng(stop.latitude, stop.longitude),
                          width: 34,
                          height: 34,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedStop = stop;
                              });
                            },
                            child: Icon(
                              Icons.location_on,
                              color: isSelected
                                  ? const Color(0xFF0B5A25)
                                  : const Color(0xFFB63519),
                              size: isSelected ? 28 : 24,
                            ),
                          ),
                        );
                      },
                    )
                    .toList(),
              ),
              MarkerLayer(
                markers: _liveRouteBuses
                    .where((bus) => bus.hasLocation)
                    .map(
                      (bus) {
                        final index = _liveRouteBuses.indexOf(bus);
                        final isFocused = index == _focusedBusIndex;
                        return Marker(
                          point: LatLng(bus.latitude!, bus.longitude!),
                          width: isFocused ? 50 : 44,
                          height: isFocused ? 50 : 44,
                          child: GestureDetector(
                            onTap: () {
                              if (!mounted) {
                                return;
                              }
                              setState(() {
                                _focusedBusIndex = index;
                                _selectedStop = null;
                              });
                              if (_vehiclePageController.hasClients) {
                                _vehiclePageController.animateToPage(
                                  index,
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutCubic,
                                );
                              }
                              _focusSelectedVehicle();
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isFocused
                                        ? const Color(0xFF0B5A25)
                                        : const Color(0xFF164B9D),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    bus.id.isEmpty ? 'Bus' : bus.id,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.directions_bus,
                                  color: isFocused
                                      ? const Color(0xFF0B5A25)
                                      : const Color(0xFF164B9D),
                                  size: isFocused ? 26 : 22,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                    .toList(growable: false),
              ),
            ],
          ),
          if (_selectedStop != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 18,
              child: _SelectedStopInfoCard(
                stop: _selectedStop!,
                estimate: _arrivalByStopKey[_selectedStop!.key],
                currentRouteCode: widget.routeCode,
                currentDirection: _currentDirection,
                lastRefreshAt: _lastBusRefreshAt,
                onClose: () {
                  setState(() {
                    _selectedStop = null;
                  });
                },
              ),
            )
          else
            Positioned(
              left: 12,
              right: 12,
              bottom: 18,
              child: SizedBox(
                height: 128,
                child: _liveRouteBuses.isEmpty
                    ? const _VehicleEmptyFloatingCard()
                    : PageView.builder(
                        controller: _vehiclePageController,
                        itemCount: _liveRouteBuses.length,
                        onPageChanged: (index) {
                          setState(() {
                            _focusedBusIndex = index;
                          });
                          _focusSelectedVehicle();
                        },
                        itemBuilder: (context, index) {
                          final bus = _liveRouteBuses[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _VehicleFloatingCard(
                              bus: bus,
                              routeCode: widget.routeCode,
                              direction: _currentDirection,
                            ),
                          );
                        },
                      ),
              ),
            ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.white.withValues(alpha: 0.55),
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
        ],
      ),
    );
  }

  LineStop? _resolveSelectedStop(List<LineStop> stops, LineStop? previous) {
    if (stops.isEmpty) {
      return null;
    }
    if (previous == null) {
      return stops.first;
    }
    for (final stop in stops) {
      if (stop.key == previous.key) {
        return stop;
      }
    }
    return stops.first;
  }

  static List<dynamic> _asList(dynamic value) {
    if (value is List<dynamic>) {
      return value;
    }
    return const <dynamic>[];
  }

  static String _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  static double? _readDouble(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final parsed = _toDouble(map[key]);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.replaceAll(',', '.'));
    }
    return null;
  }

  List<BusVehicle> _extractLiveBusesFromPathPayload(
      Map<String, dynamic> payload) {
    final dedupe = <String>{};
    final result = <BusVehicle>[];

    void addRawBus(dynamic rawBusNode) {
      if (rawBusNode is! Map<String, dynamic>) {
        return;
      }

      final lat = _readDouble(rawBusNode, const ['lat', 'latitude', 'y']);
      final lon = _readDouble(
        rawBusNode,
        const ['lng', 'lon', 'longitude', 'x'],
      );
      if (lat == null || lon == null) {
        return;
      }

      final busId = _readString(rawBusNode, const [
        'busId',
        'BusId',
        'id',
        'Id',
        'vehicleId',
      ]);
      final displayRouteCode = _readString(rawBusNode, const [
        'displayRouteCode',
        'DisplayRouteCode',
        'routeCode',
        'RouteCode',
      ]);
      final direction = _readString(rawBusNode, const ['direction', 'Direction']);
      final name = _readString(rawBusNode, const ['name', 'Name', 'RouteName']);

      final normalizedRoute =
          displayRouteCode.isEmpty ? widget.routeCode : displayRouteCode;
      final normalizedDirection =
          direction.isEmpty ? _currentDirection : direction;
      final key =
          '${busId.isEmpty ? 'anon' : busId}|${lat.toStringAsFixed(6)}|${lon.toStringAsFixed(6)}|$normalizedRoute|$normalizedDirection';
      if (!dedupe.add(key)) {
        return;
      }

      result.add(
        BusVehicle(
          id: busId,
          displayRouteCode: normalizedRoute,
          routeCode: normalizedRoute,
          name: name,
          direction: normalizedDirection,
          latitude: lat,
          longitude: lon,
          raw: rawBusNode,
        ),
      );
    }

    for (final path in _asList(payload['pathList'])) {
      if (path is! Map<String, dynamic>) {
        continue;
      }
      for (final rawBus in _asList(path['busList'])) {
        addRawBus(rawBus);
      }
    }

    // Some payload variants may include a top-level busList.
    for (final rawBus in _asList(payload['busList'])) {
      addRawBus(rawBus);
    }

    return result;
  }

  Map<String, StopArrivalEstimate> _buildStopArrivalEstimates(
    List<LineStop> stops,
    List<BusVehicle> buses,
  ) {
    if (stops.isEmpty || buses.isEmpty) {
      return const <String, StopArrivalEstimate>{};
    }

    final result = <String, StopArrivalEstimate>{};

    for (final stop in stops) {
      final candidates = <_BusEtaCandidate>[];
      for (final bus in buses) {
        if (!bus.hasLocation) {
          continue;
        }

        final distance = _distanceMeters(
          bus.latitude!,
          bus.longitude!,
          stop.latitude,
          stop.longitude,
        );
        final etaMinutes = (distance / _etaMetersPerMinute).clamp(1, 180).round();
        candidates.add(
          _BusEtaCandidate(
            busId: bus.id,
            etaMinutes: etaMinutes,
          ),
        );
      }

      if (candidates.isEmpty) {
        continue;
      }

      candidates.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
      final first = candidates.first;
      final second = candidates.length > 1 ? candidates[1] : null;

      result[stop.key] = StopArrivalEstimate(
        nearestEtaMinutes: first.etaMinutes,
        nearestBusId: first.busId,
        nextEtaMinutes: second?.etaMinutes,
        nextBusId: second?.busId,
      );
    }

    return result;
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  double _toRadians(double value) => value * (math.pi / 180.0);

  LatLng _resolveRouteCenter() {
    if (_stops.isNotEmpty) {
      final middleIndex = _stops.length ~/ 2;
      final middleStop = _stops[middleIndex];
      return LatLng(middleStop.latitude, middleStop.longitude);
    }

    if (_pathPoints.isNotEmpty) {
      return _pathPoints[_pathPoints.length ~/ 2];
    }

    return const LatLng(37.0000, 35.3213);
  }

  void _fitMapToRoute() {
    final points = _pathPoints.isNotEmpty
        ? _pathPoints
        : _stops.map((stop) => LatLng(stop.latitude, stop.longitude)).toList();

    if (points.isEmpty) {
      final center = _resolveRouteCenter();
      _mapController.move(center, 12.8);
      _lastMapCenter = center;
      _lastMapZoom = 12.8;
      return;
    }

    if (points.length == 1) {
      _mapController.move(points.first, 15);
      _lastMapCenter = points.first;
      _lastMapZoom = 15;
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      if (point.latitude < minLat) {
        minLat = point.latitude;
      }
      if (point.latitude > maxLat) {
        maxLat = point.latitude;
      }
      if (point.longitude < minLng) {
        minLng = point.longitude;
      }
      if (point.longitude > maxLng) {
        maxLng = point.longitude;
      }
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        ),
        padding: const EdgeInsets.all(28),
      ),
    );
    _lastMapCenter = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    _lastMapZoom = 13.2;
  }

}

class _VehicleFloatingCard extends StatelessWidget {
  const _VehicleFloatingCard({
    required this.bus,
    required this.routeCode,
    required this.direction,
  });

  final BusVehicle bus;
  final String routeCode;
  final String direction;

  @override
  Widget build(BuildContext context) {
    final lat = bus.latitude?.toStringAsFixed(5) ?? '-';
    final lon = bus.longitude?.toStringAsFixed(5) ?? '-';

    return Material(
      elevation: 4,
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_bus, color: Color(0xFF0B5A25)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bus.id.isEmpty ? 'Arac' : 'Arac ${bus.id}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  direction == '1' ? 'Donus' : 'Gidis',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Hat: $routeCode'),
            if (bus.name.isNotEmpty)
              Text(
                bus.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Text('Konum: $lat, $lon'),
          ],
        ),
      ),
    );
  }
}

class _VehicleEmptyFloatingCard extends StatelessWidget {
  const _VehicleEmptyFloatingCard();

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(14),
      child: const Center(
        child: Text(
          'Canli arac bilgisi bekleniyor...',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _SelectedStopInfoCard extends StatelessWidget {
  const _SelectedStopInfoCard({
    required this.stop,
    required this.estimate,
    required this.currentRouteCode,
    required this.currentDirection,
    required this.lastRefreshAt,
    required this.onClose,
  });

  final LineStop stop;
  final StopArrivalEstimate? estimate;
  final String currentRouteCode;
  final String currentDirection;
  final DateTime? lastRefreshAt;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final refreshLabel = lastRefreshAt == null
        ? 'Guncellenmedi'
        : '${lastRefreshAt!.hour.toString().padLeft(2, '0')}:${lastRefreshAt!.minute.toString().padLeft(2, '0')}:${lastRefreshAt!.second.toString().padLeft(2, '0')}';
    final routeList = stop.routes.isEmpty
        ? currentRouteCode
        : stop.routes.take(8).join(', ');

    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white.withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stop.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Detayi kapat',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Ne geliyor: Hatlar $routeList',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Ne gidiyor: Hat $currentRouteCode • ${currentDirection == '1' ? 'Donus' : 'Gidis'}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              estimate == null
                  ? 'Tahmin yok • Son: $refreshLabel'
                  : 'En yakin: ${estimate!.nearestEtaMinutes} dk, Sonraki: ${estimate!.nextEtaMinutes ?? '-'} dk',
              style: TextStyle(
                fontSize: 12,
                color: estimate == null
                    ? const Color(0xFF6A6A6A)
                    : const Color(0xFF175E2F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LineStop {
  const LineStop({
    required this.stopId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.routes,
  });

  final String stopId;
  final String name;
  final double latitude;
  final double longitude;
  final List<String> routes;

  String get key =>
      stopId.isNotEmpty ? stopId : '${latitude.toStringAsFixed(6)}|${longitude.toStringAsFixed(6)}';
}

class StopArrivalEstimate {
  const StopArrivalEstimate({
    required this.nearestEtaMinutes,
    required this.nearestBusId,
    required this.nextEtaMinutes,
    required this.nextBusId,
  });

  final int nearestEtaMinutes;
  final String nearestBusId;
  final int? nextEtaMinutes;
  final String? nextBusId;
}

class _BusEtaCandidate {
  const _BusEtaCandidate({
    required this.busId,
    required this.etaMinutes,
  });

  final String busId;
  final int etaMinutes;
}
