import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_env.dart';
import '../models/bus_vehicle.dart';
import '../models/transit_stop.dart';

class AdanaApiService {
  AdanaApiService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  static const String tokenUrl = 'https://akillikentapi.adana.bel.tr/api/token';
  static const String busesUrl = 'https://akillikentapi.adana.bel.tr/api/buses';
  static const String nearbyStopsUrl =
      'https://akillikentapi.adana.bel.tr/api/nearByStops';
  static const String allAttentionBusUrl =
      'https://akillikentapi.adana.bel.tr/api/all_attention_bus';
  static const String stopBusTimeByBusIdUrl =
      'https://akillikentapi.adana.bel.tr/api/stopBusTimeBusId';
  static const String attentionBusByBusIdUrl =
      'https://akillikentapi.adana.bel.tr/api/attentionBusId';
  static const String kentkartPathInfoUrl =
      'https://service.kentkart.com/rl1/api/sep/pathInfo';

  static const String _kentkartRegion = '003';
  static const String _kentkartLang = 'tr';
  static const String _kentkartAuthType = '3';
  static const String _kentkartResultType = '111111';
  static const String _stopsCacheKey = 'stops_catalog_v1';
  static const String _stopsCacheUpdatedAtKey = 'stops_catalog_updated_at_ms';
  static const Duration _stopsCacheTtl = Duration(days: 30);

  final http.Client _httpClient;
  String? _token;
  List<TransitStop>? _cachedStops;
  SharedPreferences? _prefs;
  bool _storageUnavailable = false;

  bool get isDemoMode => false;

  Future<String> ensureToken({bool forceRefresh = false}) async {
    if (!AppEnv.hasApiCredentials) {
      throw Exception(
        'Gercek veri icin ADANA_EMAIL ve ADANA_PASSWORD zorunlu. '
        'Ornek: flutter run --dart-define=ADANA_EMAIL=mail --dart-define=ADANA_PASSWORD=sifre',
      );
    }

    if (_token != null && !forceRefresh) {
      return _token!;
    }

    final response = await _httpClient.post(
      Uri.parse(tokenUrl),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'okhttp/3.12.0',
      },
      body: {
        'email': AppEnv.tokenEmail,
        'password': AppEnv.tokenPassword,
      },
    );

    final parsed = _decodeJson(response);
    final tokenValue =
        parsed['token'] ?? parsed['access_token'] ?? parsed['data'];
    if (tokenValue == null || tokenValue.toString().trim().isEmpty) {
      throw Exception('Token alinamadi: beklenmeyen API yaniti.');
    }

    _token = tokenValue.toString();
    return _token!;
  }

  Future<List<BusVehicle>> fetchBuses() async {
    final token = await ensureToken();
    final response = await _httpClient.post(
      Uri.parse(busesUrl),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'User-Agent': 'okhttp/3.12.0',
      },
    );

    final decoded = _decodeJson(response);
    final list = _extractList(decoded);
    return list
        .whereType<Map<String, dynamic>>()
        .map(BusVehicle.fromJson)
        .toList();
  }

  Future<dynamic> fetchNearbyStops({
    required String lat,
    required String lon,
  }) async {
    final token = await ensureToken();
    final response = await _httpClient.post(
      Uri.parse(nearbyStopsUrl),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'lat': lat,
        'lon': lon,
      },
    );
    return _decodeJson(response);
  }

  Future<dynamic> fetchAllAttentionBus() async {
    final token = await ensureToken();
    final response = await _httpClient.post(
      Uri.parse(allAttentionBusUrl),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    return _decodeJson(response);
  }

  Future<dynamic> fetchStopBusTimeByBusId(String busId) async {
    final token = await ensureToken();
    final response = await _httpClient.post(
      Uri.parse(stopBusTimeByBusIdUrl),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'BusId': busId,
      },
    );
    return _decodeJson(response);
  }

  Future<dynamic> fetchAttentionBusByBusId(String busId) async {
    final token = await ensureToken();
    final response = await _httpClient.post(
      Uri.parse(attentionBusByBusIdUrl),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'BusId': busId,
      },
    );
    return _decodeJson(response);
  }

  Future<dynamic> fetchKentkartPathInfo({
    required String displayRouteCode,
    required String direction,
  }) async {
    if (!AppEnv.hasKentkartToken) {
      return <String, dynamic>{
        'pathList': <dynamic>[],
        'note': 'KENTKART_TOKEN tanimli degil.',
      };
    }

    final uri = Uri.parse(kentkartPathInfoUrl).replace(queryParameters: {
      'region': _kentkartRegion,
      'lang': _kentkartLang,
      'authType': _kentkartAuthType,
      'token': AppEnv.kentkartToken,
      'displayRouteCode': displayRouteCode,
      'resultType': _kentkartResultType,
      'direction': direction,
    });

    final response = await _httpClient.get(uri, headers: {
      'Accept': 'application/json',
      'User-Agent':
          'Dalvik/2.1.0 (Linux; U; Android 11; sdk_gphone_x86 Build/RSR1.240422.006)',
    });

    return _decodeJson(response);
  }

  Future<List<TransitStop>> fetchStopsForDisplayRouteCode(
    String displayRouteCode,
  ) async {
    final stopMap = <String, TransitStop>{};

    for (final direction in const ['0', '1']) {
      try {
        final response = await _fetchPathInfoWithRetry(
          displayRouteCode: displayRouteCode,
          direction: direction,
        );
        final payload = response is Map<String, dynamic>
            ? response
            : <String, dynamic>{'data': response};
        final stops = _extractStopsFromPathPayload(payload);
        for (final stop in stops) {
          final existing = stopMap[stop.stopId];
          if (existing == null) {
            stopMap[stop.stopId] = stop;
          } else {
            final mergedRoutes = <String>{...existing.routes, ...stop.routes}
              ..removeWhere((element) => element.isEmpty);
            stopMap[stop.stopId] = TransitStop(
              stopId: existing.stopId,
              stopName: existing.stopName,
              latitude: existing.latitude,
              longitude: existing.longitude,
              routes: mergedRoutes.toList()..sort(),
            );
          }
        }
      } catch (_) {
        continue;
      }
    }

    return stopMap.values.toList()
      ..sort((a, b) => a.stopName.compareTo(b.stopName));
  }

  Future<List<TransitStop>> fetchAllStopsCatalog({
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      return _fetchAndPersistStopsCatalog();
    }

    if (_cachedStops != null) {
      if (_isStopsCacheStale()) {
        unawaited(_refreshStopsCatalogInBackground());
      }
      return _cachedStops!;
    }

    final cachedFromDisk = await _readStopsCacheFromStorage();
    if (cachedFromDisk.isNotEmpty) {
      _cachedStops = cachedFromDisk;
      if (_isStopsCacheStale()) {
        unawaited(_refreshStopsCatalogInBackground());
      }
      return cachedFromDisk;
    }

    return _fetchAndPersistStopsCatalog();
  }

  Future<void> _refreshStopsCatalogInBackground() async {
    try {
      await _fetchAndPersistStopsCatalog();
    } catch (_) {
      // Keep stale cache rather than failing the UI path.
    }
  }

  Future<List<TransitStop>> _fetchAndPersistStopsCatalog() async {
    final previous = _cachedStops ?? await _readStopsCacheFromStorage();
    final result = await _fetchAllStopsCatalogFromNetwork();

    if (result.isEmpty && previous.isNotEmpty) {
      _cachedStops = previous;
      return previous;
    }

    if (previous.isNotEmpty && result.length < (previous.length * 0.55)) {
      // Keep existing catalog if fetched data looks suspiciously incomplete.
      _cachedStops = previous;
      return previous;
    }

    _cachedStops = result;
    await _writeStopsCacheToStorage(result);
    return result;
  }

  Future<List<TransitStop>> _fetchAllStopsCatalogFromNetwork() async {
    final buses = await fetchBuses();
    final routeCodes = <String>{};
    for (final bus in buses) {
      if (bus.displayRouteCode.isEmpty) {
        continue;
      }
      routeCodes.add(bus.displayRouteCode);
    }

    final routeDirectionPairs = <String>{};
    for (final routeCode in routeCodes) {
      routeDirectionPairs.add('$routeCode|0');
      routeDirectionPairs.add('$routeCode|1');
    }

    final stopMap = <String, TransitStop>{};

    for (final pair in routeDirectionPairs) {
      final split = pair.split('|');
      if (split.length != 2) {
        continue;
      }

      final displayRouteCode = split[0];
      final direction = split[1];

      try {
        final response = await _fetchPathInfoWithRetry(
          displayRouteCode: displayRouteCode,
          direction: direction,
        );
        final payload = response is Map<String, dynamic>
            ? response
            : <String, dynamic>{'data': response};
        final stops = _extractStopsFromPathPayload(payload);
        for (final stop in stops) {
          final existing = stopMap[stop.stopId];
          if (existing == null) {
            stopMap[stop.stopId] = stop;
          } else {
            final mergedRoutes = <String>{...existing.routes, ...stop.routes}
              ..removeWhere((element) => element.isEmpty);
            stopMap[stop.stopId] = TransitStop(
              stopId: existing.stopId,
              stopName: existing.stopName,
              latitude: existing.latitude,
              longitude: existing.longitude,
              routes: mergedRoutes.toList()..sort(),
            );
          }
        }
      } catch (_) {
        continue;
      }
    }

    return stopMap.values.toList()
      ..sort((a, b) => a.stopName.compareTo(b.stopName));
  }

  Future<dynamic> _fetchPathInfoWithRetry({
    required String displayRouteCode,
    required String direction,
  }) async {
    try {
      return await fetchKentkartPathInfo(
        displayRouteCode: displayRouteCode,
        direction: direction,
      );
    } catch (_) {
      return await fetchKentkartPathInfo(
        displayRouteCode: displayRouteCode,
        direction: direction,
      );
    }
  }

  List<TransitStop> _extractStopsFromPathPayload(Map<String, dynamic> payload) {
    final pathList = payload['pathList'];
    if (pathList is! List) {
      return const <TransitStop>[];
    }

    final stopMap = <String, TransitStop>{};

    for (final path in pathList) {
      if (path is! Map<String, dynamic>) {
        continue;
      }

      final rawStops = path['busStopList'];
      if (rawStops is! List) {
        continue;
      }

      for (final rawStop in rawStops) {
        if (rawStop is! Map<String, dynamic>) {
          continue;
        }

        final stopId = _readString(rawStop, const ['stopId', 'StopId', 'id']);
        if (stopId.isEmpty) {
          continue;
        }

        final stopName = _readString(
          rawStop,
          const ['stopName', 'StopName', 'name', 'durakAdi'],
        );
        final lat = _readDouble(rawStop, const ['lat', 'latitude', 'y']);
        final lng =
            _readDouble(rawStop, const ['lng', 'lon', 'longitude', 'x']);
        if (lat == null || lng == null) {
          continue;
        }

        final routesRaw = _readString(rawStop, const ['routes']);
        final routes = routesRaw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

        stopMap[stopId] = TransitStop(
          stopId: stopId,
          stopName: stopName.isEmpty ? 'Durak $stopId' : stopName,
          latitude: lat,
          longitude: lng,
          routes: routes,
        );
      }
    }

    return stopMap.values.toList(growable: false);
  }

  bool _isStopsCacheStale() {
    final updatedAtMs = _prefs?.getInt(_stopsCacheUpdatedAtKey);
    if (updatedAtMs == null) {
      return true;
    }
    final updatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
    return DateTime.now().difference(updatedAt) >= _stopsCacheTtl;
  }

  Future<List<TransitStop>> _readStopsCacheFromStorage() async {
    final prefs = await _getPrefsSafe();
    if (prefs == null) {
      return <TransitStop>[];
    }

    final raw = prefs.getString(_stopsCacheKey);
    if (raw == null || raw.isEmpty) {
      return <TransitStop>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <TransitStop>[];
      }

      final stops = decoded
          .whereType<Map<String, dynamic>>()
          .map(TransitStop.fromJson)
          .where((stop) => stop.stopId.isNotEmpty)
          .toList(growable: false)
        ..sort((a, b) => a.stopName.compareTo(b.stopName));

      return stops;
    } catch (_) {
      return <TransitStop>[];
    }
  }

  Future<void> _writeStopsCacheToStorage(List<TransitStop> stops) async {
    final prefs = await _getPrefsSafe();
    if (prefs == null) {
      return;
    }

    try {
      final raw = jsonEncode(stops.map((stop) => stop.toJson()).toList());
      await prefs.setString(_stopsCacheKey, raw);
      await prefs.setInt(
        _stopsCacheUpdatedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      _storageUnavailable = true;
    }
  }

  Future<SharedPreferences?> _getPrefsSafe() async {
    if (_storageUnavailable) {
      return null;
    }
    if (_prefs != null) {
      return _prefs;
    }
    try {
      _prefs = await SharedPreferences.getInstance();
      return _prefs;
    } catch (_) {
      _storageUnavailable = true;
      return null;
    }
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('API hatasi (${response.statusCode}): ${response.body}');
    }

    final bodyText = utf8.decode(response.bodyBytes);
    final decoded = jsonDecode(bodyText);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    if (decoded is List<dynamic>) {
      return <String, dynamic>{'data': decoded};
    }

    throw Exception('Beklenmeyen yanit tipi.');
  }

  List<dynamic> _extractList(Map<String, dynamic> payload) {
    final keys = ['data', 'result', 'list', 'items', 'buses'];
    for (final key in keys) {
      final value = payload[key];
      if (value is List<dynamic>) {
        return value;
      }
    }

    if (payload.values.every((element) => element is! List<dynamic>)) {
      return <dynamic>[];
    }

    return payload.values.firstWhere(
      (value) => value is List<dynamic>,
      orElse: () => <dynamic>[],
    ) as List<dynamic>;
  }

  static String _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  static double? _readDouble(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final parsed = _toDouble(map[key]);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value.toString().replaceAll(',', '.'));
  }
}
