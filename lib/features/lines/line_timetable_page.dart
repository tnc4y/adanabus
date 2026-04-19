import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme_utils.dart';
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

class _LineTimetablePageState extends State<LineTimetablePage> {
  final AdanaApiService _apiService = AdanaApiService();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _weekdaySectionKey = GlobalKey();
  final GlobalKey _saturdaySectionKey = GlobalKey();
  final GlobalKey _sundaySectionKey = GlobalKey();

  bool _isLoading = true;
  String? _error;
  TimetableData _data = TimetableData.empty();

  void _logDebug(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint('[TIMETABLE] $message');
  }

  @override
  void initState() {
    super.initState();
    _loadTimetable();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      for (final busId in busIds) {
        _logDebug('stopBusTimeBusId cagrisi: BusId=$busId');
        final dynamic raw = await _apiService.fetchStopBusTimeByBusId(busId);
        final payload =
            raw is Map<String, dynamic> ? raw : <String, dynamic>{'data': raw};
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
          _logDebug('Saat verisi bulundu, secilen BusId=$busId');
          break;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _data = resolved ??
            TimetableData(
              fromStop: widget.fromStopName,
              toStop: widget.toStopName,
              apiUpdatedAt: null,
              weekdayTimes: const <String>[],
              saturdayTimes: const <String>[],
              sundayTimes: const <String>[],
            );
      });

      _logDebug(
          'Yukleme tamamlandi: from=${_data.fromStop}, to=${_data.toStop}');

      _scrollToNearestOccurrence();
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
    final routeBuses =
        buses.where((bus) => bus.displayRouteCode == widget.routeCode).toList();
    _logDebug(
        'Route ${widget.routeCode} icin bulunan arac=${routeBuses.length}');
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

  TimetableDayBucket _bucketForDate(DateTime date) {
    if (date.weekday == DateTime.saturday) {
      return TimetableDayBucket.saturday;
    }
    if (date.weekday == DateTime.sunday) {
      return TimetableDayBucket.sunday;
    }
    return TimetableDayBucket.weekday;
  }

  GlobalKey _sectionKeyForBucket(TimetableDayBucket bucket) {
    switch (bucket) {
      case TimetableDayBucket.weekday:
        return _weekdaySectionKey;
      case TimetableDayBucket.saturday:
        return _saturdaySectionKey;
      case TimetableDayBucket.sunday:
        return _sundaySectionKey;
      case TimetableDayBucket.unknown:
        return _weekdaySectionKey;
    }
  }

  _TimetableOccurrence? _findNearestOccurrence() {
    if (!_data.hasAnyTimes) {
      return null;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _TimetableOccurrence? best;

    for (var dayOffset = 0; dayOffset < 7; dayOffset++) {
      final date = today.add(Duration(days: dayOffset));
      final bucket = _bucketForDate(date);
      final times = _timesForBucket(bucket);

      for (final time in times) {
        final minutes = TimetableDataParser.toMinutes(time);
        if (minutes == null) {
          continue;
        }

        final occurrence = DateTime(
          date.year,
          date.month,
          date.day,
          minutes ~/ 60,
          minutes % 60,
        );
        if (occurrence.isBefore(now)) {
          continue;
        }

        if (best == null || occurrence.isBefore(best.scheduledAt)) {
          best = _TimetableOccurrence(
            bucket: bucket,
            time: time,
            scheduledAt: occurrence,
          );
        }
      }
    }

    return best;
  }

  List<String> _timesForBucket(TimetableDayBucket bucket) {
    switch (bucket) {
      case TimetableDayBucket.weekday:
        return _data.weekdayTimes;
      case TimetableDayBucket.saturday:
        return _data.saturdayTimes;
      case TimetableDayBucket.sunday:
        return _data.sundayTimes;
      case TimetableDayBucket.unknown:
        return const <String>[];
    }
  }

  void _scrollToNearestOccurrence() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final nearest = _findNearestOccurrence();
      if (nearest == null) {
        return;
      }

      final key = _sectionKeyForBucket(nearest.bucket);
      final context = key.currentContext;
      if (context == null) {
        return;
      }

      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tripFrom =
        _data.fromStop.isEmpty ? widget.fromStopName : _data.fromStop;
    final nearest = _findNearestOccurrence();
    final todayBucket = _bucketForDate(DateTime.now());

    return Scaffold(
      backgroundColor: AppThemeUtils.getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: AppThemeUtils.getBackgroundColor(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cikis Saatleri',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            Text(
              '${widget.routeName} • ${widget.routeCode}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppThemeUtils.getSecondaryTextColor(context),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadTimetable,
            icon: _isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppThemeUtils.getSecondaryTextColor(context),
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Yenile',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                if (_isLoading && !_data.hasAnyTimes)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                            color:
                                AppThemeUtils.getAccentColor(context, 'green')),
                        const SizedBox(height: 14),
                        Text(
                          'Saatler yukleniyor...',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppThemeUtils.getSecondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (!_data.hasAnyTimes)
                  _TimetableEmptyState(
                    title: _error == null
                        ? 'Saat verisi bulunamadi'
                        : 'Saatler alinmadi',
                    message: _error == null
                        ? 'Bu hat icin hafta ici, cumartesi ve pazar saatleri hazir degil.'
                        : _error!,
                    onRetry: _isLoading ? null : _loadTimetable,
                  )
                else
                  ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    children: [
                      _TimetableHeaderCard(
                        routeName: widget.routeName,
                        routeCode: widget.routeCode,
                        tripFrom: tripFrom,
                        apiUpdatedAt: _data.apiUpdatedAt,
                        nearest: nearest,
                      ),
                      const SizedBox(height: 12),
                      _TimetableThreeColumnTable(
                        weekdayTimes: _data.weekdayTimes,
                        saturdayTimes: _data.saturdayTimes,
                        sundayTimes: _data.sundayTimes,
                        nearest: nearest,
                        todayBucket: todayBucket,
                      ),
                    ],
                  ),
                if (_isLoading && _data.hasAnyTimes)
                  Positioned.fill(
                    child: ColoredBox(
                      color: AppThemeUtils.getOverlayColor(context, 0.24),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                if (_error != null && _data.hasAnyTimes)
                  Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppThemeUtils.getDisabledColor(context),
                        borderRadius: BorderRadius.circular(12),
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

class _TimetableOccurrence {
  const _TimetableOccurrence({
    required this.bucket,
    required this.time,
    required this.scheduledAt,
  });

  final TimetableDayBucket bucket;
  final String time;
  final DateTime scheduledAt;
}

class _TimetableHeaderCard extends StatelessWidget {
  const _TimetableHeaderCard({
    required this.routeName,
    required this.routeCode,
    required this.tripFrom,
    required this.apiUpdatedAt,
    required this.nearest,
  });

  final String routeName;
  final String routeCode;
  final String tripFrom;
  final DateTime? apiUpdatedAt;
  final _TimetableOccurrence? nearest;

  @override
  Widget build(BuildContext context) {
    final blue = AppThemeUtils.getAccentColor(context, 'blue');
    final green = AppThemeUtils.getAccentColor(context, 'green');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: isDark
              ? [
                  const Color(0xFF101826),
                  const Color(0xFF0E1724),
                ]
              : [
                  const Color(0xFFF7FAFF),
                  const Color(0xFFEFF5FF),
                ],
        ),
        border: Border.all(color: AppThemeUtils.getBorderColor(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: blue.withValues(alpha: isDark ? 0.18 : 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.schedule_rounded, color: blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$routeName ($routeCode)',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cikis duragi: $tripFrom',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppThemeUtils.getSecondaryTextColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (apiUpdatedAt != null)
              Text(
                'API son guncelleme: ${_formatClock(apiUpdatedAt!)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppThemeUtils.getSecondaryTextColor(context),
                ),
              ),
            const SizedBox(height: 12),
            if (nearest != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: green.withValues(alpha: isDark ? 0.14 : 0.09),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: green.withValues(alpha: isDark ? 0.22 : 0.16)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: green.withValues(alpha: isDark ? 0.24 : 0.14),
                        shape: BoxShape.circle,
                      ),
                      child:
                          Icon(Icons.near_me_rounded, size: 18, color: green),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'En yakin sefer',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color:
                                  AppThemeUtils.getSecondaryTextColor(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatNearestOccurrenceLabel(
                              nearest!.scheduledAt,
                              nearest!.time,
                            ),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppThemeUtils.getTextColor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatClock(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatNearestOccurrenceLabel(DateTime date, String time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;

    if (diff == 0) {
      return 'Bugun • $time';
    }
    if (diff == 1) {
      return 'Yarin • $time';
    }
    switch (date.weekday) {
      case DateTime.monday:
        return 'Pazartesi • $time';
      case DateTime.tuesday:
        return 'Sali • $time';
      case DateTime.wednesday:
        return 'Carsamba • $time';
      case DateTime.thursday:
        return 'Persembe • $time';
      case DateTime.friday:
        return 'Cuma • $time';
      case DateTime.saturday:
        return 'Cumartesi • $time';
      case DateTime.sunday:
        return 'Pazar • $time';
      default:
        return 'Yakin • $time';
    }
  }
}

class _TimetableThreeColumnTable extends StatelessWidget {
  const _TimetableThreeColumnTable({
    required this.weekdayTimes,
    required this.saturdayTimes,
    required this.sundayTimes,
    required this.nearest,
    required this.todayBucket,
  });

  final List<String> weekdayTimes;
  final List<String> saturdayTimes;
  final List<String> sundayTimes;
  final _TimetableOccurrence? nearest;
  final TimetableDayBucket todayBucket;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blue = AppThemeUtils.getAccentColor(context, 'blue');
    final orange = AppThemeUtils.getAccentColor(context, 'orange');
    final green = AppThemeUtils.getAccentColor(context, 'green');

    final rowCount = [
      weekdayTimes.length,
      saturdayTimes.length,
      sundayTimes.length,
    ].reduce((a, b) => a > b ? a : b);

    return Container(
      decoration: BoxDecoration(
        color: AppThemeUtils.getCardColor(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppThemeUtils.getBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Text(
                  'Sefer saatleri',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppThemeUtils.getTextColor(context),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (rowCount == 0)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Tablo icin saat verisi bulunamadi.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppThemeUtils.getSecondaryTextColor(context),
                ),
              ),
            )
          else
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(1),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1),
                },
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: AppThemeUtils.getBorderColor(context),
                    width: 1,
                  ),
                  verticalInside: BorderSide(
                    color: AppThemeUtils.getBorderColor(context),
                    width: 1,
                  ),
                ),
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: AppThemeUtils.getSubtleBackgroundColor(context),
                    ),
                    children: [
                      _TableHeaderCell(
                        label: 'Hafta ici',
                        accent: blue,
                        isToday: todayBucket == TimetableDayBucket.weekday,
                      ),
                      _TableHeaderCell(
                        label: 'Cumartesi',
                        accent: orange,
                        isToday: todayBucket == TimetableDayBucket.saturday,
                      ),
                      _TableHeaderCell(
                        label: 'Pazar',
                        accent: green,
                        isToday: todayBucket == TimetableDayBucket.sunday,
                      ),
                    ],
                  ),
                  for (var i = 0; i < rowCount; i++)
                    TableRow(
                      decoration: BoxDecoration(
                        color: i.isEven
                            ? Colors.transparent
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.02)
                                : Colors.black.withValues(alpha: 0.02)),
                      ),
                      children: [
                        _TableTimeCell(
                          value:
                              i < weekdayTimes.length ? weekdayTimes[i] : null,
                          accent: blue,
                          isNearest: i < weekdayTimes.length &&
                              nearest?.bucket == TimetableDayBucket.weekday &&
                              nearest?.time == weekdayTimes[i],
                        ),
                        _TableTimeCell(
                          value: i < saturdayTimes.length
                              ? saturdayTimes[i]
                              : null,
                          accent: orange,
                          isNearest: i < saturdayTimes.length &&
                              nearest?.bucket == TimetableDayBucket.saturday &&
                              nearest?.time == saturdayTimes[i],
                        ),
                        _TableTimeCell(
                          value: i < sundayTimes.length ? sundayTimes[i] : null,
                          accent: green,
                          isNearest: i < sundayTimes.length &&
                              nearest?.bucket == TimetableDayBucket.sunday &&
                              nearest?.time == sundayTimes[i],
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell({
    required this.label,
    required this.accent,
    required this.isToday,
  });

  final String label;
  final Color accent;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppThemeUtils.getTextColor(context),
              ),
            ),
          ),
          if (isToday)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Bug',
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TableTimeCell extends StatelessWidget {
  const _TableTimeCell({
    required this.value,
    required this.accent,
    required this.isNearest,
  });

  final String? value;
  final Color accent;
  final bool isNearest;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        child: Text(
          '-',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppThemeUtils.getSecondaryTextColor(context),
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isNearest
          ? accent.withValues(alpha: isDark ? 0.16 : 0.10)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Text(
        value!,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isNearest ? FontWeight.w800 : FontWeight.w700,
          color: isNearest ? accent : AppThemeUtils.getTextColor(context),
        ),
      ),
    );
  }
}

class _TimetableEmptyState extends StatelessWidget {
  const _TimetableEmptyState({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final blue = AppThemeUtils.getAccentColor(context, 'blue');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppThemeUtils.getCardColor(context),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppThemeUtils.getBorderColor(context)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.schedule_rounded, color: blue, size: 28),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppThemeUtils.getTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: AppThemeUtils.getSecondaryTextColor(context),
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => onRetry!.call(),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Yeniden dene'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
