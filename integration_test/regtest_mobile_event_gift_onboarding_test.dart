@Tags(['mobile'])
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';

import 'support/mobile_regtest_flow.dart';

/// Runs only with a separately funded card from create_mobile_event_fixture.
/// All UI, wallet creation, proof generation and receiving sync are real.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeZcashWalletRuntime);

  testWidgets('claims an event card while creating the first mobile wallet', (
    tester,
  ) async {
    const encoded = String.fromEnvironment('VIZOR_EVENT_GIFT_FIXTURE');
    expect(
      encoded,
      isNotEmpty,
      reason: 'Pass the base64-encoded regtest fixture.',
    );
    final data =
        jsonDecode(utf8.decode(base64Decode(encoded))) as Map<String, dynamic>;
    expect(data['network'], 'regtest');
    final link = VizorPaymentLink(
      network: 'regtest',
      address: '',
      mnemonic: data['mnemonic'] as String,
      birthdayHeight: data['birthdayHeight'] as int,
      amountZatoshi: BigInt.parse(data['amountZatoshi'] as String),
      fundingTxid: data['fundingTxid'] as String,
      skipScan: true,
      label: 'Event gift card',
      createdAt: DateTime.now().toUtc(),
    );
    await cleanupE2eWalletState();
    await cleanupMobileE2ePaymentLinkClaimWallets();
    await AppSecureStore.instance.writePlain(
      kRpcEndpointUrlKey,
      mobileE2eLightwalletdUrl,
    );
    await AppSecureStore.instance.writePlain(
      kRpcEndpointPresetKey,
      kCustomRpcEndpointPresetId,
    );
    addTearDown(() async {
      await Clipboard.setData(const ClipboardData(text: ''));
      await cleanupE2eWalletState();
      await cleanupMobileE2ePaymentLinkClaimWallets();
    });
    await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
    await pumpUntil(
      tester,
      () =>
          tester.any(find.byKey(const ValueKey('mobile_welcome_redeem_card'))),
      description: 'welcome to render',
    );
    logE2e('EVENT_WALKTHROUGH_READY');
    await settle(tester, const Duration(seconds: 8));
    await Clipboard.setData(ClipboardData(text: link.toShareUri().toString()));
    await tapWidget(tester, const ValueKey('mobile_welcome_redeem_card'));
    await tapWidget(tester, const ValueKey('payment_link_mobile_paste_button'));
    await pumpUntil(
      tester,
      () => tester.any(
        find.byKey(const ValueKey('gift_claim_create_a_wallet_to_claim')),
      ),
      description: 'the actual funded card inspection',
      timeout: const Duration(minutes: 2),
    );
    await settle(tester, const Duration(seconds: 2));
    await tapWidget(
      tester,
      const ValueKey('gift_claim_create_a_wallet_to_claim'),
      timeout: const Duration(minutes: 2),
    );
    await enterPasscode(tester, mobileE2ePasscode);
    await enterPasscode(tester, mobileE2ePasscode);
    await settle(tester, const Duration(seconds: 2));
    await tapAppButton(
      tester,
      const ValueKey('mobile_customise_account_continue'),
    );
    await tapWidget(
      tester,
      const ValueKey('mobile_biometrics_not_now'),
      timeout: const Duration(minutes: 2),
    );
    await waitForHome(tester);
    final submissionDeadline = DateTime.now().add(const Duration(minutes: 3));
    while ((await zcashdRpc<List<Object?>>('getrawmempool')).isEmpty) {
      if (DateTime.now().isAfter(submissionDeadline)) {
        fail('The actual claim was not accepted into the node mempool.');
      }
      await settle(tester, const Duration(milliseconds: 250));
    }
    await mineRegtestBlocks(10);
    await waitForShieldedBalance(tester, '0.50 $mobileE2eTicker');
    await pumpUntil(
      tester,
      () => tester.any(find.text('Redeemed a gift card')),
      description: 'the redeemed gift activity on Home',
    );
    await settle(tester, const Duration(seconds: 4));
    logE2e('EVENT_WALKTHROUGH_RECEIVED');
    await settle(tester, const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(minutes: 8)));
}
