import 'package:flutter/material.dart';

import '../../data/models/transit_stop.dart';
import 'favorite_route_detail_page.dart';
import 'favorite_route_item.dart';
import '../stops/stop_detail_page.dart';
import '../stops/stop_picker_page.dart';
import 'favorites_controller.dart';
import 'favorite_stop_item.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({
    super.key,
    required this.favoritesController,
  });

  final FavoritesController favoritesController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: favoritesController,
      builder: (context, _) {
        final lines = favoritesController.favoriteLines;
        final stops = favoritesController.favoriteStops;
        final routes = favoritesController.favoriteRoutes;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Favoriler'),
            actions: [
              if (lines.isNotEmpty)
                IconButton(
                  onPressed: favoritesController.clearFavoriteLines,
                  icon: const Icon(Icons.delete_sweep_outlined),
                  tooltip: 'Tumunu temizle',
                ),
              if (stops.isNotEmpty)
                IconButton(
                  onPressed: favoritesController.clearFavoriteStops,
                  icon: const Icon(Icons.location_off_outlined),
                  tooltip: 'Tum durak favorilerini temizle',
                ),
              if (routes.isNotEmpty)
                IconButton(
                  onPressed: favoritesController.clearFavoriteRoutes,
                  icon: const Icon(Icons.alt_route_outlined),
                  tooltip: 'Tum kayitli rotalari temizle',
                ),
            ],
          ),
          body: !favoritesController.isReady
              ? const Center(child: CircularProgressIndicator())
              : lines.isEmpty && stops.isEmpty && routes.isEmpty
                  ? const _EmptyFavoritesState()
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Kayitli Rotalar',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final startStop =
                                    await Navigator.of(context).push<TransitStop>(
                                  MaterialPageRoute(
                                    builder: (_) => const StopPickerPage(
                                      selectedStopIds: <String>{},
                                    ),
                                  ),
                                );
                                if (startStop == null || !context.mounted) {
                                  return;
                                }

                                final endStop =
                                    await Navigator.of(context).push<TransitStop>(
                                  MaterialPageRoute(
                                    builder: (_) => StopPickerPage(
                                      selectedStopIds: <String>{
                                        startStop.stopId,
                                      },
                                    ),
                                  ),
                                );
                                if (endStop == null || !context.mounted) {
                                  return;
                                }

                                if (startStop.stopId == endStop.stopId) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Baslangic ve varis ayni olamaz.'),
                                    ),
                                  );
                                  return;
                                }

                                final added = favoritesController
                                    .toggleFavoriteRoute(
                                  FavoriteRouteItem(
                                    startStopId: startStop.stopId,
                                    startStopName: startStop.stopName,
                                    startLatitude: startStop.latitude,
                                    startLongitude: startStop.longitude,
                                    startRoutes: startStop.routes,
                                    endStopId: endStop.stopId,
                                    endStopName: endStop.stopName,
                                    endLatitude: endStop.latitude,
                                    endLongitude: endStop.longitude,
                                    endRoutes: endStop.routes,
                                  ),
                                );

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      added
                                          ? 'Kayitli rota eklendi'
                                          : 'Kayitli rota favorilerden cikarildi',
                                    ),
                                    duration:
                                        const Duration(milliseconds: 1100),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.alt_route_outlined),
                              label: const Text('Rota Ekle'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (routes.isEmpty)
                          const _SectionEmpty(
                            text: 'Henuz kayitli iki-durak rota yok.',
                          )
                        else
                          ...routes.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _FavoritePairRouteCard(
                                item: item,
                                onRemove: () => favoritesController
                                    .removeFavoriteRoute(item.key),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => FavoriteRouteDetailPage(
                                        item: item,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Favori Duraklar',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () async {
                                final selectedStop = await Navigator.of(context)
                                    .push<TransitStop>(
                                  MaterialPageRoute(
                                    builder: (_) => StopPickerPage(
                                      selectedStopIds: stops
                                          .map((item) => item.stopId)
                                          .toSet(),
                                    ),
                                  ),
                                );
                                if (selectedStop != null) {
                                  final added =
                                      favoritesController.toggleFavoriteStop(
                                    FavoriteStopItem(
                                      stopId: selectedStop.stopId,
                                      stopName: selectedStop.stopName,
                                      latitude: selectedStop.latitude,
                                      longitude: selectedStop.longitude,
                                    ),
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          added
                                              ? 'Durak favorilere eklendi'
                                              : 'Durak favorilerden cikarildi',
                                        ),
                                        duration:
                                            const Duration(milliseconds: 1000),
                                      ),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.add_location_alt_outlined),
                              label: const Text('Durak Ekle'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (stops.isEmpty)
                          const _SectionEmpty(text: 'Henuz favori durak yok.')
                        else
                          ...stops.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _FavoriteStopCard(
                                item: item,
                                onRemove: () => favoritesController
                                    .removeFavoriteStop(item.stopId),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => StopDetailPage(
                                        favoriteStop: item,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        Text(
                          'Favori Hatlar',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (lines.isEmpty)
                          const _SectionEmpty(text: 'Henuz favori hat yok.')
                        else
                          ...lines.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _FavoriteLineCard(
                                routeCode: item.routeCode,
                                routeName: item.routeName,
                                onRemove: () => favoritesController
                                    .removeFavoriteLine(item.routeCode),
                              ),
                            ),
                          ),
                      ],
                    ),
        );
      },
    );
  }
}

class _FavoriteLineCard extends StatelessWidget {
  const _FavoriteLineCard({
    required this.routeCode,
    required this.routeName,
    required this.onRemove,
  });

  final String routeCode;
  final String routeName;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E7F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFFEAF2FF),
            ),
            child: Text(
              routeCode,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              routeName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Favoriden kaldir',
          ),
        ],
      ),
    );
  }
}

class _FavoriteStopCard extends StatelessWidget {
  const _FavoriteStopCard({
    required this.item,
    required this.onRemove,
    required this.onTap,
  });

  final FavoriteStopItem item;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E7F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.stopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'ID: ${item.stopId}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Favoriden kaldir',
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritePairRouteCard extends StatelessWidget {
  const _FavoritePairRouteCard({
    required this.item,
    required this.onRemove,
    required this.onTap,
  });

  final FavoriteRouteItem item;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E7F0)),
        ),
        child: Row(
          children: [
            const Icon(Icons.alt_route_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.startStopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.endStopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'ID: ${item.startStopId} -> ${item.endStopId}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Favoriden kaldir',
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E7F0)),
      ),
      child: Text(text),
    );
  }
}

class _EmptyFavoritesState extends StatelessWidget {
  const _EmptyFavoritesState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_border, size: 44),
          const SizedBox(height: 6),
          Text(
            'Henuz favori yok',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text('Hat, durak veya iki durakli rota ekleyebilirsin.'),
        ],
      ),
    );
  }
}
