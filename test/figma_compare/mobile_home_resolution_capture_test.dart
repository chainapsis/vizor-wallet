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
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_tab_bar.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
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

  for (final viewport in viewports.entries) {
    final platform = viewport.key.startsWith('android')
        ? TargetPlatform.android
        : TargetPlatform.iOS;
    final scales =
        viewport.key == 'small-phone' ||
            viewport.key == 'ipad-mini' ||
            viewport.key == 'iphone-16pro'
        ? [1.0, 1.3, 2.0]
        : [1.0];
    for (final scale in scales) {
      for (final theme
          in scale == 1.0
              ? [ThemeMode.dark, ThemeMode.light]
              : [ThemeMode.dark]) {
        for (final kind in ['transactions', 'swaps', 'reported']) {
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
              textIssues.addAll(
                readableTextIssues([
                  find.byType(ActivityFeedRow),
                  find.byType(MobileTopNav),
                  find.byKey(const ValueKey('mobile_home_send')),
                  find.byKey(const ValueKey('mobile_home_receive')),
                ]),
              );
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
