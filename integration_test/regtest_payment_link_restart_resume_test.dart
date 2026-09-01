import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/core/storage/wallet_paths.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';

import 'support/desktop_regtest_flow.dart';
import 'support/payment_link_regtest_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(initializeZcashWalletRuntime);

  testWidgets(
    'recovers two Gift Card claims after a real process restart',
    (tester) async {
      addTearDown(() async {
        await Clipboard.setData(const ClipboardData(text: ''));
        await cleanupDesktopRegtestWallet();
        await deletePaymentLinkClaimWalletDirectories();
        await deletePaymentLinkRestartManifest();
      });

      final manifest = await readPaymentLinkRestartManifest();
      expect(manifest.claims, hasLength(2));
      for (final claim in manifest.claims) {
        expect(
          await (await paymentLinkClaimWalletDirectoryByName(
            claim.directoryName,
          )).exists(),
          isTrue,
        );
      }

      e2eLog('launching a new Flutter process with two retained claims');
      await tester.pumpWidget(await buildBootstrappedZcashWalletApp());
      await unlockDesktopRegtestWallet(tester);

      // Do not navigate to Gift Cards. Recovery must be owned by the app root
      // and start after unlock while the user remains on Home.
      expect(
        find.byKey(const ValueKey('payment_links_desktop_screen')),
        findsNothing,
      );

      final firstClaim = manifest.claims[0];
      final secondClaim = manifest.claims[1];
      await waitForPaymentLinkHistoryTransaction(
        tester,
        accountUuid: manifest.receiverAccountUuid,
        txKind: 'received',
        amount: firstClaim.amountZatoshi,
        pending: false,
      );
      await waitForPaymentLinkHistoryTransaction(
        tester,
        accountUuid: manifest.receiverAccountUuid,
        txKind: 'received',
        amount: secondClaim.amountZatoshi,
        pending: false,
      );

      final receivedRecords = await waitForReceivedRecords(
        tester,
        (records) => manifest.claims.every(
          (claim) => records.any(
            (record) =>
                record.address == claim.address &&
                record.status == PaymentLinkReceivedStatus.received,
          ),
        ),
        description: 'both retained claims to reach Received after restart',
        timeout: const Duration(minutes: 4),
      );
      expect(receivedRecords, hasLength(2));
      for (final claim in manifest.claims) {
        final record = receivedRecords.singleWhere(
          (candidate) => candidate.address == claim.address,
        );
        expect(record.claimLink, isNull);
        expect(record.claimTxids, isNotEmpty);
        final directory = await paymentLinkClaimWalletDirectoryByName(
          claim.directoryName,
        );
        expect(await directory.exists(), isFalse);
      }

      await waitForPaymentLinkAccountBalance(
        tester,
        accountUuid: manifest.receiverAccountUuid,
        total:
            manifest.receiverStartingTotal +
            firstClaim.amountZatoshi +
            secondClaim.amountZatoshi,
      );
      expect(
        find.byKey(const ValueKey('payment_links_desktop_screen')),
        findsNothing,
      );
      e2eLog('both retained claims recovered and deleted after restart');
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
