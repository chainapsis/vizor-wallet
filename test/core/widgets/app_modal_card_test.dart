import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_modal_card.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, {required bool highlight}) {
    return tester.pumpWidget(
      AppTheme(
        data: AppThemeData.dark,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: AppModalCard(
              highlight: highlight,
              child: const SizedBox(height: 80),
            ),
          ),
        ),
      ),
    );
  }

  final innerHighlight = find.byKey(
    const ValueKey('app_modal_inner_highlight'),
  );

  testWidgets('a default card paints no inner highlight', (tester) async {
    await pumpCard(tester, highlight: false);

    expect(find.byType(AppModalCard), findsOneWidget);
    expect(innerHighlight, findsNothing);
  });

  testWidgets('the inner highlight is opt-in', (tester) async {
    await pumpCard(tester, highlight: true);

    expect(innerHighlight, findsOneWidget);
    expect(
      tester.widget<CustomPaint>(innerHighlight).foregroundPainter,
      isNotNull,
    );
  });
}
