import 'package:flutter/material.dart';

import '../../core/theme_utils.dart';
import '../../data/models/bus_option.dart';
import '../../data/services/adana_api_service.dart';
import '../favorites/favorites_controller.dart';
import 'line_detail_page.dart';
import 'trip_planner_page.dart';

class LinesPage extends StatefulWidget {
  const LinesPage({super.key, required this.favoritesController});
  final FavoritesController favoritesController;

  @override
  State<LinesPage> createState() => _LinesPageState();
}

class _LinesPageState extends State<LinesPage> {
  final AdanaApiService _apiService = AdanaApiService();
  final TextEditingController _searchController = TextEditingController();

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLines() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final buses = await _apiService.fetchBuses();
      final options = BusOption.fromBuses(buses);
      setState(() => _allOptions = options);
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.favoritesController,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final normalizedQuery = _query.toLowerCase().trim();
        final filtered = _allOptions.where((option) {
          if (normalizedQuery.isEmpty) return true;
          final name = option.names.isEmpty ? '' : option.names.first;
          return option.displayRouteCode.toLowerCase().contains(normalizedQuery) ||
              name.toLowerCase().contains(normalizedQuery);
        }).toList();

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              // ── App Bar ──────────────────────────────────────────────
              SliverAppBar(
                pinned: true,
                floating: false,
                backgroundColor:
                    isDark ? const Color(0xFF0F1722) : Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                titleSpacing: 20,
                title: const Text(
                  'Hat Listesi',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                ),
                actions: [
                  IconButton(
                    onPressed: _isLoading ? null : _loadLines,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 22),
                    tooltip: 'Yenile',
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TripPlannerPage()),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      icon: const Icon(Icons.alt_route_rounded, size: 16),
                      label: const Text('Rota Planla'),
                    ),
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(60),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _SearchBar(
                      controller: _searchController,
                      isDark: isDark,
                      onChanged: (v) => setState(() => _query = v),
                      onClear: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
                  ),
                ),
              ),

              // ── Error ──────────────────────────────────────────────
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Container(
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
                              _error!,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7A2010),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _error = null),
                            icon: const Icon(Icons.close_rounded,
                                size: 16, color: Color(0xFFB63519)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // ── Stats row ─────────────────────────────────────────
              if (!_isLoading && filtered.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      normalizedQuery.isEmpty
                          ? '${filtered.length} hat aktif'
                          : '${filtered.length} sonuç bulundu',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppThemeUtils.getSecondaryTextColor(context),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),

              // ── Loading ────────────────────────────────────────────
              if (_isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              // ── Empty ──────────────────────────────────────────────
              else if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48,
                            color: AppThemeUtils.getSecondaryTextColor(context)),
                        const SizedBox(height: 12),
                        Text(
                          'Hat bulunamadı',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                )
              // ── List ───────────────────────────────────────────────
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final option = filtered[index];
                      final routeName = option.names.isEmpty
                          ? 'İsim bilgisi yok'
                          : option.names.first;
                      return _LineTile(
                        option: option,
                        routeName: routeName,
                        isSelected: option.displayRouteCode == _selectedRouteCode,
                        isFavorite: widget.favoritesController
                            .isFavoriteRoute(option.displayRouteCode),
                        onTap: () {
                          setState(() => _selectedRouteCode = option.displayRouteCode);
                          final direction = option.directions.isNotEmpty
                              ? option.directions.first
                              : '0';
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => LineDetailPage(
                              routeCode: option.displayRouteCode,
                              routeName: routeName,
                              direction: direction,
                            ),
                          ));
                        },
                        onToggleFavorite: () {
                          final added = widget.favoritesController.toggleFavoriteLine(
                            routeCode: option.displayRouteCode,
                            routeName: routeName,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                              added
                                  ? 'Hat ${option.displayRouteCode} favorilere eklendi'
                                  : 'Hat ${option.displayRouteCode} kaldırıldı',
                            ),
                            duration: const Duration(milliseconds: 1100),
                          ));
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Search Bar ──────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.isDark,
    required this.onChanged,
    required this.onClear,
  });
  final TextEditingController controller;
  final bool isDark;
  final void Function(String) onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2535) : const Color(0xFFF3F6FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF2A3647) : const Color(0xFFE2E7F0),
        ),
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
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppThemeUtils.getTextColor(context),
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Hat numarası veya adı ara…',
                hintStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppThemeUtils.getSecondaryTextColor(context),
                ),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.close_rounded,
                    size: 16,
                    color: AppThemeUtils.getSecondaryTextColor(context)),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Line Tile ───────────────────────────────────────────────────────────────

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
    final blue = AppThemeUtils.getAccentColor(context, 'blue');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final borderColor = isSelected
        ? blue.withValues(alpha: 0.6)
        : AppThemeUtils.getBorderColor(context);

    return Material(
      color: AppThemeUtils.getCardColor(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.3),
            color: isSelected
                ? blue.withValues(alpha: isDark ? 0.08 : 0.04)
                : null,
          ),
          child: Row(
            children: [
              // Route code badge
              Container(
                constraints: const BoxConstraints(minWidth: 46),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  option.displayRouteCode,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: blue,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Route name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppThemeUtils.getTextColor(context),
                      ),
                    ),
                    if (option.directions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${option.directions.length} yön • Aktif',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppThemeUtils.getAccentColor(context, 'green'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Favorite toggle
              GestureDetector(
                onTap: onToggleFavorite,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isFavorite
                        ? const Color(0xFFDA9F18)
                        : AppThemeUtils.getSecondaryTextColor(context),
                    size: 22,
                  ),
                ),
              ),
              // Chevron
              Icon(Icons.chevron_right_rounded,
                  size: 20,
                  color: AppThemeUtils.getSecondaryTextColor(context)),
            ],
          ),
        ),
      ),
    );
  }
}
