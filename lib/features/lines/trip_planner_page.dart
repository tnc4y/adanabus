import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../data/models/bus_option.dart';
import '../../data/models/bus_vehicle.dart';
import '../../data/models/transit_stop.dart';
import '../../data/models/trip_destination.dart';
import '../../data/services/adana_api_service.dart';
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
      throw StateError('Konum servisi kapali. Lutfen GPS acin.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw StateError('Konum izni reddedildi.');
    }

    if (permission == LocationPermission.deniedForever) {
      throw StateError('Konum izni kalici olarak kapali. Ayarlardan acin.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  String _mapLocationError(Object error) {
    final message = error.toString();
    if (message.contains('permission') || message.contains('izin')) {
      return 'Konum izni olmadan konumlar alinamaz.';
    }
    if (message.contains('servisi kapali') || message.contains('disabled')) {
      return 'Konum servisi kapali. Lutfen GPS acip tekrar deneyin.';
    }
    return message;
  }

  Future<void> _setOriginFromGPS() async {
    try {
      final position = await _getCurrentPosition();
      setState(() {
        _originPosition = position;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Baslangic konumu alindi.'),
            duration: Duration(milliseconds: 800),
          ),
        );
      }
    } catch (error) {
      setState(() {
        _planningError = _mapLocationError(error);
      });
    }
  }

  Future<void> _setOriginFromMap() async {
    final destination = await showDialog<TripDestination?>(
      context: context,
      builder: (context) =>
          _LocationMapDialog(title: 'Baslangic Konumunu Secin'),
    );

    if (destination != null) {
      setState(() {
        _originPosition = Position(
          latitude: destination.latitude,
          longitude: destination.longitude,
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
          name: 'Hedef Konumu',
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hedef konumu alindi.'),
            duration: Duration(milliseconds: 800),
          ),
        );
      }
    } catch (error) {
      setState(() {
        _planningError = _mapLocationError(error);
      });
    }
  }

  Future<void> _setDestinationFromMap() async {
    final destination = await showDialog<TripDestination?>(
      context: context,
      builder: (context) => _LocationMapDialog(title: 'Hedef Konumunu Secin'),
    );

    if (destination != null) {
      setState(() {
        _destinationPoint = destination;
      });
    }
  }

  Future<void> _planTrip() async {
    if (_originPosition == null || _destinationPoint == null) {
      setState(() {
        _planningError = 'Lutfen baslangic ve hedef konumlarini secin.';
      });
      return;
    }

    setState(() {
      _isPlanning = true;
      _planningError = null;
      _rankedTrips = <RankedTripOption>[];
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

      if (!mounted) {
        return;
      }

      setState(() {
        _rankedTrips = trips;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _planningError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPlanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yolculuk Planla'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlangıç Konumu
            Card(
              elevation: 0,
              color: const Color(0xFFF1F6FF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFD9E6FF)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.flag,
                            color: Color(0xFF164B9D), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Başlangıç Konumu',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _setOriginFromGPS,
                            icon: const Icon(Icons.gps_fixed),
                            label: const Text('GPS'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _setOriginFromMap,
                            icon: const Icon(Icons.map),
                            label: const Text('Harita'),
                          ),
                        ),
                      ],
                    ),
                    if (_originPosition != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFE4EAF5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Color(0xFF4CAF50), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_originPosition!.latitude.toStringAsFixed(4)}, ${_originPosition!.longitude.toStringAsFixed(4)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Text(
                        'Başlangıç konumunu seçiniz.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Hedef Konumu
            Card(
              elevation: 0,
              color: const Color(0xFFFFF5F0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFFFFD9CE)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            color: Color(0xFFB63519), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Hedef Konumu',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _setDestinationFromGPS,
                            icon: const Icon(Icons.gps_fixed),
                            label: const Text('GPS'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _setDestinationFromMap,
                            icon: const Icon(Icons.map),
                            label: const Text('Harita'),
                          ),
                        ),
                      ],
                    ),
                    if (_destinationPoint != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFFD9CE)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Color(0xFF4CAF50), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _destinationPoint!.name,
                                    style:
                                        Theme.of(context).textTheme.labelSmall,
                                  ),
                                  Text(
                                    '${_destinationPoint!.latitude.toStringAsFixed(4)}, ${_destinationPoint!.longitude.toStringAsFixed(4)}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Text(
                        'Hedef konumunu seçiniz.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Planla Tuşu
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed:
                    (_originPosition != null && _destinationPoint != null)
                        ? (_isPlanning ? null : _planTrip)
                        : null,
                icon: const Icon(Icons.search),
                label: Text(_isPlanning ? 'Hesaplaniyor...' : 'Planla'),
              ),
            ),
            if (_isPlanning) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(minHeight: 4),
            ],
            if (_planningError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1EE),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFB3A1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Color(0xFFB63519), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _planningError!,
                        style: const TextStyle(color: Color(0xFFB63519)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_rankedTrips.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'En İyi ${_rankedTrips.length} Rota',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              ..._rankedTrips.map(
                (trip) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TripOptionCard(
                    trip: trip,
                    onSelect: () {
                      Navigator.of(context).push(
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
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LocationMapDialog extends StatefulWidget {
  const _LocationMapDialog({required this.title});

  final String title;

  @override
  State<_LocationMapDialog> createState() => _LocationMapDialogState();
}

class _LocationMapDialogState extends State<_LocationMapDialog> {
  final MapController _mapController = MapController();
  LatLng? _selectedPoint;
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        children: [
          AppBar(
            title: Text(widget.title),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(37.0000, 35.3213),
                initialZoom: 13,
                onTap: (tapPosition, point) {
                  setState(() {
                    _selectedPoint = point;
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.adanabus',
                  maxZoom: 19,
                ),
                if (_selectedPoint != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selectedPoint!,
                        width: 42,
                        height: 42,
                        child: const Icon(
                          Icons.location_on,
                          color: Color(0xFFB63519),
                          size: 32,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (_selectedPoint != null)
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFFF5F5F5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Secilen: ${_selectedPoint!.latitude.toStringAsFixed(4)}, ${_selectedPoint!.longitude.toStringAsFixed(4)}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      hintText: 'Konum adi (orn: Merkez, Park)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('İptal'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            final name = _nameController.text.trim().isEmpty
                                ? 'Secilen Konum'
                                : _nameController.text.trim();
                            final destination = TripDestination(
                              latitude: _selectedPoint!.latitude,
                              longitude: _selectedPoint!.longitude,
                              name: name,
                            );
                            Navigator.pop(context, destination);
                          },
                          child: const Text('Onayla'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TripOptionCard extends StatelessWidget {
  const _TripOptionCard({
    required this.trip,
    required this.onSelect,
  });

  final RankedTripOption trip;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4EAF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: const Color(0xFFEAF2FF),
                ),
                child: Text(
                  'Rota ${trip.rank}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: const Color(0xFFFFF1EE),
                ),
                child: Text(
                  'Hat ${trip.line.displayRouteCode}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFB63519),
                      ),
                ),
              ),
                if (trip.isTransfer)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: const Color(0xFFFFECD1),
                    ),
                    child: Text(
                      'Aktarma',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFE65100),
                          ),
                    ),
                  ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: const Color(0xFFE8F5E9),
                ),
                child: Text(
                  'Skor: ${trip.score}/100',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2E7D32),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _TinyMetric(
                icon: Icons.directions_walk,
                label: '${trip.walkToStartMinutes.toStringAsFixed(1)} dk yuru',
              ),
              _TinyMetric(
                icon: Icons.schedule,
                label: '${trip.waitMinutes.toStringAsFixed(1)} dk bekleme',
              ),
              _TinyMetric(
                icon: Icons.directions_bus,
                label: '${trip.busRideMinutes.toStringAsFixed(1)} dk seyahat',
              ),
              _TinyMetric(
                icon: Icons.time_to_leave,
                label: '${trip.walkFromEndMinutes.toStringAsFixed(1)} dk inis',
              ),
            ],
          ),
          const SizedBox(height: 8),
           if (trip.isTransfer && trip.transferLine != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFFD54F), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.swap_horiz, size: 16, color: const Color(0xFFE65100)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Hat ${trip.transferLine!.displayRouteCode} - ${trip.transferDirection}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Aktarma: ${trip.transferStop?.stopName ?? "?"}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${trip.transferWaitMinutes.toInt()} dk bekleme',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: const Color(0xFFE65100),
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
           const SizedBox(height: 8),
           Row(
            children: [
              Expanded(
                child: Text(
                  '${trip.startStop.stopName} → ${trip.endStop.stopName}',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onSelect,
                icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Aç'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TinyMetric extends StatelessWidget {
  const _TinyMetric({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF666666)),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}
