import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:zcash_wallet/src/core/formatting/date_format.dart';
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
      late List<String> shared;
      await tester.pumpWidget(
        LocalizedTestScope(
          locale: language.locale,
          child: Builder(
            builder: (context) {
              final name = context.l10n.localeName;
              month = DateFormat.yMMMM(name).format(DateTime(2025));
              weekday = DateFormat.E(name).format(DateTime(2023));
              final day = DateTime(2026, 5, 25, 13, 30);
              shared = [
                formatMonthDay(day, name),
                formatMonthDayYear(day, name),
                formatDayMonthTime(day, name),
                formatNumericDate(DateTime(2026, 5, 7), name),
                formatNumericMonthYear(DateTime(2026, 5, 7), name),
              ];
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
      expect(shared, switch (language) {
        AppLanguage.en => [
          'May 25',
          'May 25, 2026',
          '25 May, 13:30',
          '05/07/2026',
          '05/2026',
        ],
        AppLanguage.ko => [
          '5월 25일',
          '2026년 5월 25일',
          '5월 25일 13:30',
          '2026. 05. 07.',
          '2026. 05.',
        ],
        AppLanguage.zh => [
          '5月25日',
          '2026年5月25日',
          '5月25日 13:30',
          '2026/05/07',
          '2026/05',
        ],
      });
    });
  }
}
