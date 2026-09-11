import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_tooltip.dart';

void main() {
  testWidgets('a focusable help tooltip is reachable without a pointer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: Center(
            child: AppTooltip(
              message: 'Send USDC on Ethereum only.',
              focusable: true,
              child: AppIcon(AppIcons.help, size: 20),
            ),
          ),
        ),
      ),
    );

    // Announces as a control named by the message, so a screen-reader user
    // can find it in the buttons list.
    expect(find.bySemanticsLabel('Send USDC on Ethereum only.'), findsOneWidget);
    expect(find.text('Send USDC on Ethereum only.'), findsNothing);

    // Keyboard focus shows the tooltip; leaving hides it again.
    final focus = Focus.of(tester.element(find.byType(AppIcon)));
    focus.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Send USDC on Ethereum only.'), findsOneWidget);

    focus.unfocus();
    await tester.pumpAndSettle();
    expect(find.text('Send USDC on Ethereum only.'), findsNothing);
  });

  testWidgets('a plain tooltip stays out of the tab order', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: Center(
            child: AppTooltip(
              message: 'Hover only',
              child: AppIcon(AppIcons.help, size: 20),
            ),
          ),
        ),
      ),
    );

    expect(
      find.descendant(of: find.byType(AppTooltip), matching: find.byType(Focus)),
      findsNothing,
    );
  });
}
