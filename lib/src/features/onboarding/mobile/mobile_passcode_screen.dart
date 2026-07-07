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
import '../../../providers/multisig_pending_session_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../create/onboarding_split_view.dart'
    show clearCreateOnboardingSecretState;
import '../keystone/keystone_onboarding_flow.dart'
    show keystoneOnboardingProvider;
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_create_steps.dart';
import 'passcode_widgets.dart';

/// Length of the mobile wallet passcode. The digit string is stored as
/// the wallet password verbatim (see the wallet password policy note in
/// AGENTS.md), so unlocking re-enters the same six digits.
const kMobilePasscodeLength = 6;

enum _PasscodePhase { create, confirm, submitting }

/// Mobile passcode setup — Figma `Passcode 1` / `Passcode Confirm`
/// (4394:82593 / 4394:82944). Two-phase entry (create → confirm); a
/// mismatch restarts from the create phase, iOS-style. On a match the
/// six-digit string is committed as the wallet password and the wallet
/// is created/imported with exactly the desktop set-password sequence
/// (prepare → account mutation under the sync pause → commit, with
/// rollback on failure).
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

  /// Mirrors `SetPasswordScreen._submit` — same prepare/commit/rollback
  /// sequence, same flow branches; only the credential UI differs.
  Future<void> _submit(String passcode) async {
    final args = widget.args;
    setState(() {
      _phase = _PasscodePhase.submitting;
      _error = null;
    });

    final router = GoRouter.of(context);
    final securityNotifier = ref.read(appSecurityProvider.notifier);
    final accountNotifier = ref.read(accountProvider.notifier);
    final routerRefresh = ref.read(routerRefreshProvider);
    var passwordPrepared = false;
    var passwordCommitted = false;
    MultisigPendingSession? pendingMultisigSession;

    try {
      await routerRefresh.pauseWhile(() async {
        await securityNotifier.preparePasswordSetup(passcode);
        passwordPrepared = true;

        await runWithSyncPausedForAccountMutation(ref, () async {
          switch (args.flow) {
            case SetPasswordFlow.create:
              await accountNotifier.createAccountFromMnemonic(
                mnemonic: args.requiredMnemonic,
              );
            case SetPasswordFlow.importWallet:
              await accountNotifier.importAccount(
                mnemonic: args.requiredMnemonic,
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
            case SetPasswordFlow.multisigCreateSession:
              pendingMultisigSession = await ref
                  .read(multisigPendingSessionsProvider.notifier)
                  .createSession(
                    coordinatorUrl: args.requiredMultisigCoordinatorUrl,
                  );
            case SetPasswordFlow.multisigJoinSession:
              pendingMultisigSession = await ref
                  .read(multisigPendingSessionsProvider.notifier)
                  .joinSession(
                    coordinatorUrl: args.requiredMultisigCoordinatorUrl,
                    inviteCode: args.requiredMultisigInviteCode,
                  );
            case SetPasswordFlow.multisigFinalize:
              final sessions = await ref.read(
                multisigPendingSessionsProvider.future,
              );
              final session =
                  multisigSessionByStorageId(
                    sessions,
                    args.requiredMultisigSessionStorageId,
                  ) ??
                  multisigSessionById(
                    sessions,
                    args.requiredMultisigSessionStorageId,
                  );
              if (session == null) {
                throw StateError('Multisig session not found.');
              }
              if (!multisigLocalBackupCompleted(session)) {
                throw StateError(
                  'Confirm the local multisig backup before creating this account.',
                );
              }
              await accountNotifier.finalizeMultisigAccount(
                session.storageId,
                backupArtifactJson: args.requiredMultisigBackupArtifactJson,
                backupPassphrase: args.requiredMultisigBackupPassphrase,
              );
            case SetPasswordFlow.multisigRestore:
              await accountNotifier.restoreMultisigAccountFromBackup(
                backupArtifactJson: args.requiredMultisigBackupArtifactJson,
                backupPassphrase: args.requiredMultisigBackupPassphrase,
                backupFilePath: args.multisigBackupFilePath,
                coordinatorUrl: args.requiredMultisigCoordinatorUrl,
              );
          }
        });

        securityNotifier.commitPasswordSetup();
        passwordCommitted = true;
        if (args.flow == SetPasswordFlow.importKeystone) {
          ref.read(keystoneOnboardingProvider.notifier).resetScan();
        }
        if (args.flow == SetPasswordFlow.create) {
          clearCreateOnboardingSecretState(ref.read);
        }
        final pending = pendingMultisigSession;
        if (pending != null) {
          router.go(
            '/multisig/session/${Uri.encodeComponent(pending.storageId)}',
          );
          return;
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
    final colors = context.colors;
    final isConfirm = _phase == _PasscodePhase.confirm;
    final isSubmitting = _phase == _PasscodePhase.submitting;
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
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.steps(
              progress: mobileCreateProgress(5),
              onBack: isSubmitting
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
