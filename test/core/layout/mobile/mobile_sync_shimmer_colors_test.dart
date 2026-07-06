@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

const _figmaSyncingText = Color(0xFFA3A4A4);
const _figmaSyncingHighlight = Color(0xFFFFFFFF);

void main() {
  testWidgets('mobile top nav syncing state uses Figma static colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mobileHarness(
        disableAnimations: true,
        child: _syncingTopNav(animated: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ShaderMask), findsNothing);
    final text = tester.widget<Text>(find.text('20% Syncing...'));
    expect(text.style?.color, _figmaSyncingText);
    expect(_hasMobileSyncIndicator(tester, _figmaSyncingText), isTrue);
    expect(AppThemeData.dark.colors.sync.textSyncing, _figmaSyncingText);
    expect(AppThemeData.dark.colors.sync.lightSyncing, _figmaSyncingText);
  });

  testWidgets('mobile top nav syncing shimmer uses Figma highlight color', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mobileHarness(
        disableAnimations: false,
        child: _syncingTopNav(animated: true),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(ShaderMask), findsOneWidget);
    final text = tester.widget<Text>(find.text('20% Syncing...'));
    expect(text.style?.color, _figmaSyncingHighlight);
    expect(_hasMobileSyncIndicator(tester, _figmaSyncingText), isTrue);
    expect(
      AppThemeData.dark.colors.sync.textSyncingHighlight,
      _figmaSyncingHighlight,
    );

    await tester.pumpWidget(const SizedBox());
  });
}

Widget _syncingTopNav({required bool animated}) {
  return MobileTopNav.account(
    accountName: 'Account1',
    syncLabel: '20% Syncing...',
    syncLabelColor: AppThemeData.dark.colors.sync.textSyncing,
    syncIndicatorColor: AppThemeData.dark.colors.sync.lightSyncing,
    syncHighlightColor: AppThemeData.dark.colors.sync.textSyncingHighlight,
    syncAnimated: animated,
  );
}

Widget _mobileHarness({
  required bool disableAnimations,
  required Widget child,
}) {
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: AppTheme(
          data: AppThemeData.dark,
          child: Center(child: child),
        ),
      ),
    ),
  );
}

bool _hasMobileSyncIndicator(WidgetTester tester, Color color) {
  return tester.widgetList<Container>(find.byType(Container)).any((container) {
    final decoration = container.decoration;
    return decoration is BoxDecoration && decoration.color == color;
  });
}
