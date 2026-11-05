import 'package:intl/intl.dart' show DateFormat;

// Pass `context.l10n.localeName` (or `AppLocalizations.localeName`). Month
// and weekday names come from intl's CLDR data, so every language gets its
// own order and forms.

/// Formats a date as `Jan 5` (English) in the local time zone.
String formatMonthDay(DateTime date, String localeName) =>
    DateFormat.MMMd(localeName).format(date.toLocal());

/// Formats a date as `Jan 5, 2026` (English) in the local time zone.
String formatMonthDayYear(DateTime date, String localeName) =>
    DateFormat.yMMMd(localeName).format(date.toLocal());

/// Formats a timestamp as `25 May, 13:30` in English, the Figma send status
/// format, and as the CLDR month-day plus 24-hour time elsewhere
/// (`5월 25일 13:30`, `5月25日 13:30`), in the local time zone.
String formatDayMonthTime(DateTime date, String localeName) {
  final local = date.toLocal();
  final format = localeName == 'en'
      ? DateFormat('d MMM, HH:mm', 'en') // l10n-ignore: date pattern
      : DateFormat.MMMd(localeName).add_Hm();
  return format.format(local);
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
    if (!value.isFinite) return null;
    final millisecondsValue = value > 100000000000 ? value : value * 1000;
    if (!millisecondsValue.isFinite) return null;
    final milliseconds = millisecondsValue.toInt();
    try {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    } on ArgumentError {
      return null;
    }
  }
  final text = value.toString().trim();
  final numeric = num.tryParse(text);
  if (numeric != null) return parseFlexibleDate(numeric);
  return DateTime.tryParse(text);
}
