import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/activity/activity_feed_sections.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';

ActivityEntry entry(int i, DateTime time) => ActivityEntry(
  timestamp: time,
  row: ActivityRowData(
    stableId: 'row-$i',
    title: 'Received',
    leadingIconName: 'plane',
    leadingBackgroundColor: const Color(0xff000000),
    leadingIconColor: const Color(0xffffffff),
    amountText: '+1 ZEC',
    statusText: '',
    timestampText: '',
  ),
);

void main() {
  test('equal-time prefix is stable across page appends', () {
    for (final count in [20, 40, 60, 100]) {
      final sections = buildActivityFeedSections(
        List.generate(count, (i) => entry(i, DateTime.utc(2026))),
        limit: 20,
      );
      expect(
        sections.expand((s) => s.rows).map((r) => r.stableId),
        List.generate(20, (i) => 'row-$i'),
        reason: '$count loaded rows',
      );
    }
  });

  test('page limit applies after timestamp ordering and date grouping', () {
    final sections = buildActivityFeedSections(
      List.generate(
        40,
        (i) => entry(i, DateTime.utc(2026, 1, 1).add(Duration(days: i))),
      ),
      limit: 20,
    );
    expect(
      sections.expand((s) => s.rows).map((r) => r.stableId),
      List.generate(20, (i) => 'row-${39 - i}'),
    );
  });
}
