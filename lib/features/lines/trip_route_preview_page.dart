import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

  bool _isLoading = true;
  String? _error;
  final List<_RouteSegment> _segments = <_RouteSegment>[];
  final List<Marker> _markers = <Marker>[];

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
    });

    try {
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
            child: _RouteLegend(trip: widget.trip),
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
  const _RouteLegend({required this.trip});

  final RankedTripOption trip;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${trip.startStop.stopName} → ${trip.endStop.stopName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            _LegendRow(
              color: const Color(0xFF2E7D32),
              title: 'Başlangıç',
              subtitle: 'Konumdan çıkış noktası',
            ),
            _LegendRow(
              color: const Color(0xFF164B9D),
              title: 'Hat ${trip.line.displayRouteCode}',
              subtitle: trip.direction == '1' ? 'Dönüş' : 'Gidiş',
            ),
            if (trip.isTransfer && trip.transferLine != null)
              _LegendRow(
                color: const Color(0xFFE65100),
                title: 'Aktarma: ${trip.transferStop?.stopName ?? "?"}',
                subtitle:
                    'Hat ${trip.transferLine!.displayRouteCode} • ${trip.transferDirection == '1' ? 'Dönüş' : 'Gidiş'}',
              ),
            _LegendRow(
              color: const Color(0xFFB63519),
              title: 'Varış durağı',
              subtitle:
                  '${trip.endStop.stopName} • ${trip.walkFromEndMinutes.toStringAsFixed(1)} dk yürüme',
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
