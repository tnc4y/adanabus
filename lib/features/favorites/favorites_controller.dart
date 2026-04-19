import 'package:flutter/foundation.dart';

import 'favorite_home_entry.dart';
import 'favorite_line_item.dart';
import 'favorite_route_item.dart';
import 'favorite_stop_item.dart';
import 'favorites_storage.dart';

class FavoritesController extends ChangeNotifier {
  final List<FavoriteLineItem> _favoriteLines = <FavoriteLineItem>[];
  final List<FavoriteStopItem> _favoriteStops = <FavoriteStopItem>[];
  final List<FavoriteRouteItem> _favoriteRoutes = <FavoriteRouteItem>[];
  final List<String> _homeOrderKeys = <String>[];
  bool _isReady = false;
  Future<void> _saveQueue = Future<void>.value();

  bool get isReady => _isReady;

  List<FavoriteLineItem> get favoriteLines =>
      List<FavoriteLineItem>.unmodifiable(_favoriteLines);
  List<FavoriteStopItem> get favoriteStops =>
      List<FavoriteStopItem>.unmodifiable(_favoriteStops);
  List<FavoriteRouteItem> get favoriteRoutes =>
      List<FavoriteRouteItem>.unmodifiable(_favoriteRoutes);

  List<String> get homeOrderKeys =>
      List<String>.unmodifiable(_homeOrderKeys);

  List<FavoriteHomeEntry> get homeEntries {
    final allEntries = <FavoriteHomeEntry>[
      ..._favoriteRoutes.map(FavoriteHomeEntry.route),
      ..._favoriteStops.map(FavoriteHomeEntry.stop),
      ..._favoriteLines.map(FavoriteHomeEntry.line),
    ];
    final byKey = <String, FavoriteHomeEntry>{
      for (final entry in allEntries) entry.key: entry,
    };

    final ordered = <FavoriteHomeEntry>[];
    final seen = <String>{};

    for (final key in _homeOrderKeys) {
      final entry = byKey[key];
      if (entry != null) {
        ordered.add(entry);
        seen.add(key);
      }
    }

    for (final entry in allEntries) {
      if (seen.add(entry.key)) {
        ordered.add(entry);
      }
    }

    return List<FavoriteHomeEntry>.unmodifiable(ordered);
  }

  Future<void> initialize() async {
    if (_isReady) {
      return;
    }
    try {
      await _loadFromStorage();
    } catch (_) {
      // Persistence is optional; app should continue even if storage fails.
    }
    _isReady = true;
    notifyListeners();
  }

  bool isFavoriteRoute(String routeCode) {
    return _favoriteLines.any((item) => item.routeCode == routeCode);
  }

  bool isFavoriteStop(String stopId) {
    return _favoriteStops.any((item) => item.stopId == stopId);
  }

  bool isFavoriteRoutePair(String startStopId, String endStopId) {
    final key = '$startStopId->$endStopId';
    return _favoriteRoutes.any((item) => item.key == key);
  }

  bool toggleFavoriteLine({
    required String routeCode,
    required String routeName,
  }) {
    final index =
        _favoriteLines.indexWhere((item) => item.routeCode == routeCode);
    if (index >= 0) {
      _favoriteLines.removeAt(index);
      _scheduleSave();
      notifyListeners();
      return false;
    }

    _favoriteLines.add(
      FavoriteLineItem(routeCode: routeCode, routeName: routeName),
    );
    _favoriteLines.sort((a, b) => a.routeCode.compareTo(b.routeCode));
    _ensureHomeKey('line:$routeCode');
    _scheduleSave();
    notifyListeners();
    return true;
  }

  void removeFavoriteLine(String routeCode) {
    _favoriteLines.removeWhere((item) => item.routeCode == routeCode);
    _homeOrderKeys.remove('line:$routeCode');
    _scheduleSave();
    notifyListeners();
  }

  void clearFavoriteLines() {
    _favoriteLines.clear();
    _scheduleSave();
    notifyListeners();
  }

  bool toggleFavoriteStop(FavoriteStopItem stop) {
    final index =
        _favoriteStops.indexWhere((item) => item.stopId == stop.stopId);
    if (index >= 0) {
      _favoriteStops.removeAt(index);
      _scheduleSave();
      notifyListeners();
      return false;
    }

    _favoriteStops.add(stop);
    _favoriteStops.sort((a, b) => a.stopName.compareTo(b.stopName));
    _ensureHomeKey('stop:${stop.stopId}');
    _scheduleSave();
    notifyListeners();
    return true;
  }

  void removeFavoriteStop(String stopId) {
    _favoriteStops.removeWhere((item) => item.stopId == stopId);
    _homeOrderKeys.remove('stop:$stopId');
    _scheduleSave();
    notifyListeners();
  }

  void clearFavoriteStops() {
    _favoriteStops.clear();
    _scheduleSave();
    notifyListeners();
  }

  bool toggleFavoriteRoute(FavoriteRouteItem route) {
    final index = _favoriteRoutes.indexWhere((item) => item.key == route.key);
    if (index >= 0) {
      _favoriteRoutes.removeAt(index);
      _scheduleSave();
      notifyListeners();
      return false;
    }

    _favoriteRoutes.add(route);
    _favoriteRoutes.sort((a, b) {
      final byStart = a.startStopName.compareTo(b.startStopName);
      if (byStart != 0) {
        return byStart;
      }
      return a.endStopName.compareTo(b.endStopName);
    });
    _ensureHomeKey('route:${route.key}');
    _scheduleSave();
    notifyListeners();
    return true;
  }

  void removeFavoriteRoute(String routeKey) {
    _favoriteRoutes.removeWhere((item) => item.key == routeKey);
    _homeOrderKeys.remove('route:$routeKey');
    _scheduleSave();
    notifyListeners();
  }

  void clearFavoriteRoutes() {
    _favoriteRoutes.clear();
    _homeOrderKeys.removeWhere((item) => item.startsWith('route:'));
    _scheduleSave();
    notifyListeners();
  }

  void reorderHomeEntry(int oldIndex, int newIndex) {
    final entries = homeEntries;
    if (entries.isEmpty) {
      return;
    }
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= entries.length) {
      return;
    }

    final keys = entries.map((entry) => entry.key).toList(growable: true);
    final moved = keys.removeAt(oldIndex);
    keys.insert(newIndex, moved);

    _homeOrderKeys
      ..clear()
      ..addAll(keys);
    _scheduleSave();
    notifyListeners();
  }

  Future<void> _loadFromStorage() async {
    final loaded = await FavoritesStorage.instance.loadFavoriteLines();
    _favoriteLines
      ..clear()
      ..addAll(loaded);

    final loadedStops = await FavoritesStorage.instance.loadFavoriteStops();
    _favoriteStops
      ..clear()
      ..addAll(loadedStops);

    final loadedRoutes = await FavoritesStorage.instance.loadFavoriteRoutes();
    _favoriteRoutes
      ..clear()
      ..addAll(loadedRoutes);

    final loadedHomeOrder = await FavoritesStorage.instance
        .loadFavoriteHomeOrderKeys();
    _homeOrderKeys
      ..clear()
      ..addAll(loadedHomeOrder);
    _pruneHomeOrder();
  }

  Future<void> _saveToStorage() async {
    try {
      await FavoritesStorage.instance.replaceFavoriteLines(_favoriteLines);
      await FavoritesStorage.instance.replaceFavoriteStops(_favoriteStops);
      await FavoritesStorage.instance.replaceFavoriteRoutes(_favoriteRoutes);
      await FavoritesStorage.instance.replaceFavoriteHomeOrderKeys(
        _homeOrderKeys,
      );
    } catch (_) {
      // Ignore and retry on next save attempt.
    }
  }

  void _ensureHomeKey(String key) {
    if (!_homeOrderKeys.contains(key)) {
      _homeOrderKeys.add(key);
    }
  }

  void _pruneHomeOrder() {
    final validKeys = homeEntries.map((entry) => entry.key).toSet();
    _homeOrderKeys.removeWhere((key) => !validKeys.contains(key));
  }

  void _scheduleSave() {
    _saveQueue = _saveQueue.then((_) => _saveToStorage());
  }
}
