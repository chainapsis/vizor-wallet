@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_qr_fullscreen_view.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_qr_share_card.dart';

import '../../support/payment_links_screen_support.dart';
import '../../support/widget_test_viewport.dart';

Finder keyed(String value) => find.byKey(ValueKey(value));

Future<void> openShareSheet(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Show gift card QR code'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadPaymentLinksTestFonts);

  testWidgets(
    'QR tap opens once and close or Back restores the share sheet',
    (tester) async {
      final operations = FakePaymentLinkOperations(records: [fundedRecovery]);
      final clipboard = FakePaymentLinkClipboard();
      await pumpPaymentLinksScreen(
        tester,
        operations: operations,
        clipboard: clipboard,
      );
      await openShareSheet(tester);
      final card = tester.widget<PaymentLinkQrShareCard>(
        find.byType(PaymentLinkQrShareCard),
      );
      // Artwork outside the QR is not an enlargement target.
      await tester.tapAt(
        tester.getTopLeft(keyed('payment_link_qr_share_card')) +
            const Offset(20, 20),
      );
      await tester.pumpAndSettle();
      expect(keyed('payment_link_qr_fullscreen'), findsNothing);
      expect(
        find.bySemanticsLabel('Show gift card QR code full screen'),
        findsOneWidget,
      );
      await tester.tap(keyed('payment_link_qr_code'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PaymentLinkQrFullscreenView>(
              find.byType(PaymentLinkQrFullscreenView),
            )
            .link,
        card.qrData,
      );
      expect(
        tester.getSize(keyed('payment_link_qr_fullscreen')),
        const Size(390, 844),
      );
      expect(find.text('Share card').hitTestable(), findsNothing);
      expect(operations.sharedLinks, isEmpty);
      await tester.tap(keyed('payment_link_qr_fullscreen_close'));
      await tester.pumpAndSettle();
      expect(keyed('payment_link_share_sheet'), findsOneWidget);
      // Exercise two activation callbacks in the same frame, before the new
      // popup can intercept a second tap (e.g. accessibility activation).
      card.onQrTap!();
      card.onQrTap!();
      await tester.pumpAndSettle();
      expect(find.byType(PaymentLinkQrFullscreenView), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(keyed('payment_link_qr_fullscreen'), findsNothing);
      expect(keyed('payment_link_share_sheet'), findsOneWidget);
      expect(operations.sharedLinks, isEmpty);
      await tester.tap(keyed('payment_link_share_copy_button'));
      await tester.pumpAndSettle();
      expect(clipboard.copiedSecrets, [card.qrData]);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('leaving the gift flow removes its fullscreen QR and sheet', (
    tester,
  ) async {
    await pumpPaymentLinksScreen(
      tester,
      operations: FakePaymentLinkOperations(records: [fundedRecovery]),
    );
    final router = GoRouter.of(
      tester.element(keyed('payment_links_mobile_screen')),
    );
    await openShareSheet(tester);
    await tester.tap(keyed('payment_link_qr_code'));
    await tester.pumpAndSettle();
    router.go('/settings');
    await tester.pumpAndSettle();
    expect(keyed('payment_link_qr_fullscreen'), findsNothing);
    expect(keyed('payment_link_share_sheet'), findsNothing);
    expect(router.state.uri.path, '/settings');
    expect(tester.takeException(), isNull);
  });

  testWidgets('locking the wallet dismisses both QR surfaces', (tester) async {
    final security = _Security();
    await pumpPaymentLinksScreen(
      tester,
      securityNotifier: security,
      // Start from a locked bootstrap with an unlocked live session, so the
      // startup fallback cannot override the subsequent live lock signal.
      bootstrap: AppBootstrapState(
        initialLocation: '/payment-links',
        initialAccountState: paymentLinksAccountState,
        initialSyncSnapshot: AppSyncSnapshot.empty,
        network: paymentLinksBootstrap.network,
        rpcEndpointConfig: paymentLinksBootstrap.rpcEndpointConfig,
        themeMode: ThemeMode.dark,
        privacyModeEnabled: false,
        isPasswordConfigured: true,
        isUnlocked: false,
        passwordRotationRecoveryFailed: false,
      ),
      operations: FakePaymentLinkOperations(records: [fundedRecovery]),
    );
    final router = GoRouter.of(
      tester.element(keyed('payment_links_mobile_screen')),
    );
    await openShareSheet(tester);
    await tester.tap(keyed('payment_link_qr_code'));
    await tester.pumpAndSettle();
    security.lock();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/unlock');
    expect(keyed('payment_link_qr_fullscreen'), findsNothing);
    expect(keyed('payment_link_share_sheet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unencodable QR exposes a localized accessible error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appSupportedLocales(),
        home: AppTheme(
          data: AppThemeData.dark,
          child: PaymentLinkQrFullscreenView(
            link: List.filled(5000, 'a').join(),
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('QR code could not be generated'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('QR code could not be generated')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final (name, theme) in [
    ('light', AppThemeData.light),
    ('dark', AppThemeData.dark),
  ]) {
    for (final size in [
      const Size(393, 852),
      const Size(320, 568),
      const Size(852, 393),
    ]) {
      testWidgets('long QR fits $size with large text in $name', (
        tester,
      ) async {
        await setWidgetTestViewport(tester, size, devicePixelRatio: 3);
        const insets = EdgeInsets.fromLTRB(0, 44, 0, 34);
        final longLink =
            'https://link.vizor.cash/payment-links/open#v3='
            '${List.filled(1100, 'A').join()}';
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: appSupportedLocales(),
            home: AppTheme(
              data: theme,
              child: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  padding: insets,
                  viewPadding: insets,
                  textScaler: const TextScaler.linear(2),
                ),
                child: PaymentLinkQrFullscreenView(
                  link: longLink,
                  onClose: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final qrRect = tester.getRect(keyed('payment_link_fullscreen_qr_code'));
        final closeRect = tester.getRect(
          keyed('payment_link_qr_fullscreen_close'),
        );
        expect(qrRect.width, qrRect.height);
        expect(qrRect.width, greaterThan(180));
        expect(qrRect.left, greaterThanOrEqualTo(16));
        expect(qrRect.right, lessThanOrEqualTo(size.width - 16));
        expect(qrRect.top, greaterThan(closeRect.bottom));
        expect(qrRect.bottom, lessThanOrEqualTo(size.height - insets.bottom));
        expect(closeRect.top, greaterThanOrEqualTo(insets.top));
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  @override
  void lock() => state = state.copyWith(isUnlocked: false);
}
