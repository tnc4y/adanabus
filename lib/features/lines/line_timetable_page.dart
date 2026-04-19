import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/models/bus_vehicle.dart';
import '../../data/services/adana_api_service.dart';
import 'line_timetable_parser.dart';

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
  TimetableData _data = TimetableData.empty();
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

      TimetableData? resolved;
      String? usedBusId;

      for (final busId in busIds) {
        _logDebug('stopBusTimeBusId cagrisi: BusId=$busId');
        final dynamic raw = await _apiService.fetchStopBusTimeByBusId(busId);
        final payload = raw is Map<String, dynamic>
            ? raw
            : <String, dynamic>{'data': raw};
        _logDebug('Ham yanit tipi: ${payload.runtimeType} (BusId=$busId)');
        final parsed = TimetableDataParser.parse(
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
        _data = resolved ?? TimetableData(
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
      final minutes = TimetableDataParser.toMinutes(times[i]);
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
                    TimetableTimesList(
                      times: _data.weekdayTimes,
                      nearestIndex: _nearestIndex(_data.weekdayTimes),
                      controller: _weekdayController,
                    ),
                    TimetableTimesList(
                      times: _data.saturdayTimes,
                      nearestIndex: _nearestIndex(_data.saturdayTimes),
                      controller: _saturdayController,
                    ),
                    TimetableTimesList(
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
