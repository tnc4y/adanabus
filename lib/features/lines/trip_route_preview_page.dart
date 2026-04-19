import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/bus_vehicle.dart';
import '../../data/models/trip_destination.dart';
import '../../data/services/adana_api_service.dart';
import '../shared/app_map_tile_layer.dart';
import 'smart_trip_recommender_v2.dart';
import 'trip_route_preview_widgets.dart';

class TripRoutePreviewPage extends StatefulWidget {
  const TripRoutePreviewPage({
    super.key,
    required this.trip,
    required this.origin,
    required this.destination,
  });

  final RankedTripOption trip;
  final LatLng origin;
  final TripDestination destination;

  @override
  State<TripRoutePreviewPage> createState() => _TripRoutePreviewPageState();
}

class _TripRoutePreviewPageState extends State<TripRoutePreviewPage> {
  final AdanaApiService _apiService = AdanaApiService();
  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  bool _isLoading = true;
  String? _error;
  final List<TripRouteSegment> _segments = <TripRouteSegment>[];
  final List<Marker> _markers = <Marker>[];
  TripLineLiveStatus? _primaryLiveStatus;
  TripLineLiveStatus? _transferLiveStatus;

  @override
  void initState() {
    super.initState();
    _loadRoutePreview();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadRoutePreview() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _segments.clear();
      _markers.clear();
      _primaryLiveStatus = null;
      _transferLiveStatus = null;
    });

    try {
      final allBuses = await _apiService.fetchBuses();

      final firstSegment = await _loadSegment(
        routeCode: widget.trip.line.displayRouteCode,
        direction: widget.trip.direction,
        color: const Color(0xFF164B9D),
        label: 'Hat ${widget.trip.line.displayRouteCode}',
      );
      if (firstSegment != null) {
        _segments.add(firstSegment);
      }

      if (widget.trip.isTransfer && widget.trip.transferLine != null) {
        final secondSegment = await _loadSegment(
          routeCode: widget.trip.transferLine!.displayRouteCode,
          direction: widget.trip.transferDirection ?? '0',
          color: const Color(0xFFE65100),
          label: 'Hat ${widget.trip.transferLine!.displayRouteCode}',
        );
        if (secondSegment != null) {
          _segments.add(secondSegment);
        }
      }

      final primary = _buildLiveStatusForLine(
        allBuses: allBuses,
        routeCode: widget.trip.line.displayRouteCode,
        direction: widget.trip.direction,
        referenceStop: LatLng(
          widget.trip.startStop.latitude,
          widget.trip.startStop.longitude,
        ),
      );
      _primaryLiveStatus = primary;

      if (widget.trip.isTransfer && widget.trip.transferLine != null) {
        _transferLiveStatus = _buildLiveStatusForLine(
          allBuses: allBuses,
          routeCode: widget.trip.transferLine!.displayRouteCode,
          direction: widget.trip.transferDirection ?? '0',
          referenceStop: widget.trip.transferStop == null
              ? null
              : LatLng(
                  widget.trip.transferStop!.latitude,
                  widget.trip.transferStop!.longitude,
                ),
        );
      }

      _buildMarkers();

      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fitMap();
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  TripLineLiveStatus _buildLiveStatusForLine({
    required List<BusVehicle> allBuses,
    required String routeCode,
    required String direction,
    required LatLng? referenceStop,
  }) {
    final lineBuses = allBuses
        .where(
          (bus) =>
              bus.displayRouteCode == routeCode && bus.direction == direction,
        )
        .toList(growable: false);

    final withLocation = lineBuses.where((bus) => bus.hasLocation).toList(growable: false);
    final sampleVehicles = withLocation
        .take(3)
        .map((bus) => bus.id.isEmpty ? (bus.name.isEmpty ? '-' : bus.name) : bus.id)
        .toList(growable: false);

    double? nearestMeters;
    if (referenceStop != null && withLocation.isNotEmpty) {
      var best = double.infinity;
      for (final bus in withLocation) {
        final meters = _distance.as(
          LengthUnit.Meter,
          LatLng(bus.latitude!, bus.longitude!),
          referenceStop,
        );
        if (meters < best) {
          best = meters;
        }
      }
      if (best.isFinite) {
        nearestMeters = best;
      }
    }

    return TripLineLiveStatus(
      routeCode: routeCode,
      direction: direction,
      totalBusCount: lineBuses.length,
      locatedBusCount: withLocation.length,
      nearestMetersToReferenceStop: nearestMeters,
      sampleVehicles: sampleVehicles,
    );
  }

  Future<TripRouteSegment?> _loadSegment({
    required String routeCode,
    required String direction,
    required Color color,
    required String label,
  }) async {
    final dynamic response = await _apiService.fetchKentkartPathInfo(
      displayRouteCode: routeCode,
      direction: direction,
    );

    final payload = response is Map<String, dynamic>
        ? response
        : <String, dynamic>{'data': response};

    final points = _extractPathPoints(payload);
    if (points.isEmpty) {
      return null;
    }

    return TripRouteSegment(points: points, color: color, label: label);
  }

  void _buildMarkers() {
    _markers.add(
      Marker(
        point: widget.origin,
        width: 34,
        height: 34,
        child: TripMapIconPin(
          icon: Icons.play_arrow,
          color: const Color(0xFF2E7D32),
        ),
      ),
    );

    _markers.add(
      Marker(
        point: LatLng(
          widget.trip.startStop.latitude,
          widget.trip.startStop.longitude,
        ),
        width: 34,
        height: 34,
        child: TripMapIconPin(
          icon: Icons.directions_bus,
          color: const Color(0xFF164B9D),
        ),
      ),
    );

    if (widget.trip.isTransfer && widget.trip.transferStop != null) {
      _markers.add(
        Marker(
          point: LatLng(
            widget.trip.transferStop!.latitude,
            widget.trip.transferStop!.longitude,
          ),
          width: 34,
          height: 34,
          child: TripMapIconPin(
            icon: Icons.swap_horiz,
            color: const Color(0xFFE65100),
          ),
        ),
      );
    }

    _markers.add(
      Marker(
        point: LatLng(
          widget.trip.endStop.latitude,
          widget.trip.endStop.longitude,
        ),
        width: 34,
        height: 34,
        child: TripMapIconPin(
          icon: Icons.location_on,
          color: const Color(0xFFB63519),
        ),
      ),
    );

    _markers.add(
      Marker(
        point: LatLng(widget.destination.latitude, widget.destination.longitude),
        width: 34,
        height: 34,
        child: TripMapIconPin(
          icon: Icons.flag,
          color: const Color(0xFF4A148C),
        ),
      ),
    );

    for (final segment in _segments) {
      if (segment.points.isEmpty) {
        continue;
      }
      final midpoint = segment.points[segment.points.length ~/ 2];
      _markers.add(
        Marker(
          point: midpoint,
          width: 110,
          height: 32,
          child: TripLineBadge(label: segment.label, color: segment.color),
        ),
      );
    }
  }

  void _fitMap() {
    final points = <LatLng>[
      widget.origin,
      LatLng(widget.trip.startStop.latitude, widget.trip.startStop.longitude),
      if (widget.trip.isTransfer && widget.trip.transferStop != null)
        LatLng(
          widget.trip.transferStop!.latitude,
          widget.trip.transferStop!.longitude,
        ),
      LatLng(widget.trip.endStop.latitude, widget.trip.endStop.longitude),
      LatLng(widget.destination.latitude, widget.destination.longitude),
      ..._segments.expand((segment) => segment.points),
    ];

    if (points.isEmpty) {
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        ),
        padding: const EdgeInsets.all(36),
      ),
    );
  }

  TripRouteTimelineData _buildTimelineData() {
    final now = DateTime.now();

    final walkToStart = _roundMinutes(widget.trip.walkToStartMinutes);
    final transferWait = _roundMinutes(widget.trip.transferWaitMinutes);
    final totalWait = _roundMinutes(widget.trip.waitMinutes);
    final firstWait = widget.trip.isTransfer
        ? (totalWait - transferWait).clamp(0, totalWait)
        : totalWait;

    final firstRideMinutes = _roundMinutes(_estimateFirstRideMinutes());
    final secondRideMinutes = widget.trip.isTransfer
        ? _roundMinutes(_estimateSecondRideMinutes())
        : 0;
    final walkFromEnd = _roundMinutes(widget.trip.walkFromEndMinutes);

    final startStopArrival = now.add(Duration(minutes: walkToStart));
    final firstBoarding = startStopArrival.add(Duration(minutes: firstWait));

    DateTime? transferArrival;
    DateTime? secondBoarding;
    late DateTime endStopArrival;

    if (widget.trip.isTransfer) {
      transferArrival = firstBoarding.add(Duration(minutes: firstRideMinutes));
      secondBoarding = transferArrival.add(Duration(minutes: transferWait));
      endStopArrival = secondBoarding.add(Duration(minutes: secondRideMinutes));
    } else {
      endStopArrival = firstBoarding.add(
        Duration(minutes: _roundMinutes(widget.trip.busRideMinutes)),
      );
    }

    final destinationArrival = endStopArrival.add(Duration(minutes: walkFromEnd));
    final leadFromTerminal = _roundMinutes(_estimateLeadFromTerminalMinutes());
    final terminalDeparture = firstBoarding.subtract(
      Duration(minutes: leadFromTerminal),
    );

    return TripRouteTimelineData(
      now: now,
      terminalDeparture: terminalDeparture,
      startStopArrival: startStopArrival,
      firstBoarding: firstBoarding,
      transferArrival: transferArrival,
      secondBoarding: secondBoarding,
      endStopArrival: endStopArrival,
      destinationArrival: destinationArrival,
      leadFromTerminalMinutes: leadFromTerminal,
      firstWaitMinutes: firstWait,
      transferWaitMinutes: transferWait,
    );
  }

  double _estimateFirstRideMinutes() {
    if (!widget.trip.isTransfer || widget.trip.transferStop == null) {
      return widget.trip.busRideMinutes;
    }

    final meters = _distance.as(
      LengthUnit.Meter,
      LatLng(widget.trip.startStop.latitude, widget.trip.startStop.longitude),
      LatLng(
        widget.trip.transferStop!.latitude,
        widget.trip.transferStop!.longitude,
      ),
    );
    return meters / 450;
  }

  double _estimateSecondRideMinutes() {
    if (!widget.trip.isTransfer || widget.trip.transferStop == null) {
      return 0;
    }

    final meters = _distance.as(
      LengthUnit.Meter,
      LatLng(
        widget.trip.transferStop!.latitude,
        widget.trip.transferStop!.longitude,
      ),
      LatLng(widget.trip.endStop.latitude, widget.trip.endStop.longitude),
    );
    return meters / 450;
  }

  double _estimateLeadFromTerminalMinutes() {
    if (_segments.isEmpty || _segments.first.points.isEmpty) {
      return 0;
    }

    final points = _segments.first.points;
    final startStop = LatLng(
      widget.trip.startStop.latitude,
      widget.trip.startStop.longitude,
    );

    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final meters = _distance.as(LengthUnit.Meter, points[i], startStop);
      if (meters < nearestDistance) {
        nearestDistance = meters;
        nearestIndex = i;
      }
    }

    var leadMeters = 0.0;
    for (var i = 1; i <= nearestIndex; i++) {
      leadMeters += _distance.as(LengthUnit.Meter, points[i - 1], points[i]);
    }
    return leadMeters / 450;
  }

  int _roundMinutes(double value) {
    if (!value.isFinite) {
      return 0;
    }
    return value.round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rota Önizleme'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.origin,
              initialZoom: 13,
            ),
            children: [
              buildAppMapTileLayer(context),
              PolylineLayer(
                polylines: _segments
                    .map(
                      (segment) => Polyline(
                        points: segment.points,
                        color: segment.color,
                        strokeWidth: 5,
                      ),
                    )
                    .toList(),
              ),
              MarkerLayer(markers: _markers),
            ],
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
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: TripRouteHeaderChips(trip: widget.trip),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: TripRouteLegend(
              trip: widget.trip,
              timeline: _buildTimelineData(),
              primaryLiveStatus: _primaryLiveStatus,
              transferLiveStatus: _transferLiveStatus,
            ),
          ),
        ],
      ),
    );
  }

  static List<LatLng> _extractPathPoints(Map<String, dynamic> payload) {
    final pathList = _asList(payload['pathList']);
    final points = <LatLng>[];

    void addPoint(double lat, double lon) {
      final point = LatLng(lat, lon);
      if (points.isEmpty || points.last != point) {
        points.add(point);
      }
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
            final lon = _readDouble(entry, const ['lon', 'lng', 'longitude', 'x']);
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

    return points;
  }

  static List<dynamic> _asList(dynamic value) {
    if (value is List<dynamic>) {
      return value;
    }
    return const <dynamic>[];
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
}
