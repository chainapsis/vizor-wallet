import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';

import '../../support/localized_test_scope.dart';

// Screens format dates with intl's DateFormat(l10n.localeName). That only
// works when the app's localization delegates have loaded the CLDR date data
// for every language, released or not.
void main() {
  for (final language in AppLanguage.values) {
    testWidgets('${language.tag} date names load with the app delegates', (
      tester,
    ) async {
      late String month;
      late String weekday;
      await tester.pumpWidget(
        LocalizedTestScope(
          locale: language.locale,
          child: Builder(
            builder: (context) {
              final name = context.l10n.localeName;
              month = DateFormat.yMMMM(name).format(DateTime(2025));
              weekday = DateFormat.E(name).format(DateTime(2023));
              return const SizedBox();
            },
          ),
        ),
      );

      expect(month, switch (language) {
        AppLanguage.en => 'January 2025',
        AppLanguage.ko => '2025년 1월',
        AppLanguage.zh => '2025年1月',
      });
      expect(weekday, switch (language) {
        AppLanguage.en => 'Sun',
        AppLanguage.ko => '일',
        AppLanguage.zh => '周日',
      });
    });
  }
}
