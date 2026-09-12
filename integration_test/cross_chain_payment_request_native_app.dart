import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/pay/widgets/cross_chain_payment_request_card.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_state_provider.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_zec_staging_address_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/payment_uri_prefill_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'support/cross_chain_payment_native_fixture.dart';

const _driverUrl = String.fromEnvironment('VIZOR_PAYMENT_E2E_DRIVER_URL');
const _bundleId = String.fromEnvironment('VIZOR_PAYMENT_E2E_BUNDLE_ID');
const _continue = ValueKey('cross_chain_payment_request_continue');
const _cancel = ValueKey('cross_chain_payment_request_cancel');

/// Built and cold-launched by the dedicated runner, not a Flutter test driver.
/// Both initial and later URLs come through Launch Services / AppDelegate.
void main() {
  if (!Platform.isMacOS ||
      !_bundleId.startsWith('com.keplr.vizor.payment-e2e.') ||
      !Uri.parse(_driverUrl).host.startsWith('127.0.0.1')) {
    throw StateError(
      'Run scripts/e2e/flutter-macos-cross-chain-payment-request.py',
    );
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  unawaited(
    binding.allTestsPassed.future.then((passed) async {
      await _driver('result', {
        'passed': passed,
        'results': binding.results.map((key, value) => MapEntry(key, '$value')),
      });
      exit(passed ? 0 : 1);
    }),
  );

  testWidgets(
    'native cold and warm payment URLs reach review safely',
    (tester) async {
      await _driver('ready', {'pid': pid});
      FlutterSecureStorage.setMockInitialValues({});
      await initializeZcashWalletRuntime();
      // Wallet storage is an in-memory fixture; password verification still
      // uses AppSecurityNotifier and Rust. Never access a user's Keychain.
      final store = AppSecureStore.testing(
        storage: const FlutterSecureStorage(),
      );
      await store.configurePassword(nativePaymentPassword);
      store.clearSessionPassword();
      final pricing = NativePaymentPricing();
      final privacy = NativePaymentPrivacy();
      await tester.pumpWidget(
        buildZcashWalletApp(
          bootstrap: nativePaymentBootstrap(),
          overrides: [
            accountProvider.overrideWith(NativePaymentAccount.new),
            syncProvider.overrideWith(NativePaymentSync.new),
            appSecurityProvider.overrideWith(
              () => AppSecurityNotifier.testing(store: store),
            ),
            networkPrivacyProvider.overrideWith(() => privacy),
            swapIntentProvider.overrideWithValue(pricing),
            swapZecStagingAddressServiceProvider.overrideWithValue(
              SwapZecStagingAddressService(
                reserveFreshOrchardAddress: ({required accountUuid}) async =>
                    'u1e2e-refund-address',
              ),
            ),
          ],
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ZcashWalletApp)),
      );
      await _until(
        tester,
        () => container.read(paymentUriPrefillProvider) != null,
        'cold-launch URL parked by the native bridge and real Rust parser',
      );
      expect(
        find.byKey(const ValueKey('unlock_password_field')),
        findsOneWidget,
      );
      expect(find.byType(CrossChainPaymentRequestCard), findsNothing);
      await _driver('milestone', {'name': 'cold URL retained behind lock'});

      await tester.enterText(
        find.byKey(const ValueKey('unlock_password_field')),
        nativePaymentPassword,
      );
      await _tap(tester, const ValueKey('unlock_submit_button'));
      await _until(
        tester,
        () => tester.any(find.text('Connecting to Tor…')),
        'Tor loading card after unlock',
      );
      expect(
        find.byKey(const ValueKey('payment_request_icon_skeleton')),
        findsOneWidget,
      );
      expect(_button(tester, _continue).onPressed, isNull);
      privacy.setStatus(NetworkPrivacyConnectionStatus.connected);
      await _until(
        tester,
        () => tester.any(find.text('Checking payment options…')),
        'token loading after Tor connects',
      );
      expect(
        find.byKey(const ValueKey('payment_request_amount_skeleton')),
        findsOneWidget,
      );
      pricing.releaseTokens();
      await _until(
        tester,
        () => _button(tester, _continue).onPressed != null,
        'resolved Bitcoin card',
      );
      expect(find.text('0.00123456'), findsOneWidget);
      expect(find.text('BTC'), findsOneWidget);
      expect(find.text('Bitcoin'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payment_request_icon_skeleton')),
        findsNothing,
      );
      await _tap(tester, _cancel);
      await _until(
        tester,
        () => !tester.any(find.byType(CrossChainPaymentRequestCard)),
        'cancelled card',
      );
      expect(pricing.quotes, isEmpty);
      await _driver('milestone', {
        'name': 'unlock and Tor/token loading resolved; cancel did not quote',
      });

      privacy.setStatus(NetworkPrivacyConnectionStatus.connecting);
      await _driver('open', {'uri': nativeEthereumUri});
      await _until(
        tester,
        () => tester.any(find.text('Connecting to Tor…')),
        'warm Ethereum URL',
      );
      privacy.setStatus(NetworkPrivacyConnectionStatus.failed);
      await _until(
        tester,
        () => tester.any(find.text('Try again')),
        'Tor failure retry action',
      );
      await _tap(tester, _continue);
      expect(privacy.retries, 1);
      await _until(
        tester,
        () => tester.any(find.text('Connecting to Tor…')),
        'retry loading',
      );
      privacy.setStatus(NetworkPrivacyConnectionStatus.connected);
      await _until(
        tester,
        () =>
            tester.any(find.text('Review payment')) &&
            _button(tester, _continue).onPressed != null,
        'resolved Base USDC request',
      );
      expect(find.text('25'), findsOneWidget);
      expect(find.text('USDC'), findsOneWidget);
      expect(find.text('Base'), findsOneWidget);
      await _tap(tester, _continue);
      await _until(
        tester,
        () => tester.any(find.byKey(const ValueKey('pay_review_step'))),
        'real Pay review',
      );
      expect(pricing.quotes, hasLength(1));
      final quote = pricing.quotes.single;
      expect(quote.destination, nativePaymentRecipient);
      expect(quote.externalAsset, nativeUsdcAsset);
      expect(quote.amount, 25);
      expect(find.byType(CrossChainPaymentRequestCard), findsNothing);
      await _tap(
        tester,
        const ValueKey('pay_wizard_back_link'),
        appButton: false,
      );
      await _until(
        tester,
        () => tester.any(find.byKey(const ValueKey('pay_recipient_step'))),
        'Back to preserved Pay recipient',
      );
      expect(
        container.read(swapStateProvider).destinationText,
        nativePaymentRecipient,
      );
      expect(container.read(swapStateProvider).receiveAmountText, '25');
      expect(pricing.quotes, hasLength(1));
      await _driver('milestone', {
        'name':
            'warm URL, Tor retry, exact asset/amount/address review and Back passed',
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

AppButton _button(WidgetTester tester, Key key) =>
    tester.widget<AppButton>(find.byKey(key));

Future<void> _tap(WidgetTester tester, Key key, {bool appButton = true}) async {
  await _until(
    tester,
    () =>
        tester.any(find.byKey(key)) &&
        (!appButton || _button(tester, key).onPressed != null),
    'enabled $key',
  );
  await tester.ensureVisible(find.byKey(key));
  await tester.tap(find.byKey(key));
  await tester.pump();
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String description,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _driver(String action, Map<String, Object?> data) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse('$_driverUrl/$action'));
    request.headers.contentType = ContentType.json;
    final body = utf8.encode(jsonEncode(data));
    request.contentLength = body.length;
    request.add(body);
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode != 200) {
      throw StateError('Native driver $action failed: ${response.statusCode}');
    }
  } finally {
    client.close(force: true);
  }
}
