import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'favorite_line_item.dart';
import 'favorite_route_item.dart';
import 'favorite_stop_item.dart';

class FavoritesStorage {
  FavoritesStorage._();

  static final FavoritesStorage instance = FavoritesStorage._();

  static const String _dbName = 'adanabus_local.db';
  static const String _favoriteLinesTable = 'favorite_lines';
  static const String _favoriteStopsTable = 'favorite_stops';
  static const String _favoriteRoutesTable = 'favorite_routes';
  static const String _favoriteHomeOrderTable = 'favorite_home_order';

  Database? _db;

  Future<Database> _getDatabase() async {
    if (_db != null) {
      return _db!;
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);

    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_favoriteLinesTable (
            route_code TEXT PRIMARY KEY,
            route_name TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE $_favoriteStopsTable (
            stop_id TEXT PRIMARY KEY,
            stop_name TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE $_favoriteRoutesTable (
            route_key TEXT PRIMARY KEY,
            start_stop_id TEXT NOT NULL,
            start_stop_name TEXT NOT NULL,
            start_latitude REAL NOT NULL,
            start_longitude REAL NOT NULL,
            start_routes TEXT NOT NULL,
            end_stop_id TEXT NOT NULL,
            end_stop_name TEXT NOT NULL,
            end_latitude REAL NOT NULL,
            end_longitude REAL NOT NULL,
            end_routes TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE $_favoriteHomeOrderTable (
            item_key TEXT PRIMARY KEY,
            sort_index INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $_favoriteRoutesTable (
              route_key TEXT PRIMARY KEY,
              start_stop_id TEXT NOT NULL,
              start_stop_name TEXT NOT NULL,
              start_latitude REAL NOT NULL,
              start_longitude REAL NOT NULL,
              start_routes TEXT NOT NULL,
              end_stop_id TEXT NOT NULL,
              end_stop_name TEXT NOT NULL,
              end_latitude REAL NOT NULL,
              end_longitude REAL NOT NULL,
              end_routes TEXT NOT NULL
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS $_favoriteHomeOrderTable (
              item_key TEXT PRIMARY KEY,
              sort_index INTEGER NOT NULL
            )
          ''');
        }
      },
    );

    return _db!;
  }

  Future<List<FavoriteLineItem>> loadFavoriteLines() async {
    final db = await _getDatabase();
    final rows = await db.query(
      _favoriteLinesTable,
      orderBy: 'route_code ASC',
    );

    return rows
        .map(
          (row) => FavoriteLineItem(
            routeCode: (row['route_code'] ?? '').toString(),
            routeName: (row['route_name'] ?? '').toString(),
          ),
        )
        .where((item) => item.routeCode.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<FavoriteStopItem>> loadFavoriteStops() async {
    final db = await _getDatabase();
    final rows = await db.query(
      _favoriteStopsTable,
      orderBy: 'stop_name ASC',
    );

    return rows
        .map(
          (row) => FavoriteStopItem(
            stopId: (row['stop_id'] ?? '').toString(),
            stopName: (row['stop_name'] ?? '').toString(),
            latitude: (row['latitude'] as num?)?.toDouble() ?? 0,
            longitude: (row['longitude'] as num?)?.toDouble() ?? 0,
          ),
        )
        .where((item) => item.stopId.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<FavoriteRouteItem>> loadFavoriteRoutes() async {
    final db = await _getDatabase();
    final rows = await db.query(
      _favoriteRoutesTable,
      orderBy: 'start_stop_name ASC, end_stop_name ASC',
    );

    return rows
        .map(
          (row) => FavoriteRouteItem(
            startStopId: (row['start_stop_id'] ?? '').toString(),
            startStopName: (row['start_stop_name'] ?? '').toString(),
            startLatitude: (row['start_latitude'] as num?)?.toDouble() ?? 0,
            startLongitude: (row['start_longitude'] as num?)?.toDouble() ?? 0,
            startRoutes: _splitCsv((row['start_routes'] ?? '').toString()),
            endStopId: (row['end_stop_id'] ?? '').toString(),
            endStopName: (row['end_stop_name'] ?? '').toString(),
            endLatitude: (row['end_latitude'] as num?)?.toDouble() ?? 0,
            endLongitude: (row['end_longitude'] as num?)?.toDouble() ?? 0,
            endRoutes: _splitCsv((row['end_routes'] ?? '').toString()),
          ),
        )
        .where(
          (item) => item.startStopId.isNotEmpty && item.endStopId.isNotEmpty,
        )
        .toList(growable: false);
  }

  Future<List<String>> loadFavoriteHomeOrderKeys() async {
    final db = await _getDatabase();
    final rows = await db.query(
      _favoriteHomeOrderTable,
      orderBy: 'sort_index ASC',
    );

    return rows
        .map((row) => (row['item_key'] ?? '').toString())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> replaceFavoriteLines(List<FavoriteLineItem> lines) async {
    final db = await _getDatabase();
    await db.transaction((txn) async {
      await txn.delete(_favoriteLinesTable);
      for (final line in lines) {
        await txn.insert(_favoriteLinesTable, {
          'route_code': line.routeCode,
          'route_name': line.routeName,
        });
      }
    });
  }

  Future<void> replaceFavoriteStops(List<FavoriteStopItem> stops) async {
    final db = await _getDatabase();
    await db.transaction((txn) async {
      await txn.delete(_favoriteStopsTable);
      for (final stop in stops) {
        await txn.insert(_favoriteStopsTable, {
          'stop_id': stop.stopId,
          'stop_name': stop.stopName,
          'latitude': stop.latitude,
          'longitude': stop.longitude,
        });
      }
    });
  }

  Future<void> replaceFavoriteRoutes(List<FavoriteRouteItem> routes) async {
    final db = await _getDatabase();
    await db.transaction((txn) async {
      await txn.delete(_favoriteRoutesTable);
      for (final route in routes) {
        await txn.insert(_favoriteRoutesTable, {
          'route_key': route.key,
          'start_stop_id': route.startStopId,
          'start_stop_name': route.startStopName,
          'start_latitude': route.startLatitude,
          'start_longitude': route.startLongitude,
          'start_routes': route.startRoutes.join(','),
          'end_stop_id': route.endStopId,
          'end_stop_name': route.endStopName,
          'end_latitude': route.endLatitude,
          'end_longitude': route.endLongitude,
          'end_routes': route.endRoutes.join(','),
        });
      }
    });
  }

  Future<void> replaceFavoriteHomeOrderKeys(List<String> keys) async {
    final db = await _getDatabase();
    await db.transaction((txn) async {
      await txn.delete(_favoriteHomeOrderTable);
      for (var index = 0; index < keys.length; index++) {
        final key = keys[index].trim();
        if (key.isEmpty) {
          continue;
        }
        await txn.insert(_favoriteHomeOrderTable, {
          'item_key': key,
          'sort_index': index,
        });
      }
    });
  }

  static List<String> _splitCsv(String value) {
    if (value.trim().isEmpty) {
      return const <String>[];
    }
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
