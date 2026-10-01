@Tags(['mobile', 'figma-capture'])
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_app.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_scenarios.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/layout/minimum_visible_label.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_tab_bar.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';

import 'figma_compare_font_loader.dart';
import '../support/responsive_capture.dart';

void main() {
  const output = String.fromEnvironment('HOME_RESOLUTION_CAPTURE_DIR');
  if (output.isEmpty) return;
  final capture = ResponsiveCaptureOutput(output);
  setUpAll(loadFigmaCompareFonts);

  const viewports = <String, ({Size size, EdgeInsets padding})>{
    'small-phone': (size: Size(320, 568), padding: EdgeInsets.only(top: 20)),
    'ipad-mini': (
      size: Size(375, 667),
      padding: EdgeInsets.only(top: 20, bottom: 25),
    ),
    'ipad-pro13': (
      size: Size(390, 844),
      padding: EdgeInsets.only(top: 20, bottom: 25),
    ),
    'iphone-16pro': (
      size: Size(402, 874),
      padding: EdgeInsets.only(top: 62, bottom: 34),
    ),
    'large-phone': (
      size: Size(430, 932),
      padding: EdgeInsets.only(top: 59, bottom: 34),
    ),
    'android-small': (
      size: Size(360, 800),
      padding: EdgeInsets.only(top: 24, bottom: 24),
    ),
  };

  // Account name and sync label combinations the Home fixtures do not reach.
  for (final scale in [1.0, 1.35, 2.0]) {
    testWidgets('top-nav-labels-${scale}x', (tester) async {
      const widths = [320.0, 375.0, 402.0];
      const names = ['Zcash', 'Savings for travel', 'Long term savings 01'];
      const labels = [
        'Vizor is synced',
        '45% Syncing...',
        'Connecting to Tor…',
        'Syncing failed. Wallet data error...',
      ];
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 2400);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.reset);
      final errors = <String>[];
      final original = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details.exceptionAsString());
      };
      addTearDown(() => FlutterError.onError = original);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, child) =>
              AppTheme(data: AppThemeData.dark, child: child!),
          home: Builder(
            builder: (context) => Align(
              alignment: Alignment.topLeft,
              child: RepaintBoundary(
                key: boundary,
                child: Material(
                  color: context.colors.background.window,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final width in widths) ...[
                          if (width != widths.first) const SizedBox(width: 16),
                          SizedBox(
                            width: width,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final name in names)
                                  for (final label in labels)
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: context.colors.text.muted,
                                            width: 0.5,
                                          ),
                                        ),
                                      ),
                                      child: MobileTopNav.account(
                                        accountName: name,
                                        syncLabel: label,
                                      ),
                                    ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final issues = readableTextIssues([
        find.byType(MobileTopNav),
      ], ellipsisAllowed: names.toSet());
      await capture.capturePng(tester, boundary, 'top-nav-labels-${scale}x');
      await tester.runAsync(() async {
        capture.writeJson('top-nav-labels-${scale}x', {
          'textScale': scale,
          'errors': errors,
          'issues': issues,
        });
      });
      await tester.pumpWidget(const SizedBox.shrink());
      FlutterError.onError = original;
      expect(errors, isEmpty);
      expect(issues, isEmpty);
    });
  }

  for (final viewport in viewports.entries) {
    final platform = viewport.key.startsWith('android')
        ? TargetPlatform.android
        : TargetPlatform.iOS;
    final scales =
        viewport.key == 'small-phone' ||
            viewport.key == 'ipad-mini' ||
            viewport.key == 'iphone-16pro'
        ? [1.0, 1.35, 2.0]
        : [1.0];
    for (final scale in scales) {
      for (final theme
          in scale == 1.0
              ? [ThemeMode.dark, ThemeMode.light]
              : [ThemeMode.dark]) {
        for (final kind in ['transactions', 'swaps', 'reported', 'long']) {
          final name = '${viewport.key}-$kind-${theme.name}-${scale}x';
          testWidgets(name, (tester) async {
            expect(kAppFormFactor, AppFormFactor.mobile);
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            const channel = MethodChannel('com.zcash.wallet/window_appearance');
            final messenger = TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger;
            messenger.setMockMethodCallHandler(channel, (_) async => null);
            addTearDown(
              () => messenger.setMockMethodCallHandler(channel, null),
            );
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = viewport.value.size;
            tester.view.padding = FakeViewPadding(
              top: viewport.value.padding.top,
              bottom: viewport.value.padding.bottom,
            );
            tester.view.viewPadding = tester.view.padding;
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            addTearDown(tester.view.reset);

            final errors = <String>[];
            final original = FlutterError.onError;
            FlutterError.onError = (details) {
              errors.add(details.exceptionAsString());
            };
            addTearDown(() => FlutterError.onError = original);
            final boundary = GlobalKey();
            await tester.pumpWidget(
              FigmaCompareApp(
                scenario: figmaCompareScenarios.firstWhere(
                  (scenario) => scenario.id == 'mobile-home-ten-$kind',
                ),
                themeMode: theme,
                captureBoundaryKey: boundary,
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 600));
            final images = find.byType(Image).evaluate().toList();
            await tester.runAsync(() async {
              for (final element in images) {
                await precacheImage((element.widget as Image).image, element);
              }
            });
            await tester.pump(const Duration(milliseconds: 300));

            final scrollable = tester.state<ScrollableState>(
              find.byType(Scrollable).first,
            );
            final tabBar = tester.getRect(find.byType(AppMobileTabBar));
            final snapshots = <String, Object?>{};
            final textIssues = <String>{};
            for (final position in ['top', 'middle', 'bottom']) {
              final fraction = switch (position) {
                'middle' => 0.5,
                'bottom' => 1.0,
                _ => 0.0,
              };
              scrollable.position.jumpTo(
                scrollable.position.maxScrollExtent * fraction,
              );
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 300));
              if (position == 'bottom') {
                scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
                await tester.pump();
              }
              final activityRows = tester
                  .widgetList<ActivityFeedRow>(find.byType(ActivityFeedRow))
                  .map((row) => row.row);
              textIssues.addAll(
                readableTextIssues(
                  [
                    find.byType(ActivityFeedRow),
                    find.byType(MobileTopNav),
                    find.byKey(const ValueKey('mobile_home_send')),
                    find.byKey(const ValueKey('mobile_home_receive')),
                    find.byKey(const ValueKey('mobile_home_shielded_balance')),
                  ],
                  // Amounts never truncate. Titles keep their first word (see
                  // _activityLayoutIssues); the rest of a title, its
                  // subtitle, statuses and the account name may ellipsize.
                  ellipsisAllowed: {
                    for (final row in activityRows) ...[
                      row.title,
                      if (row.subtitle != null) row.subtitle!,
                      row.statusText.trim(),
                      if (row.amountSubtitle != null) row.amountSubtitle!,
                    ],
                    ...tester
                        .widgetList<MobileTopNav>(find.byType(MobileTopNav))
                        .map((nav) => nav.accountName),
                  },
                ),
              );
              textIssues.addAll(_activityLayoutIssues(tester, scale));
              textIssues.addAll(_balanceIssues(tester));
              final rows = <Map<String, Object?>>[];
              for (var index = 0; index < 10; index++) {
                final finder = find.byKey(
                  ValueKey('mobile_home_activity_row_$index'),
                );
                if (finder.evaluate().isEmpty) continue;
                final rect = tester.getRect(finder);
                rows.add({
                  'index': index,
                  'rect': _rect(rect),
                  'fullyAboveTabBar':
                      rect.top >= 0 && rect.bottom <= tabBar.top,
                });
              }
              snapshots[position] = {
                'scrollPixels': scrollable.position.pixels,
                'scrollExtent': scrollable.position.maxScrollExtent,
                'tabBar': _rect(tabBar),
                'rows': rows,
              };
              await capture.capturePng(tester, boundary, '$name-$position');
            }

            final lastRow = tester.getRect(
              find.byKey(const ValueKey('mobile_home_activity_row_9')),
            );
            final seeAll = tester.renderObject<RenderParagraph>(
              find.text('See all'),
            );
            final seeAllHeight = seeAll.size.height;
            final seeAllIntrinsicHeight = seeAll.getMaxIntrinsicHeight(
              seeAll.size.width,
            );
            final issues = <String>[
              ...textIssues,
              if (seeAllIntrinsicHeight > seeAllHeight + 0.5)
                'See all text needs $seeAllIntrinsicHeight px but has $seeAllHeight px of height.',
              if (lastRow.bottom > tabBar.top)
                'The tenth activity remains under the floating tab bar at the bottom.',
              if (lastRow.left < 0 || lastRow.right > viewport.value.size.width)
                'The tenth activity extends beyond the horizontal viewport.',
            ];
            expect(
              find.byKey(const ValueKey('mobile_home_activity_row_10')),
              findsNothing,
            );
            final groups = find.byType(ActivityFeedRowGroup);
            expect(groups, findsNWidgets(10));
            final childRows = tester
                .widgetList<ActivityFeedRowGroup>(groups)
                .fold<int>(
                  0,
                  (count, group) => count + group.row.childRows.length,
                );
            expect(childRows, kind == 'swaps' ? 10 : 0);
            await tester.runAsync(() async {
              capture.writeJson(name, {
                'viewport': {
                  'width': viewport.value.size.width,
                  'height': viewport.value.size.height,
                  'topInset': viewport.value.padding.top,
                  'bottomInset': viewport.value.padding.bottom,
                },
                'platform': platform.name,
                'theme': theme.name,
                'textScale': scale,
                'parentCount': 10,
                'childCount': childRows,
                'seeAll': {
                  'height': seeAllHeight,
                  'intrinsicHeight': seeAllIntrinsicHeight,
                },
                'errors': errors,
                'issues': issues,
                'snapshots': snapshots,
              });
            });
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            FlutterError.onError = original;
            debugDefaultTargetPlatformOverride = null;
            expect(errors, isEmpty, reason: name);
            expect(issues, isEmpty, reason: name);
          });
        }
      }
    }
  }
}

List<double> _rect(Rect rect) => [rect.left, rect.top, rect.right, rect.bottom];

/// Default text keeps every activity row on one line, and any layout keeps at
/// least the title's first word visible.
List<String> _activityLayoutIssues(WidgetTester tester, double scale) {
  final issues = <String>[];
  for (final element in find.byType(ActivityFeedRow).evaluate()) {
    final row = (element.widget as ActivityFeedRow).row;
    final box = element.renderObject! as RenderBox;
    if (scale == 1.0 && box.size.height > 44.5) {
      issues.add('Default-text row stacks: ${row.title}');
    }
    final title = find.descendant(
      of: find.byWidget(element.widget),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText() == row.title,
      ),
    );
    if (title.evaluate().isEmpty) continue;
    final paragraph = tester.renderObject<RenderParagraph>(title.first);
    final minimum = TextPainter(
      text: TextSpan(
        text: minimumVisibleLabel(row.title),
        style: paragraph.text.style,
      ),
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    if (paragraph.size.width + 0.5 < minimum.width) {
      issues.add('Title hides its first word: ${row.title}');
    }
    minimum.dispose();
  }
  return issues;
}

/// The balance number must stay on one line; only the ticker may wrap.
List<String> _balanceIssues(WidgetTester tester) {
  final finder = find.byKey(const ValueKey('mobile_home_shielded_balance'));
  if (finder.evaluate().isEmpty) return const [];
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)).first,
  );
  final text = paragraph.text.toPlainText();
  final numberLength = text.lastIndexOf(' ');
  final lineTops = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: numberLength),
      )
      .map((box) => box.top.round())
      .toSet();
  return [if (lineTops.length > 1) 'Balance number breaks across lines: $text'];
}
