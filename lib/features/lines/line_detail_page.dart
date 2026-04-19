import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/services/adana_api_service.dart';
import '../../data/models/bus_vehicle.dart';

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

  bool _isLoading = false;
  String? _error;
  String _currentDirection = '0';
  List<LineStop> _stops = <LineStop>[];
  List<LatLng> _pathPoints = <LatLng>[];
  List<LineScheduleItem> _schedules = <LineScheduleItem>[];
  List<BusVehicle> _liveRouteBuses = <BusVehicle>[];
  Map<String, StopArrivalEstimate> _arrivalByStopKey =
      <String, StopArrivalEstimate>{};
  LineStop? _selectedStop;
  int _routeBusRecordCount = 0;
  Timer? _liveBusTimer;
  DateTime? _lastBusRefreshAt;
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
      final busIds = routeBuses
          .where(
            (bus) =>
                bus.displayRouteCode == widget.routeCode &&
                bus.direction == _currentDirection &&
                bus.id.isNotEmpty,
          )
          .map((bus) => bus.id)
          .toSet()
          .take(6)
          .toList();
        final liveRouteBuses = routeBuses
          .where(
              (bus) =>
                  bus.displayRouteCode == widget.routeCode &&
                  bus.direction == _currentDirection &&
                  bus.hasLocation,
          )
          .toList(growable: false);
        final routeBusRecords = routeBuses
            .where(
              (bus) =>
                  bus.displayRouteCode == widget.routeCode &&
                  bus.direction == _currentDirection,
            )
            .length;

      final stops = _extractStops(pathPayload);
      final points = _extractPathPoints(pathPayload, stops);
      final stopNameById = _extractStopNameById(pathPayload);
      final schedules = await _loadRealSchedules(busIds, stopNameById);
      final resolvedLiveBuses = liveBusesFromPath.isNotEmpty
          ? liveBusesFromPath
          : liveRouteBuses;
      final arrivals = _buildStopArrivalEstimates(stops, resolvedLiveBuses);

      setState(() {
        _stops = stops;
        _pathPoints = points;
        _schedules = schedules;
        _liveRouteBuses = resolvedLiveBuses;
        _arrivalByStopKey = arrivals;
        _selectedStop = _resolveSelectedStop(stops, _selectedStop);
        _routeBusRecordCount = routeBusRecords;
        _lastBusRefreshAt = DateTime.now();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _fitMapToRoute();
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
        _schedules = <LineScheduleItem>[];
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
        final routeBusRecords = buses
          .where(
          (bus) =>
            bus.displayRouteCode == widget.routeCode &&
            bus.direction == _currentDirection,
          )
          .length;
      final resolved = liveBusesFromPath.isNotEmpty
          ? liveBusesFromPath
          : filteredFromBuses;
        final arrivals = _buildStopArrivalEstimates(_stops, resolved);

      if (!mounted) {
        return;
      }

      setState(() {
        _liveRouteBuses = resolved;
        _arrivalByStopKey = arrivals;
        _routeBusRecordCount = routeBusRecords;
        _lastBusRefreshAt = DateTime.now();
      });
    } catch (_) {
      // Live tracking should not break the route page if one refresh fails.
    }
  }

  Future<List<LineScheduleItem>> _loadRealSchedules(
    List<String> busIds,
    Map<String, String> stopNameById,
  ) async {
    final result = <LineScheduleItem>[];
    final dedupe = <String>{};

    for (final busId in busIds) {
      try {
        final response = await _apiService.fetchStopBusTimeByBusId(busId);
        final records = _extractAnyRecords(response);
        for (final record in records) {
          final time = _extractTime(record);
          if (time == null) {
            continue;
          }

          final stopName = _readString(record, const [
            'StopName',
            'stopName',
            'stationName',
            'Name',
            'name',
          ]);
          final stopId = _readString(record, const ['StopId', 'stopId']);
          final resolvedStopName = stopName.isNotEmpty
              ? stopName
              : (stopNameById[stopId] ?? 'Durak bilgisi yok');

          final key = '$busId|$time|$resolvedStopName';
          if (!dedupe.add(key)) {
            continue;
          }

          result.add(
            LineScheduleItem(
              busId: busId,
              stopName: resolvedStopName,
              timeText: time,
            ),
          );
        }
      } catch (_) {
        continue;
      }
    }

    result.sort((a, b) => a.timeText.compareTo(b.timeText));
    return result;
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

  @override
  Widget build(BuildContext context) {
    final center = _resolveRouteCenter();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Hat ${widget.routeCode}'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(68),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                children: [
                  Text(
                    widget.routeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('Gidis'),
                        selected: _currentDirection == '0',
                        onSelected: _isLoading
                            ? null
                            : (_) {
                                if (_currentDirection != '0') {
                                  setState(() {
                                    _currentDirection = '0';
                                  });
                                  _loadDetail();
                                }
                              },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Donus'),
                        selected: _currentDirection == '1',
                        onSelected: _isLoading
                            ? null
                            : (_) {
                                if (_currentDirection != '1') {
                                  setState(() {
                                    _currentDirection = '1';
                                  });
                                  _loadDetail();
                                }
                              },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
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
                              (bus) => Marker(
                                point: LatLng(bus.latitude!, bus.longitude!),
                                width: 46,
                                height: 46,
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
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.directions_bus,
                                      color: Color(0xFF0B5A25),
                                      size: 24,
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 8,
                            offset: Offset(0, 2),
                            color: Color(0x22000000),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Canli: ${_liveRouteBuses.length} otobus',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _lastBusRefreshAt == null
                                  ? 'Guncellenmedi'
                                  : 'Son: ${_lastBusRefreshAt!.hour.toString().padLeft(2, '0')}:${_lastBusRefreshAt!.minute.toString().padLeft(2, '0')}:${_lastBusRefreshAt!.second.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF444444),
                              ),
                            ),
                            if (_routeBusRecordCount > 0 &&
                                _liveRouteBuses.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  'API bu hatta konum vermiyor',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF9C2E1D),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: _refreshLiveBuses,
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.refresh, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Simdi yenile',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_selectedStop != null)
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 150,
                      child: _SelectedStopInfoCard(
                        stop: _selectedStop!,
                        estimate: _arrivalByStopKey[_selectedStop!.key],
                        currentRouteCode: widget.routeCode,
                        currentDirection: _currentDirection,
                        lastRefreshAt: _lastBusRefreshAt,
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
            ),
            SizedBox(
              height: 260,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Saatler'),
                      Tab(text: 'Duraklar'),
                      Tab(text: 'Araclar'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _ScheduleTab(
                          schedules: _schedules,
                        ),
                        _StopsTab(
                          stops: _stops,
                          arrivalByStopKey: _arrivalByStopKey,
                          lastRefreshAt: _lastBusRefreshAt,
                        ),
                        _VehiclesTab(
                          buses: _liveRouteBuses,
                          routeBusRecordCount: _routeBusRecordCount,
                          lastRefreshAt: _lastBusRefreshAt,
                          onRefresh: _refreshLiveBuses,
                        ),
                      ],
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

  static List<Map<String, dynamic>> _extractAnyRecords(dynamic payload) {
    final collected = <Map<String, dynamic>>[];

    void walk(dynamic node, int depth) {
      if (depth > 6 || node == null) {
        return;
      }

      if (node is Map<String, dynamic>) {
        collected.add(node);
        for (final value in node.values) {
          walk(value, depth + 1);
        }
        return;
      }

      if (node is List) {
        for (final item in node) {
          walk(item, depth + 1);
        }
      }
    }

    walk(payload, 0);
    return collected;
  }

  static String? _extractTime(Map<String, dynamic> record) {
    final direct = _readString(record, const [
      'PassTime',
      'passTime',
      'Time',
      'time',
      'Saat',
      'hour',
      'arrivalTime',
      'nextTime',
    ]);
    if (_looksLikeTime(direct)) {
      return direct;
    }

    for (final value in record.values) {
      final text = value?.toString() ?? '';
      final match = RegExp(r'(?:[01]?\d|2[0-3]):[0-5]\d').firstMatch(text);
      if (match != null) {
        return match.group(0);
      }
    }
    return null;
  }

  static bool _looksLikeTime(String value) {
    return RegExp(r'^(?:[01]?\d|2[0-3]):[0-5]\d$').hasMatch(value.trim());
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
      _mapController.move(_resolveRouteCenter(), 12.8);
      return;
    }

    if (points.length == 1) {
      _mapController.move(points.first, 15);
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
  }

  static Map<String, String> _extractStopNameById(
      Map<String, dynamic> payload) {
    final pathList = _asList(payload['pathList']);
    final map = <String, String>{};

    for (final item in pathList) {
      if (item is! Map<String, dynamic>) {
        continue;
      }

      final rawStops = _asList(item['busStopList']);
      for (final rawStop in rawStops) {
        if (rawStop is! Map<String, dynamic>) {
          continue;
        }

        final stopId = _readString(rawStop, const ['stopId', 'StopId']);
        final stopName = _readString(rawStop, const ['stopName', 'StopName']);
        if (stopId.isNotEmpty && stopName.isNotEmpty) {
          map[stopId] = stopName;
        }
      }
    }

    return map;
  }
}

class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab({required this.schedules});

  final List<LineScheduleItem> schedules;

  @override
  Widget build(BuildContext context) {
    if (schedules.isEmpty) {
      return const Center(
        child: Text('Saat bilgisi bulunamadi.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      itemCount: schedules.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final schedule = schedules[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F9FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  schedule.stopName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                schedule.timeText,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StopsTab extends StatelessWidget {
  const _StopsTab({
    required this.stops,
    required this.arrivalByStopKey,
    required this.lastRefreshAt,
  });

  final List<LineStop> stops;
  final Map<String, StopArrivalEstimate> arrivalByStopKey;
  final DateTime? lastRefreshAt;

  @override
  Widget build(BuildContext context) {
    final refreshLabel = lastRefreshAt == null
        ? 'Guncellenmedi'
        : '${lastRefreshAt!.hour.toString().padLeft(2, '0')}:${lastRefreshAt!.minute.toString().padLeft(2, '0')}:${lastRefreshAt!.second.toString().padLeft(2, '0')}';

    if (stops.isEmpty) {
      return const Center(
        child: Text('Durak bilgisi bulunamadi.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      itemCount: stops.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final stop = stops[index];
        final estimate = arrivalByStopKey[stop.key];
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBF2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFEAF2FF),
                child:
                    Text('${index + 1}', style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    if (estimate == null)
                      Text(
                        'Tahmini gelis verisi yok • Son: $refreshLabel',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6A6A6A),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _EtaChip(
                            label:
                                'En yakin: ${estimate.nearestEtaMinutes} dk${estimate.nearestBusId.isEmpty ? '' : ' (Arac ${estimate.nearestBusId})'}',
                            color: const Color(0xFFE8F5E9),
                            textColor: const Color(0xFF175E2F),
                          ),
                          if (estimate.nextEtaMinutes != null)
                            _EtaChip(
                              label:
                                  'Sonraki: ${estimate.nextEtaMinutes} dk${(estimate.nextBusId ?? '').isEmpty ? '' : ' (Arac ${estimate.nextBusId})'}',
                              color: const Color(0xFFEAF2FF),
                              textColor: const Color(0xFF164B9D),
                            ),
                          _EtaChip(
                            label: 'Guncelleme: $refreshLabel',
                            color: const Color(0xFFF5F5F5),
                            textColor: const Color(0xFF555555),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EtaChip extends StatelessWidget {
  const _EtaChip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
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
  });

  final LineStop stop;
  final StopArrivalEstimate? estimate;
  final String currentRouteCode;
  final String currentDirection;
  final DateTime? lastRefreshAt;

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
            Text(
              stop.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
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

class _VehiclesTab extends StatelessWidget {
  const _VehiclesTab({
    required this.buses,
    required this.routeBusRecordCount,
    required this.lastRefreshAt,
    required this.onRefresh,
  });

  final List<BusVehicle> buses;
  final int routeBusRecordCount;
  final DateTime? lastRefreshAt;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final timeLabel = lastRefreshAt == null
        ? 'Guncellenmedi'
        : '${lastRefreshAt!.hour.toString().padLeft(2, '0')}:${lastRefreshAt!.minute.toString().padLeft(2, '0')}:${lastRefreshAt!.second.toString().padLeft(2, '0')}';

    if (buses.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F9FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Canli arac verisi su anda yok.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text('Son yenileme: $timeLabel'),
                const SizedBox(height: 6),
                Text('Hatta bulunan kayit sayisi: $routeBusRecordCount'),
                if (routeBusRecordCount > 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Bu hatta kayit var ancak API konum bilgisi vermiyor.',
                      style: TextStyle(
                        color: Color(0xFF9C2E1D),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Yeniden dene'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      itemCount: buses.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF8F1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Canli arac: ${buses.length} • Son: $timeLabel',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Yenile',
                ),
              ],
            ),
          );
        }

        final bus = buses[index - 1];
        final lat = bus.latitude?.toStringAsFixed(6) ?? '-';
        final lon = bus.longitude?.toStringAsFixed(6) ?? '-';

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F9FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.directions_bus,
                    color: Color(0xFF0B5A25),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bus.id.isEmpty ? 'Arac' : 'Arac ${bus.id}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (bus.direction.isNotEmpty)
                    Text(
                      bus.direction == '1' ? 'Donus' : 'Gidis',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Hat: ${bus.displayRouteCode.isEmpty ? '-' : bus.displayRouteCode}'),
              if (bus.name.isNotEmpty) Text('Ad: ${bus.name}'),
              Text('Konum: $lat, $lon'),
            ],
          ),
        );
      },
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

class LineScheduleItem {
  const LineScheduleItem({
    required this.busId,
    required this.stopName,
    required this.timeText,
  });

  final String busId;
  final String stopName;
  final String timeText;
}
