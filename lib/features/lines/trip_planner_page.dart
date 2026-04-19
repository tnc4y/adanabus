import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme_utils.dart';
import '../../data/models/bus_option.dart';
import '../../data/models/bus_vehicle.dart';
import '../../data/models/transit_stop.dart';
import '../../data/models/trip_destination.dart';
import '../../data/services/adana_api_service.dart';
import '../shared/app_map_tile_layer.dart';
import 'trip_planner_widgets.dart';
import 'trip_route_preview_page.dart';
import 'smart_trip_recommender_v2.dart';

class TripPlannerPage extends StatefulWidget {
  const TripPlannerPage({super.key});

  @override
  State<TripPlannerPage> createState() => _TripPlannerPageState();
}

class _TripPlannerPageState extends State<TripPlannerPage> {
  final AdanaApiService _apiService = AdanaApiService();

  Position? _originPosition;
  TripDestination? _destinationPoint;
  List<RankedTripOption> _rankedTrips = <RankedTripOption>[];
  bool _isPlanning = false;
  String? _planningError;

  Future<Position> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw StateError('Konum servisi kapalı. Lütfen GPS açın.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw StateError('Konum izni reddedildi.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw StateError('Konum izni kalıcı olarak kapalı. Ayarlardan açın.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  String _mapLocationError(Object error) {
    final msg = error.toString();
    if (msg.contains('permission') || msg.contains('izin')) {
      return 'Konum izni olmadan konum alınamaz.';
    }
    if (msg.contains('kapali') || msg.contains('disabled')) {
      return 'Konum servisi kapalı. GPS açıp tekrar deneyin.';
    }
    return msg;
  }

  Future<void> _setOriginFromGPS() async {
    try {
      final position = await _getCurrentPosition();
      setState(() => _originPosition = position);
    } catch (error) {
      setState(() => _planningError = _mapLocationError(error));
    }
  }

  Future<void> _setOriginFromMap() async {
    final dest = await Navigator.of(context).push<TripDestination>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const LocationPickerPage(title: 'Başlangıç Konumunu Seç'),
      ),
    );
    if (dest != null) {
      setState(() {
        _originPosition = Position(
          latitude: dest.latitude,
          longitude: dest.longitude,
          timestamp: DateTime.now(),
          accuracy: 50,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      });
    }
  }

  Future<void> _setDestinationFromGPS() async {
    try {
      final position = await _getCurrentPosition();
      setState(() {
        _destinationPoint = TripDestination(
          latitude: position.latitude,
          longitude: position.longitude,
          name: 'Mevcut Konumum',
        );
      });
    } catch (error) {
      setState(() => _planningError = _mapLocationError(error));
    }
  }

  Future<void> _setDestinationFromMap() async {
    final dest = await Navigator.of(context).push<TripDestination>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const LocationPickerPage(title: 'Hedef Konumunu Seç'),
      ),
    );
    if (dest != null) setState(() => _destinationPoint = dest);
  }

  Future<void> _planTrip() async {
    if (_originPosition == null || _destinationPoint == null) {
      setState(() => _planningError = 'Lütfen başlangıç ve hedef konumlarını seçin.');
      return;
    }
    setState(() {
      _isPlanning = true;
      _planningError = null;
      _rankedTrips = [];
    });
    try {
      final results = await Future.wait<dynamic>([
        _apiService.fetchAllStopsCatalog(),
        _apiService.fetchBuses(),
      ]);
      final stops = results[0] as List<TransitStop>;
      final buses = results[1] as List<BusVehicle>;
      final lines = BusOption.fromBuses(buses);
      final trips = await SmartTripRecommenderV2.recommendTrips(
        origin: _originPosition!,
        destination: _destinationPoint!,
        stops: stops,
        lines: lines,
        liveBuses: buses,
        apiService: _apiService,
        resultLimit: 3,
      );
      if (!mounted) return;
      setState(() => _rankedTrips = trips);
    } catch (error) {
      if (!mounted) return;
      setState(() => _planningError = error.toString());
    } finally {
      if (mounted) setState(() => _isPlanning = false);
    }
  }

  void _swapLocations() {
    if (_originPosition == null && _destinationPoint == null) return;
    final oldOriginLat = _originPosition?.latitude;
    final oldOriginLon = _originPosition?.longitude;
    final oldDest = _destinationPoint;
    setState(() {
      if (oldDest != null) {
        _originPosition = Position(
          latitude: oldDest.latitude,
          longitude: oldDest.longitude,
          timestamp: DateTime.now(),
          accuracy: 50,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      } else {
        _originPosition = null;
      }
      if (oldOriginLat != null && oldOriginLon != null) {
        _destinationPoint = TripDestination(
          latitude: oldOriginLat,
          longitude: oldOriginLon,
          name: 'Başlangıç Konumu',
        );
      } else {
        _destinationPoint = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = AppThemeUtils.getAccentColor(context, 'blue');
    final orange = AppThemeUtils.getAccentColor(context, 'orange');
    final green = AppThemeUtils.getAccentColor(context, 'green');
    final canPlan = _originPosition != null && _destinationPoint != null;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0F1722) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: const Text(
          'Rota Planla',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Origin / Destination Card ──────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: AppThemeUtils.getCardColor(context),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppThemeUtils.getBorderColor(context)),
                    ),
                    child: Column(
                      children: [
                        // Origin Row
                        _LocationRow(
                          isDark: isDark,
                          color: green,
                          icon: Icons.radio_button_checked_rounded,
                          label: 'Başlangıç',
                          value: _originPosition != null
                              ? '${_originPosition!.latitude.toStringAsFixed(5)}, ${_originPosition!.longitude.toStringAsFixed(5)}'
                              : null,
                          hint: 'Başlangıç konumunu seç',
                          onGps: _setOriginFromGPS,
                          onMap: _setOriginFromMap,
                          onClear: _originPosition != null
                              ? () => setState(() => _originPosition = null)
                              : null,
                        ),
                        // Divider + Swap
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                width: 1,
                                height: 20,
                                color: AppThemeUtils.getBorderColor(context),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: _swapLocations,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppThemeUtils.getSubtleBackgroundColor(context),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppThemeUtils.getBorderColor(context),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.swap_vert_rounded,
                                    size: 18,
                                    color: AppThemeUtils.getSecondaryTextColor(context),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                        ),
                        // Destination Row
                        _LocationRow(
                          isDark: isDark,
                          color: orange,
                          icon: Icons.location_on_rounded,
                          label: 'Hedef',
                          value: _destinationPoint?.name.isNotEmpty == true
                              ? _destinationPoint!.name
                              : _destinationPoint != null
                                  ? '${_destinationPoint!.latitude.toStringAsFixed(5)}, ${_destinationPoint!.longitude.toStringAsFixed(5)}'
                                  : null,
                          hint: 'Hedef konumunu seç',
                          onGps: _setDestinationFromGPS,
                          onMap: _setDestinationFromMap,
                          onClear: _destinationPoint != null
                              ? () => setState(() => _destinationPoint = null)
                              : null,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Info tip ──────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: isDark ? 0.1 : 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: green.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bolt_rounded, color: green, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Anlık en hızlı rota hesaplanır (canlı araç + gerçek kalkış saatine göre).',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: green,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Plan Button ───────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canPlan ? (_isPlanning ? null : _planTrip) : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        backgroundColor: blue,
                        disabledBackgroundColor:
                            AppThemeUtils.getBorderColor(context),
                      ),
                      icon: _isPlanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.alt_route_rounded, size: 20),
                      label: Text(
                        _isPlanning ? 'Hesaplanıyor…' : 'Rota Planla',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  // ── Error ─────────────────────────────────────────────
                  if (_planningError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1EE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFD0C8)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Color(0xFFB63519), size: 17),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _planningError!,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7A2010),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _planningError = null),
                            icon: const Icon(Icons.close_rounded,
                                size: 16, color: Color(0xFFB63519)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Results ───────────────────────────────────────────
                  if (_rankedTrips.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_rankedTrips.length} rota bulundu',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ..._rankedTrips.map(
                      (trip) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TripOptionCard(
                          trip: trip,
                          onSelect: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TripRoutePreviewPage(
                                trip: trip,
                                origin: LatLng(
                                  _originPosition!.latitude,
                                  _originPosition!.longitude,
                                ),
                                destination: _destinationPoint!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Location Row ─────────────────────────────────────────────────────────────

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.isDark,
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.onGps,
    required this.onMap,
    required this.onClear,
  });

  final bool isDark;
  final Color color;
  final IconData icon;
  final String label;
  final String? value;
  final String hint;
  final VoidCallback onGps;
  final VoidCallback onMap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value ?? hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: value != null ? FontWeight.w700 : FontWeight.w500,
                    color: value != null
                        ? AppThemeUtils.getTextColor(context)
                        : AppThemeUtils.getSecondaryTextColor(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // GPS button
          _SmallIconBtn(
            icon: Icons.my_location_rounded,
            color: color,
            isDark: isDark,
            onTap: onGps,
            tooltip: 'GPS ile al',
          ),
          const SizedBox(width: 4),
          // Map button
          _SmallIconBtn(
            icon: Icons.map_rounded,
            color: color,
            isDark: isDark,
            onTap: onMap,
            tooltip: 'Haritadan seç',
          ),
          if (onClear != null) ...[
            const SizedBox(width: 4),
            _SmallIconBtn(
              icon: Icons.close_rounded,
              color: AppThemeUtils.getSecondaryTextColor(context),
              isDark: isDark,
              onTap: onClear!,
              tooltip: 'Temizle',
            ),
          ],
        ],
      ),
    );
  }
}

class _SmallIconBtn extends StatelessWidget {
  const _SmallIconBtn({
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.15 : 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}

// ─── Location Picker Page (Full Screen) ──────────────────────────────────────

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key, required this.title});
  final String title;

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final MapController _mapController = MapController();
  final TextEditingController _nameController = TextEditingController();

  static const LatLng _adanaCenter = LatLng(37.0000, 35.3213);

  LatLng _center = _adanaCenter;
  bool _isDragging = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      _mapController.move(LatLng(pos.latitude, pos.longitude), 15.5);
    } catch (_) {}
  }

  void _confirm() {
    final name = _nameController.text.trim().isEmpty
        ? 'Seçilen Konum'
        : _nameController.text.trim();
    Navigator.pop(
      context,
      TripDestination(
        latitude: _center.latitude,
        longitude: _center.longitude,
        name: name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = AppThemeUtils.getAccentColor(context, 'blue');
    final cardBg = AppThemeUtils.getCardColor(context);

    return Scaffold(
      body: Stack(
        children: [
          // ── Full screen map ─────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _adanaCenter,
              initialZoom: 13.5,
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture) {
                  setState(() {
                    _center = camera.center;
                    _isDragging = true;
                  });
                }
              },
              onMapEvent: (event) {
                if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) {
                  setState(() => _isDragging = false);
                }
              },
            ),
            children: [
              buildAppMapTileLayer(context),
            ],
          ),

          // ── Crosshair pin at center ─────────────────────────────────
          Center(
            child: AnimatedScale(
              scale: _isDragging ? 1.18 : 1.0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutBack,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: blue,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: blue.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      '${_center.latitude.toStringAsFixed(4)}, ${_center.longitude.toStringAsFixed(4)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(
                    Icons.location_on_rounded,
                    color: blue,
                    size: 42,
                    shadows: [
                      Shadow(
                        color: blue.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: blue.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Top bar ─────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  // Back button
                  _MapBtn(
                    isDark: isDark,
                    child: const Icon(Icons.arrow_back_rounded, size: 20),
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 10),
                  // Title pill
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: cardBg.withValues(alpha: 0.93),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppThemeUtils.getTextColor(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── GPS button (right side) ─────────────────────────────────
          Positioned(
            right: 14,
            bottom: 230,
            child: _MapBtn(
              isDark: isDark,
              onTap: _goToMyLocation,
              child: Icon(
                Icons.my_location_rounded,
                size: 20,
                color: blue,
              ),
            ),
          ),

          // ── Zoom buttons ────────────────────────────────────────────
          Positioned(
            right: 14,
            bottom: 320,
            child: Column(
              children: [
                _MapBtn(
                  isDark: isDark,
                  onTap: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1),
                  child: const Icon(Icons.add_rounded, size: 20),
                ),
                const SizedBox(height: 6),
                _MapBtn(
                  isDark: isDark,
                  onTap: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1),
                  child: const Icon(Icons.remove_rounded, size: 20),
                ),
              ],
            ),
          ),

          // ── Bottom confirmation panel ──────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppThemeUtils.getBorderColor(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Konum Adı (isteğe bağlı)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppThemeUtils.getSecondaryTextColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppThemeUtils.getTextColor(context),
                    ),
                    decoration: InputDecoration(
                      hintText: 'ör: Merkez, Ev, İş…',
                      hintStyle: TextStyle(
                        color: AppThemeUtils.getSecondaryTextColor(context),
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: AppThemeUtils.getSubtleBackgroundColor(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'İptal',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _confirm,
                          style: FilledButton.styleFrom(
                            backgroundColor: blue,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text(
                            'Bu Konumu Seç',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapBtn extends StatelessWidget {
  const _MapBtn({required this.isDark, required this.onTap, required this.child});
  final bool isDark;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1A2535).withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(child: child),
      ),
    );
  }
}
