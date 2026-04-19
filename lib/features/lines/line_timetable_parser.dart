import 'package:flutter/material.dart';

class TimetableTimesList extends StatelessWidget {
  const TimetableTimesList({
    super.key,
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
            color:
                isNearest ? const Color(0xFFE8F5E9) : const Color(0xFFF6F8FC),
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

class TimetableData {
  const TimetableData({
    required this.fromStop,
    required this.toStop,
    required this.apiUpdatedAt,
    required this.weekdayTimes,
    required this.saturdayTimes,
    required this.sundayTimes,
  });

  final String fromStop;
  final String toStop;
  final DateTime? apiUpdatedAt;
  final List<String> weekdayTimes;
  final List<String> saturdayTimes;
  final List<String> sundayTimes;

  bool get hasAnyTimes =>
      weekdayTimes.isNotEmpty ||
      saturdayTimes.isNotEmpty ||
      sundayTimes.isNotEmpty;

  factory TimetableData.empty() {
    return const TimetableData(
      fromStop: '',
      toStop: '',
      apiUpdatedAt: null,
      weekdayTimes: <String>[],
      saturdayTimes: <String>[],
      sundayTimes: <String>[],
    );
  }
}

enum TimetableDayBucket { weekday, saturday, sunday, unknown }

class TimetableScheduleSection {
  const TimetableScheduleSection({
    required this.index,
    required this.node,
    this.keyHint = '',
  });

  final int index;
  final dynamic node;
  final String keyHint;
}

class TimetableDataParser {
  static final RegExp _timeExp = RegExp(r'\b(?:[01]?\d|2[0-3]):[0-5]\d\b');

  static TimetableData parse({
    required Map<String, dynamic> payload,
    required String fallbackFrom,
    required String fallbackTo,
  }) {
    final sections = _collectScheduleSections(payload);
    if (sections.isEmpty) {
      sections.add(TimetableScheduleSection(index: 0, node: payload));
    }

    final weekday = <String>{};
    final saturday = <String>{};
    final sunday = <String>{};
    final apiUpdatedAt = _extractApiUpdatedAt(payload);
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
          case TimetableDayBucket.weekday:
            weekday.add(time);
            break;
          case TimetableDayBucket.saturday:
            saturday.add(time);
            break;
          case TimetableDayBucket.sunday:
            sunday.add(time);
            break;
          case TimetableDayBucket.unknown:
            weekday.add(time);
            break;
        }
      }
    }

    if (weekday.isEmpty && sections.isNotEmpty) {
      weekday.addAll(_extractTimesFromNode(sections.first.node));
    }

    return TimetableData(
      fromStop: from.isEmpty ? fallbackFrom : from,
      toStop: to.isEmpty ? fallbackTo : to,
      apiUpdatedAt: apiUpdatedAt,
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

  static List<TimetableScheduleSection> _collectScheduleSections(
    Map<String, dynamic> payload,
  ) {
    final sections = <TimetableScheduleSection>[];
    var index = 0;

    void addFromList(List<dynamic> values, String keyHint) {
      for (final value in values) {
        if (value is Map<String, dynamic>) {
          sections.add(
            TimetableScheduleSection(
              index: index++,
              node: value,
              keyHint: '$keyHint ${_collectKeyHint(value)}',
            ),
          );
        } else if (value != null) {
          sections.add(
            TimetableScheduleSection(
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
          TimetableScheduleSection(
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

  static TimetableDayBucket _bucketFromSection(
      TimetableScheduleSection section) {
    final dayType = _findDayTypeValue(section.node);
    if (dayType == 0) {
      return TimetableDayBucket.weekday;
    }
    if (dayType == 6) {
      return TimetableDayBucket.saturday;
    }
    if (dayType == 7) {
      return TimetableDayBucket.sunday;
    }

    // Fallback when dayType is absent.
    final mod = section.index % 3;
    if (mod == 0) {
      return TimetableDayBucket.weekday;
    }
    if (mod == 1) {
      return TimetableDayBucket.saturday;
    }
    return TimetableDayBucket.sunday;
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

  static DateTime? _extractApiUpdatedAt(dynamic node) {
    final found = <DateTime>[];

    void walk(dynamic value, {String keyPath = ''}) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString();
          final nextPath = keyPath.isEmpty ? key : '$keyPath.$key';
          if (_looksLikeUpdateKey(nextPath)) {
            final parsed = _parseDateCandidate(entry.value);
            if (parsed != null) {
              found.add(parsed);
            }
          }
          walk(entry.value, keyPath: nextPath);
        }
        return;
      }

      if (value is List) {
        for (final item in value) {
          walk(item, keyPath: keyPath);
        }
      }
    }

    walk(node);
    if (found.isEmpty) {
      return null;
    }
    found.sort((a, b) => b.compareTo(a));
    return found.first;
  }

  static bool _looksLikeUpdateKey(String keyPath) {
    final k = keyPath.toLowerCase().replaceAll('_', '');
    return k.contains('update') ||
        k.contains('updated') ||
        k.contains('timestamp') ||
        k.contains('created') ||
        k.contains('modified') ||
        k.contains('guncel') ||
        k.contains('last');
  }

  static DateTime? _parseDateCandidate(dynamic raw) {
    if (raw == null) {
      return null;
    }

    if (raw is num) {
      final value = raw.toInt();
      if (value <= 0) {
        return null;
      }
      if (value > 9999999999) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true)
            .toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true)
          .toLocal();
    }

    final text = raw.toString().trim();
    if (text.isEmpty) {
      return null;
    }

    final parsedIso = DateTime.tryParse(text);
    if (parsedIso != null) {
      return parsedIso.toLocal();
    }

    final normalized = text.replaceAll('/', '.').replaceAll('-', '.');
    final fullDate = RegExp(
      r'^(\d{1,2})\.(\d{1,2})\.(\d{4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
    ).firstMatch(normalized);
    if (fullDate != null) {
      final day = int.tryParse(fullDate.group(1)!);
      final month = int.tryParse(fullDate.group(2)!);
      final year = int.tryParse(fullDate.group(3)!);
      final hour = int.tryParse(fullDate.group(4) ?? '0') ?? 0;
      final minute = int.tryParse(fullDate.group(5) ?? '0') ?? 0;
      final second = int.tryParse(fullDate.group(6) ?? '0') ?? 0;
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day, hour, minute, second);
      }
    }

    final clockOnly =
        RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(text);
    if (clockOnly != null) {
      final hour = int.tryParse(clockOnly.group(1)!);
      final minute = int.tryParse(clockOnly.group(2)!);
      final second = int.tryParse(clockOnly.group(3) ?? '0') ?? 0;
      if (hour != null && minute != null) {
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day, hour, minute, second);
      }
    }

    return null;
  }
}
