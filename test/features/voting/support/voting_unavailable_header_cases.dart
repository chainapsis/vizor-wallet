import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/voting_unavailable_preview.dart';

void votingUnavailableHeaderTests() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('unavailable notice stays below header at text scale $scale', (
      tester,
    ) async {
      const mobile = kAppFormFactor == AppFormFactor.mobile;
      tester.view.physicalSize = mobile
          ? const Size(393, 852)
          : const Size(800, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var retries = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: VotingUnavailablePreview(onRetry: () => retries++),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final notice = find.byKey(
        const ValueKey('voting_participation_unavailable'),
      );
      final header = find.text(mobile ? 'Coinholder voting' : 'Vote');
      expect(
        tester.getBottomLeft(header).dy,
        lessThan(tester.getTopLeft(notice).dy),
      );
      expect(
        find.ancestor(of: notice, matching: find.byType(SingleChildScrollView)),
        findsOneWidget,
      );
      await tester.tap(find.text('Check again'));
      expect(retries, 1);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();
      expect(header, findsOneWidget);
      expect(tester.getTopLeft(header).dy, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });
  }
}
