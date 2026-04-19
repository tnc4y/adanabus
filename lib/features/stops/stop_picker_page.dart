import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme_utils.dart';
import '../../data/models/transit_stop.dart';
import '../../data/services/adana_api_service.dart';
import '../shared/app_map_tile_layer.dart';

enum StopPickerViewMode { list, map }

class StopPickerPage extends StatefulWidget {
  const StopPickerPage({
    super.key,
    required this.selectedStopIds,
  });

  final Set<String> selectedStopIds;

  @override
  State<StopPickerPage> createState() => _StopPickerPageState();
}

class _StopPickerPageState extends State<StopPickerPage> {
  final AdanaApiService _apiService = AdanaApiService();
  final MapController _mapController = MapController();

  static const double _initialMapZoom = 12.5;
  static const double _minMapZoom = 11.8;
  static const double _maxMapZoom = 19.0;
  static const double _denseMarkerZoomThreshold = 12.3;
  static const int _hardMarkerCap = 2200;

  List<TransitStop> _allStops = <TransitStop>[];
  List<TransitStop> _routeStops = <TransitStop>[];
  bool _isLoading = false;
  bool _isRouteLoading = false;
  String? _error;
  String _query = '';
  StopPickerViewMode _viewMode = StopPickerViewMode.list;
  String _routeQueryLoaded = '';
  LatLngBounds? _currentBounds;
  double _currentZoom = _initialMapZoom;

  @override
  void initState() {
    super.initState();
    _loadStops();
  }

  Future<void> _loadStops({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final stops = await _apiService.fetchAllStopsCatalog(
        forceRefresh: forceRefresh,
      );
      setState(() {
        _allStops = stops;
        if (forceRefresh) {
          _routeStops = <TransitStop>[];
          _routeQueryLoaded = '';
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

  void _selectStop(TransitStop stop) {
    Navigator.of(context).pop(stop);
  }

  Future<void> _maybeLoadRouteStopsForQuery(String query) async {
    final normalized = query.trim();
    final isRouteCode = RegExp(r'^[0-9A-Za-z]{2,8}$').hasMatch(normalized);

    if (!isRouteCode) {
      if (_routeStops.isNotEmpty || _routeQueryLoaded.isNotEmpty) {
        setState(() {
          _routeStops = <TransitStop>[];
          _routeQueryLoaded = '';
          _isRouteLoading = false;
        });
      }
      return;
    }

    if (_routeQueryLoaded == normalized) {
      return;
    }

    setState(() {
      _isRouteLoading = true;
      _routeQueryLoaded = normalized;
    });

    try {
      final stops = await _apiService.fetchStopsForDisplayRouteCode(normalized);
      if (!mounted || _routeQueryLoaded != normalized) {
        return;
      }
      setState(() {
        _routeStops = stops;
      });
    } catch (_) {
      if (!mounted || _routeQueryLoaded != normalized) {
        return;
      }
      setState(() {
        _routeStops = <TransitStop>[];
      });
    } finally {
      if (mounted && _routeQueryLoaded == normalized) {
        setState(() {
          _isRouteLoading = false;
        });
      }
    }
  }

  LatLng _resolveMapCenter(List<TransitStop> stops) {
    if (stops.isNotEmpty) {
      return LatLng(stops.first.latitude, stops.first.longitude);
    }
    if (_allStops.isNotEmpty) {
      return LatLng(_allStops.first.latitude, _allStops.first.longitude);
    }
    return const LatLng(37.0000, 35.3213);
  }

  List<TransitStop> _buildVisibleStopsForMap(List<TransitStop> allFiltered) {
    Iterable<TransitStop> candidates = allFiltered;

    final bounds = _currentBounds;
    if (bounds != null) {
      candidates = candidates.where(
        (stop) => bounds.contains(LatLng(stop.latitude, stop.longitude)),
      );
    }

    var visible = candidates.toList(growable: false);

    if (_currentZoom <= _denseMarkerZoomThreshold && visible.length > 600) {
      final stride = _currentZoom < 12.0 ? 8 : 4;
      final thinned = <TransitStop>[];
      for (var i = 0; i < visible.length; i += stride) {
        thinned.add(visible[i]);
      }
      visible = thinned;
    }

    if (visible.length > _hardMarkerCap) {
      visible = visible.take(_hardMarkerCap).toList(growable: false);
    }

    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = _query.toLowerCase().trim();
    final combined = <String, TransitStop>{
      for (final stop in _allStops) stop.stopId: stop,
      for (final stop in _routeStops) stop.stopId: stop,
    };

    final filtered = combined.values.where((stop) {
      if (normalizedQuery.isEmpty) {
        return true;
      }
      return stop.stopName.toLowerCase().contains(normalizedQuery) ||
          stop.stopId.toLowerCase().contains(normalizedQuery) ||
          stop.routes
              .any((route) => route.toLowerCase().contains(normalizedQuery));
    }).toList();
    final visibleMarkers = _buildVisibleStopsForMap(filtered);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Durak Sec'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : () => _loadStops(forceRefresh: true),
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SegmentedButton<StopPickerViewMode>(
              segments: const [
                ButtonSegment<StopPickerViewMode>(
                  value: StopPickerViewMode.list,
                  label: Text('Liste'),
                  icon: Icon(Icons.list_alt_outlined),
                ),
                ButtonSegment<StopPickerViewMode>(
                  value: StopPickerViewMode.map,
                  label: Text('Harita'),
                  icon: Icon(Icons.map_outlined),
                ),
              ],
              selected: <StopPickerViewMode>{_viewMode},
              onSelectionChanged: (selection) {
                setState(() {
                  _viewMode = selection.first;
                });
              },
            ),
            const SizedBox(height: 8),
            TextField(
              onChanged: (value) {
                setState(() => _query = value);
                _maybeLoadRouteStopsForQuery(value);
              },
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Durak adi, id veya hat ara',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isRouteLoading
                    ? 'Hat duraklari canli yukleniyor...'
                    : 'Toplam durak: ${combined.length}',
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppThemeUtils.getDisabledColor(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!),
              ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(child: Text('Durak bulunamadi.'))
                      : _viewMode == StopPickerViewMode.list
                          ? ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final stop = filtered[index];
                                final isSelected = widget.selectedStopIds
                                    .contains(stop.stopId);
                                return ListTile(
                                  tileColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: const BorderSide(
                                      color: Color(0xFFE2E7F0),
                                    ),
                                  ),
                                  title: Text(stop.stopName),
                                  subtitle: Text(
                                    'ID: ${stop.stopId} | Hat: ${stop.routes.take(3).join(', ')}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Icon(
                                    isSelected
                                        ? Icons.check_circle
                                        : Icons.add_circle_outline,
                                    color: isSelected
                                        ? const Color(0xFF2E7D32)
                                        : null,
                                  ),
                                  onTap: () => _selectStop(stop),
                                );
                              },
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                children: [
                                  FlutterMap(
                                    mapController: _mapController,
                                    options: MapOptions(
                                      initialCenter:
                                          _resolveMapCenter(filtered),
                                      initialZoom: _initialMapZoom,
                                      minZoom: _minMapZoom,
                                      maxZoom: _maxMapZoom,
                                      onPositionChanged: (camera, _) {
                                        final nextBounds = camera.visibleBounds;
                                        final nextZoom = camera.zoom;
                                        if (!mounted) {
                                          return;
                                        }
                                        if (_currentZoom != nextZoom ||
                                            _currentBounds != nextBounds) {
                                          setState(() {
                                            _currentZoom = nextZoom;
                                            _currentBounds = nextBounds;
                                          });
                                        }
                                      },
                                    ),
                                    children: [
                                      buildAppMapTileLayer(context),
                                      MarkerLayer(
                                        markers: visibleMarkers.map((stop) {
                                          final isSelected = widget
                                              .selectedStopIds
                                              .contains(stop.stopId);
                                          return Marker(
                                            point: LatLng(
                                              stop.latitude,
                                              stop.longitude,
                                            ),
                                            width: 34,
                                            height: 34,
                                            child: GestureDetector(
                                              onTap: () => _selectStop(stop),
                                              child: Icon(
                                                Icons.location_on,
                                                size: 26,
                                                color: isSelected
                                                    ? const Color(0xFF2E7D32)
                                                    : const Color(0xFFB63519),
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                  Positioned(
                                    left: 10,
                                    right: 10,
                                    bottom: 10,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.95,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 8,
                                        ),
                                        child: Text(
                                          'Haritada gorunen marker: ${visibleMarkers.length}/${filtered.length} | Zoom: ${_currentZoom.toStringAsFixed(1)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
