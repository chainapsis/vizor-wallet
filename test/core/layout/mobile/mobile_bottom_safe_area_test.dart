import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/app_mobile_shell.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_bottom_safe_area.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

/// Home-indicator inset reported by Face ID iPhones.
const double _inset = 34;

const _childKey = ValueKey('content');

Widget _host({required double bottomPadding}) {
  return MediaQuery(
    data: const MediaQueryData(
      size: Size(800, 600),
      padding: EdgeInsets.only(bottom: _inset),
      viewPadding: EdgeInsets.only(bottom: _inset),
    ),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: MobileBottomSafeArea(
          bottomPadding: bottomPadding,
          child: const SizedBox(key: _childKey, width: 50, height: 10),
        ),
      ),
    ),
  );
}

const _barKey = ValueKey('bar');

Widget _shellHost() {
  return MaterialApp(
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(800, 600),
        padding: EdgeInsets.only(bottom: _inset),
        viewPadding: EdgeInsets.only(bottom: _inset),
      ),
      child: const AppMobileShell(
        body: SizedBox.expand(),
        tabBar: SizedBox(key: _barKey, height: 64),
      ),
    ),
  );
}

void main() {
  testWidgets('iOS skips the inset when the content padding clears the '
      'home indicator', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      _host(bottomPadding: kIosHomeIndicatorClearance),
    );

    final screenBottom = tester.getBottomLeft(find.byType(Align)).dy;
    expect(tester.getBottomLeft(find.byKey(_childKey)).dy, screenBottom);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('iOS keeps the inset when the content padding is too small', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      _host(bottomPadding: kIosHomeIndicatorClearance - 1),
    );

    final screenBottom = tester.getBottomLeft(find.byType(Align)).dy;
    expect(
      tester.getBottomLeft(find.byKey(_childKey)).dy,
      screenBottom - _inset,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android always keeps the inset', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(_host(bottomPadding: AppSpacing.base));

    final screenBottom = tester.getBottomLeft(find.byType(Align)).dy;
    expect(
      tester.getBottomLeft(find.byKey(_childKey)).dy,
      screenBottom - _inset,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shell tab bar gap on iOS matches the side margins', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(_shellHost());

    final screenBottom = tester.getBottomLeft(find.byType(AppMobileShell)).dy;
    final bar = find.byKey(_barKey);
    // 16 below the bar — the same gap as the 16px side margins, with
    // the home indicator floating inside it instead of stacking on top.
    expect(tester.getBottomLeft(bar).dy, screenBottom - AppSpacing.sm);
    expect(tester.getTopLeft(bar).dx, AppSpacing.sm);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shell tab bar gap on Android keeps the Figma 12 above the '
      'inset', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(_shellHost());

    final screenBottom = tester.getBottomLeft(find.byType(AppMobileShell)).dy;
    expect(
      tester.getBottomLeft(find.byKey(_barKey)).dy,
      screenBottom - _inset - AppSpacing.s,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
