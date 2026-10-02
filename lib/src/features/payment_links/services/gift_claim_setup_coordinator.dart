import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../providers/payment_link_claim_coordinator_provider.dart';
import '../providers/payment_link_intake_provider.dart';
import '../providers/gift_claim_flow_provider.dart';
import '../widgets/mobile/payment_link_claim_account_sheet.dart';
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
  String? createdAccountUuid,
}) {
  final coordinator = ref.read(paymentLinkClaimCoordinatorProvider);
  final intake = ref.read(paymentLinkIntakeProvider.notifier);
  final accounts = ref.read(accountProvider.notifier);
  final store = ref.read(paymentLinkReceivedStoreProvider);
  final flow = ref.read(giftClaimFlowProvider.notifier);
  flow.beginWalletSetup(inspection, passcode: password);
  return ref
      .read(routerRefreshProvider)
      .pauseWhile(
        () => coordinator.trackRetention(() async {
          var accountUuid = createdAccountUuid;
          var needsRecovery = accountUuid != null;
          if (accountUuid == null) {
            try {
              accountUuid = await setUpGiftCardWallet(
                ref,
                passcode: password,
                link: inspection.link,
                accountName: accountName,
                profilePictureId: profilePictureId,
              );
            } on GiftClaimAccountCreatedException catch (error) {
              final createdUuid = error.accountUuid;
              if (createdUuid == null) {
                throw WalletAccountStateUncertainException(error.cause);
              }
              accountUuid = createdUuid;
              needsRecovery = true;
            }
          }

          if (needsRecovery) {
            try {
              // The credential is already committed. Finish the existing account's
              // journal now; this unlocked session will not run unlock recovery.
              await accounts.recoverPendingAccountMnemonic();
              final saved = await store.find(inspection.link.address);
              if (saved?.setupAccountUuid != accountUuid ||
                  saved?.claimLink?.hasSameCanonicalPayload(inspection.link) !=
                      true) {
                throw StateError('Gift Card receiving account was not saved.');
              }
            } catch (error, stackTrace) {
              // Retain the UUID so the screen retries recovery, never creation.
              Error.throwWithStackTrace(
                GiftClaimAccountCreatedException(accountUuid, error),
                stackTrace,
              );
            }
          }

          intake.discard(inspection.link);
          unawaited(
            coordinator
                .claimSetupCard(inspection, destinationAccountUuid: accountUuid)
                .catchError((Object error) {
                  // The durable Card stays in Received for the existing recovery.
                  log(
                    'GiftClaimSetup: claim needs recovery: ${error.runtimeType}',
                  );
                }),
          );
          flow.finishWalletSetup(inspection);
          onComplete();
        }),
      );
}

/// Finishes the existing-wallet choice before Face ID, using the inspection
/// already performed on the Gift screen. Only restart recovery scans again.
Future<void> completeGiftClaimImportSetup(WidgetRef ref) async {
  final context = ref.context;
  final request = ref.read(giftClaimSetupReturnProvider);
  if (request == null) return;
  final accountState = ref.read(accountProvider).value;
  final accounts = [
    for (final account in accountState?.accounts ?? const <AccountInfo>[])
      if (!request.accountUuidsBeforeSetup.contains(account.uuid)) account,
  ];
  if (accounts.isEmpty) return;
  final coordinator = ref.read(paymentLinkClaimCoordinatorProvider);
  final journal = ref.read(giftClaimImportStoreProvider);
  final store = ref.read(paymentLinkReceivedStoreProvider);

  Future<void> finish(String? recipient) async {
    await coordinator.trackRetention(() async {
      await store.saveReady(request.link, setupAccountUuid: recipient);
      if (recipient != null) {
        // Register the existing inspection before clearing the live journal.
        // Recovery must not begin a second scan in between these operations.
        unawaited(
          coordinator
              .claimSetupCard(
                request.inspection,
                destinationAccountUuid: recipient,
              )
              .catchError((Object error) {
                log('Gift import claim needs recovery: ${error.runtimeType}');
              }),
        );
      }
      await journal.clear(request);
    });
    if (!context.mounted) return;
    if (!ref
        .read(giftClaimSetupReturnProvider.notifier)
        .clearIfMatches(request)) {
      return;
    }
    ref.read(paymentLinkIntakeProvider.notifier).discard(request.link);
  }

  try {
    if (accounts.length == 1) {
      await finish(accounts.single.uuid);
      return;
    }
    // Keep the card before showing a dismissible choice. An unbound Received
    // card is never automatically claimed by restart/resume recovery.
    await coordinator.trackRetention(() => store.saveReady(request.link));
    if (!context.mounted) return;
    final activeAccountUuid = accountState?.activeAccountUuid;
    final confirmed = await showPaymentLinkClaimAccountSheet(
      context: context,
      amountZatoshi: request.link.amountZatoshi,
      accounts: accounts,
      activeAccountUuid: accounts.any((a) => a.uuid == activeAccountUuid)
          ? activeAccountUuid!
          : accounts.first.uuid,
      onConfirm: (uuid) async {
        final current = ref.read(accountProvider).value;
        if (!identical(ref.read(giftClaimSetupReturnProvider), request) ||
            ref.read(appSecurityProvider).requiresUnlock ||
            current == null ||
            !accounts.any((a) => a.uuid == uuid) ||
            !current.accounts.any((a) => a.uuid == uuid)) {
          throw const PaymentLinkClaimDestinationChangedException();
        }
        if (current.activeAccountUuid != uuid) {
          await ref.read(accountProvider.notifier).switchAccount(uuid);
        }
        if (!context.mounted ||
            ref.read(appSecurityProvider).requiresUnlock ||
            ref.read(accountProvider).value?.activeAccountUuid != uuid) {
          throw const PaymentLinkClaimDestinationChangedException();
        }
        await finish(uuid);
      },
    );
    if (!confirmed && context.mounted) await finish(null);
  } catch (error) {
    // Import and password commit already succeeded. Preserve the journal and
    // let recovery bind the Card; never invite creation of another account.
    if (context.mounted) {
      ref.read(giftClaimSetupReturnProvider.notifier).clearIfMatches(request);
      ref.read(paymentLinkIntakeProvider.notifier).discard(request.link);
    }
    journal.releaseLiveHandoff();
    coordinator.resume();
    log('Gift import handoff needs recovery: ${error.runtimeType}');
  }
}
