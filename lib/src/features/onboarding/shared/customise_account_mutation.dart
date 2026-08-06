import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../create/onboarding_split_view.dart'
    show clearCreateOnboardingSecretState;
import '../keystone/keystone_onboarding_flow.dart';
import 'onboarding_flow_args.dart';

Future<void> runCustomisedAccountMutation(
  WidgetRef ref, {
  required SetPasswordScreenArgs setupArgs,
  required String accountName,
  required String profilePictureId,
  String? deriveFromAccountUuid,
  VoidCallback? onStoppingSync,
  VoidCallback? onSyncPaused,
}) async {
  final accountNotifier = ref.read(accountProvider.notifier);
  await runWithSyncPausedForAccountMutation(
    ref,
    () async {
      if (deriveFromAccountUuid != null) {
        await accountNotifier.deriveAccountFromExistingSeed(
          sourceAccountUuid: deriveFromAccountUuid,
          name: accountName,
          profilePictureId: profilePictureId,
        );
        return;
      }
      switch (setupArgs.flow) {
        case SetPasswordFlow.create:
          await accountNotifier.createAccountFromMnemonic(
            mnemonic: setupArgs.requiredMnemonic,
            name: accountName,
            profilePictureId: profilePictureId,
          );
        case SetPasswordFlow.importWallet:
          await accountNotifier.importAccount(
            mnemonic: setupArgs.requiredMnemonic,
            bip39Passphrase: setupArgs.bip39Passphrase,
            birthdayHeight: setupArgs.importBirthdayHeight,
            name: accountName,
            profilePictureId: profilePictureId,
            additionalAccountIndices:
                setupArgs.selectedAdditionalAccountIndices,
          );
        case SetPasswordFlow.importKeystone:
          await accountNotifier.importKeystoneAccount(
            name: accountName,
            profilePictureId: profilePictureId,
            ufvk: setupArgs.requiredKeystoneUfvk,
            seedFingerprint: setupArgs.requiredKeystoneSeedFingerprint,
            zip32Index: setupArgs.requiredKeystoneZip32Index,
            birthdayHeight: setupArgs.importBirthdayHeight,
          );
        case SetPasswordFlow.importWalletLink:
          throw StateError('Wallet Link does not use account customisation.');
      }
    },
    onStoppingSync: onStoppingSync,
    onSyncPaused: onSyncPaused,
  );
}

void clearCustomisedAccountDraft(WidgetRef ref, SetPasswordFlow flow) {
  switch (flow) {
    case SetPasswordFlow.create:
      clearCreateOnboardingSecretState(ref.read);
    case SetPasswordFlow.importKeystone:
      ref.read(keystoneOnboardingProvider.notifier).resetScan();
    case SetPasswordFlow.importWallet:
      break;
    case SetPasswordFlow.importWalletLink:
      throw StateError('Wallet Link does not use account customisation.');
  }
}
