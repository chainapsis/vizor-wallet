import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_content.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/layout/app_layout.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

void main() {
  test('large desktop window min width is 75% of the 1080 canvas', () {
    expect(AppLayoutMode.large.minimumSize, const Size(810, 720));
    expect(AppLayoutMode.large.defaultSize, const Size(1080, 720));
  });

  test('design pane width matches the 1080 desktop chrome', () {
    expect(
      AppDesktopContentMetrics.designPaneWidth,
      AppWindowSizing.minWidth -
          AppSpacing.xs * 3 -
          AppDesktopShell.defaultSidebarWidth,
    );
    expect(AppDesktopContentMetrics.designPaneWidth, 800);
  });

  test('content column stays 420 at the design pane and smaller', () {
    expect(AppDesktopContentMetrics.widthForPane(800), 420);
    expect(AppDesktopContentMetrics.widthForPane(520), 420);
    expect(AppDesktopContentMetrics.widthForPane(300), 300);
    expect(AppDesktopContentMetrics.surfaceWidthForPane(800), 396);
  });

  test('content column grows with extra pane width', () {
    expect(AppDesktopContentMetrics.widthForPane(1120), 740);
    expect(AppDesktopContentMetrics.surfaceWidthForPane(1120), 716);
  });

  testWidgets('AppDesktopContentColumn uses the design width in an 800 pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 720,
          child: AppDesktopContentColumn(
            contentKey: ValueKey('column'),
            child: SizedBox(height: 10),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const ValueKey('column'))).width, 420);
  });

  testWidgets('AppDesktopContentColumn grows in a wider pane', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 1120,
            height: 720,
            child: AppDesktopContentColumn(
              contentKey: ValueKey('column'),
              child: SizedBox(height: 10),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const ValueKey('column'))).width, 740);
  });
}
