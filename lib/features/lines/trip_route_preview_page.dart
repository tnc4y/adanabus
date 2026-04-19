import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/bus_vehicle.dart';
import '../../data/models/trip_destination.dart';
import '../../data/services/adana_api_service.dart';
import 'smart_trip_recommender_v2.dart';

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
  final List<_RouteSegment> _segments = <_RouteSegment>[];
  final List<Marker> _markers = <Marker>[];
  _LineLiveStatus? _primaryLiveStatus;
  _LineLiveStatus? _transferLiveStatus;

  @override
  void initState() {
    super.initState();
    _loadRoutePreview();
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

  _LineLiveStatus _buildLiveStatusForLine({
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

    return _LineLiveStatus(
      routeCode: routeCode,
      direction: direction,
      totalBusCount: lineBuses.length,
      locatedBusCount: withLocation.length,
      nearestMetersToReferenceStop: nearestMeters,
      sampleVehicles: sampleVehicles,
    );
  }

  Future<_RouteSegment?> _loadSegment({
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

    return _RouteSegment(points: points, color: color, label: label);
  }

  void _buildMarkers() {
    _markers.add(
      Marker(
        point: widget.origin,
        width: 34,
        height: 34,
        child: _MapIconPin(
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
        child: _MapIconPin(
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
          child: _MapIconPin(
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
        child: _MapIconPin(
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
        child: _MapIconPin(
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
          child: _LineBadge(label: segment.label, color: segment.color),
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

  _RouteTimelineData _buildTimelineData() {
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

    return _RouteTimelineData(
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
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.adanabus',
                maxZoom: 19,
              ),
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
            child: _RouteHeaderChips(trip: widget.trip),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _RouteLegend(
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

class _RouteSegment {
  const _RouteSegment({
    required this.points,
    required this.color,
    required this.label,
  });

  final List<LatLng> points;
  final Color color;
  final String label;
}

class _MapIconPin extends StatelessWidget {
  const _MapIconPin({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            offset: Offset(0, 2),
            color: Color(0x33000000),
          ),
        ],
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}

class _RouteHeaderChips extends StatelessWidget {
  const _RouteHeaderChips({required this.trip});

  final RankedTripOption trip;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _RouteChip(
        color: const Color(0xFF164B9D),
        label: 'Hat ${trip.line.displayRouteCode}',
        subtitle: trip.direction == '1' ? 'Dönüş' : 'Gidiş',
      ),
      if (trip.isTransfer && trip.transferLine != null)
        _RouteChip(
          color: const Color(0xFFE65100),
          label: 'Hat ${trip.transferLine!.displayRouteCode}',
          subtitle: trip.transferDirection == '1' ? 'Dönüş' : 'Gidiş',
        ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: chips),
    );
  }
}

class _RouteChip extends StatelessWidget {
  const _RouteChip({
    required this.color,
    required this.label,
    required this.subtitle,
  });

  final Color color;
  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 8,
            offset: Offset(0, 2),
            color: Color(0x22000000),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LineBadge extends StatelessWidget {
  const _LineBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          boxShadow: const [
            BoxShadow(
              blurRadius: 10,
              offset: Offset(0, 2),
              color: Color(0x33000000),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RouteLegend extends StatelessWidget {
  const _RouteLegend({
    required this.trip,
    required this.timeline,
    required this.primaryLiveStatus,
    required this.transferLiveStatus,
  });

  final RankedTripOption trip;
  final _RouteTimelineData timeline;
  final _LineLiveStatus? primaryLiveStatus;
  final _LineLiveStatus? transferLiveStatus;

  @override
  Widget build(BuildContext context) {
    final primary = primaryLiveStatus;
    final transfer = transferLiveStatus;

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white.withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${trip.startStop.stopName} → ${trip.endStop.stopName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                if (primary != null)
                  _MiniDotChip(
                    color: const Color(0xFF164B9D),
                    label: '${primary.locatedBusCount}/${primary.totalBusCount}',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _MiniInfoChip(
                    icon: Icons.access_time,
                    label: 'Çıkış ${_fmtClock(timeline.terminalDeparture)}',
                  ),
                  const SizedBox(width: 8),
                  _MiniInfoChip(
                    icon: Icons.directions_bus,
                    label: 'Biniş ${_fmtClock(timeline.firstBoarding)}',
                  ),
                  const SizedBox(width: 8),
                  _MiniInfoChip(
                    icon: Icons.flag,
                    label: 'Varış ${_fmtClock(timeline.destinationArrival)}',
                  ),
                  if (trip.isTransfer && trip.transferLine != null) ...[
                    const SizedBox(width: 8),
                    _MiniInfoChip(
                      icon: Icons.swap_horiz,
                      label: 'Aktarma ${trip.transferLine!.displayRouteCode}',
                    ),
                  ],
                  if (primary != null) ...[
                    const SizedBox(width: 8),
                    _MiniInfoChip(
                      icon: Icons.my_location,
                      label: primary.nearestMetersToReferenceStop == null
                          ? 'Canlı araç var'
                          : 'Canlı ~${primary.nearestMetersToReferenceStop!.round()}m',
                    ),
                  ],
                  if (transfer != null) ...[
                    const SizedBox(width: 8),
                    _MiniInfoChip(
                      icon: Icons.alt_route,
                      label: 'Aktarma canlı ${transfer.locatedBusCount}',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtClock(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _MiniInfoChip extends StatelessWidget {
  const _MiniInfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E7F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF5E6B82)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _MiniDotChip extends StatelessWidget {
  const _MiniDotChip({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _RouteTimelineData {
  const _RouteTimelineData({
    required this.now,
    required this.terminalDeparture,
    required this.startStopArrival,
    required this.firstBoarding,
    required this.transferArrival,
    required this.secondBoarding,
    required this.endStopArrival,
    required this.destinationArrival,
    required this.leadFromTerminalMinutes,
    required this.firstWaitMinutes,
    required this.transferWaitMinutes,
  });

  final DateTime now;
  final DateTime terminalDeparture;
  final DateTime startStopArrival;
  final DateTime firstBoarding;
  final DateTime? transferArrival;
  final DateTime? secondBoarding;
  final DateTime endStopArrival;
  final DateTime destinationArrival;
  final int leadFromTerminalMinutes;
  final int firstWaitMinutes;
  final int transferWaitMinutes;
}

class _LineLiveStatus {
  const _LineLiveStatus({
    required this.routeCode,
    required this.direction,
    required this.totalBusCount,
    required this.locatedBusCount,
    required this.nearestMetersToReferenceStop,
    required this.sampleVehicles,
  });

  final String routeCode;
  final String direction;
  final int totalBusCount;
  final int locatedBusCount;
  final double? nearestMetersToReferenceStop;
  final List<String> sampleVehicles;
}
