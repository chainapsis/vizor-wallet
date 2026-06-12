import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/feedback/app_haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../create/onboarding_split_view.dart'
    show clearCreateOnboardingSecretState;
import '../keystone/keystone_onboarding_flow.dart'
    show keystoneOnboardingProvider;
import '../shared/onboarding_error_messages.dart';
import '../shared/onboarding_flow_args.dart';
import 'mobile_create_steps.dart';
import 'mobile_onboarding_scaffold.dart';
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
              );
            case SetPasswordFlow.importKeystone:
              await accountNotifier.importKeystoneAccount(
                name: args.requiredKeystoneAccountName,
                ufvk: args.requiredKeystoneUfvk,
                seedFingerprint: args.requiredKeystoneSeedFingerprint,
                zip32Index: args.requiredKeystoneZip32Index,
                birthdayHeight: args.importBirthdayHeight,
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

    return MobileOnboardingStepScaffold(
      progress: mobileCreateProgress(5),
      onBack: isSubmitting ? null : () => Navigator.of(context).maybePop(),
      title: isConfirm ? 'Confirm Passcode' : 'Create Passcode',
      // The passcode frames title in Headline L (32, glyph extent 27-28
      // in passcode1/confirm/5), not the XL step title.
      titleStyle: AppTypography.headlineLarge,
      subtitle: isSubmitting
          ? 'Setting up your wallet...'
          : isConfirm
          ? 'Re-enter your passcode.'
          : '6 digits length',
      child: Column(
        children: [
          const SizedBox(height: AppSpacing.md),
          PasscodeDots(length: kMobilePasscodeLength, filled: _entry.length),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PasscodeNumpad(
            onDigit: _onDigit,
            onBackspace: _onBackspace,
            canDelete: _entry.isNotEmpty,
            enabled: !isSubmitting,
          ),
        ],
      ),
    );
  }
}
