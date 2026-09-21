import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/payment_links/models/gift_card_usage.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/gift_card_tracking_provider.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/gift_card_usage_status.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_desktop_views.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void _noop() {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFigmaCompareFonts);
  for (final mobile in [false, true]) {
    testWidgets(
      'inline ${mobile ? 'mobile' : 'desktop'} status keeps actions fixed and exposes failures',
      (tester) async {
        var usage = const GiftCardUsage(status: GiftCardUsageStatus.unused);
        final container = ProviderContainer(
          overrides: [
            giftCardUsageProvider('card').overrideWith((ref) async => usage),
          ],
        );
        addTearDown(container.dispose);
        final status = GiftCardUsageStatusView(
          address: 'card',
          inline: true,
          dateText: mobile ? 'September 14' : null,
        );
        final row = mobile
            ? PaymentLinkCardListMobileRow(
                thumbnail: const SizedBox(),
                amountText: '0.25 ZEC',
                dateText: 'September 14',
                showLinkActions: true,
                onCopyLink: _noop,
                onShowQr: _noop,
                metadata: status,
              )
            : PaymentLinkCardListRow(
                thumbnail: const SizedBox(),
                amountText: '0.25 ZEC',
                dateText: 'September 14',
                showLinkActions: true,
                onCopyLink: _noop,
                onShowQr: _noop,
                usageStatus: status,
              );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: AppTheme(
                data: AppThemeData.dark,
                child: Scaffold(
                  body: Center(
                    child: SizedBox(width: mobile ? 358 : 390, child: row),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final copy = find.byKey(
          ValueKey(
            mobile
                ? 'payment_link_mobile_card_copy_action'
                : 'payment_link_card_copy_action',
          ),
        );
        final original = tester.getRect(copy);
        final notifier = container.read(giftCardTrackingStateProvider.notifier);
        Finder icon(String name) =>
            find.byWidgetPredicate((w) => w is AppIcon && w.name == name);
        expect(find.text('Unused'), findsOneWidget);
        expect(find.textContaining('Card use:'), findsNothing);
        notifier.update(true, false);
        await tester.pump(const Duration(milliseconds: 100));
        expect(icon(AppIcons.loader), findsOneWidget);
        expect(
          mobile ? tester.getRect(copy).left : tester.getRect(copy),
          mobile ? original.left : original,
        );
        notifier.update(false, false, {'card'});
        await tester.pump();
        expect(icon(AppIcons.loader), findsNothing);
        expect(icon(AppIcons.warningCircle), findsOneWidget);
        expect(
          mobile ? tester.getRect(copy).left : tester.getRect(copy),
          mobile ? original.left : original,
        );
        await tester.tap(find.text('Unused'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Card use: Unused. Update failed'), findsOneWidget);
        await tester.pump(const Duration(seconds: 9));
        usage = const GiftCardUsage(
          status: GiftCardUsageStatus.used,
          cleaned: true,
        );
        container.invalidate(giftCardUsageProvider('card'));
        notifier.update(true, false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Used'), findsOneWidget);
        expect(icon(AppIcons.loader), findsNothing);
        expect(icon(AppIcons.warningCircle), findsNothing);
        expect(
          mobile ? tester.getRect(copy).left : tester.getRect(copy),
          mobile ? original.left : original,
        );
        notifier.update(false, false);
        for (final reason in [null, GiftCardUsageReason.awaitingConfirmation]) {
          usage = GiftCardUsage(reason: reason);
          container.invalidate(giftCardUsageProvider('card'));
          await tester.pumpAndSettle();
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(usage.label),
          );
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(
            mobile ? tester.getRect(copy).left : tester.getRect(copy),
            mobile ? original.left : original,
          );
        }
        notifier.update(true, false);
        await tester.pump();
        expect(find.text('Checking…'), findsOneWidget);
        notifier.update(false, true);
        await tester.pump();
        expect(find.text('Confirming'), findsOneWidget);
        expect(icon(AppIcons.warningCircle), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'completion status explains pending funding and avoids duplicate checking',
    (tester) async {
      final container = ProviderContainer(
        overrides: [
          giftCardUsageProvider('card').overrideWith(
            (ref) async => const GiftCardUsage(
              reason: GiftCardUsageReason.awaitingConfirmation,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: AppTheme(
              data: AppThemeData.dark,
              child: const Scaffold(
                body: GiftCardUsageStatusView(address: 'card'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Card use: Confirming'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.text(
          'Your link is ready to share. Usage tracking will begin once the funding transaction is confirmed.',
        ),
        findsOneWidget,
      );
      container
          .read(giftCardTrackingStateProvider.notifier)
          .update(true, false);
      await tester.pump();
      expect(find.text('Card use: Checking…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
    },
  );

  for (final mobile in [false, true]) {
    for (final status in [
      GiftCardUsageStatus.unused,
      GiftCardUsageStatus.spendDetected,
      GiftCardUsageStatus.used,
    ]) {
      testWidgets(
        'grouped status hides $status and preserves feedback (mobile: $mobile)',
        (tester) async {
          final container = ProviderContainer(
            overrides: [
              giftCardUsageProvider(
                'card',
              ).overrideWith((ref) async => GiftCardUsage(status: status)),
            ],
          );
          addTearDown(container.dispose);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: AppTheme(
                  data: AppThemeData.dark,
                  child: Scaffold(
                    body: GiftCardUsageStatusView(
                      address: 'card',
                      inline: true,
                      dateText: mobile ? 'September 14' : null,
                      hideStableLabel: true,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('September 14'),
            mobile ? findsOneWidget : findsNothing,
          );
          expect(find.text('Unused'), findsNothing);
          expect(find.text('Used'), findsNothing);
          expect(find.text('Use detected'), findsNothing);
          expect(find.text(' · '), findsNothing);
          final semantics = tester.ensureSemantics();
          final labels = <String>[];
          try {
            await tester.pump();
            void collect(SemanticsNode node) {
              labels.add(node.label);
              node.visitChildren((child) {
                collect(child);
                return true;
              });
            }

            collect(tester.getSemantics(find.byType(Scaffold)));
          } finally {
            semantics.dispose();
          }
          expect(labels.any((label) => label.contains('Card use:')), isFalse);
          expect(labels.any((label) => label.contains('September 14')), mobile);

          final notifier = container.read(
            giftCardTrackingStateProvider.notifier,
          );
          notifier.update(true, false);
          await tester.pump();
          expect(find.text('Checking…'), findsOneWidget);

          notifier.update(false, false, {'card'});
          await tester.pump();
          expect(find.text('Update failed'), findsOneWidget);
        },
      );
    }
  }

  for (final (width, scale) in [
    (288.0, 1.0),
    (361.0, 1.0),
    (440.0, 1.0),
    (288.0, 1.5),
    (361.0, 2.0),
  ]) {
    testWidgets(
      'mobile metadata wraps without losing details at $width / $scale',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              giftCardUsageProvider('card').overrideWith(
                (ref) async =>
                    const GiftCardUsage(status: GiftCardUsageStatus.unused),
              ),
            ],
            child: MaterialApp(
              home: AppTheme(
                data: AppThemeData.dark,
                child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: width,
                        child: PaymentLinkCardListMobileRow(
                          thumbnail: const SizedBox(),
                          amountText: '0.25 ZEC',
                          dateText: 'September 14',
                          showLinkActions: true,
                          onCopyLink: _noop,
                          onShowQr: _noop,
                          metadata: const GiftCardUsageStatusView(
                            address: 'card',
                            inline: true,
                            dateText: 'September 14',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final text in ['0.25 ZEC', 'September 14', 'Unused']) {
          expect(
            tester
                .renderObject<RenderParagraph>(find.text(text))
                .didExceedMaxLines,
            isFalse,
          );
        }
        final date = tester.getRect(find.text('September 14'));
        final usage = tester.getRect(find.text('Unused'));
        if (width == 440 && scale == 1) {
          expect(usage.top, date.top);
          expect(find.text(' · '), findsOneWidget);
          expect(
            tester.getSize(find.byType(PaymentLinkCardListMobileRow)).height,
            lessThan(108),
          );
        } else if (width == 288 || scale > 1) {
          expect(usage.top, greaterThanOrEqualTo(date.bottom));
          expect(usage.left, date.left);
          expect(find.text(' · '), findsNothing);
        }
        for (final key in [
          'payment_link_mobile_card_copy_action',
          'payment_link_mobile_card_qr_action',
        ]) {
          expect(tester.getSize(find.byKey(ValueKey(key))), const Size(44, 44));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
