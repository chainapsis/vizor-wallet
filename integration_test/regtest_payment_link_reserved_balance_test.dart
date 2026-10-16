import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_hardware_signing_service.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_service.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'support/desktop_regtest_flow.dart';
import 'support/payment_link_regtest_flow.dart';

const _balanceKey = ValueKey('home_desktop_balance_amount_text');
final _funded = BigInt.from(125_000_000);

// A Gift Card funding that is prepared and proved but never signed holds the
// whole balance under an unsigned reservation. This is the state a Ledger user
// is in while the device waits for approval (#721): Home must keep showing the
// funds as held, and cancelling must release them.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets('Home keeps unsigned Gift Card reservations in the balance', (
    tester,
  ) async {
    addTearDown(() async {
      await cleanupDesktopRegtestWallet();
      await cleanupRegtestPaymentLinkClaimWallets();
    });

    await cleanupDesktopRegtestWallet();
    await cleanupRegtestPaymentLinkClaimWallets();

    await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
    await importDesktopRegtestWallet(tester);
    final account = await firstDesktopRegtestAccountUuid();
    await waitForForegroundSyncIdle(tester);
    await waitForPaymentLinkAccountBalance(
      tester,
      accountUuid: account,
      total: _funded,
      spendable: _funded,
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ZcashWalletApp)),
    );
    expect(_homeBalanceText(tester), '1.25');

    // The same calls Ledger's prepare and prove make; signing never happens.
    final hardware = container.read(paymentLinkHardwareSigningServiceProvider);
    final draft = await hardware.createFundingPczt(
      amountZatoshi: BigInt.from(10_000_000),
      sourceAccountUuid: account,
    );
    await hardware.addProofsForSigning(draft: draft);

    // A new block drives the ordinary sync that used to show 0.
    await minePaymentLinkRegtestBlocks(1);
    final height = await paymentLinkZcashdRpc<int>('getblockcount');
    await pumpUntil(
      tester,
      () {
        final sync = container.read(syncProvider).value;
        return sync != null && sync.chainTipHeight >= height && !sync.isSyncing;
      },
      description: 'sync to height $height',
      timeout: const Duration(minutes: 3),
    );
    await _settle(tester);

    final reserved = await readPaymentLinkAccountBalance(account);
    e2eLog(
      'reserved: held=${reserved.held} locked=${reserved.locked} '
      'historyHold=${reserved.historyHold} spendable=${reserved.spendable} '
      'home=${_homeBalanceText(tester)}',
    );
    expect(reserved.held, _funded);
    expect(
      reserved.saplingHeld + reserved.orchardHeld + reserved.ironwoodHeld,
      _funded,
    );
    expect(reserved.locked, BigInt.zero);
    expect(reserved.historyHold, BigInt.zero);
    expect(reserved.spendable, BigInt.zero);
    expect(reserved.total, _funded);
    expect(_homeBalanceText(tester), '1.25');

    // What the signing overlay's Cancel does.
    await hardware.discardPcztDraft(draft: draft);
    await container.read(syncProvider.notifier).refreshAfterSend();
    await waitForForegroundSyncIdle(tester);
    await _settle(tester);

    final released = await readPaymentLinkAccountBalance(account);
    expect(released.held, BigInt.zero);
    expect(released.spendable, _funded);
    expect(_homeBalanceText(tester), '1.25');
    expect(
      await container
          .read(paymentLinkOperationsProvider)
          .loadCreatedLinkRecoveries(),
      isEmpty,
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

String? _homeBalanceText(WidgetTester tester) {
  final finder = find.byKey(_balanceKey);
  if (!tester.any(finder)) return null;
  return tester.widget<Text>(finder).data;
}
