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
        const status = GiftCardUsageStatusView(address: 'card', inline: true);
        final row = mobile
            ? PaymentLinkCardListMobileRow(
                thumbnail: const SizedBox(),
                amountText: '0.25 ZEC',
                dateText: 'September 14',
                showLinkActions: true,
                onCopyLink: _noop,
                onShowQr: _noop,
                usageStatus: status,
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
        expect(tester.getRect(copy), original);
        notifier.update(false, false, {'card'});
        await tester.pump();
        expect(icon(AppIcons.loader), findsNothing);
        expect(icon(AppIcons.warningCircle), findsOneWidget);
        expect(tester.getRect(copy), original);
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
        expect(tester.getRect(copy), original);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [288.0, 358.0, 440.0]) {
    testWidgets('mobile row preserves card details and tap targets at $width', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppTheme(
            data: AppThemeData.dark,
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
                    usageStatus: const Text('Unused'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final text in ['0.25 ZEC', 'September 14']) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(text))
              .didExceedMaxLines,
          isFalse,
        );
      }
      for (final key in [
        'payment_link_mobile_card_copy_action',
        'payment_link_mobile_card_qr_action',
      ]) {
        expect(tester.getSize(find.byKey(ValueKey(key))), const Size(44, 44));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
