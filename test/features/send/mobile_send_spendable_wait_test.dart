@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/send_use_cases.dart';

import '../../support/widget_test_viewport.dart';

void main() {
  testWidgets(
    'an amount covered by confirming funds says when, not that it is short',
    (tester) async {
      await setWidgetTestViewport(tester, const Size(393, 852));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          home: AppTheme(
            data: AppThemeData.light,
            child: const Builder(builder: buildMobileSendAmountWaitingUseCase),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1.2 ZEC'), findsOneWidget);
      expect(find.text('+1.3 ZEC in 1–3 min'), findsOneWidget);
      expect(find.text('Available in 1–3 min'), findsOneWidget);
      expect(find.text('Not enough ZEC'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('mobile_send_spendable_wait_line')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Available now'), findsOneWidget);
      expect(find.text('Just received'), findsOneWidget);
      expect(find.text('+1.3 ZEC'), findsOneWidget);
      expect(find.text('2.5 ZEC'), findsOneWidget);
    },
  );
}
