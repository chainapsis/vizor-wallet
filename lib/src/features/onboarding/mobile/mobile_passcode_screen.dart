import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/feedback/app_haptics.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../wallet_link/services/wallet_link_completion.dart';
import '../keystone/keystone_onboarding_flow.dart'
    show keystoneOnboardingProvider;
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_onboarding_progress.dart';
import 'mobile_passcode_layout.dart';

/// Length of the mobile wallet passcode. The digit string is stored as
/// the wallet password verbatim (see the wallet password policy note in
/// AGENTS.md), so unlocking re-enters the same six digits.
const kMobilePasscodeLength = 6;

enum _PasscodePhase { create, confirm, submitting }

/// Mobile passcode setup — Figma `Passcode 1` / `Passcode Confirm`
/// (4394:82593 / 4394:82944). Two-phase entry (create → confirm); a
/// mismatch restarts from the create phase, iOS-style. On a match the
/// six-digit string is forwarded to account customisation for create flows.
/// Import flows still use the desktop set-password sequence (prepare → account
/// mutation under the sync pause → commit, with rollback on failure).
class MobilePasscodeScreen extends ConsumerStatefulWidget {
  const MobilePasscodeScreen({required this.args, super.key});

  final SetPasswordScreenArgs args;

  @override
  ConsumerState<MobilePasscodeScreen> createState() =>
      _MobilePasscodeScreenState();
}

class _MobilePasscodeScreenState extends ConsumerState<MobilePasscodeScreen> {
  var _phase = _PasscodePhase.create;
  var _entry = '';
  String? _firstPasscode;
  String? _error;

  void _onDigit(int digit) {
    if (_phase == _PasscodePhase.submitting) return;
    if (_entry.length >= kMobilePasscodeLength) return;
    setState(() {
      _entry += '$digit';
      _error = null;
    });
    if (_entry.length == kMobilePasscodeLength) {
      _onEntryComplete();
    }
  }

  void _onBackspace() {
    if (_phase == _PasscodePhase.submitting || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  void _onEntryComplete() {
    switch (_phase) {
      case _PasscodePhase.create:
        setState(() {
          _firstPasscode = _entry;
          _entry = '';
          _phase = _PasscodePhase.confirm;
        });
      case _PasscodePhase.confirm:
        if (_entry == _firstPasscode) {
          _submit(_entry);
        } else {
          unawaited(AppHaptics.error());
          setState(() {
            _entry = '';
            _firstPasscode = null;
            _phase = _PasscodePhase.create;
            _error = "Passcodes didn't match. Try again.";
          });
        }
      case _PasscodePhase.submitting:
        break;
    }
  }

  /// Software, Keystone, and Ledger setup continue to account customisation without
  /// persisting the pending passcode. Wallet Link remains an immediate import.
  Future<void> _submit(String passcode) async {
    final args = widget.args;
    setState(() {
      _phase = _PasscodePhase.submitting;
      _error = null;
    });

    final router = GoRouter.of(context);
    if (args.flow != SetPasswordFlow.importWalletLink) {
      await router.push<void>(
        '/onboarding/customise-account',
        extra: CustomiseAccountArgs(setupArgs: args, pendingPassword: passcode),
      );
      if (!mounted) return;
      setState(() {
        _phase = _PasscodePhase.create;
        _entry = '';
        _firstPasscode = null;
      });
      return;
    }

    final securityNotifier = ref.read(appSecurityProvider.notifier);
    final accountNotifier = ref.read(accountProvider.notifier);
    final routerRefresh = ref.read(routerRefreshProvider);
    var passwordPrepared = false;
    var passwordCommitted = false;
    LinkedWalletAccountsImportResult? walletLinkAccountImportResult;
    var walletLinkImportedContactCount = 0;

    try {
      await routerRefresh.pauseWhile(() async {
        await securityNotifier.preparePasswordSetup(passcode);
        passwordPrepared = true;

        await runWithSyncPausedForAccountMutation(ref, () async {
          switch (args.flow) {
            case SetPasswordFlow.importLedger:
            case SetPasswordFlow.create:
              throw StateError(
                'Create flow must continue through account customisation.',
              );
            case SetPasswordFlow.importWallet:
              await accountNotifier.importAccount(
                mnemonic: args.requiredMnemonic,
                bip39Passphrase: args.bip39Passphrase,
                birthdayHeight: args.importBirthdayHeight,
                additionalAccountIndices: args.selectedAdditionalAccountIndices,
              );
            case SetPasswordFlow.importKeystone:
              await accountNotifier.importKeystoneAccount(
                name: args.requiredKeystoneAccountName,
                ufvk: args.requiredKeystoneUfvk,
                seedFingerprint: args.requiredKeystoneSeedFingerprint,
                zip32Index: args.requiredKeystoneZip32Index,
                birthdayHeight: args.importBirthdayHeight,
              );
            case SetPasswordFlow.importWalletLink:
              walletLinkAccountImportResult = await accountNotifier
                  .importLinkedWalletAccounts(
                    network: args.requiredWalletLinkNetwork,
                    accountsToImport: args.walletLinkAccounts,
                  );
              walletLinkImportedContactCount = await ref
                  .read(addressBookProvider.notifier)
                  .importContacts(args.walletLinkContacts);
          }
        });

        securityNotifier.commitPasswordSetup();
        passwordCommitted = true;
        if (args.flow == SetPasswordFlow.importKeystone) {
          ref.read(keystoneOnboardingProvider.notifier).resetScan();
        }
        if (args.flow == SetPasswordFlow.importWalletLink) {
          final accountImportResult = walletLinkAccountImportResult;
          if (accountImportResult == null) {
            throw StateError('Wallet link import result is missing.');
          }
          await completeWalletLinkPackageBestEffort(
            packageId: args.requiredWalletLinkPackageId,
            completionToken: args.requiredWalletLinkCompletionToken,
            keyBytes: args.requiredWalletLinkKeyBytes,
            importedAccountCount: accountImportResult.importedCount,
            importedContactCount: walletLinkImportedContactCount,
          );
        }
        router.go('/onboarding/biometrics');
      });
    } catch (e, st) {
      if (passwordPrepared && !passwordCommitted) {
        try {
          await securityNotifier.rollbackPasswordSetup();
        } catch (rollbackError, rollbackStack) {
          log(
            'MobilePasscode: password rollback failed: '
            '$rollbackError\n$rollbackStack',
          );
        }
      }
      log('MobilePasscode._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _phase = _PasscodePhase.create;
        _entry = '';
        _firstPasscode = null;
        _error = onboardingSubmitErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConfirm = _phase == _PasscodePhase.confirm;
    final isSubmitting = _phase == _PasscodePhase.submitting;
    final canNavigateBack = Navigator.of(context).canPop();
    final subtitle = isSubmitting
        ? 'Setting up your wallet...'
        : isConfirm
        ? 'Re-enter your passcode.'
        : '6 digits length';

    return MobilePasscodeLayout(
      title: isConfirm ? 'Confirm Passcode' : 'Create Passcode',
      subtitle: subtitle,
      filled: _entry.length,
      error: _error,
      navigation: MobileTopNav.steps(
        progress: _progressForFlow(widget.args.flow),
        showBackButton: canNavigateBack,
        onBack: isSubmitting || !canNavigateBack
            ? null
            : () => Navigator.of(context).maybePop(),
      ),
      onDigit: _onDigit,
      onBackspace: _onBackspace,
      enabled: !isSubmitting,
    );
  }
}

double _progressForFlow(SetPasswordFlow flow) => switch (flow) {
  SetPasswordFlow.create => mobileCreateProgress(7),
  SetPasswordFlow.importLedger => kMobileLedgerPasscodeProgress,
  SetPasswordFlow.importKeystone => kMobileKeystonePasscodeProgress,
  SetPasswordFlow.importWallet => mobileImportProgress(4),
  SetPasswordFlow.importWalletLink => kMobileWalletLinkPasscodeProgress,
};
