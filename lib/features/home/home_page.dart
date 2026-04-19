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

  bool _isLoading = false;
  bool _editMode = false;
  bool _isTestMode = false;
  String? _error;
  DateTime? _lastUpdatedAt;
  Timer? _refreshTimer;

  List<BusVehicle> _liveBuses = <BusVehicle>[];
  List<TransitStop> _allStops = <TransitStop>[];
  Position? _position;
  TransitStop? _nearestStop;
  StopLiveSummary? _nearestSummary;

  @override
  void initState() {
    super.initState();
    assert(() {
      _isTestMode = true;
      return true;
    }());

    if (!_isTestMode) {
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
    _carouselController.dispose();
    super.dispose();
  }

  Future<void> _refreshDashboard({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait<dynamic>([
        _apiService.fetchBuses(),
        _apiService.fetchAllStopsCatalog(),
      ]);
      final buses = results[0] as List<BusVehicle>;
      final stops = results[1] as List<TransitStop>;

      if (!mounted) {
        return;
      }

      setState(() {
        _liveBuses = buses;
        _allStops = stops;
        _lastUpdatedAt = DateTime.now();
        _rebuildNearestStop();
        if (_position != null) {
          _rebuildNearestStop();
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted && !silent) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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

  String _formatUpdatedAt() {
    final value = _lastUpdatedAt;
    if (value == null) {
      return 'Henüz güncellenmedi';
    }
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.favoritesController,
      builder: (context, _) {
        final entries = widget.favoritesController.homeEntries;
        final favoriteStops = widget.favoritesController.favoriteStops;

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF8F4EA), Color(0xFFE4F0FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
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
                    _DashboardHeader(
                      updatedAt: _formatUpdatedAt(),
                      isLoading: _isLoading,
                      editMode: _editMode,
                      onRefresh: () async {
                        await _refreshDashboard();
                        await _requestPosition();
                      },
                      onToggleEdit: () {
                        setState(() {
                          _editMode = !_editMode;
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    _QuickActionsRow(
                      onOpenPlanner: _openPlanner,
                      onOpenStops: _openStopPicker,
                      onOpenFavorites: widget.onOpenFavorites,
                      onRefreshGps: _requestPosition,
                    ),
                    const SizedBox(height: 14),
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
                    _SectionHeader(
                      title: 'Favori Akışı',
                      subtitle: entries.isEmpty
                          ? 'Henüz bir favori eklenmemiş.'
                          : _editMode
                              ? 'Sıralamayı sürükle bırak ile değiştir.'
                              : 'Kartlara dokunarak detaylara gidebilirsin.',
                      trailing: Text(
                        '${entries.length} kayıt',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (entries.isEmpty)
                      _EmptyFavoritesHero(
                        onOpenLines: widget.onOpenLines,
                        onOpenFavorites: widget.onOpenFavorites,
                      )
                    else if (_editMode)
                      _ReorderFavoritesList(
                        entries: entries,
                        onReorder: widget.favoritesController.reorderHomeEntry,
                      )
                    else
                      SizedBox(
                        height: 228,
                        child: PageView.builder(
                          controller: _carouselController,
                          itemCount: entries.length,
                          itemBuilder: (context, index) {
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
                                onTap: () {
                                  _openFavoriteEntry(entry);
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 18),
                    _SectionHeader(
                      title: 'Yakın favori duraklar',
                      subtitle: 'Durağa yaklaşan araçları burada canlı gösteriyorum.',
                      trailing: TextButton(
                        onPressed: widget.onOpenFavorites,
                        child: const Text('Tümünü gör'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (favoriteStops.isEmpty)
                      const _EmptyInlineCard(text: 'Henüz favori durak yok.')
                    else
                      ..._buildStopCards(favoriteStops),
                    const SizedBox(height: 18),
                    if (_error != null)
                      _InlineErrorCard(message: _error!),
                    const SizedBox(height: 4),
                    _LiveFootnote(text: 'Son güncelleme: ${_formatUpdatedAt()}'),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildStopCards(List<FavoriteStopItem> stops) {
    final ordered = List<FavoriteStopItem>.from(stops);
    if (_position != null) {
      ordered.sort((a, b) {
        final da = GeoMathUtils.distanceMeters(
          _position!.latitude,
          _position!.longitude,
          a.latitude,
          a.longitude,
        );
        final db = GeoMathUtils.distanceMeters(
          _position!.latitude,
          _position!.longitude,
          b.latitude,
          b.longitude,
        );
        return da.compareTo(db);
      });
    }

    return ordered.take(5).map((stop) {
      final summary = StopLiveSummaryService.summarizeStop(
        _favoriteStopToTransitStop(stop),
        _liveBuses,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _FavoriteStopLiveCard(
          item: stop,
          summary: summary,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StopDetailPage(favoriteStop: stop),
              ),
            );
          },
        ),
      );
    }).toList(growable: false);
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

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.updatedAt,
    required this.isLoading,
    required this.editMode,
    required this.onRefresh,
    required this.onToggleEdit,
  });

  final String updatedAt;
  final bool isLoading;
  final bool editMode;
  final Future<void> Function() onRefresh;
  final VoidCallback onToggleEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF143B72), Color(0xFF1D6AE5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 10),
            color: Color(0x22000000),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.directions_bus_filled, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AdanaBus',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              IconButton(
                onPressed: isLoading ? null : onToggleEdit,
                icon: Icon(
                  editMode ? Icons.done : Icons.edit,
                  color: Colors.white,
                ),
                tooltip: editMode ? 'Bitti' : 'Düzenle',
              ),
              IconButton(
                onPressed: isLoading ? null : () => onRefresh(),
                icon: const Icon(Icons.refresh, color: Colors.white),
                tooltip: 'Yenile',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Favoriler, canlı araçlar ve en yakın durağı tek ekranda yönet.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderChip(label: 'Güncelleme: $updatedAt'),
              _HeaderChip(label: editMode ? 'Edit modu açık' : 'Edit modu kapalı'),
            ],
          ),
        ],
      ),
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
      color: Colors.white,
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
                  const Icon(Icons.near_me, color: Color(0xFF2E7D32)),
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
              Text('ID: ${stop.stopId}'),
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
  });

  final FavoriteHomeEntry entry;
  final VoidCallback onTap;
  final StopLiveSummary? liveSummary;

  @override
  Widget build(BuildContext context) {
    final accent = switch (entry.kind) {
      FavoriteHomeEntryKind.line => const Color(0xFF164B9D),
      FavoriteHomeEntryKind.stop => const Color(0xFF2E7D32),
      FavoriteHomeEntryKind.route => const Color(0xFFE65100),
    };

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [accent.withValues(alpha: 0.08), Colors.white],
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeaderChip(
                      label: liveSummary!.hasEstimate
                          ? 'En yakın araç: ${liveSummary!.nearestEtaMinutes} dk'
                          : 'Canlı araç bekleniyor',
                    ),
                    if (liveSummary!.nextEtaMinutes != null)
                      _HeaderChip(
                        label: 'Sonraki: ${liveSummary!.nextEtaMinutes} dk',
                      ),
                    _HeaderChip(label: 'Araç: ${liveSummary!.liveBusCount}'),
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
          const Text('Hat, durak veya kayıtlı rota ekleyerek ana sayfayı doldurabilirsin.'),
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

class _FavoriteStopLiveCard extends StatelessWidget {
  const _FavoriteStopLiveCard({
    required this.item,
    required this.summary,
    required this.onTap,
  });

  final FavoriteStopItem item;
  final StopLiveSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasEstimate = summary.hasEstimate;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 0.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.location_on_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.stopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text('ID: ${item.stopId}'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _HeaderChip(
                          label: hasEstimate
                              ? 'En yakın: ${summary.nearestEtaMinutes} dk'
                              : 'Canlı veri yok',
                        ),
                        if (summary.nextEtaMinutes != null)
                          _HeaderChip(label: 'Sonraki: ${summary.nextEtaMinutes} dk'),
                        _HeaderChip(label: 'Araç: ${summary.liveBusCount}'),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
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
      color: Colors.white,
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
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 3),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
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

class _EmptyInlineCard extends StatelessWidget {
  const _EmptyInlineCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E7F0)),
      ),
      child: Text(text),
    );
  }
}

class _LiveFootnote extends StatelessWidget {
  const _LiveFootnote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF6A6A6A),
          ),
    );
  }
}

double mathMax(double a, double b) => a > b ? a : b;
