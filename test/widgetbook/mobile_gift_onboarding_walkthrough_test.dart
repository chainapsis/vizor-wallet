@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/payment_links/services/gift_claim_import_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_customise_account_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_biometrics_screen.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/mobile/payment_link_mobile_views.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_gift_card.dart';
import 'package:zcash_wallet/src/features/payment_links/widgets/payment_link_long_sync_warning.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/features/activity/gift_card_activity_index.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/widgetbook/mobile_gift_onboarding_use_cases.dart';
import '../figma_compare/figma_compare_font_loader.dart';

Future<void> _render(WidgetTester tester, WidgetBuilder builder) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  await tester.pumpWidget(
    MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _advance(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(tester.takeException(), isNull);
}

Future<void> _reachCustomise(WidgetTester tester) async {
  if (find
      .byKey(const ValueKey('mobile_welcome_redeem_card'))
      .evaluate()
      .isNotEmpty) {
    await tester.tap(find.byKey(const ValueKey('mobile_welcome_redeem_card')));
    await _advance(tester);
  }
  await tester.tap(
    find.byKey(const ValueKey('payment_link_mobile_paste_button')),
  );
  await _advance(tester);
  await tester.tap(
    find.byKey(const ValueKey('gift_claim_create_a_wallet_to_claim')),
  );
  await _advance(tester);
  for (var round = 0; round < 2; round++) {
    for (final digit in '123456'.split('')) {
      await tester.tap(find.bySemanticsLabel('Digit $digit'));
      await tester.pump();
    }
  }
  await _advance(tester);
  expect(find.byType(MobileCustomiseAccountScreen), findsOneWidget);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MobileCustomiseAccountScreen)),
  );
  expect(container.read(accountProvider).value?.hasAccounts, isFalse);
}

void main() {
  setUpAll(loadFigmaCompareFonts);
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channelName in [
      'window_manager',
      'com.zcash.wallet/privacy_exposure',
      'com.zcash.wallet/privacy_shield',
    ]) {
      final channel = MethodChannel(channelName);
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'isFocused' ? true : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
  });
  testWidgets('checking hides both card artwork and amount', (tester) async {
    await _render(tester, buildMobileGiftOnboardingChecking);
    await _advance(tester);
    expect(find.byType(PaymentLinkLoadingMobileCard), findsOneWidget);
    expect(find.byType(PaymentLinkGiftCard), findsNothing);
    expect(find.text('4.45'), findsNothing);
    expect(find.byKey(const ValueKey('gift_claim_close_button')), findsNothing);
  });

  testWidgets('the old card preview opens the existing warning sheet', (
    tester,
  ) async {
    await _render(tester, buildMobileGiftOnboardingLongSyncWarning);
    await _advance(tester);

    expect(find.byType(PaymentLinkLongSyncWarningSheet), findsOneWidget);
    expect(find.byType(PaymentLinkGiftCard), findsNothing);
    expect(find.byType(PaymentLinkLoadingMobileCard), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('payment_link_long_sync_sheet_cancel_button')),
    );
    await _advance(tester);
    expect(find.byType(PaymentLinkLongSyncWarningSheet), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_welcome_redeem_card')),
      findsOneWidget,
    );
  });
  testWidgets('full gift setup waits for name and carries it to Home', (
    tester,
  ) async {
    await _render(tester, buildMobileGiftOnboardingWalkthrough);
    await _reachCustomise(tester);
    expect(find.bySemanticsLabel('Back'), findsNothing);
    expect(find.text('Skip for now'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('mobile_customise_account_name_field')),
      'My gift wallet',
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await _advance(tester);
    expect(find.byType(MobileBiometricsScreen), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MobileBiometricsScreen)),
    );
    expect(
      container.read(accountProvider).value?.activeAccount?.name,
      'My gift wallet',
    );
    final store = container.read(paymentLinkReceivedStoreProvider);
    final submitted = (await store.load()).single;
    expect(submitted.status, PaymentLinkReceivedStatus.receiving);
    expect(submitted.destinationAccountUuid, 'gift-preview');
    expect(submitted.claimTxids, isNotEmpty);
    final pendingIndex = await container.read(
      giftCardActivityIndexProvider('gift-preview').future,
    );
    final stableId = pendingIndex.withPendingClaims(const []).single;
    expect(pendingIndex.metadataFor(stableId)!.isClaimInFlight, isTrue);
    await tester.tap(find.byKey(const ValueKey('mobile_biometrics_enable')));
    await _advance(tester);
    expect(container.read(biometricUnlockProvider).value?.enabled, isTrue);
    expect(find.text('My gift wallet'), findsWidgets);
    expect(find.text('Redeeming a card...'), findsOneWidget);
    expect(find.text('No activity'), findsNothing);
    expect(find.byKey(const ValueKey('mobile_home_send')), findsNothing);
    final receive = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_home_receive')),
    );
    expect(receive.onPressed, isNotNull);
    expect(find.byKey(const ValueKey('mobile_home_pay')), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await _advance(tester);
    expect(
      (await store.load()).single.status,
      PaymentLinkReceivedStatus.received,
    );
    expect(find.text('Redeemed a gift card'), findsOneWidget);
    final receivedIndex = await container.read(
      giftCardActivityIndexProvider('gift-preview').future,
    );
    final received = container
        .read(syncProvider)
        .requireValue
        .recentTransactions
        .single;
    expect(received.txidHex, submitted.claimTxids);
    expect(received.displayAmount, submitted.amountZatoshi);
    expect(
      receivedIndex.metadataFor(received)!.stableId,
      pendingIndex.metadataFor(stableId)!.stableId,
    );
    expect(find.byKey(const ValueKey('mobile_home_backup')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('mobile_home_carousel_indicator_1')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('mobile_home_zcash_education')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('mobile_home_zcash_education')));
    await _advance(tester);
    expect(find.text('The Shielded World'), findsOneWidget);
    expect(find.byType(MobileCustomiseAccountScreen), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mobile_intro_skip')));
    await _advance(tester);
    expect(find.text('My gift wallet'), findsWidgets);
    expect(
      find.byKey(const ValueKey('mobile_home_zcash_education')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('mobile_home_backup')));
    await _advance(tester);
    await tester.tap(
      find.byKey(const ValueKey('mobile_seed_backup_intro_continue')),
    );
    await _advance(tester);
    // The same enabled Face ID state is retained through the Home preview.
    expect(find.bySemanticsLabel('Digit 1'), findsNothing);
    expect(find.text('September 1, 2026'), findsOneWidget);
    expect(find.text('3000000'), findsOneWidget);
    final backedUp = find.byKey(const ValueKey('mobile_seed_backed_up'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await _advance(tester);
    await tester.ensureVisible(backedUp);
    await tester.tap(backedUp);
    await _advance(tester);
    expect(find.text('My gift wallet'), findsWidgets);
    expect(find.byKey(const ValueKey('mobile_home_backup')), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_home_zcash_education')),
      findsNothing,
    );
  });
  testWidgets('gift setup can randomise and continue with the suggested name', (
    tester,
  ) async {
    await _render(tester, buildMobileGiftOnboardingWalkthrough);
    await _reachCustomise(tester);
    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_randomise')),
    );
    await tester.pump();
    final name = tester
        .widget<TextField>(
          find.byKey(const ValueKey('mobile_customise_account_name_field')),
        )
        .controller!
        .text;
    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await _advance(tester);
    expect(find.byType(MobileCustomiseAccountScreen), findsNothing);
    expect(find.byType(MobileBiometricsScreen), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MobileBiometricsScreen)),
    );
    final card =
        (await container.read(paymentLinkReceivedStoreProvider).load()).single;
    expect(card.status, PaymentLinkReceivedStatus.receiving);
    expect(card.setupAccountUuid, 'gift-preview');
    expect(await container.read(giftClaimImportStoreProvider).load(), isNull);
    await tester.tap(find.byKey(const ValueKey('mobile_biometrics_not_now')));
    await _advance(tester);
    expect(find.text(name), findsWidgets);
    expect(find.byKey(const ValueKey('mobile_home_backup')), findsOneWidget);
  });
  testWidgets('a pre-account error retains the entered name', (tester) async {
    await _render(tester, buildMobileGiftOnboardingSubmissionError);
    await _reachCustomise(tester);
    await tester.enterText(
      find.byKey(const ValueKey('mobile_customise_account_name_field')),
      'Keep this name',
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await _advance(tester);
    expect(find.byType(MobileCustomiseAccountScreen), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep this name',
    );
  });
  testWidgets(
    'remind later hides the backup banner and keeps education pending',
    (tester) async {
      await _render(tester, buildMobileGiftOnboardingWalkthrough);
      await _reachCustomise(tester);
      await tester.tap(
        find.byKey(const ValueKey('mobile_customise_account_continue')),
      );
      await _advance(tester);
      await tester.tap(find.byKey(const ValueKey('mobile_biometrics_not_now')));
      await _advance(tester);
      await tester.tap(find.byKey(const ValueKey('mobile_home_backup')));
      await _advance(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.text('Remind me later')),
      );
      await tester.tap(
        find.byKey(const ValueKey('mobile_seed_backup_remind_later')),
      );
      await _advance(tester);
      final account = container
          .read(accountProvider)
          .requireValue
          .activeAccount!;
      expect(account.setupPending, isTrue);
      expect(account.backupReminderSnoozeCount, 1);
      expect(account.giftEducationPending, isTrue);
      expect(find.byKey(const ValueKey('mobile_home_backup')), findsNothing);
      expect(
        find.byKey(const ValueKey('mobile_home_zcash_education')),
        findsOneWidget,
      );
    },
  );
  testWidgets('claim failure preview waits for Home and opens its Card', (
    tester,
  ) async {
    await _render(tester, buildMobileGiftOnboardingClaimFailure);
    await _advance(tester);
    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await _advance(tester);
    expect(find.byType(MobileBiometricsScreen), findsOneWidget);
    expect(find.text('Couldn’t redeem your gift card.'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mobile_biometrics_not_now')));
    await _advance(tester);
    expect(find.text('Couldn’t redeem your gift card.'), findsOneWidget);
    expect(find.text('Gift card redemption failed'), findsNothing);
    await tester.tap(find.text('View card'));
    await _advance(tester);
    expect(find.text('Couldn’t redeem your gift card.'), findsNothing);
  });

  testWidgets(
    'storage recovery preview retries without recreating the wallet',
    (tester) async {
      await _render(tester, buildMobileGiftOnboardingStorageRecovery);
      await _advance(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MobileCustomiseAccountScreen)),
      );
      final button = find.byKey(
        const ValueKey('mobile_customise_account_continue'),
      );
      await tester.tap(button);
      await _advance(tester);
      expect(
        find.text('Couldn’t finish saving your wallet. Try again.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(MobileBiometricsScreen), findsNothing);
      expect(container.read(accountProvider).value!.accounts, hasLength(1));
      expect(
        await container.read(paymentLinkReceivedStoreProvider).load(),
        isEmpty,
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('mobile_customise_account_name_field')),
            )
            .enabled,
        isFalse,
      );

      await tester.tap(button);
      await _advance(tester);
      expect(find.byType(MobileBiometricsScreen), findsOneWidget);
      expect(container.read(accountProvider).value!.accounts, hasLength(1));
      final record =
          (await container.read(paymentLinkReceivedStoreProvider).load())
              .single;
      expect(record.setupAccountUuid, 'gift-preview');
      expect(record.status, PaymentLinkReceivedStatus.receiving);
    },
  );

  for (final confirm in [true, false]) {
    testWidgets(
      'imported receiving account preview ${confirm ? 'claims into Savings' : 'keeps a dismissed card unclaimed'}',
      (tester) async {
        await _render(tester, buildMobileGiftOnboardingImportAccounts);
        for (var round = 0; round < 2; round++) {
          for (final digit in '123456'.split('')) {
            await tester.tap(find.bySemanticsLabel('Digit $digit'));
            await tester.pump();
          }
        }
        await _advance(tester);
        expect(find.text('Choose receiving account'), findsOneWidget);
        expect(find.text('Personal wallet'), findsOneWidget);
        expect(find.text('Savings'), findsOneWidget);
        final container = ProviderScope.containerOf(
          tester.element(find.text('Savings')),
        );
        expect(
          container.read(appSecurityProvider).isPasswordConfigured,
          isTrue,
        );
        expect(
          (await container.read(paymentLinkReceivedStoreProvider).load())
              .single
              .setupAccountUuid,
          isNull,
        );
        if (confirm) {
          await tester.tap(
            find.byKey(
              const ValueKey('payment_link_claim_account_gift-import-1'),
            ),
          );
          await tester.tap(
            find.byKey(const ValueKey('payment_link_claim_account_confirm')),
          );
        } else {
          await tester.tap(find.bySemanticsLabel('Close'));
        }
        await _advance(tester);
        expect(find.byType(MobileBiometricsScreen), findsOneWidget);
        final record =
            (await container.read(paymentLinkReceivedStoreProvider).load())
                .single;
        expect(record.setupAccountUuid, confirm ? 'gift-import-1' : isNull);
        expect(
          record.status,
          confirm
              ? PaymentLinkReceivedStatus.receiving
              : PaymentLinkReceivedStatus.readyToClaim,
        );
        expect(
          await container.read(giftClaimImportStoreProvider).load(),
          isNull,
        );
      },
    );
  }

  testWidgets('an existing wallet import returns to the inspected gift', (
    tester,
  ) async {
    await _render(tester, buildMobileGiftOnboardingWalkthrough);
    await tester.tap(find.byKey(const ValueKey('mobile_welcome_redeem_card')));
    await _advance(tester);
    await tester.tap(
      find.byKey(const ValueKey('payment_link_mobile_paste_button')),
    );
    await _advance(tester);
    await tester.tap(find.text('Claim with an existing wallet'));
    await _advance(tester);
    await tester.tap(find.byKey(const ValueKey('mobile_import_passphrase')));
    await _advance(tester);
    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await _advance(tester);
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_review_continue')),
    );
    await _advance(tester);
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_birthday_mode_height')),
    );
    await _advance(tester);
    await tester.enterText(
      find.byKey(const ValueKey('mobile_import_birthday_height')),
      '3000000',
    );
    await _advance(tester);
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_birthday_continue')),
    );
    await _advance(tester);
    for (var round = 0; round < 2; round++) {
      for (final digit in '123456'.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $digit'));
        await tester.pump();
      }
    }
    await _advance(tester);
    await tester.enterText(
      find.byKey(const ValueKey('mobile_customise_account_name_field')),
      'My imported wallet',
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await _advance(tester);
    expect(find.byType(MobileBiometricsScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mobile_biometrics_not_now')));
    await _advance(tester);
    expect(find.text('My imported wallet'), findsWidgets);
    expect(find.byType(MobileCustomiseAccountScreen), findsNothing);
  });
}
