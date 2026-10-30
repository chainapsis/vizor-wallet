import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/activity_scroll_anchor.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_skeleton_row.dart';

ActivityRowData row(int id) => ActivityRowData(
  stableId: 'row-$id',
  title: 'Received',
  leadingIconName: AppIcons.plane,
  leadingBackgroundColor: const Color(0xff103030),
  leadingIconColor: const Color(0xff50aaaa),
  subtitle: 'Shielded',
  amountText: '+1 ZEC',
  statusText: 'Completed',
  timestampText: 'Oct 23, 12:00',
);

void main() {
  testWidgets('initial skeleton has five rows with the loaded row geometry', (
    tester,
  ) async {
    const mobile = kAppFormFactor == AppFormFactor.mobile;
    Widget feed(bool loading) => MaterialApp(
      home: AppTheme(
        data: AppThemeData.dark,
        child: Center(
          child: SizedBox(
            width: mobile ? 390 : 420,
            height: 600,
            child: CustomScrollView(
              slivers: [
                ActivityFeedSliver(
                  isLoading: loading,
                  showHeader: !mobile,
                  cardWidth: mobile ? null : 396,
                  sections: loading
                      ? const []
                      : [
                          ActivityFeedSectionData(
                            title: 'This week',
                            rows: List.generate(5, row),
                          ),
                        ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(feed(true));
    expect(find.byType(ActivitySkeletonRow), findsNWidgets(5));
    final skeletonRects = tester.getRect(
      find.byType(ActivitySkeletonRow).first,
    );
    final skeletonTops = [
      for (var i = 0; i < 5; i++)
        tester.getTopLeft(find.byType(ActivitySkeletonRow).at(i)).dy,
    ];
    await tester.pumpWidget(feed(false));
    await tester.pumpAndSettle();
    expect(find.byType(ActivitySkeletonRow), findsNothing);
    final header = find
        .ancestor(
          of: find.text('This week'),
          matching: find.byType(DecoratedBox),
        )
        .first;
    expect(
      tester.getSize(header).width,
      tester.getSize(find.byType(ActivityFeedRowGroup).first).width + 32,
    );
    for (var i = 0; i < 5; i++) {
      final actual = tester.getRect(find.byType(ActivityFeedRowGroup).at(i));
      expect(actual.top, skeletonTops[i]);
      expect(actual.width, skeletonRects.width);
      expect(actual.height, skeletonRects.height);
    }
  });

  testWidgets('append adds three skeletons and keeps existing rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: CustomScrollView(
            slivers: [
              ActivityFeedSliver(
                sections: [
                  ActivityFeedSectionData(
                    title: 'This week',
                    rows: List.generate(3, row),
                  ),
                ],
                isLoadingMore: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(ActivitySkeletonRow), findsNWidgets(3));
    expect(find.byType(ActivityFeedRowGroup), findsNWidgets(3));
  });

  testWidgets('completed empty state has no skeleton', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: const CustomScrollView(
            slivers: [ActivityFeedSliver(sections: [])],
          ),
        ),
      ),
    );
    expect(find.text('No activity yet'), findsOneWidget);
    expect(find.byType(ActivitySkeletonRow), findsNothing);
  });

  testWidgets(
    'refresh insertion preserves the visible row and scroll position',
    (tester) async {
      final anchor = ActivityScrollAnchor();
      var rows = List.generate(40, row);
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return SizedBox(
                  height: 400,
                  child: CustomScrollView(
                    controller: anchor.controller,
                    slivers: [
                      ActivityFeedSliver(
                        scrollAnchor: anchor,
                        sections: [
                          ActivityFeedSectionData(
                            title: 'This week',
                            rows: rows,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      anchor.controller.jumpTo(550);
      await tester.pump();
      final before = tester.getTopLeft(find.byKey(anchor.keyFor('row-10'))).dy;
      final restore = anchor.capture();
      update(() {
        rows = [...List.generate(30, (i) => row(100 + i)), ...rows];
      });
      restore();
      await tester.pump();
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(anchor.keyFor('row-10'))).dy,
        closeTo(before, 0.1),
      );
      await tester.pumpWidget(const SizedBox());
      anchor.dispose();
    },
  );
}
