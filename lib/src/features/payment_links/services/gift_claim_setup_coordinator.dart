import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../providers/payment_link_claim_coordinator_provider.dart';
import '../providers/payment_link_intake_provider.dart';
import '../providers/gift_claim_flow_provider.dart';
import 'gift_claim_import_store.dart';
import 'payment_link_received_store.dart';
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

/// Finishes the existing-wallet choice before Face ID, using the inspection
/// already performed on the Gift screen. Only restart recovery scans again.
Future<void> completeGiftClaimImportSetup(WidgetRef ref) async {
  final request = ref.read(giftClaimSetupReturnProvider);
  if (request == null) return;
  final accounts = ref.read(accountProvider).value;
  final recipient = request.recipientAccountUuid(
    currentAccountUuids: accounts?.accounts.map((a) => a.uuid) ?? const [],
    activeAccountUuid: accounts?.activeAccountUuid,
  );
  if (recipient == null) return;
  final coordinator = ref.read(paymentLinkClaimCoordinatorProvider);
  final journal = ref.read(giftClaimImportStoreProvider);
  try {
    await coordinator.trackRetention(() async {
      await ref
          .read(paymentLinkReceivedStoreProvider)
          .saveReady(request.link, setupAccountUuid: recipient);
      await journal.clear(request);
    });
    if (!ref
        .read(giftClaimSetupReturnProvider.notifier)
        .clearIfMatches(request)) {
      return;
    }
    ref.read(paymentLinkIntakeProvider.notifier).discard(request.link);
    unawaited(
      coordinator
          .claimSetupCard(request.inspection, destinationAccountUuid: recipient)
          .catchError((Object error) {
            log('Gift import claim needs recovery: ${error.runtimeType}');
          }),
    );
  } catch (error) {
    // Import and password commit already succeeded. Preserve the journal and
    // let recovery bind the Card; never invite creation of another account.
    ref.read(giftClaimSetupReturnProvider.notifier).clearIfMatches(request);
    ref.read(paymentLinkIntakeProvider.notifier).discard(request.link);
    journal.releaseLiveHandoff();
    coordinator.resume();
    log('Gift import handoff needs recovery: ${error.runtimeType}');
  }
}
