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
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

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

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadStops({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final stops = await _apiService.fetchAllStopsCatalog(forceRefresh: forceRefresh);
      setState(() {
        _allStops = stops;
        if (forceRefresh) {
          _routeStops = <TransitStop>[];
          _routeQueryLoaded = '';
        }
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectStop(TransitStop stop) => Navigator.of(context).pop(stop);

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
    if (_routeQueryLoaded == normalized) return;

    setState(() {
      _isRouteLoading = true;
      _routeQueryLoaded = normalized;
    });

    try {
      final stops = await _apiService.fetchStopsForDisplayRouteCode(normalized);
      if (!mounted || _routeQueryLoaded != normalized) return;
      setState(() => _routeStops = stops);
    } catch (_) {
      if (!mounted || _routeQueryLoaded != normalized) return;
      setState(() => _routeStops = <TransitStop>[]);
    } finally {
      if (mounted && _routeQueryLoaded == normalized) {
        setState(() => _isRouteLoading = false);
      }
    }
  }

  LatLng _resolveMapCenter(List<TransitStop> stops) {
    if (stops.isNotEmpty) return LatLng(stops.first.latitude, stops.first.longitude);
    if (_allStops.isNotEmpty) return LatLng(_allStops.first.latitude, _allStops.first.longitude);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green = AppThemeUtils.getAccentColor(context, 'green');
    final blue = AppThemeUtils.getAccentColor(context, 'blue');

    final normalizedQuery = _query.toLowerCase().trim();
    final combined = <String, TransitStop>{
      for (final stop in _allStops) stop.stopId: stop,
      for (final stop in _routeStops) stop.stopId: stop,
    };
    final filtered = combined.values.where((stop) {
      if (normalizedQuery.isEmpty) return true;
      return stop.stopName.toLowerCase().contains(normalizedQuery) ||
          stop.stopId.toLowerCase().contains(normalizedQuery) ||
          stop.routes.any((route) => route.toLowerCase().contains(normalizedQuery));
    }).toList();
    final visibleMarkers = _buildVisibleStopsForMap(filtered);

    return Scaffold(
      backgroundColor: AppThemeUtils.getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: AppThemeUtils.getCardColor(context),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Durak Seç',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            Text(
              '${combined.length} durak',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppThemeUtils.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : () => _loadStops(forceRefresh: true),
            icon: _isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppThemeUtils.getSecondaryTextColor(context),
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Yenile',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Search + view toggle bar
          Container(
            color: AppThemeUtils.getCardColor(context),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                // Search field
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppThemeUtils.getSubtleBackgroundColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppThemeUtils.getBorderColor(context)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: AppThemeUtils.getSecondaryTextColor(context),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          onChanged: (value) {
                            setState(() => _query = value);
                            _maybeLoadRouteStopsForQuery(value);
                          },
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppThemeUtils.getTextColor(context),
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Durak adı, ID veya hat kodu ara…',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: AppThemeUtils.getSecondaryTextColor(context),
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _query = '');
                            _maybeLoadRouteStopsForQuery('');
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: AppThemeUtils.getSecondaryTextColor(context),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 12),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // View mode + stats row
                Row(
                  children: [
                    // Pills toggle
                    Container(
                      decoration: BoxDecoration(
                        color: AppThemeUtils.getSubtleBackgroundColor(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppThemeUtils.getBorderColor(context)),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ViewToggleBtn(
                            icon: Icons.list_alt_rounded,
                            label: 'Liste',
                            active: _viewMode == StopPickerViewMode.list,
                            isDark: isDark,
                            onTap: () => setState(() => _viewMode = StopPickerViewMode.list),
                          ),
                          const SizedBox(width: 3),
                          _ViewToggleBtn(
                            icon: Icons.map_rounded,
                            label: 'Harita',
                            active: _viewMode == StopPickerViewMode.map,
                            isDark: isDark,
                            onTap: () => setState(() => _viewMode = StopPickerViewMode.map),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_isRouteLoading)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: blue,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Hat yükleniyor…',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: blue,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        normalizedQuery.isEmpty
                            ? '${combined.length} durak'
                            : '${filtered.length} sonuç',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppThemeUtils.getSecondaryTextColor(context),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Error banner
          if (_error != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A1A1A) : const Color(0xFFFFF0EE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD0C8)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFB63519), size: 17),
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
                    icon: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFB63519)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          // Content
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: green),
                        const SizedBox(height: 14),
                        Text(
                          'Duraklar yükleniyor…',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppThemeUtils.getSecondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color: AppThemeUtils.getSecondaryTextColor(context),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Durak bulunamadı',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppThemeUtils.getTextColor(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '"$_query" ile eşleşen durak yok',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppThemeUtils.getSecondaryTextColor(context),
                              ),
                            ),
                          ],
                        ),
                      )
                    : _viewMode == StopPickerViewMode.list
                        ? ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final stop = filtered[index];
                              final isSelected = widget.selectedStopIds.contains(stop.stopId);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _StopListTile(
                                  stop: stop,
                                  isSelected: isSelected,
                                  isDark: isDark,
                                  onTap: () => _selectStop(stop),
                                ),
                              );
                            },
                          )
                        : _MapView(
                            filtered: filtered,
                            visibleMarkers: visibleMarkers,
                            mapController: _mapController,
                            selectedStopIds: widget.selectedStopIds,
                            currentZoom: _currentZoom,
                            onSelectStop: _selectStop,
                            onPositionChanged: (camera) {
                              final nextBounds = camera.visibleBounds;
                              final nextZoom = camera.zoom;
                              if (!mounted) return;
                              if (_currentZoom != nextZoom || _currentBounds != nextBounds) {
                                setState(() {
                                  _currentZoom = nextZoom;
                                  _currentBounds = nextBounds;
                                });
                              }
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ─── View Toggle Button ───────────────────────────────────────────────────────

class _ViewToggleBtn extends StatelessWidget {
  const _ViewToggleBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final blue = AppThemeUtils.getAccentColor(context, 'blue');

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? (isDark ? blue.withValues(alpha: 0.2) : blue.withValues(alpha: 0.12))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: active
              ? Border.all(color: blue.withValues(alpha: isDark ? 0.35 : 0.25))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? blue : AppThemeUtils.getSecondaryTextColor(context),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: active ? blue : AppThemeUtils.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Stop List Tile ───────────────────────────────────────────────────────────

class _StopListTile extends StatelessWidget {
  const _StopListTile({
    required this.stop,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final TransitStop stop;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final green = AppThemeUtils.getAccentColor(context, 'green');
    final blue = AppThemeUtils.getAccentColor(context, 'blue');

    return Material(
      color: AppThemeUtils.getCardColor(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? green.withValues(alpha: isDark ? 0.4 : 0.35)
                  : AppThemeUtils.getBorderColor(context),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isSelected
                      ? green.withValues(alpha: 0.12)
                      : AppThemeUtils.getSubtleBackgroundColor(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.place_rounded,
                  size: 18,
                  color: isSelected ? green : AppThemeUtils.getSecondaryTextColor(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.stopName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppThemeUtils.getTextColor(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Durak #${stop.stopId}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppThemeUtils.getSecondaryTextColor(context),
                      ),
                    ),
                    if (stop.routes.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: stop.routes
                              .take(6)
                              .map(
                                (route) => Container(
                                  margin: const EdgeInsets.only(right: 5),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: blue.withValues(alpha: isDark ? 0.15 : 0.08),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: blue.withValues(alpha: isDark ? 0.25 : 0.15),
                                    ),
                                  ),
                                  child: Text(
                                    route,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: blue,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: AppThemeUtils.getSecondaryTextColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Map View ────────────────────────────────────────────────────────────────

class _MapView extends StatelessWidget {
  const _MapView({
    required this.filtered,
    required this.visibleMarkers,
    required this.mapController,
    required this.selectedStopIds,
    required this.currentZoom,
    required this.onSelectStop,
    required this.onPositionChanged,
  });

  final List<TransitStop> filtered;
  final List<TransitStop> visibleMarkers;
  final MapController mapController;
  final Set<String> selectedStopIds;
  final double currentZoom;
  final void Function(TransitStop) onSelectStop;
  final void Function(MapCamera) onPositionChanged;

  LatLng _resolveCenter() {
    if (filtered.isNotEmpty) return LatLng(filtered.first.latitude, filtered.first.longitude);
    return const LatLng(37.0000, 35.3213);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final green = AppThemeUtils.getAccentColor(context, 'green');
    final orange = AppThemeUtils.getAccentColor(context, 'orange');

    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: _resolveCenter(),
            initialZoom: 12.5,
            minZoom: 11.8,
            maxZoom: 19.0,
            onPositionChanged: (camera, _) => onPositionChanged(camera),
          ),
          children: [
            buildAppMapTileLayer(context),
            MarkerLayer(
              markers: visibleMarkers.map((stop) {
                final isSelected = selectedStopIds.contains(stop.stopId);
                final color = isSelected ? green : orange;
                return Marker(
                  point: LatLng(stop.latitude, stop.longitude),
                  width: 36,
                  height: 36,
                  child: GestureDetector(
                    onTap: () => onSelectStop(stop),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.4),
                            blurRadius: 5,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        isSelected ? Icons.check_rounded : Icons.place_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        // Bottom info pill
        Positioned(
          left: 12,
          right: 12,
          bottom: 16,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A2535).withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppThemeUtils.getBorderColor(context)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '${visibleMarkers.length} / ${filtered.length} durak görünüyor  ·  zoom ${currentZoom.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppThemeUtils.getSecondaryTextColor(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
