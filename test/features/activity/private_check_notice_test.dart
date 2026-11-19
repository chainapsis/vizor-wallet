import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/activity/widgets/private_check_notice.dart';

import '../../support/localized_test_scope.dart';
import '../../support/test_l10n.dart';

Widget _slot(bool checking, {bool reduceMotion = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduceMotion),
  child: AppTheme(
    data: AppThemeData.light,
    child: LocalizedTestScope(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 360,
          child: PrivateCheckNoticeSlot(
            checking: checking,
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
          ),
        ),
      ),
    ),
  ),
);

double _height(WidgetTester tester) =>
    tester.getSize(find.byType(PrivateCheckNoticeSlot)).height;

void main() {
  testWidgets('a notice shown from the start has no entrance', (tester) async {
    await tester.pumpWidget(_slot(true));

    expect(find.text(testL10n.activityPrivateCheckNotice), findsOneWidget);
    final shown = _height(tester);
    expect(shown, greaterThan(AppSpacing.md));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_height(tester), shown);
  });

  testWidgets('a notice eases out with its spacing, then eases back in', (
    tester,
  ) async {
    await tester.pumpWidget(_slot(true));
    final shown = _height(tester);

    await tester.pumpWidget(_slot(false));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_height(tester), inExclusiveRange(0, shown));
    await tester.pump(PrivateCheckNoticeSlot.exitDuration);
    expect(_height(tester), 0);
    expect(find.text(testL10n.activityPrivateCheckNotice), findsNothing);

    await tester.pumpWidget(_slot(true));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_height(tester), inExclusiveRange(0, shown));
    await tester.pump(PrivateCheckNoticeSlot.enterDuration);
    expect(_height(tester), shown);
  });

  testWidgets('reduced motion switches the notice at once', (tester) async {
    await tester.pumpWidget(_slot(true, reduceMotion: true));

    await tester.pumpWidget(_slot(false, reduceMotion: true));
    await tester.pump();
    expect(_height(tester), 0);

    await tester.pumpWidget(_slot(true, reduceMotion: true));
    await tester.pump();
    expect(find.text(testL10n.activityPrivateCheckNotice), findsOneWidget);
  });
}
