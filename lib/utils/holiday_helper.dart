import 'package:cloud_firestore/cloud_firestore.dart';

class HolidayHelper {
  HolidayHelper._();

  static const Map<String, String> standardOfficialHolidays = {
    '2026-01-01': 'New Year',
    '2026-01-14': 'Pongal',
    '2026-01-26': 'Republic Day',
    '2026-03-04': 'Holi',
    '2026-03-21': 'Eid-ul-Fitr',
    '2026-03-26': 'Ram Navami',
    '2026-04-03': 'Good Friday',
    '2026-04-05': 'Easter',
    '2026-04-14': 'Tamil New Year',
    '2026-05-01': 'May Day',
    '2026-05-27': 'Eid-ul-Zuha',
    '2026-06-26': 'Muharram',
    '2026-08-15': 'Independence Day',
    '2026-08-26': 'Milad-un-Nabi',
    '2026-09-04': 'Janmashtami',
    '2026-10-02': 'Gandhi Jayanti',
    '2026-10-20': 'Dussehra',
    '2026-11-08': 'Diwali',
    '2026-11-24': 'Guru Nanak Jayanti',
    '2026-12-25': 'Christmas',
  };

  static String formatDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Extracts all date keys ('YYYY-MM-DD') that represent company holidays or public office leaves.
  static Set<String> extractHolidayDateKeys(Map<String, dynamic>? data) {
    final result = <String>{...standardOfficialHolidays.keys};
    if (data == null) return result;

    final rawDates = data['holidayDates'];
    if (rawDates is List) {
      for (final d in rawDates) {
        if (d == null) continue;
        final str = d.toString().trim();
        if (str.isNotEmpty) result.add(str);
      }
    } else if (rawDates is String) {
      result.addAll(
        rawDates
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty),
      );
    }

    final rawEvents = data['holidayEvents'];
    if (rawEvents is List) {
      for (final ev in rawEvents) {
        if (ev is Map) {
          final dk = ev['dateKey']?.toString().trim();
          if (dk != null && dk.isNotEmpty) {
            result.add(dk);
            continue;
          }
          final rawDate = ev['date'];
          if (rawDate is Timestamp) {
            result.add(formatDateKey(rawDate.toDate()));
          } else if (rawDate != null) {
            final parsed = DateTime.tryParse(rawDate.toString().trim());
            if (parsed != null) {
              result.add(formatDateKey(parsed));
            }
          }
        }
      }
    }

    return result;
  }

  /// Extracts dateKey -> holidayName map from config and standard official holidays.
  static Map<String, String> extractHolidayNames(Map<String, dynamic>? data) {
    final names = Map<String, String>.from(standardOfficialHolidays);
    if (data == null) return names;

    final rawEvents = data['holidayEvents'];
    if (rawEvents is List) {
      for (final ev in rawEvents) {
        if (ev is Map) {
          final name = ev['title']?.toString().trim() ?? 'Office Leave';
          final dk = ev['dateKey']?.toString().trim();
          if (dk != null && dk.isNotEmpty) {
            names[dk] = name;
            continue;
          }
          final rawDate = ev['date'];
          if (rawDate is Timestamp) {
            names[formatDateKey(rawDate.toDate())] = name;
          } else if (rawDate != null) {
            final parsed = DateTime.tryParse(rawDate.toString().trim());
            if (parsed != null) {
              names[formatDateKey(parsed)] = name;
            }
          }
        }
      }
    }

    final rawDates = data['holidayDates'];
    if (rawDates is List) {
      for (final d in rawDates) {
        if (d == null) continue;
        final str = d.toString().trim();
        if (str.isNotEmpty) {
          names.putIfAbsent(str, () => 'Office Leave');
        }
      }
    }

    return names;
  }

  /// Determines whether a given date is an official company/public holiday.
  static bool isOfficeHoliday(
    DateTime date, {
    Map<String, dynamic>? geoConfigData,
    Set<String>? holidayDateKeys,
  }) {
    final key = formatDateKey(date);
    if (holidayDateKeys != null) {
      return holidayDateKeys.contains(key);
    }
    final keys = extractHolidayDateKeys(geoConfigData);
    return keys.contains(key);
  }

  /// Determines whether a given date is an office working day.
  /// Saturday is working, Sunday depends on [sundayWorking], and all holidays return false.
  static bool isWorkingDate(
    DateTime date, {
    Map<String, dynamic>? geoConfigData,
    Set<String>? holidayDateKeys,
    bool? sundayWorking,
  }) {
    if (isOfficeHoliday(
      date,
      geoConfigData: geoConfigData,
      holidayDateKeys: holidayDateKeys,
    )) {
      return false;
    }

    final isSundayWorking = sundayWorking ??
        (geoConfigData?['sundayWorking'] as bool? ?? false);

    if (date.weekday == DateTime.saturday) return true;
    if (date.weekday == DateTime.sunday) return isSundayWorking;
    return true;
  }
}
