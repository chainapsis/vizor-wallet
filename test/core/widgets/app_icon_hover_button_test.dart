import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon_hover_button.dart';

void main() {
  testWidgets('the keyboard reaches and presses it, with a focus ring', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AppTheme(
          data: AppThemeData.dark,
          child: Center(
            child: AppIconHoverButton(
              key: const ValueKey('button'),
              icon: AppIcons.help,
              semanticLabel: 'Help',
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    BoxBorder? ring() =>
        (tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: find.byKey(const ValueKey('button')),
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .border;
    expect(ring(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(ring(), isNotNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(taps, 2);
  });
}
