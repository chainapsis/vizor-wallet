import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';

import '../../support/localized_test_scope.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('ko'), Locale('zh')]) {
    testWidgets('keypad keys are announced in ${locale.languageCode}', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(locale);
      await tester.pumpWidget(
        LocalizedTestScope(
          locale: locale,
          child: AppTheme(
            data: AppThemeData.dark,
            child: PasscodeNumpad(
              onDigit: (_) {},
              onBackspace: () {},
              onHelp: () {},
              canDelete: true,
            ),
          ),
        ),
      );

      expect(
        find.bySemanticsLabel(l10n.onboardingPasscodeHelpSemantics),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(l10n.onboardingPasscodeDeleteSemantics),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(l10n.onboardingPasscodeDigitSemantics(7)),
        findsOneWidget,
      );
    });
  }
}
