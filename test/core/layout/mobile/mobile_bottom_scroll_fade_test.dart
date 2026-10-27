@Tags(['mobile'])
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_bottom_scroll_fade.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

Future<void> _pump(WidgetTester tester, {required int rows}) {
  return tester.pumpWidget(
    AppTheme(
      data: AppThemeData.light,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            height: 300,
            child: MobileBottomScrollFade(
              child: ListView(
                children: [
                  for (var i = 0; i < rows; i++) const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

double _fadeAlpha(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find.byKey(const ValueKey('mobile_bottom_scroll_fade_layer')),
  );
  final gradient = (box.decoration as BoxDecoration).gradient!;
  return gradient.colors.last.a;
}

void main() {
  testWidgets('shows at rest when the list overflows', (tester) async {
    await _pump(tester, rows: 20);
    await tester.pump();

    expect(_fadeAlpha(tester), 1);
  });

  testWidgets('clears at the end of the list', (tester) async {
    await _pump(tester, rows: 20);
    await tester.pump();

    final position = tester
        .state<ScrollableState>(find.byType(Scrollable))
        .position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();

    expect(_fadeAlpha(tester), 0);
  });

  testWidgets('stays clear for a list that fits', (tester) async {
    await _pump(tester, rows: 3);
    await tester.pump();

    expect(_fadeAlpha(tester), 0);
  });
}
