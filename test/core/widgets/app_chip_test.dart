import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_chip.dart';

void main() {
  testWidgets('AppChip can use min width without truncating the label', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: AppChip(
                key: ValueKey('mnemonic_chip'),
                minWidth: 90,
                leadingText: '01',
                label: 'acknowledge',
                labelOverflow: TextOverflow.visible,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('mnemonic_chip'))).width,
      greaterThan(90),
    );

    final label = tester.widget<Text>(find.text('acknowledge'));
    expect(label.overflow, TextOverflow.visible);
  });

  testWidgets('AppChip keeps default text chips fixed width', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppTheme(
          data: AppThemeData.light,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: AppChip(
                key: ValueKey('fixed_chip'),
                leadingText: '01',
                label: 'acknowledge',
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const ValueKey('fixed_chip'))).width, 80);

    final label = tester.widget<Text>(find.text('acknowledge'));
    expect(label.overflow, TextOverflow.ellipsis);
  });
}
