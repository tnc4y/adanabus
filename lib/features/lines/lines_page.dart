import 'package:flutter/material.dart';

import '../../core/theme_utils.dart';
import '../../data/models/bus_option.dart';
import '../../data/services/adana_api_service.dart';
import '../favorites/favorites_controller.dart';
import 'line_detail_page.dart';
import 'trip_planner_page.dart';

class LinesPage extends StatefulWidget {
  const LinesPage({
    super.key,
    required this.favoritesController,
  });

  final FavoritesController favoritesController;

  @override
  State<LinesPage> createState() => _LinesPageState();
}

class _LinesPageState extends State<LinesPage> {
  final AdanaApiService _apiService = AdanaApiService();

  List<BusOption> _allOptions = <BusOption>[];
  String _query = '';
  String _selectedRouteCode = '';
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLines();
  }

  Future<void> _loadLines() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final buses = await _apiService.fetchBuses();
      final options = BusOption.fromBuses(buses);
      setState(() {
        _allOptions = options;
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.favoritesController,
      builder: (context, _) {
        final normalizedQuery = _query.toLowerCase().trim();
        final filtered = _allOptions.where((option) {
          if (normalizedQuery.isEmpty) {
            return true;
          }

          final name = option.names.isEmpty ? '' : option.names.first;
          return option.displayRouteCode
                  .toLowerCase()
                  .contains(normalizedQuery) ||
              name.toLowerCase().contains(normalizedQuery);
        }).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Hatlar'),
            actions: [
              IconButton(
                onPressed: _isLoading ? null : _loadLines,
                icon: const Icon(Icons.refresh),
                tooltip: 'Yenile',
              ),
              IconButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TripPlannerPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.route),
                tooltip: 'Yolculuk Planla',
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Hat numarasi veya hat adi ara',
                  ),
                ),
                const SizedBox(height: 10),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
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
                          ? const Center(
                              child: Text('Hat bulunamadi.'),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final option = filtered[index];
                                final routeName = option.names.isEmpty
                                    ? 'Isim bilgisi yok'
                                    : option.names.first;
                                return _LineTile(
                                  option: option,
                                  routeName: routeName,
                                  isSelected: option.displayRouteCode ==
                                      _selectedRouteCode,
                                  isFavorite: widget.favoritesController
                                      .isFavoriteRoute(option.displayRouteCode),
                                  onTap: () {
                                    setState(() {
                                      _selectedRouteCode =
                                          option.displayRouteCode;
                                    });
                                    final direction =
                                        option.directions.isNotEmpty
                                            ? option.directions.first
                                            : '0';
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => LineDetailPage(
                                          routeCode: option.displayRouteCode,
                                          routeName: routeName,
                                          direction: direction,
                                        ),
                                      ),
                                    );
                                  },
                                  onToggleFavorite: () {
                                    final added = widget.favoritesController
                                        .toggleFavoriteLine(
                                      routeCode: option.displayRouteCode,
                                      routeName: routeName,
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          added
                                              ? 'Hat ${option.displayRouteCode} favorilere eklendi'
                                              : 'Hat ${option.displayRouteCode} favorilerden cikarildi',
                                        ),
                                        duration:
                                            const Duration(milliseconds: 1100),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.option,
    required this.routeName,
    required this.isSelected,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  final BusOption option;
  final String routeName;
  final bool isSelected;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? AppThemeUtils.getAccentColor(context, 'blue')
        : AppThemeUtils.getBorderColor(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppThemeUtils.getCardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: AppThemeUtils.getSubtleBackgroundColor(context),
              ),
              child: Text(
                option.displayRouteCode,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                routeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: onToggleFavorite,
              icon: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: isFavorite ? const Color(0xFFDA9F18) : null,
              ),
              tooltip: isFavorite ? 'Favoriden cikar' : 'Favoriye ekle',
            ),
          ],
        ),
      ),
    );
  }
}
