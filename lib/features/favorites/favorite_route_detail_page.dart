import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/services/adana_api_service.dart';
import '../shared/geo_math_utils.dart';
import 'favorite_route_item.dart';
import 'favorite_route_detail_service.dart';

class FavoriteRouteDetailPage extends StatefulWidget {
  const FavoriteRouteDetailPage({
    super.key,
    required this.item,
  });

  final FavoriteRouteItem item;

  @override
  State<FavoriteRouteDetailPage> createState() => _FavoriteRouteDetailPageState();
}

class _FavoriteRouteDetailPageState extends State<FavoriteRouteDetailPage> {
  final AdanaApiService _apiService = AdanaApiService();
  final FavoriteRouteDetailService _detailService =
      const FavoriteRouteDetailService();
  final MapController _mapController = MapController();

  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdatedAt;
  List<FavoriteRouteCandidate> _candidates = <FavoriteRouteCandidate>[];
  String? _selectedKey;

  static const List<Color> _palette = <Color>[
    Color(0xFF164B9D),
    Color(0xFFE65100),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFC62828),
    Color(0xFF00838F),
    Color(0xFF9E9D24),
  ];
  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final parsed = await _detailService.loadCandidates(
        apiService: _apiService,
        item: widget.item,
        palette: _palette,
      );

      setState(() {
        _candidates = parsed;
        if (parsed.isEmpty) {
          _selectedKey = null;
        } else {
          final keepCurrent = parsed.any((c) => c.key == _selectedKey);
          _selectedKey = keepCurrent ? _selectedKey : parsed.first.key;
        }
        _lastUpdatedAt = DateTime.now();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _fitToSelection();
        }
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

  void _fitToSelection() {
    final selected = _selected;
    if (selected == null) {
      _mapController.move(LatLng(widget.item.startLatitude, widget.item.startLongitude), 13.8);
      return;
    }

    final allPoints = <LatLng>[
      LatLng(widget.item.startLatitude, widget.item.startLongitude),
      LatLng(widget.item.endLatitude, widget.item.endLongitude),
      ...selected.remainingPoints,
    ];

    final bounds = GeoMathUtils.boundsForPoints(allPoints);
    if (bounds == null) {
      return;
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(24),
      ),
    );
  }

  FavoriteRouteCandidate? get _selected {
    if (_candidates.isEmpty) {
      return null;
    }
    return _candidates.firstWhere(
      (item) => item.key == _selectedKey,
      orElse: () => _candidates.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final updated = _lastUpdatedAt == null
        ? 'Guncellenmedi'
        : '${_lastUpdatedAt!.hour.toString().padLeft(2, '0')}:${_lastUpdatedAt!.minute.toString().padLeft(2, '0')}:${_lastUpdatedAt!.second.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.item.startStopName} → ${widget.item.endStopName}'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadCandidates,
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: LatLng(widget.item.startLatitude, widget.item.startLongitude),
                    initialZoom: 13.8,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.adanabus',
                    ),
                    if (selected != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: selected.remainingPoints,
                            color: selected.color.withValues(alpha: 0.9),
                            strokeWidth: 5,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(widget.item.startLatitude, widget.item.startLongitude),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.trip_origin, color: Color(0xFF2E7D32), size: 26),
                        ),
                        Marker(
                          point: LatLng(widget.item.endLatitude, widget.item.endLongitude),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.flag, color: Color(0xFFB63519), size: 28),
                        ),
                        if (selected != null)
                          ...selected.buses.where((b) => b.hasLocation).map(
                                (bus) => Marker(
                                  point: LatLng(bus.latitude!, bus.longitude!),
                                  width: 44,
                                  height: 44,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                      const Icon(Icons.directions_bus, size: 22, color: Color(0xFF0B5A25)),
                                    ],
                                  ),
                                ),
                              ),
                      ],
                    ),
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
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              itemCount: _candidates.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F7FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Son guncelleme: $updated • Uygun hat: ${_candidates.length}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  );
                }

                final item = _candidates[index - 1];
                final isSelected = selected?.key == item.key;
                final etaText = item.nearestEtaMinutes == null
                    ? 'Tahmini gelis: Veri yok'
                    : 'Tahmini gelis: ${item.nearestEtaMinutes} dk${item.nextEtaMinutes == null ? '' : ' • Sonraki ${item.nextEtaMinutes} dk'}';

                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    setState(() {
                      _selectedKey = item.key;
                    });
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _fitToSelection();
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFFEAF2FF) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF164B9D) : const Color(0xFFE2E7F0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Hat ${item.routeCode} • ${item.direction == '1' ? 'Donus' : 'Gidis'}',
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(
                              '${(item.remainingMeters / 1000).toStringAsFixed(1)} km',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF555555)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Nereden geliyor: ${item.fromStopName.isEmpty ? '-' : item.fromStopName}'),
                        Text('Nereye gidiyor: ${item.toStopName.isEmpty ? '-' : item.toStopName}'),
                        const SizedBox(height: 4),
                        Text(
                          etaText,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: item.nearestEtaMinutes == null
                                ? const Color(0xFF8A6D3B)
                                : const Color(0xFF175E2F),
                          ),
                        ),
                        Text('Canli arac: ${item.buses.length}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

}
