import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_claim_outcome_view.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final availability in [
    PaymentLinkAvailability.claimedElsewhere,
    PaymentLinkAvailability.failed,
    PaymentLinkAvailability.noBalance,
  ]) {
    testWidgets(
      '${availability.name} keeps its actions accessible with large text',
      (tester) async {
        const mobile = kAppFormFactor == AppFormFactor.mobile;
        await tester.binding.setSurfaceSize(
          mobile ? const Size(393, 852) : const Size(800, 704),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        var checks = 0;
        var archives = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: Scaffold(
                body: PaymentLinkClaimOutcomeView(
                  availability: availability,
                  onBack: () {},
                  onCheck: () => checks++,
                  onArchive: () => archives++,
                ),
              ),
            ),
          ),
        );
        final scroll = find.byKey(
          const ValueKey('payment_link_claim_outcome_scroll'),
        );
        final dropZone = find.byKey(
          ValueKey(
            mobile
                ? 'payment_link_mobile_redeem_drop_zone'
                : 'payment_link_redeem_drop_zone',
          ),
        );
        final check = find.text('Check status');

        for (final scale in [1.0, 2.0, 1.0]) {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpAndSettle();
          if (!mobile) {
            expect(
              tester.getBottomLeft(find.text('Redeem the Card')).dy,
              lessThan(tester.getTopLeft(dropZone).dy),
            );
          }
          final position = tester
              .state<ScrollableState>(
                find.descendant(of: scroll, matching: find.byType(Scrollable)),
              )
              .position;
          expect(position.maxScrollExtent, scale == 1 ? 0 : greaterThan(0));
          position.jumpTo(position.maxScrollExtent);
          await tester.pumpAndSettle();
          expect(check.hitTestable(), findsOneWidget);
          expect(
            tester.getBottomLeft(check).dy,
            lessThanOrEqualTo(tester.getBottomLeft(dropZone).dy),
          );
          await tester.tap(check);
          await tester.tap(find.text('Hide card'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(checks, 3);
        expect(archives, 3);
      },
    );
  }
}
