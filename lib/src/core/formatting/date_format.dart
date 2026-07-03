const _monthAbbreviations = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Abbreviated English month name for a 1-indexed [month] (1 = Jan, 12 = Dec).
String monthAbbreviation(int month) => _monthAbbreviations[month - 1];

/// Formats a date as `Jan 5` in the local time zone.
String formatMonthDay(DateTime date) {
  final local = date.toLocal();
  return '${monthAbbreviation(local.month)} ${local.day}';
}

/// Formats a date as `Jan 5, 2026` in the local time zone.
String formatMonthDayYear(DateTime date) {
  final local = date.toLocal();
  return '${monthAbbreviation(local.month)} ${local.day}, ${local.year}';
}

/// Formats a timestamp as `25 May, 13:30` (Figma send status format) in the
/// local time zone.
String formatDayMonthTime(DateTime date) {
  final local = date.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${monthAbbreviation(local.month)}, $hh:$mm';
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
