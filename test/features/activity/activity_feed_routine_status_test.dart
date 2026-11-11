import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/activity/models/activity_row_data.dart';
import 'package:zcash_wallet/src/features/activity/widgets/activity_feed.dart';

// The line under the amount shows the timestamp for routine states and the
// status otherwise. It used to compare the status with English labels, so a
// Korean "완료" row showed "완료" instead of its time.
void main() {
  Widget feed(ActivityRowData row) {
    const mobile = kAppFormFactor == AppFormFactor.mobile;
    return MaterialApp(
      locale: const Locale('ko'),
      supportedLocales: appSupportedLocales(preview: true),
      localizationsDelegates: appLocalizationsDelegates,
      home: AppTheme(
        data: AppThemeData.dark,
        child: Center(
          child: SizedBox(
            width: mobile ? 390 : 420,
            height: 600,
            child: CustomScrollView(
              slivers: [
                ActivityFeedSliver(
                  isLoading: false,
                  showHeader: !mobile,
                  cardWidth: mobile ? null : 396,
                  sections: [
                    ActivityFeedSectionData(title: '이번 주', rows: [row]),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ActivityRowData row({required String status, required bool routine}) {
    return ActivityRowData(
      stableId: 'row',
      title: '받음',
      leadingIconName: AppIcons.plane,
      leadingBackgroundColor: const Color(0xff103030),
      leadingIconColor: const Color(0xff50aaaa),
      amountText: '+1 ZEC',
      statusText: status,
      statusIsRoutine: routine,
      timestampText: '10월 23일 12:00',
    );
  }

  testWidgets('a routine status shows the timestamp in any language', (
    tester,
  ) async {
    await tester.pumpWidget(feed(row(status: '완료', routine: true)));
    await tester.pumpAndSettle();

    expect(find.text('완료'), findsNothing);
    expect(find.text('10월 23일 12:00'), findsWidgets);
  });

  testWidgets('another status shows the status itself', (tester) async {
    await tester.pumpWidget(feed(row(status: '입금 부족', routine: false)));
    await tester.pumpAndSettle();

    expect(find.text('입금 부족'), findsWidgets);
  });
}
