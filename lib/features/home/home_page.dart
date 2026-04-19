import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/models/bus_vehicle.dart';
import '../../data/models/transit_stop.dart';
import '../../data/services/adana_api_service.dart';
import '../favorites/favorite_home_entry.dart';
import '../favorites/favorite_route_detail_page.dart';
import '../favorites/favorite_stop_item.dart';
import '../favorites/favorites_controller.dart';
import '../lines/trip_planner_page.dart';
import '../shared/geo_math_utils.dart';
import '../shared/stop_live_summary_service.dart';
import '../stops/stop_detail_page.dart';
import '../stops/stop_picker_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.favoritesController,
    required this.onOpenLines,
    required this.onOpenFavorites,
  });

  final FavoritesController favoritesController;
  final VoidCallback onOpenLines;
  final VoidCallback onOpenFavorites;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final AdanaApiService _apiService = AdanaApiService();
  final PageController _carouselController = PageController(viewportFraction: 0.84);
  static const double _etaMetersPerMinute = 320;

  bool _editMode = false;
  String? _error;
  Timer? _refreshTimer;
  Timer? _warmupRetryTimer;
  int _warmupRetryCount = 0;

  List<BusVehicle> _liveBuses = <BusVehicle>[];
  List<TransitStop> _allStops = <TransitStop>[];
  Position? _position;
  TransitStop? _nearestStop;
  StopLiveSummary? _nearestSummary;

  @override
  void initState() {
    super.initState();
    // In widget tests this environment variable is true; in normal app/debug it is false.
    final isWidgetTest = const bool.fromEnvironment('FLUTTER_TEST');
    if (!isWidgetTest) {
      _refreshDashboard();
      _requestPosition();
      _refreshTimer = Timer.periodic(
        const Duration(seconds: 35),
        (_) => _refreshDashboard(silent: true),
      );
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _warmupRetryTimer?.cancel();
    _carouselController.dispose();
    super.dispose();
  }

  void _scheduleWarmupRetryIfNeeded() {
    if (_warmupRetryCount >= 3) {
      return;
    }
    if (_liveBuses.isNotEmpty) {
      _warmupRetryCount = 0;
      _warmupRetryTimer?.cancel();
      return;
    }

    _warmupRetryTimer?.cancel();
    final delaySeconds = 2 + _warmupRetryCount;
    _warmupRetryTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted) {
        return;
      }
      if (_liveBuses.isNotEmpty) {
        return;
      }
      _warmupRetryCount++;
      _refreshDashboard(silent: true);
      _scheduleWarmupRetryIfNeeded();
    });
  }

  Future<void> _refreshDashboard({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _error = null;
      });
    }

    List<BusVehicle>? buses;
    List<TransitStop>? stops;
    String? busesError;
    String? stopsError;

    try {
      buses = await _apiService.fetchBuses();
    } catch (error) {
      busesError = error.toString();
    }

    try {
      stops = await _apiService.fetchAllStopsCatalog();
    } catch (error) {
      stopsError = error.toString();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      if (buses != null) {
        _liveBuses = buses;
      }
      if (stops != null) {
        _allStops = stops;
      }
      _rebuildNearestStop();

      if (busesError == null && stopsError == null) {
        _error = null;
      } else if (busesError != null && stopsError != null) {
        _error = 'Canli veri alinamadi: $busesError';
      } else if (busesError != null && _liveBuses.isEmpty) {
        _error = 'Canli veri alinamadi: $busesError';
      } else if (stopsError != null && _allStops.isEmpty) {
        _error = 'Durak katalogu alinamadi: $stopsError';
      }
    });

    _scheduleWarmupRetryIfNeeded();
  }

  Future<void> _requestPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _position = position;
        _rebuildNearestStop();
      });
    } catch (_) {
      // GPS is optional in the dashboard; keep the page usable without it.
    }
  }

  void _rebuildNearestStop() {
    if (_position == null || _allStops.isEmpty) {
      _nearestStop = null;
      _nearestSummary = null;
      return;
    }

    final nearest = StopLiveSummaryService.findNearestStop(_position!, _allStops);
    if (nearest == null) {
      _nearestStop = null;
      _nearestSummary = null;
      return;
    }

    _nearestStop = nearest;
    _nearestSummary = StopLiveSummaryService.summarizeStop(
      nearest,
      _liveBuses,
    );
  }

  Future<void> _addNearestStopToFavorites() async {
    final nearest = _nearestStop;
    if (nearest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yakın durak bulunamadı.')),
      );
      return;
    }

    final added = widget.favoritesController.toggleFavoriteStop(
      FavoriteStopItem(
        stopId: nearest.stopId,
        stopName: nearest.stopName,
        latitude: nearest.latitude,
        longitude: nearest.longitude,
      ),
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'En yakın durak favorilere eklendi' : 'Durak favorilerden çıkarıldı',
        ),
      ),
    );
  }

  void _openStopPicker() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const StopPickerPage(selectedStopIds: <String>{}),
      ),
    );
  }

  void _openPlanner() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TripPlannerPage()),
    );
  }

  List<_HomeApproachingBus> _buildApproachingForStop(FavoriteStopItem stop) {
    final list = <_HomeApproachingBus>[];
    for (final bus in _liveBuses) {
      if (!bus.hasLocation) {
        continue;
      }
      final etaMinutes = (GeoMathUtils.distanceMeters(
                bus.latitude!,
                bus.longitude!,
                stop.latitude,
                stop.longitude,
              ) /
              _etaMetersPerMinute)
          .clamp(1, 180)
          .round();
      final routeCode = bus.displayRouteCode.isNotEmpty
          ? bus.displayRouteCode
          : (bus.routeCode.isNotEmpty ? bus.routeCode : '?');
      final vehicle = bus.id.isNotEmpty
          ? bus.id
          : (bus.name.isNotEmpty ? bus.name : '-');
      final direction = bus.direction == '1' ? 'Donus' : 'Gidis';

      list.add(
        _HomeApproachingBus(
          routeCode: routeCode,
          direction: direction,
          etaMinutes: etaMinutes,
          vehicle: vehicle,
        ),
      );
    }
    list.sort((a, b) => a.etaMinutes.compareTo(b.etaMinutes));
    return list.take(3).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.favoritesController,
      builder: (context, _) {
        final entries = widget.favoritesController.homeEntries;

        return Scaffold(
          appBar: AppBar(
            title: const Text('AdanaBus'),
          ),
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF3F8FF), Color(0xFFE7F0FF), Color(0xFFF8FBFF)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  await _refreshDashboard();
                  await _requestPosition();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  children: [
                    if (_nearestStop != null)
                      _NearestStopCard(
                        stop: _nearestStop!,
                        summary: _nearestSummary,
                        onAdd: _addNearestStopToFavorites,
                        onOpenStop: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => StopDetailPage(
                                favoriteStop: FavoriteStopItem(
                                  stopId: _nearestStop!.stopId,
                                  stopName: _nearestStop!.stopName,
                                  latitude: _nearestStop!.latitude,
                                  longitude: _nearestStop!.longitude,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    if (_nearestStop != null) const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          'Favoriler',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          '${entries.length}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF5E6B82),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (entries.isEmpty)
                      _EmptyFavoritesHero(
                        onOpenLines: widget.onOpenLines,
                        onOpenFavorites: widget.onOpenFavorites,
                      )
                    else if (_editMode)
                      Column(
                        children: [
                          _ReorderFavoritesList(
                            entries: entries,
                            onReorder: widget.favoritesController.reorderHomeEntry,
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _editMode = false;
                                });
                              },
                              icon: const Icon(Icons.check),
                              label: const Text('Bitti'),
                            ),
                          ),
                        ],
                      )
                    else
                      SizedBox(
                        height: 228,
                        child: PageView.builder(
                          controller: _carouselController,
                          itemCount: entries.length + 1,
                          itemBuilder: (context, index) {
                            if (index == entries.length) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _CarouselManageCard(
                                  onTap: () {
                                    setState(() {
                                      _editMode = true;
                                    });
                                  },
                                ),
                              );
                            }
                            final entry = entries[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: _FavoriteHomeCard(
                                entry: entry,
                                liveSummary: entry.kind == FavoriteHomeEntryKind.stop
                                    ? StopLiveSummaryService.summarizeStop(
                                        _favoriteStopToTransitStop(entry.stop!),
                                        _liveBuses,
                                      )
                                    : null,
                                approachingBuses: entry.kind == FavoriteHomeEntryKind.stop
                                    ? _buildApproachingForStop(entry.stop!)
                                    : const <_HomeApproachingBus>[],
                                onTap: () {
                                  _openFavoriteEntry(entry);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 18),
                    _QuickActionsRow(
                      onOpenPlanner: _openPlanner,
                      onOpenStops: _openStopPicker,
                      onOpenFavorites: widget.onOpenFavorites,
                      onRefreshGps: _requestPosition,
                    ),
                    const SizedBox(height: 14),
                    if (_error != null)
                      _InlineErrorCard(message: _error!),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openFavoriteEntry(FavoriteHomeEntry entry) {
    switch (entry.kind) {
      case FavoriteHomeEntryKind.line:
        widget.onOpenLines();
        break;
      case FavoriteHomeEntryKind.stop:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StopDetailPage(
              favoriteStop: entry.stop!,
            ),
          ),
        );
        break;
      case FavoriteHomeEntryKind.route:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FavoriteRouteDetailPage(item: entry.route!),
          ),
        );
        break;
    }
  }

  TransitStop _favoriteStopToTransitStop(FavoriteStopItem stop) {
    return TransitStop(
      stopId: stop.stopId,
      stopName: stop.stopName,
      latitude: stop.latitude,
      longitude: stop.longitude,
      routes: const <String>[],
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.onOpenPlanner,
    required this.onOpenStops,
    required this.onOpenFavorites,
    required this.onRefreshGps,
  });

  final VoidCallback onOpenPlanner;
  final VoidCallback onOpenStops;
  final VoidCallback onOpenFavorites;
  final Future<void> Function() onRefreshGps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.route,
            label: 'Rota Belirle',
            onTap: onOpenPlanner,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.place_outlined,
            label: 'Duraklar',
            onTap: onOpenStops,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.star,
            label: 'Favoriler',
            onTap: onOpenFavorites,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.gps_fixed,
            label: 'GPS',
            onTap: () => onRefreshGps(),
          ),
        ),
      ],
    );
  }
}

class _NearestStopCard extends StatelessWidget {
  const _NearestStopCard({
    required this.stop,
    required this.summary,
    required this.onAdd,
    required this.onOpenStop,
  });

  final TransitStop stop;
  final StopLiveSummary? summary;
  final VoidCallback onAdd;
  final VoidCallback onOpenStop;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4FAF6),
      borderRadius: BorderRadius.circular(18),
      elevation: 1,
      child: InkWell(
        onTap: onOpenStop,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.near_me, color: Color(0xFF1C7A47)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'En yakın durak',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  TextButton(
                    onPressed: onAdd,
                    child: const Text('Favorilere ekle'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                stop.stopName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text('Durak ID: ${stop.stopId}'),
              const SizedBox(height: 10),
              if (summary == null || !summary!.hasEstimate)
                const Text('Yakın araç verisi bekleniyor.')
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeaderChip(
                      label: 'En yakın: ${summary!.nearestEtaMinutes} dk',
                    ),
                    if (summary!.nextEtaMinutes != null)
                      _HeaderChip(
                        label: 'Sonraki: ${summary!.nextEtaMinutes} dk',
                      ),
                    _HeaderChip(label: 'Canlı araç: ${summary!.liveBusCount}'),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteHomeCard extends StatelessWidget {
  const _FavoriteHomeCard({
    required this.entry,
    required this.onTap,
    required this.liveSummary,
    required this.approachingBuses,
  });

  final FavoriteHomeEntry entry;
  final VoidCallback onTap;
  final StopLiveSummary? liveSummary;
  final List<_HomeApproachingBus> approachingBuses;

  @override
  Widget build(BuildContext context) {
    final accent = switch (entry.kind) {
      FavoriteHomeEntryKind.line => const Color(0xFF0A4FB5),
      FavoriteHomeEntryKind.stop => const Color(0xFF1C7A47),
      FavoriteHomeEntryKind.route => const Color(0xFFE17900),
    };

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 1.2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.18), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.subtitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              if (entry.kind == FavoriteHomeEntryKind.stop && liveSummary != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeaderChip(label: 'Canlı araç: ${liveSummary!.liveBusCount}'),
                    const SizedBox(height: 6),
                    if (approachingBuses.isEmpty)
                      Text(
                        'Yaklaşan araç bilgisi bekleniyor',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      ...approachingBuses.map(
                        (bus) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Hat ${bus.routeCode} • ${bus.direction} • ${bus.etaMinutes} dk • Araç ${bus.vehicle}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                  ],
                )
              else
                Text(
                  entry.kind == FavoriteHomeEntryKind.line
                      ? 'Hat detayına git'
                      : entry.kind == FavoriteHomeEntryKind.route
                          ? 'Kayıtlı rotayı aç'
                          : 'Durak detayını aç',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeApproachingBus {
  const _HomeApproachingBus({
    required this.routeCode,
    required this.direction,
    required this.etaMinutes,
    required this.vehicle,
  });

  final String routeCode;
  final String direction;
  final int etaMinutes;
  final String vehicle;
}

class _ReorderFavoritesList extends StatelessWidget {
  const _ReorderFavoritesList({
    required this.entries,
    required this.onReorder,
  });

  final List<FavoriteHomeEntry> entries;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: mathMax(300, entries.length * 92.0),
      child: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        itemCount: entries.length,
        onReorder: onReorder,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return Container(
            key: ValueKey(entry.key),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E7F0)),
            ),
            child: ListTile(
              leading: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_indicator),
              ),
              title: Text(entry.title),
              subtitle: Text(entry.subtitle),
              trailing: _KindBadge(kind: entry.kind),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyFavoritesHero extends StatelessWidget {
  const _EmptyFavoritesHero({
    required this.onOpenLines,
    required this.onOpenFavorites,
  });

  final VoidCallback onOpenLines;
  final VoidCallback onOpenFavorites;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E7F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Henüz favori yok',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          const Text('Henüz favori eklenmedi.'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: onOpenLines,
                icon: const Icon(Icons.route),
                label: const Text('Hatlara git'),
              ),
              OutlinedButton.icon(
                onPressed: onOpenFavorites,
                icon: const Icon(Icons.star_outline),
                label: const Text('Favorileri aç'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

  final FavoriteHomeEntryKind kind;

  @override
  Widget build(BuildContext context) {
    final text = switch (kind) {
      FavoriteHomeEntryKind.line => 'Hat',
      FavoriteHomeEntryKind.stop => 'Durak',
      FavoriteHomeEntryKind.route => 'Rota',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFBFDFF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(minHeight: 86),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E7F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: const Color(0xFF164B9D)),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarouselManageCard extends StatelessWidget {
  const _CarouselManageCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD7DFEE)),
            gradient: const LinearGradient(
              colors: [Color(0xFFF7FAFF), Color(0xFFEAF1FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tune, size: 28, color: Color(0xFF164B9D)),
              SizedBox(height: 10),
              Text(
                'Düzenle',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InlineErrorCard extends StatelessWidget {
  const _InlineErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1EE),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(message),
    );
  }
}

double mathMax(double a, double b) => a > b ? a : b;
