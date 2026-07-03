import 'package:intl/intl.dart';

/// Clamps [locale] to one whose date symbols are actually loaded.
///
/// Inside the app the `flutter_localizations` delegates initialize date
/// symbols for every supported locale. Pure Dart unit tests never run those
/// delegates, so an explicit locale would throw `LocaleDataException`;
/// falling back to null keeps intl's built-in default (English) working.
String? intlSafeLocale(String? locale) {
  if (locale == null) return null;
  try {
    return DateFormat.localeExists(locale) ? locale : null;
  } catch (_) {
    return null;
  }
}

/// Formats a date as `Jan 5` in the local time zone. Pass the active
/// `l10n.localeName` for localized month names; null keeps English.
String formatMonthDay(DateTime date, {String? locale}) {
  return DateFormat.MMMd(intlSafeLocale(locale)).format(date.toLocal());
}

/// Formats a date as `Jan 5, 2026` in the local time zone.
String formatMonthDayYear(DateTime date, {String? locale}) {
  return DateFormat.yMMMd(intlSafeLocale(locale)).format(date.toLocal());
}

/// Formats a timestamp as `25 May, 13:30` (Figma send status format) in the
/// local time zone. Non-English locales use their own day/month order
/// (e.g. Korean `7월 3일, 12:18`).
String formatDayMonthTime(DateTime date, {String? locale}) {
  final safe = intlSafeLocale(locale);
  final local = date.toLocal();
  if (safe == null || safe.startsWith('en')) {
    return DateFormat('d MMM, HH:mm', safe).format(local);
  }
  final day = DateFormat.MMMd(safe).format(local);
  final time = DateFormat('HH:mm', safe).format(local);
  return '$day, $time';
}

/// Parses a flexible date value into a local-zone [DateTime].
///
/// Accepts a [DateTime] (returned as-is), a numeric epoch (values above
/// 100000000000 are treated as milliseconds, smaller values as seconds), or a
/// string holding either of those forms or an ISO-8601 timestamp. Returns
/// `null` when nothing parseable is found.
DateTime? parseFlexibleDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is num) {
    final milliseconds = value > 100000000000
        ? value.toInt()
        : (value * 1000).toInt();
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
  final text = value.toString().trim();
  final numeric = num.tryParse(text);
  if (numeric != null) return parseFlexibleDate(numeric);
  return DateTime.tryParse(text);
}
