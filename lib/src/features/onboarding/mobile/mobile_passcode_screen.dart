import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/feedback/app_haptics.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../payment_links/services/gift_claim_setup_coordinator.dart';
import '../../wallet_link/services/wallet_link_completion.dart';
import '../keystone/keystone_onboarding_flow.dart'
    show keystoneOnboardingProvider;
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_onboarding_progress.dart';
import 'mobile_onboarding_progress_scope.dart';
import 'passcode_widgets.dart';

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
  const MobilePasscodeScreen({
    required SetPasswordScreenArgs this.args,
    this.completeWalletLinkPackage = completeWalletLinkPackageBestEffort,
    super.key,
  }) : onConfirmed = null,
       position = null;

  const MobilePasscodeScreen.giftCard({
    required Future<void> Function(String passcode) this.onConfirmed,
    required OnboardingProgressPosition this.position,
    super.key,
  }) : args = null,
       completeWalletLinkPackage = completeWalletLinkPackageBestEffort;

  final SetPasswordScreenArgs? args;
  final Future<void> Function(String passcode)? onConfirmed;
  final OnboardingProgressPosition? position;
  final WalletLinkCompletionCallback completeWalletLinkPackage;

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
    final onConfirmed = widget.onConfirmed;
    if (onConfirmed != null) {
      setState(() => _phase = _PasscodePhase.submitting);
      try {
        await onConfirmed(passcode);
      } catch (error) {
        if (mounted) _error = onboardingSubmitErrorMessage(error);
      }
      if (!mounted) return;
      setState(() {
        _phase = _PasscodePhase.create;
        _entry = '';
        _firstPasscode = null;
      });
      return;
    }
    final args = widget.args!;
    setState(() {
      _phase = _PasscodePhase.submitting;
      _error = null;
    });

    final router = GoRouter.of(context);
    if (args.flow != SetPasswordFlow.importWalletLink) {
      await router.push<void>(
        '/onboarding/customise-account',
        extra: MobileOnboardingRouteArgs(
          setupMode: MobileOnboardingProgressScope.of(context).setupMode,
          payload: CustomiseAccountArgs(
            setupArgs: args,
            pendingPassword: passcode,
          ),
        ),
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
              walletLinkImportedContactCount = args.walletLinkContacts.isEmpty
                  ? 0
                  : await ref
                        .read(addressBookProvider.notifier)
                        .importContacts(args.walletLinkContacts);
          }
        });

        await securityNotifier.completePasswordSetup();
        passwordCommitted = true;
        if (args.flow == SetPasswordFlow.importKeystone) {
          ref.read(keystoneOnboardingProvider.notifier).resetScan();
        }
        if (args.flow == SetPasswordFlow.importWalletLink) {
          final accountImportResult = walletLinkAccountImportResult;
          if (accountImportResult == null) {
            throw StateError('Wallet link import result is missing.');
          }
          await widget.completeWalletLinkPackage(
            packageId: args.requiredWalletLinkPackageId,
            completionToken: args.requiredWalletLinkCompletionToken,
            keyBytes: args.requiredWalletLinkKeyBytes,
            importedAccountCount: accountImportResult.importedCount,
            importedContactCount: walletLinkImportedContactCount,
          );
        }
        await completeGiftClaimImportSetup(ref);
        router.go('/onboarding/biometrics');
      });
    } catch (e, st) {
      if (passwordPrepared && !passwordCommitted) {
        try {
          await securityNotifier.finishPasswordSetupAfterFailure(
            accountMayExist:
                e is WalletAccountSetupInterruptedException ||
                (ref.read(accountProvider).value?.hasAccounts ?? false),
          );
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
    final colors = context.colors;
    final isConfirm = _phase == _PasscodePhase.confirm;
    final isSubmitting = _phase == _PasscodePhase.submitting;
    final canNavigateBack = Navigator.of(context).canPop();
    final subtitle = isSubmitting
        ? 'Setting up your wallet...'
        : isConfirm
        ? 'Re-enter your passcode.'
        : '6 digits length';

    // A custom body rather than MobileOnboardingStepScaffold: the keypad is
    // pinned at the bottom and the dots + error are centred in the gap
    // above it, matching the other passcode screens — which the scaffold's
    // scrolling step layout can't express.
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.steps(
              progress:
                  (widget.position ??
                          MobileOnboardingProgressScope.of(context).at(
                            onboardingFlowForSetup(widget.args!.flow),
                            OnboardingStage.passcode,
                          ))
                      .value,
              showBackButton: canNavigateBack,
              onBack: isSubmitting || !canNavigateBack
                  ? null
                  : () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.md,
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isConfirm
                                  ? 'Confirm Passcode'
                                  : 'Create Passcode',
                              textAlign: TextAlign.center,
                              style: AppTypography.displayLarge.copyWith(
                                color: colors.text.accent,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 320),
                              child: Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                style: AppTypography.bodyMediumStrong.copyWith(
                                  color: colors.text.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            SizedBox(
                              height: kPasscodePromptDigitsHeight,
                              child: PasscodePromptField(
                                length: kMobilePasscodeLength,
                                filled: _entry.length,
                                error: _error,
                                minGap: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    PasscodeNumpad(
                      onDigit: _onDigit,
                      onBackspace: _onBackspace,
                      canDelete: _entry.isNotEmpty,
                      enabled: !isSubmitting,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
