import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme_utils.dart';
import '../../data/services/adana_api_service.dart';
import '../../data/models/bus_vehicle.dart';
import '../shared/app_map_tile_layer.dart';
import '../shared/geo_math_utils.dart';
import 'line_detail_models.dart';
import 'line_detail_overlays.dart';
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
  String? _departureTimeText;
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
      final departureTimeText = await _resolveNearestDepartureTimeForToday(
        stops: stops,
        allBuses: routeBuses,
        liveBuses: resolvedLiveBuses,
      );
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
        _departureTimeText = departureTimeText;
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
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
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
              buildAppMapTileLayer(context),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _pathPoints,
                    color: AppThemeUtils.getAccentColor(context, 'blue'),
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
                                  ? AppThemeUtils.getAccentColor(context, 'green')
                                  : AppThemeUtils.getAccentColor(context, 'orange'),
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
                                        ? AppThemeUtils.getAccentColor(context, 'green')
                                        : AppThemeUtils.getAccentColor(context, 'blue'),
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
                                      ? AppThemeUtils.getAccentColor(context, 'green')
                                      : AppThemeUtils.getAccentColor(context, 'blue'),
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
              if (_departureTimeText != null && _stops.isNotEmpty)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(_stops.first.latitude, _stops.first.longitude),
                      width: 164,
                      height: 64,
                      child: IgnorePointer(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppThemeUtils.getAccentColor(context, 'green'),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Cikis: $_departureTimeText',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Icon(
                              Icons.play_circle_fill,
                              color: AppThemeUtils.getAccentColor(context, 'green'),
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          if (_selectedStop != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 18,
              child: LineDetailSelectedStopInfoCard(
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
                  ? const LineDetailVehicleEmptyFloatingCard()
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
                            child: LineDetailVehicleFloatingCard(
                              bus: bus,
                              progress: _buildVehicleRouteProgress(bus),
                            ),
                          );
                        },
                      ),
              ),
            ),
          Positioned(
            right: 14,
            bottom: 160,
            child: _LineDetailFloatingActions(
              onToggleDirection: _isLoading ? null : _toggleDirection,
              onOpenTimetable: _openTimetablePage,
              directionTooltip:
                  _currentDirection == '1' ? 'Gidise gec' : 'Donuse gec',
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: AppThemeUtils.getOverlayColor(context, 0.55),
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
                  color: AppThemeUtils.getDisabledColor(context),
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
    if (stops.isEmpty || previous == null) {
      return null;
    }
    for (final stop in stops) {
      if (stop.key == previous.key) {
        return stop;
      }
    }
    return null;
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
      final candidates = <BusEtaCandidate>[];
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
          BusEtaCandidate(
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

  Future<String?> _resolveNearestDepartureTimeForToday({
    required List<LineStop> stops,
    required List<BusVehicle> allBuses,
    required List<BusVehicle> liveBuses,
  }) async {
    if (stops.isEmpty) {
      return null;
    }

    final candidateBusIds = <String>[];
    final seen = <String>{};

    void addBusId(String id) {
      final normalized = id.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        return;
      }
      candidateBusIds.add(normalized);
    }

    for (final bus in allBuses.where((bus) =>
        bus.displayRouteCode == widget.routeCode &&
        bus.direction == _currentDirection)) {
      addBusId(bus.id);
    }
    for (final bus in liveBuses.where((bus) =>
        bus.displayRouteCode == widget.routeCode &&
        bus.direction == _currentDirection)) {
      addBusId(bus.id);
    }

    if (candidateBusIds.isEmpty) {
      return null;
    }

    final now = TimeOfDay.now();
    final nowMinutes = (now.hour * 60) + now.minute;
    final todayDayType = _todayDayType(DateTime.now());

    int? bestMinutes;
    String? bestLabel;

    for (final busId in candidateBusIds.take(8)) {
      try {
        final dynamic raw = await _apiService.fetchStopBusTimeByBusId(busId);
        final payload = raw is Map<String, dynamic>
            ? raw
            : <String, dynamic>{'data': raw};
        final times = _extractTimesForDayType(
          payload,
          todayDayType,
          targetDirection: _currentDirection,
        );

        for (final time in times) {
          final minutes = _timeStringToMinutes(time);
          if (minutes == null || minutes < nowMinutes) {
            continue;
          }

          if (bestMinutes == null || minutes < bestMinutes) {
            bestMinutes = minutes;
            bestLabel = time;
          }
        }
      } catch (_) {
        continue;
      }
    }

    if (bestMinutes == null || bestLabel == null) {
      return null;
    }

    final diff = bestMinutes - nowMinutes;
    if (diff > 600) {
      return null;
    }

    return bestLabel;
  }

  int _todayDayType(DateTime now) {
    if (now.weekday == DateTime.saturday) {
      return 6;
    }
    if (now.weekday == DateTime.sunday) {
      return 7;
    }
    return 0;
  }

  List<String> _extractTimesForDayType(
    Map<String, dynamic> payload,
    int dayType, {
    required String targetDirection,
  }) {
    final found = <String>{};
    final timePattern = RegExp(r'\b(?:[01]?\d|2[0-3]):[0-5]\d\b');
    final dateLikePattern = RegExp(r'\b\d{4}[-/.]\d{1,2}[-/.]\d{1,2}\b');

    bool isScheduleKey(String? key) {
      final k = (key ?? '').toLowerCase().replaceAll('_', '');
      return k.contains('saat') ||
          k.contains('time') ||
          k.contains('hour') ||
          k.contains('kalkis') ||
          k.contains('departure') ||
          k.contains('sefer');
    }

    bool isNoiseKey(String? key) {
      final k = (key ?? '').toLowerCase().replaceAll('_', '');
      return k.contains('update') ||
          k.contains('timestamp') ||
          k.contains('created') ||
          k.contains('modified') ||
          k.contains('date') ||
          k.contains('guncel') ||
          k.contains('refresh') ||
          k.contains('last');
    }

    bool looksLikeScheduleValue(String text, String? keyHint) {
      if (text.trim().isEmpty) {
        return false;
      }
      if (dateLikePattern.hasMatch(text)) {
        return false;
      }
      if (isNoiseKey(keyHint)) {
        return false;
      }

      final hasTime = timePattern.hasMatch(text);
      if (!hasTime) {
        return false;
      }

      // Prefer explicit schedule fields; fallback for short plain time rows.
      if (isScheduleKey(keyHint)) {
        return true;
      }

      return text.length <= 64;
    }

    int? parseDayTypeFromMap(Map map, int? inherited) {
      int? resolved = inherited;
      for (final entry in map.entries) {
        final key = entry.key.toString().toLowerCase().replaceAll('_', '');
        if (key == 'daytype' || key == 'day') {
          final parsed = int.tryParse(entry.value.toString().trim());
          if (parsed != null) {
            resolved = parsed;
            break;
          }
        }
      }
      return resolved;
    }

    String? normalizeDirectionValue(dynamic raw) {
      if (raw == null) {
        return null;
      }

      final text = raw.toString().trim().toLowerCase();
      if (text.isEmpty) {
        return null;
      }

      if (text == '0' ||
          text == 'gidis' ||
          text == 'gidi' ||
          text == 'gidiş' ||
          text == 'outbound') {
        return '0';
      }

      if (text == '1' ||
          text == 'donus' ||
          text == 'dönüş' ||
          text == 'donuş' ||
          text == 'inbound') {
        return '1';
      }

      return null;
    }

    String? parseDirectionFromMap(Map map, String? inherited) {
      var resolved = inherited;
      for (final entry in map.entries) {
        final key = entry.key.toString().toLowerCase().replaceAll('_', '');
        if (key == 'direction' ||
            key == 'dir' ||
            key == 'routeDirection'.toLowerCase() ||
            key == 'yon' ||
            key == 'yön') {
          final parsed = normalizeDirectionValue(entry.value);
          if (parsed != null) {
            resolved = parsed;
            break;
          }
        }
      }
      return resolved;
    }

    void walk(
      dynamic node,
      int? inheritedDayType,
      String? inheritedDirection,
      String? keyHint,
    ) {
      if (node is Map) {
        final resolvedDayType = parseDayTypeFromMap(node, inheritedDayType);
        final resolvedDirection = parseDirectionFromMap(node, inheritedDirection);
        for (final entry in node.entries) {
          walk(
            entry.value,
            resolvedDayType,
            resolvedDirection,
            entry.key.toString(),
          );
        }
        return;
      }

      if (node is List) {
        for (final item in node) {
          walk(item, inheritedDayType, inheritedDirection, keyHint);
        }
        return;
      }

      if (inheritedDayType != dayType || node == null) {
        return;
      }

      if (inheritedDirection != null && inheritedDirection != targetDirection) {
        return;
      }

      final text = node.toString();
      if (!looksLikeScheduleValue(text, keyHint)) {
        return;
      }
      for (final match in timePattern.allMatches(text)) {
        final value = match.group(0);
        if (value != null) {
          found.add(value);
        }
      }
    }

    walk(payload, null, null, null);

    final sorted = found.toList(growable: false);
    sorted.sort((a, b) {
      final am = _timeStringToMinutes(a) ?? 0;
      final bm = _timeStringToMinutes(b) ?? 0;
      return am.compareTo(bm);
    });
    return sorted;
  }

  int? _timeStringToMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return null;
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      return null;
    }
    return (hour * 60) + minute;
  }

  VehicleRouteProgress? _buildVehicleRouteProgress(BusVehicle bus) {
    if (!bus.hasLocation || _stops.isEmpty) {
      return null;
    }

    final totalStops = _stops.length;
    final startStopName = _stops.first.name;
    final endStopName = _stops.last.name;

    int nextStopIndex;

    if (_pathPoints.length > 1) {
      final busPathIndex = GeoMathUtils.nearestPointIndex(
        _pathPoints,
        bus.latitude!,
        bus.longitude!,
      );

      if (busPathIndex >= 0) {
        final stopPathIndexes = _stops
            .map(
              (stop) => GeoMathUtils.nearestPointIndex(
                _pathPoints,
                stop.latitude,
                stop.longitude,
              ),
            )
            .toList(growable: false);

        nextStopIndex = stopPathIndexes.indexWhere(
          (index) => index >= 0 && index >= busPathIndex,
        );
        if (nextStopIndex < 0) {
          nextStopIndex = totalStops - 1;
        }
      } else {
        nextStopIndex = _fallbackNextStopIndexByDistance(bus);
      }
    } else {
      nextStopIndex = _fallbackNextStopIndexByDistance(bus);
    }

    nextStopIndex = nextStopIndex.clamp(0, totalStops - 1);
    final remainingStops = (totalStops - nextStopIndex).clamp(0, totalStops);
    final progress = totalStops <= 1
        ? 1.0
        : (nextStopIndex / (totalStops - 1)).clamp(0.0, 1.0);

    return VehicleRouteProgress(
      progress: progress,
      remainingStops: remainingStops,
      startStopName: startStopName,
      nextStopName: _stops[nextStopIndex].name,
      endStopName: endStopName,
    );
  }

  int _fallbackNextStopIndexByDistance(BusVehicle bus) {
    var nearestIndex = 0;
    var nearestMeters = double.infinity;

    for (var i = 0; i < _stops.length; i++) {
      final stop = _stops[i];
      final meters = _distanceMeters(
        bus.latitude!,
        bus.longitude!,
        stop.latitude,
        stop.longitude,
      );
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearestIndex = i;
      }
    }

    return math.min(nearestIndex + 1, _stops.length - 1);
  }

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

class _LineDetailFloatingActions extends StatelessWidget {
  const _LineDetailFloatingActions({
    required this.onToggleDirection,
    required this.onOpenTimetable,
    required this.directionTooltip,
  });

  final VoidCallback? onToggleDirection;
  final VoidCallback onOpenTimetable;
  final String directionTooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(14),
      color: AppThemeUtils.getCardColor(context).withValues(alpha: 0.95),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onToggleDirection,
              icon: const Icon(Icons.swap_horiz),
              tooltip: directionTooltip,
            ),
            IconButton(
              onPressed: onOpenTimetable,
              icon: const Icon(Icons.schedule),
              tooltip: 'Cikis saatleri',
            ),
          ],
        ),
      ),
    );
  }
}
