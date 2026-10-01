import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../providers/payment_link_claim_coordinator_provider.dart';
import '../providers/payment_link_intake_provider.dart';
import 'gift_wallet_setup.dart';
import 'payment_link_service.dart';

/// Commits account setup before handing the checked Card to the claim runner.
/// Face ID and Home do not wait for binding, broadcast, or confirmations.
Future<void> completeGiftClaimWalletSetup(
  WidgetRef ref, {
  required String password,
  required String accountName,
  required String profilePictureId,
  required PaymentLinkClaimInspection inspection,
  required void Function() onComplete,
}) {
  final coordinator = ref.read(paymentLinkClaimCoordinatorProvider);
  final intake = ref.read(paymentLinkIntakeProvider.notifier);
  return ref.read(routerRefreshProvider).pauseWhile(() async {
    final String accountUuid;
    try {
      accountUuid = await setUpGiftCardWallet(
        ref,
        passcode: password,
        link: inspection.link,
        accountName: accountName,
        profilePictureId: profilePictureId,
      );
    } on GiftClaimAccountCreatedException catch (error) {
      // An account may already exist. The setup journal owns recovery; never
      // offer account creation again or roll back its committed credential.
      if (error.accountUuid == null) {
        throw WalletAccountStateUncertainException(error.cause);
      }
      intake.discard(inspection.link);
      onComplete();
      return;
    }
    intake.discard(inspection.link);
    unawaited(
      coordinator
          .claimSetupCard(inspection, destinationAccountUuid: accountUuid)
          .catchError((Object error) {
            // The durable Card stays in Received for the existing recovery.
            log('GiftClaimSetup: claim needs recovery: ${error.runtimeType}');
          }),
    );
    onComplete();
  });
}
