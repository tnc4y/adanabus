import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/models/bus_vehicle.dart';
import '../../data/services/adana_api_service.dart';

class LineTimetablePage extends StatefulWidget {
  const LineTimetablePage({
    super.key,
    required this.routeCode,
    required this.routeName,
    required this.direction,
    required this.fromStopName,
    required this.toStopName,
  });

  final String routeCode;
  final String routeName;
  final String direction;
  final String fromStopName;
  final String toStopName;

  @override
  State<LineTimetablePage> createState() => _LineTimetablePageState();
}

class _LineTimetablePageState extends State<LineTimetablePage>
    with SingleTickerProviderStateMixin {
  final AdanaApiService _apiService = AdanaApiService();
  final ScrollController _weekdayController = ScrollController();
  final ScrollController _saturdayController = ScrollController();
  final ScrollController _sundayController = ScrollController();

  late final TabController _tabController;
  late final int _initialTabIndex;

  bool _isLoading = true;
  String? _error;
  String? _sourceBusId;
  _TimetableData _data = _TimetableData.empty();
  int _lastFocusedTabIndex = 0;

  void _logDebug(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[TIMETABLE] $message');
  }

  @override
  void initState() {
    super.initState();
    _initialTabIndex = _dayTabIndexForDate(DateTime.now());
    _lastFocusedTabIndex = _initialTabIndex;
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: _initialTabIndex,
    );
    _tabController.addListener(_handleTabChanged);
    _loadTimetable();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _weekdayController.dispose();
    _saturdayController.dispose();
    _sundayController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted || _tabController.indexIsChanging) {
      return;
    }
    if (_lastFocusedTabIndex == _tabController.index) {
      return;
    }
    _lastFocusedTabIndex = _tabController.index;
    _focusNearestTimeInActiveTab();
  }

  Future<void> _loadTimetable() async {
    _logDebug(
      'Saat yukleme basladi: route=${widget.routeCode}, direction=${widget.direction}',
    );
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final busIds = await _resolveCandidateBusIds();
      _logDebug('Aday BusId listesi (${busIds.length}): ${busIds.join(', ')}');
      if (busIds.isEmpty) {
        throw Exception('Bu hat icin arac ID bulunamadi.');
      }

      _TimetableData? resolved;
      String? usedBusId;

      for (final busId in busIds) {
        _logDebug('stopBusTimeBusId cagrisi: BusId=$busId');
        final dynamic raw = await _apiService.fetchStopBusTimeByBusId(busId);
        final payload = raw is Map<String, dynamic>
            ? raw
            : <String, dynamic>{'data': raw};
        _logDebug('Ham yanit tipi: ${payload.runtimeType} (BusId=$busId)');
        final parsed = _TimetableDataParser.parse(
          payload: payload,
          fallbackFrom: widget.fromStopName,
          fallbackTo: widget.toStopName,
        );
        _logDebug(
          'Parse sonucu BusId=$busId -> weekday=${parsed.weekdayTimes.length}, saturday=${parsed.saturdayTimes.length}, sunday=${parsed.sundayTimes.length}',
        );

        if (parsed.hasAnyTimes) {
          resolved = parsed;
          usedBusId = busId;
          _logDebug('Saat verisi bulundu, secilen BusId=$busId');
          break;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _data = resolved ?? _TimetableData(
          fromStop: widget.fromStopName,
          toStop: widget.toStopName,
          weekdayTimes: const <String>[],
          saturdayTimes: const <String>[],
          sundayTimes: const <String>[],
        );
        _sourceBusId = usedBusId;
      });

      _logDebug(
        'Yukleme tamamlandi: sourceBusId=${_sourceBusId ?? '-'}, from=${_data.fromStop}, to=${_data.toStop}',
      );

      _focusNearestTimeInActiveTab();
    } catch (error) {
      _logDebug('Saat yukleme hatasi: $error');
      if (!mounted) {
        return;
      }
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

  Future<List<String>> _resolveCandidateBusIds() async {
    final buses = await _apiService.fetchBuses();
    _logDebug('fetchBuses dondu: toplam arac=${buses.length}');
    final routeBuses = buses.where((bus) => bus.displayRouteCode == widget.routeCode).toList();
    _logDebug('Route ${widget.routeCode} icin bulunan arac=${routeBuses.length}');
    final dedupe = <String>{};
    final ordered = <String>[];

    void addFrom(Iterable<BusVehicle> source) {
      for (final bus in source) {
        final id = bus.id.trim();
        if (id.isEmpty || !dedupe.add(id)) {
          continue;
        }
        ordered.add(id);
      }
    }

    addFrom(routeBuses.where((bus) => bus.direction == widget.direction));
    addFrom(routeBuses.where((bus) => bus.direction != widget.direction));
    addFrom(buses);

    return ordered.take(12).toList(growable: false);
  }

  int _dayTabIndexForDate(DateTime date) {
    if (date.weekday == DateTime.saturday) {
      return 1;
    }
    if (date.weekday == DateTime.sunday) {
      return 2;
    }
    return 0;
  }

  int _nearestIndex(List<String> times) {
    if (times.isEmpty) {
      return 0;
    }

    final now = TimeOfDay.now();
    final nowMinutes = now.hour * 60 + now.minute;

    var nearest = 0;
    var nearestDistance = 24 * 60;

    for (var i = 0; i < times.length; i++) {
      final minutes = _TimetableDataParser.toMinutes(times[i]);
      if (minutes == null) {
        continue;
      }

      var distance = minutes - nowMinutes;
      if (distance < 0) {
        distance += 24 * 60;
      }

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = i;
      }
    }

    return nearest;
  }

  void _focusNearestTimeInActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final index = _tabController.index;
      final times = index == 0
          ? _data.weekdayTimes
          : index == 1
              ? _data.saturdayTimes
              : _data.sundayTimes;
      final nearest = _nearestIndex(times);
      final controller = index == 0
          ? _weekdayController
          : index == 1
              ? _saturdayController
              : _sundayController;

      if (!controller.hasClients) {
        return;
      }

      final offset = (nearest * 56.0) - 96.0;
      controller.jumpTo(offset < 0 ? 0.0 : offset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final directionText = widget.direction == '1' ? 'Donus' : 'Gidis';
    final tripFrom = _data.fromStop.isEmpty ? widget.fromStopName : _data.fromStop;
    final tripTo = _data.toStop.isEmpty ? widget.toStopName : _data.toStop;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cikis Saatleri'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadTimetable,
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          onTap: (_) => _focusNearestTimeInActiveTab(),
          tabs: const [
            Tab(text: 'Hafta ici'),
            Tab(text: 'Cumartesi'),
            Tab(text: 'Pazar'),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            color: const Color(0xFFF4F7FC),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.routeName} (${widget.routeCode})',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.route, size: 16, color: Color(0xFF164B9D)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$tripFrom -> $tripTo',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Yon: $directionText${_sourceBusId == null ? '' : ' • Arac: $_sourceBusId'}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF4C4C4C)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  children: [
                    _TimesList(
                      times: _data.weekdayTimes,
                      nearestIndex: _nearestIndex(_data.weekdayTimes),
                      controller: _weekdayController,
                    ),
                    _TimesList(
                      times: _data.saturdayTimes,
                      nearestIndex: _nearestIndex(_data.saturdayTimes),
                      controller: _saturdayController,
                    ),
                    _TimesList(
                      times: _data.sundayTimes,
                      nearestIndex: _nearestIndex(_data.sundayTimes),
                      controller: _sundayController,
                    ),
                  ],
                ),
                if (_isLoading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x66FFFFFF),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                if (_error != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1EE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(_error!),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TimesList extends StatelessWidget {
  const _TimesList({
    required this.times,
    required this.nearestIndex,
    required this.controller,
  });

  final List<String> times;
  final int nearestIndex;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    if (times.isEmpty) {
      return const Center(
        child: Text('Bu gun tipi icin saat verisi bulunamadi.'),
      );
    }

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      itemCount: times.length,
      itemBuilder: (context, index) {
        final isNearest = index == nearestIndex;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isNearest ? const Color(0xFFE8F5E9) : const Color(0xFFF6F8FC),
            borderRadius: BorderRadius.circular(10),
            border: isNearest
                ? Border.all(color: const Color(0xFF1B7F43), width: 1.2)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                Icons.schedule,
                size: 18,
                color: isNearest
                    ? const Color(0xFF1B7F43)
                    : const Color(0xFF164B9D),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  times[index],
                  style: TextStyle(
                    fontWeight: isNearest ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              if (isNearest)
                const Text(
                  'En yakin',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B7F43),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TimetableData {
  const _TimetableData({
    required this.fromStop,
    required this.toStop,
    required this.weekdayTimes,
    required this.saturdayTimes,
    required this.sundayTimes,
  });

  final String fromStop;
  final String toStop;
  final List<String> weekdayTimes;
  final List<String> saturdayTimes;
  final List<String> sundayTimes;

  bool get hasAnyTimes =>
      weekdayTimes.isNotEmpty || saturdayTimes.isNotEmpty || sundayTimes.isNotEmpty;

  factory _TimetableData.empty() {
    return const _TimetableData(
      fromStop: '',
      toStop: '',
      weekdayTimes: <String>[],
      saturdayTimes: <String>[],
      sundayTimes: <String>[],
    );
  }
}

enum _DayBucket { weekday, saturday, sunday, unknown }

class _ScheduleSection {
  const _ScheduleSection({
    required this.index,
    required this.node,
    this.keyHint = '',
  });

  final int index;
  final dynamic node;
  final String keyHint;
}

class _TimetableDataParser {
  static final RegExp _timeExp = RegExp(r'\b(?:[01]?\d|2[0-3]):[0-5]\d\b');

  static _TimetableData parse({
    required Map<String, dynamic> payload,
    required String fallbackFrom,
    required String fallbackTo,
  }) {
    final sections = _collectScheduleSections(payload);
    if (sections.isEmpty) {
      sections.add(_ScheduleSection(index: 0, node: payload));
    }

    final weekday = <String>{};
    final saturday = <String>{};
    final sunday = <String>{};
    String from = '';
    String to = '';

    for (final section in sections) {
      final bucket = _bucketFromSection(section);
      final flattened = _flattenToText(section.node);

      from = from.isNotEmpty ? from : (_extractFromByText(flattened) ?? from);
      to = to.isNotEmpty ? to : (_extractToByText(flattened) ?? to);

      final times = _extractTimesFromNode(section.node);
      for (final time in times) {
        switch (bucket) {
          case _DayBucket.weekday:
            weekday.add(time);
            break;
          case _DayBucket.saturday:
            saturday.add(time);
            break;
          case _DayBucket.sunday:
            sunday.add(time);
            break;
          case _DayBucket.unknown:
            weekday.add(time);
            break;
        }
      }
    }

    if (weekday.isEmpty && sections.isNotEmpty) {
      weekday.addAll(_extractTimesFromNode(sections.first.node));
    }

    return _TimetableData(
      fromStop: from.isEmpty ? fallbackFrom : from,
      toStop: to.isEmpty ? fallbackTo : to,
      weekdayTimes: _sortTimes(weekday),
      saturdayTimes: _sortTimes(saturday),
      sundayTimes: _sortTimes(sunday),
    );
  }

  static int? toMinutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) {
      return null;
    }
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) {
      return null;
    }
    return (h * 60) + m;
  }

  static List<_ScheduleSection> _collectScheduleSections(
    Map<String, dynamic> payload,
  ) {
    final sections = <_ScheduleSection>[];
    var index = 0;

    void addFromList(List<dynamic> values, String keyHint) {
      for (final value in values) {
        if (value is Map<String, dynamic>) {
          sections.add(
            _ScheduleSection(
              index: index++,
              node: value,
              keyHint: '$keyHint ${_collectKeyHint(value)}',
            ),
          );
        } else if (value != null) {
          sections.add(
            _ScheduleSection(
              index: index++,
              node: <String, dynamic>{'value': value},
              keyHint: keyHint,
            ),
          );
        }
      }
    }

    for (final entry in payload.entries) {
      final key = entry.key.toString().toLowerCase();
      final value = entry.value;

      if (value is List<dynamic>) {
        addFromList(value, key);
        continue;
      }

      if (value is Map<String, dynamic> && _looksLikeScheduleNode(key, value)) {
        sections.add(
          _ScheduleSection(
            index: index++,
            node: value,
            keyHint: '$key ${_collectKeyHint(value)}',
          ),
        );
      }
    }

    return sections;
  }

  static bool _looksLikeScheduleNode(String key, Map<String, dynamic> value) {
    final flattened = _flattenToText(value).toLowerCase();
    return key.contains('saat') ||
        key.contains('time') ||
        key.contains('hour') ||
        key.contains('schedule') ||
        flattened.contains('haftaici') ||
        flattened.contains('cumartesi') ||
        flattened.contains('pazar') ||
        _timeExp.hasMatch(flattened);
  }

  static String _collectKeyHint(Map<String, dynamic> node) {
    return node.keys.map((e) => e.toString().toLowerCase()).join(' ');
  }

  static _DayBucket _bucketFromSection(_ScheduleSection section) {
    final dayType = _findDayTypeValue(section.node);
    if (dayType == 0) {
      return _DayBucket.weekday;
    }
    if (dayType == 6) {
      return _DayBucket.saturday;
    }
    if (dayType == 7) {
      return _DayBucket.sunday;
    }

    // Fallback when dayType is absent.
    final mod = section.index % 3;
    if (mod == 0) {
      return _DayBucket.weekday;
    }
    if (mod == 1) {
      return _DayBucket.saturday;
    }
    return _DayBucket.sunday;
  }

  static int? _findDayTypeValue(dynamic node) {
    if (node is Map) {
      for (final entry in node.entries) {
        final key = entry.key.toString().toLowerCase();
        final normalizedKey = key.replaceAll('_', '');
        if (normalizedKey == 'daytype' || normalizedKey == 'day') {
          final parsed = int.tryParse(entry.value.toString().trim());
          if (parsed != null) {
            return parsed;
          }
        }
      }

      for (final value in node.values) {
        final nested = _findDayTypeValue(value);
        if (nested != null) {
          return nested;
        }
      }
      return null;
    }

    if (node is List) {
      for (final item in node) {
        final nested = _findDayTypeValue(item);
        if (nested != null) {
          return nested;
        }
      }
    }

    return null;
  }

  static String? _extractFromByText(String text) {
    final patterns = [
      RegExp(
        r'(?:from|kalkis|baslangic|ilk\s*durak|nereden)[:\s-]*([^|\n\r]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'([^|\n\r]+?)\s*(?:->|→|to)\s*[^|\n\r]+',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) {
        continue;
      }
      final value = match.group(1)?.trim() ?? '';
      if (value.isNotEmpty && !_timeExp.hasMatch(value)) {
        return value;
      }
    }
    return null;
  }

  static String? _extractToByText(String text) {
    final patterns = [
      RegExp(
        r'(?:to|varis|bitis|son\s*durak|nereye)[:\s-]*([^|\n\r]+)',
        caseSensitive: false,
      ),
      RegExp(
        r'[^|\n\r]+?\s*(?:->|→|to)\s*([^|\n\r]+)',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      if (match == null) {
        continue;
      }
      final value = match.group(1)?.trim() ?? '';
      if (value.isNotEmpty && !_timeExp.hasMatch(value)) {
        return value;
      }
    }
    return null;
  }

  static List<String> _extractTimesFromNode(dynamic node) {
    final text = _flattenToText(node);
    final times = <String>{};
    for (final match in _timeExp.allMatches(text)) {
      final value = match.group(0);
      if (value != null) {
        times.add(value);
      }
    }
    return _sortTimes(times);
  }

  static String _flattenToText(dynamic node) {
    if (node == null) {
      return '';
    }
    if (node is Map) {
      return node.entries
          .map((entry) => '${entry.key}:${_flattenToText(entry.value)}')
          .join(' | ');
    }
    if (node is List) {
      return node.map(_flattenToText).join(' | ');
    }
    return node.toString();
  }

  static List<String> _sortTimes(Iterable<String> raw) {
    final list = raw.toSet().toList(growable: false);
    list.sort((a, b) {
      final am = toMinutes(a) ?? 0;
      final bm = toMinutes(b) ?? 0;
      return am.compareTo(bm);
    });
    return list;
  }
}
