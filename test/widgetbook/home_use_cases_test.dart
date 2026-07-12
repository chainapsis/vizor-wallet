import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/home/widgets/pay_floating_badge.dart';
import 'package:zcash_wallet/widgetbook/home_use_cases.dart';

void main() {
  testWidgets('Pay badge use case renders the production component', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData().copyWith(disableAnimations: true),
          child: AppTheme(
            data: AppThemeData.light,
            child: Builder(builder: buildPayFloatingBadgeUseCase),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(PayFloatingBadge), findsOneWidget);
    expect(find.text('Pay in USDC'), findsOneWidget);
    expect(find.text('NEW'), findsOneWidget);
  });
}
