/// Date-grouped section building shared by the desktop activity screen
/// and the mobile activity tab: rows are sorted newest-first and grouped
/// under "This week" / month-year / "Earlier" titles.
library;

import '../../rust/api/sync.dart' as rust_sync;
import 'models/activity_row_data.dart';
import 'widgets/activity_feed.dart';

/// One activity row paired with the timestamp used for sorting and
/// section grouping.
class ActivityEntry {
  const ActivityEntry({required this.timestamp, required this.row});

  final DateTime? timestamp;
  final ActivityRowData row;
}

/// Newest first; entries without a timestamp sort last.
int compareActivityEntries(ActivityEntry a, ActivityEntry b) {
  final aTime = a.timestamp;
  final bTime = b.timestamp;
  if (aTime == null && bTime == null) return 0;
  if (aTime == null) return 1;
  if (bTime == null) return -1;
  return bTime.compareTo(aTime);
}

/// The timestamp an on-chain transaction sorts by: block time when
/// mined, creation time while pending, null when neither is known.
/// An unmined, unexpired tx with no recorded time is treated as
/// happening now — externally received mempool txs carry no block or
/// creation time and must surface at the top, not sink to "Earlier".
DateTime? transactionActivityTimestamp(rust_sync.TransactionInfo tx) {
  final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
  if (seconds > BigInt.zero) {
    return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
  }
  if (tx.minedHeight == BigInt.zero && !tx.expiredUnmined) {
    return DateTime.now();
  }
  return null;
}

/// Sorts [entries] newest-first and groups consecutive entries that
/// share a section title.
List<ActivityFeedSectionData> buildActivityFeedSections(
  List<ActivityEntry> entries,
) {
  final sorted = [...entries]..sort(compareActivityEntries);
  final sections = <ActivityFeedSectionData>[];
  List<ActivityRowData>? currentRows;
  String? currentTitle;

  for (final entry in sorted) {
    final title = _activitySectionTitle(entry.timestamp);
    if (title != currentTitle) {
      currentTitle = title;
      currentRows = <ActivityRowData>[];
      sections.add(ActivityFeedSectionData(title: title, rows: currentRows));
    }
    currentRows!.add(entry.row);
  }

  return sections;
}

String _activitySectionTitle(DateTime? timestamp) {
  if (timestamp == null) return 'Earlier';

  final local = timestamp.toLocal();
  final now = DateTime.now();
  final weekStart = _startOfWeek(now);
  final nextWeekStart = weekStart.add(const Duration(days: 7));
  if (!local.isBefore(weekStart) && local.isBefore(nextWeekStart)) {
    return 'This week';
  }

  return '${_monthName(local.month)} ${local.year}';
}

DateTime _startOfWeek(DateTime date) {
  final localDate = DateTime(date.year, date.month, date.day);
  return localDate.subtract(Duration(days: date.weekday - DateTime.monday));
}

String _monthName(int month) {
  const months = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return months[month];
}
