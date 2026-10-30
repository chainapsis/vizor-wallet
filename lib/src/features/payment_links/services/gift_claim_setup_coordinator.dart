import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../../../main.dart' show log;
import '../../../core/input/app_password_input_source.dart';
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
  required String? password,
  required String accountName,
  required String profilePictureId,
  required PaymentLinkClaimInspection inspection,
  required void Function() onComplete,
  String? createdAccountUuid,
  PasswordInputSourceCandidate? passwordInputSource,
}) {
  final coordinator = ref.read(paymentLinkClaimCoordinatorProvider);
  final intake = ref.read(paymentLinkIntakeProvider.notifier);
  final accounts = ref.read(accountProvider.notifier);
  final store = ref.read(paymentLinkReceivedStoreProvider);
  final flow = ref.read(giftClaimFlowProvider.notifier);
  final inputSourceService = ref.read(appPasswordInputSourceProvider);
  flow.beginWalletSetup(
    inspection,
    passcode: password,
    passwordInputSource: passwordInputSource,
  );
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

          if (password != null) {
            unawaited(inputSourceService.remember(passwordInputSource));
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
          flow.finishWalletSetup(inspection, handedOff: true);
          onComplete();
        }),
      );
}

/// Finishes the existing-wallet choice before Face ID, using the inspection
/// already performed on the Gift screen. Only restart recovery scans again.
Future<void> completeGiftClaimImportSetup(WidgetRef ref) =>
    _completeGiftClaimImportSetup(ref.read, ref.context);

/// Desktop route callbacks share the same durable import handoff.
Future<void> completeGiftClaimImportSetupForRoute(
  Ref ref,
  BuildContext context,
) => _completeGiftClaimImportSetup(ref.read, context);

Future<void> _completeGiftClaimImportSetup(
  T Function<T>(ProviderListenable<T> provider) read,
  BuildContext context,
) async {
  final request = read(giftClaimSetupReturnProvider);
  if (request == null) return;
  final accountState = read(accountProvider).value;
  final accounts = [
    for (final account in accountState?.accounts ?? const <AccountInfo>[])
      if (!request.accountUuidsBeforeSetup.contains(account.uuid)) account,
  ];
  if (accounts.isEmpty) return;
  final coordinator = read(paymentLinkClaimCoordinatorProvider);
  final journal = read(giftClaimImportStoreProvider);
  final flow = read(giftClaimFlowProvider.notifier);
  final store = read(paymentLinkReceivedStoreProvider);

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
      flow.finishImportSetup(request.inspection);
    });
    if (!context.mounted) return;
    if (!read(giftClaimSetupReturnProvider.notifier).clearIfMatches(request)) {
      return;
    }
    read(paymentLinkIntakeProvider.notifier).discard(request.link);
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
        final current = read(accountProvider).value;
        if (!identical(read(giftClaimSetupReturnProvider), request) ||
            read(appSecurityProvider).requiresUnlock ||
            current == null ||
            !accounts.any((a) => a.uuid == uuid) ||
            !current.accounts.any((a) => a.uuid == uuid)) {
          throw const PaymentLinkClaimDestinationChangedException();
        }
        if (current.activeAccountUuid != uuid) {
          await read(accountProvider.notifier).switchAccount(uuid);
        }
        if (!context.mounted ||
            read(appSecurityProvider).requiresUnlock ||
            read(accountProvider).value?.activeAccountUuid != uuid) {
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
      read(giftClaimSetupReturnProvider.notifier).clearIfMatches(request);
      read(paymentLinkIntakeProvider.notifier).discard(request.link);
    }
    journal.releaseLiveHandoff();
    flow.finishImportSetup(request.inspection);
    coordinator.resume();
    log('Gift import handoff needs recovery: ${error.runtimeType}');
  }
}
