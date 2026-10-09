import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_bootstrap.dart';
import '../../../core/input/app_password_input_source.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/storage/linux_keyring_coordinator.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../payment_links/providers/gift_claim_flow_provider.dart';
import '../../payment_links/services/gift_claim_setup_coordinator.dart';
import 'customise_account_mutation.dart';
import 'onboarding_flow_args.dart';
import '../../../../main.dart' show log;

/// Keeps interrupted durable setup from retrying account creation.
/// Owned by the final credential screen and discarded when that screen leaves.
class AccountSetupSubmission {
  bool requiresRecovery = false;

  Future<void> run(WidgetRef ref, Future<void> Function() action) async {
    await ref.read(routerRefreshProvider).pauseWhile(() async {
      try {
        await action();
      } catch (error) {
        if (error is WalletAccountSetupInterruptedException ||
            error is WalletAccountStateUncertainException) {
          requiresRecovery = true;
          if (ref.read(appSecurityProvider).requiresUnlock) {
            await recover(ref);
            return;
          }
        }
        rethrow;
      }
    });
  }

  Future<void> recover(WidgetRef ref) async {
    // Bootstrap inspects durable account/credential journals. Never submit a
    // second account when a prior attempt may already have written the DB.
    final reload = ref.read(appBootstrapRetryProvider);
    ref.read(appSecurityProvider.notifier).lock();
    await ref.read(routerRefreshProvider).pauseWhile(reload);
  }
}

/// Persist the first account only after both persona and credential are ready.
/// The prepare -> account -> commit ordering protects encrypted mnemonic writes.
Future<void> finishPersonalisedAccountSetup(
  WidgetRef ref, {
  required SetPasswordScreenArgs args,
  required String password,
  PasswordInputSourceCandidate? passwordInputSource,
  VoidCallback? onStoppingSync,
  VoidCallback? onSyncPaused,
}) async {
  final persona = args.persona;
  if (persona == null) throw StateError('Account personalisation is missing.');
  final router = GoRouter.of(ref.context);
  await ref.read(linuxKeyringCoordinatorProvider).runMutation(() async {
    final security = ref.read(appSecurityProvider.notifier);
    var prepared = false;
    var committed = false;
    try {
      await security.preparePasswordSetup(password);
      prepared = true;
      await runCustomisedAccountMutation(
        ref,
        setupArgs: args,
        accountName: persona.name,
        profilePictureId: persona.profilePictureId,
        onStoppingSync: onStoppingSync,
        onSyncPaused: onSyncPaused,
      );
      await security.completePasswordSetup();
      committed = true;
      unawaited(
        ref.read(appPasswordInputSourceProvider).remember(passwordInputSource),
      );
    } catch (error) {
      if (prepared && !committed) {
        try {
          await security.finishPasswordSetupAfterFailure(
            accountMayExist:
                error is WalletAccountSetupInterruptedException ||
                error is WalletAccountStateUncertainException ||
                (ref.read(accountProvider).value?.hasAccounts ?? false),
          );
        } catch (cleanupError, cleanupStack) {
          log(
            'Account setup: credential cleanup failed: '
            '$cleanupError\n$cleanupStack',
          );
        }
      }
      rethrow;
    }
  });
  if (!ref.context.mounted) return;
  await completeGiftClaimImportSetup(ref);
  if (!ref.context.mounted) return;
  clearCustomisedAccountDraft(ref, args.flow);
  router.go(
    kAppFormFactor == AppFormFactor.mobile
        ? '/onboarding/biometrics'
        : giftClaimSetupCompletionLocation(ref, otherwise: '/home'),
  );
}
