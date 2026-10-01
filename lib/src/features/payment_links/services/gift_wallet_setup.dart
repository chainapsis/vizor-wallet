import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../models/vizor_payment_link.dart';

/// Creates and durably records a first wallet for a checked Gift Card.
/// The caller pauses router refresh while this transaction is in progress.
/// Submission and receiving-account binding happen after this boundary.
Future<String> setUpGiftCardWallet(
  WidgetRef ref, {
  required String passcode,
  required VizorPaymentLink link,
  required String accountName,
  required String profilePictureId,
}) async {
  final security = ref.read(appSecurityProvider.notifier);
  final accounts = ref.read(accountProvider.notifier);
  await security.prepareGiftWalletPasswordSetup(passcode);
  final String uuid;
  try {
    uuid = await runWithSyncPausedForAccountMutation(
      ref,
      () => accounts.createGiftClaimAccount(
        name: accountName,
        profilePictureId: profilePictureId,
        link: link,
      ),
    );
  } catch (error) {
    // Preserve the credential if this attempt may have created an account.
    // The initial DB guard runs before creation and journal persistence, so
    // its failure can roll back the newly prepared password configuration.
    final accountMayExist =
        error is GiftClaimAccountCreatedException ||
        (ref.read(accountProvider).value?.hasAccounts ?? true);
    if (accountMayExist) {
      security.commitPasswordSetup();
    } else {
      await security.rollbackPasswordSetup();
    }
    rethrow;
  }
  security.commitPasswordSetup();
  try {
    await accounts.clearPendingGiftAccountSetup(accountUuid: uuid);
  } catch (error) {
    // The wallet and card are already durable. Retain the journal for unlock
    // recovery if cleanup cannot complete; do not invite account recreation.
    log('GiftWalletSetup: recovery journal cleanup failed: $error');
  }
  return uuid;
}
