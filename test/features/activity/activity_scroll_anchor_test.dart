import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/activity_scroll_anchor.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';

ActivityRowData _row(int id, {List<ActivityRowData> children = const []}) =>
    ActivityRowData(
      stableId: 'row-$id',
      title: 'Received',
      leadingIconName: AppIcons.plane,
      leadingBackgroundColor: const Color(0xff103030),
      leadingIconColor: const Color(0xff50aaaa),
      subtitle: 'Shielded',
      amountText: '+1 ZEC',
      statusText: 'Completed',
      timestampText: 'Oct 23, 12:00',
      childRows: children,
    );

void main() {
  testWidgets('bottom loading and page append never correct the viewport', (
    tester,
  ) async {
    final feed = await _mount(tester);
    final before = feed.anchor.controller.offset;
    final rowBefore = tester.getTopLeft(
      find.byKey(feed.anchor.keyFor('row-10')),
    );

    feed.change(() => feed.loading = true);
    await tester.pump();
    expect(feed.controller.tracked.corrections, isEmpty);
    expect(feed.controller.jumps, isEmpty);

    // A background refresh can remove the footer without appending a page.
    feed.change(() => feed.loading = false);
    await tester.pump();
    feed.change(() => feed.loading = true);
    await tester.pump();

    feed.change(() {
      feed.rows.addAll(List.generate(20, (i) => _row(100 + i)));
      feed.loading = false;
    });
    await tester.pump();
    expect(feed.controller.offset, before);
    expect(
      tester.getTopLeft(find.byKey(feed.anchor.keyFor('row-10'))),
      rowBefore,
    );
    expect(feed.controller.tracked.corrections, isEmpty);
    expect(feed.controller.jumps, isEmpty);
  });

  testWidgets('bottom append leaves an ongoing drag in control', (
    tester,
  ) async {
    final feed = await _mount(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    feed.controller.clearRecorded();
    final before = feed.controller.offset;
    feed.change(
      () => feed.rows.addAll(List.generate(20, (i) => _row(100 + i))),
    );
    await tester.pump();
    expect(feed.controller.offset, before);
    expect(feed.controller.tracked.corrections, isEmpty);
    expect(feed.controller.jumps, isEmpty);
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(feed.controller.offset, greaterThan(before));
    await gesture.up();
  });

  for (final physics in [
    const BouncingScrollPhysics(),
    const ClampingScrollPhysics(),
  ]) {
    testWidgets('bottom append preserves a fling with $physics', (
      tester,
    ) async {
      final feed = await _mount(tester, physics: physics);
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -120),
        1000,
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(feed.controller.position.isScrollingNotifier.value, isTrue);
      feed.controller.clearRecorded();
      final before = feed.controller.offset;
      feed.change(() => feed.loading = true);
      await tester.pump();
      feed.change(() {
        feed.rows.addAll(List.generate(20, (i) => _row(100 + i)));
        feed.loading = false;
      });
      await tester.pump();
      expect(feed.controller.tracked.corrections, isEmpty);
      expect(feed.controller.jumps, isEmpty);
      await tester.pump(const Duration(milliseconds: 16));
      expect(feed.controller.offset, greaterThan(before));
      expect(feed.controller.position.isScrollingNotifier.value, isTrue);
    });
  }

  for (final change in ['insert', 'remove', 'reorder', 'height']) {
    testWidgets('changes above the viewport preserve its row ($change)', (
      tester,
    ) async {
      final feed = await _mount(tester);
      final before = tester.getTopLeft(
        find.byKey(feed.anchor.keyFor('row-10')),
      );
      feed.change(() {
        switch (change) {
          case 'insert':
            feed.rows.insertAll(0, List.generate(30, (i) => _row(100 + i)));
          case 'remove':
            feed.rows.removeRange(0, 3);
          case 'reorder':
            feed.rows.insert(0, feed.rows.removeLast());
          case 'height':
            feed.rows[0] = _row(0, children: [_row(200)]);
        }
      });
      await tester.pump();
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(feed.anchor.keyFor('row-10'))).dy,
        closeTo(before.dy, 0.1),
      );
      expect(feed.controller.tracked.corrections, isNotEmpty);
    });
  }

  testWidgets('an append that also inserts above still preserves the row', (
    tester,
  ) async {
    final feed = await _mount(tester);
    final before = tester
        .getTopLeft(find.byKey(feed.anchor.keyFor('row-10')))
        .dy;
    feed.change(() {
      feed.rows.insertAll(0, [_row(100), _row(101)]);
      feed.rows.addAll(List.generate(20, (i) => _row(102 + i)));
    });
    await tester.pump();
    await tester.pump();
    expect(
      tester.getTopLeft(find.byKey(feed.anchor.keyFor('row-10'))).dy,
      closeTo(before, 0.1),
    );
  });
}

Future<_FeedState> _mount(
  WidgetTester tester, {
  ScrollPhysics physics = const ClampingScrollPhysics(),
}) async {
  final controller = _RecordingScrollController();
  final anchor = ActivityScrollAnchor(controller: controller);
  final key = GlobalKey<_FeedState>();
  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Center(
          child: _Feed(key: key, anchor: anchor, physics: physics),
        ),
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    anchor.dispose();
  });
  controller.jumpTo(550);
  await tester.pump();
  controller.clearRecorded();
  return key.currentState!;
}

class _Feed extends StatefulWidget {
  const _Feed({required this.anchor, required this.physics, super.key});
  final ActivityScrollAnchor anchor;
  final ScrollPhysics physics;

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> {
  final rows = List.generate(100, _row);
  bool loading = false;
  ActivityScrollAnchor get anchor => widget.anchor;
  _RecordingScrollController get controller =>
      anchor.controller as _RecordingScrollController;

  void change(VoidCallback update) {
    final restore = anchor.capture();
    setState(update);
    restore();
  }

  @override
  Widget build(BuildContext context) {
    const mobile = kAppFormFactor == AppFormFactor.mobile;
    return SizedBox(
      width: mobile ? 390 : 420,
      height: 400,
      child: CustomScrollView(
        controller: anchor.controller,
        physics: widget.physics,
        slivers: [
          ActivityFeedSliver(
            scrollAnchor: anchor,
            showHeader: !mobile,
            cardWidth: mobile ? null : 396,
            isLoadingMore: loading,
            sections: [ActivityFeedSectionData(title: 'This week', rows: rows)],
          ),
        ],
      ),
    );
  }
}

class _RecordingScrollController extends ScrollController {
  final jumps = <double>[];
  _RecordingScrollPosition get tracked => position as _RecordingScrollPosition;

  void clearRecorded() {
    jumps.clear();
    tracked.corrections.clear();
  }

  @override
  void jumpTo(double value) {
    jumps.add(value);
    super.jumpTo(value);
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _RecordingScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _RecordingScrollPosition extends ScrollPositionWithSingleContext {
  _RecordingScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
  });
  final corrections = <double>[];

  @override
  void correctBy(double correction) {
    corrections.add(correction);
    super.correctBy(correction);
  }
}
