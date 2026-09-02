import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';

void main() {
  testWidgets('vote icon SVG loads at sidebar size', (tester) async {
    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.dark,
        child: const MaterialApp(
          home: ColoredBox(
            color: Color(0xFF121212),
            child: Center(
              child: AppIcon(
                AppIcons.vote,
                size: 20,
                color: Color(0xFFF7F7F7),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.vote,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
