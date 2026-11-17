@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/scaled_mobile_rows_capture.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/l10n/l10n.dart';
import 'package:zcash_wallet/src/core/l10n/locale_typography.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/swap/models/swap_status_presentation.dart';

import '../../support/app_test_fonts.dart';
import '../../support/scaled_row_text_checks.dart';

void main() {
  setUpAll(loadAppTestFonts);
  for (final language in AppLanguage.values) {
    for (final width in [320.0, 360.0]) {
      for (final scale in [1.0, 1.5, 2.0]) {
        for (final badge in SwapStatusBadgeKind.values) {
          for (final payment in [false, true]) {
            testWidgets(
              '${language.tag} status ${badge.name} pay=$payment width=$width scale=$scale',
              (tester) async {
                tester.view.physicalSize = Size(width, 800);
                tester.view.devicePixelRatio = 1;
                addTearDown(tester.view.reset);
                await tester.pumpWidget(
                  MaterialApp(
                    locale: language.locale,
                    supportedLocales: appSupportedLocales(preview: true),
                    localizationsDelegates: appLocalizationsDelegates,
                    builder: (context, child) => AppTheme(
                      data: AppThemeData.light,
                      child: LocaleTypography(
                        child: MediaQuery(
                          data: MediaQuery.of(
                            context,
                          ).copyWith(textScaler: TextScaler.linear(scale)),
                          child: child!,
                        ),
                      ),
                    ),
                    home: MobileStatusRowCapture(
                      paymentMode: payment,
                      badgeKind: badge,
                    ),
                  ),
                );
                // The in-progress badge intentionally keeps its loader moving.
                await tester.pump();
                await tester.pump(const Duration(milliseconds: 400));
                final row = find.byKey(
                  ValueKey(
                    payment
                        ? 'mobile_pay_status_row'
                        : 'mobile_swap_status_row',
                  ),
                );
                final l10n = tester.element(row).l10n;
                final value = switch (badge) {
                  SwapStatusBadgeKind.completed => l10n.commonCompleted,
                  SwapStatusBadgeKind.failed => l10n.commonFailed,
                  SwapStatusBadgeKind.refunded => l10n.commonRefunded,
                  SwapStatusBadgeKind.warning =>
                    l10n.swapStatusBadgeNeedsAttention,
                  SwapStatusBadgeKind.liveQuote => l10n.commonInProgress,
                };
                await Scrollable.ensureVisible(
                  tester.element(row),
                  alignment: 0.5,
                );
                await tester.pump();
                final rect = tester.getRect(row);
                expectUnclippedRowText(
                  tester,
                  find.text(l10n.swapStatusRowLabel),
                  rect,
                );
                expectUnclippedRowText(tester, find.text(value), rect);
                if (scale == 1) expect(rect.height, AppSpacing.base);
                expect(tester.takeException(), isNull);
                await tester.pumpWidget(const SizedBox.shrink());
              },
            );
          }
        }
      }
    }
  }
}
