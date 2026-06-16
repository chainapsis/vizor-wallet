import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/storage/app_secure_store.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/app_security_provider.dart';
import '../../../../providers/biometric_unlock_provider.dart';
import '../../../../providers/router_refresh_provider.dart';
import '../../../onboarding/mobile/forgot_passcode_sheet.dart';
import '../../../onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../../../onboarding/mobile/passcode_widgets.dart';

enum _Phase { verify, create, confirm }

/// Mobile passcode change — Figma `Enter Passcode` / `Update Passcode` /
/// `Confirm Passcode` (4494:91005 / 91073 / 91141). Three numpad phases:
/// verify the current passcode (with the Forgot Passcode reset sheet
/// behind the help key), enter the new one, confirm it. The change goes
/// through the same `appSecurityProvider.changePassword` rotation as the
/// desktop flow. Pops `true` after a successful change.
class MobileChangePasscodeScreen extends ConsumerStatefulWidget {
  const MobileChangePasscodeScreen({super.key});

  @override
  ConsumerState<MobileChangePasscodeScreen> createState() =>
      _MobileChangePasscodeScreenState();
}

class _MobileChangePasscodeScreenState
    extends ConsumerState<MobileChangePasscodeScreen> {
  var _phase = _Phase.verify;
  var _entry = '';
  var _submitting = false;
  String? _currentPasscode;
  String? _newPasscode;
  String? _error;

  void _onDigit(int digit) {
    if (_submitting || _entry.length >= kMobilePasscodeLength) return;
    setState(() {
      _entry += '$digit';
      _error = null;
    });
    if (_entry.length == kMobilePasscodeLength) {
      _onEntryComplete();
    }
  }

  void _onBackspace() {
    if (_submitting || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  void _onEntryComplete() {
    switch (_phase) {
      case _Phase.verify:
        _verifyCurrent();
      case _Phase.create:
        if (_entry == _currentPasscode) {
          setState(() {
            _entry = '';
            _error = 'Your new passcode must be different.';
          });
          return;
        }
        setState(() {
          _newPasscode = _entry;
          _entry = '';
          _phase = _Phase.confirm;
        });
      case _Phase.confirm:
        if (_entry == _newPasscode) {
          _submit();
        } else {
          setState(() {
            _entry = '';
            _newPasscode = null;
            _phase = _Phase.create;
            _error = "Passcodes didn't match. Try again.";
          });
        }
    }
  }

  Future<void> _verifyCurrent() async {
    setState(() => _submitting = true);
    try {
      final isValid = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(_entry);
      if (!mounted) return;
      if (!isValid) {
        unawaited(AppHaptics.error());
        setState(() {
          _submitting = false;
          _entry = '';
          _error = 'Incorrect Passcode';
        });
        return;
      }
      setState(() {
        _submitting = false;
        _currentPasscode = _entry;
        _entry = '';
        _phase = _Phase.create;
      });
    } catch (e, st) {
      log('MobileChangePasscode._verifyCurrent: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _entry = '';
        _error = "Couldn't check your passcode. Please try again.";
      });
    }
  }

  /// Best effort only — a failed escrow refresh must never block the
  /// passcode change itself (worst case the escrow is dropped and the
  /// user re-enables biometrics in settings).
  Future<void> _refreshBiometricEscrow(String newPasscode) async {
    final notifier = ref.read(biometricUnlockProvider.notifier);
    final BiometricUnlockState biometric;
    try {
      biometric = await ref.read(biometricUnlockProvider.future);
    } catch (_) {
      return;
    }
    if (!biometric.enabled) return;
    try {
      await notifier.enable(newPasscode);
    } catch (_) {
      try {
        await notifier.disable();
      } catch (_) {
        // The stale escrow cannot decrypt anything on its own; leaving
        // it behind is safe even when cleanup fails.
      }
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      // Pause router refresh across the rotation + pop, like the other
      // password mutations: the security-state change notifying the
      // router mid-pop can resurrect this just-popped page.
      await ref.read(routerRefreshProvider).pauseWhile(() async {
        final didChange = await ref
            .read(appSecurityProvider.notifier)
            .changePassword(
              currentPassword: _currentPasscode!,
              newPassword: _newPasscode!,
            );
        if (!mounted) return;
        if (!didChange) {
          // The verified passcode stopped matching the stored verifier
          // — restart from scratch rather than trusting stale state.
          setState(() {
            _submitting = false;
            _restartFlow('Incorrect Passcode');
          });
          return;
        }
        // The biometric escrow holds the old passcode now — rewrite it
        // in the background (an unlock racing the rewrite just fails
        // verification and falls back to the numpad). Blocking the pop
        // on a platform channel would also hang widget tests, where
        // unmocked channels never respond.
        unawaited(_refreshBiometricEscrow(_newPasscode!));
        if (!mounted) return;
        // context.pop (not Navigator.pop) so go_router's configuration
        // updates synchronously — a deferred router refresh landing in
        // the gap restores the stale config and resurrects this page.
        context.pop(true);
      });
    } on PasswordRotationRecoveryFailedException {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _restartFlow(
          "We couldn't verify the previous passcode change. Keep your "
          'secret passphrase available before trying again.',
        );
      });
    } catch (e, st) {
      log('MobileChangePasscode._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _entry = '';
        _newPasscode = null;
        _phase = _Phase.create;
        _error = "Couldn't update your passcode. Please try again.";
      });
    }
  }

  void _restartFlow(String error) {
    _entry = '';
    _currentPasscode = null;
    _newPasscode = null;
    _phase = _Phase.verify;
    _error = error;
  }

  Future<void> _showForgotPasscodeSheet() async {
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      builder: (sheetContext) => const ForgotPasscodeSheet(),
    );
    if (confirmed != true || !mounted) return;
    final lastWarningConfirmed = await showAppMobileSheet<bool>(
      context: context,
      builder: (sheetContext) => const ForgotPasscodeLastWarningSheet(),
    );
    if (lastWarningConfirmed != true || !mounted) return;
    await _resetWallet();
  }

  Future<void> _resetWallet() async {
    setState(() => _submitting = true);
    final router = GoRouter.of(context);
    try {
      await resetWalletForForgottenPasscode(ref);
    } catch (e, st) {
      log('MobileChangePasscode._resetWallet: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _entry = '';
        _error = "Couldn't reset the app. Please try again.";
      });
      return;
    }
    router.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (title, subtitle) = switch (_phase) {
      _Phase.verify => ('Enter Passcode', 'Enter your passcode'),
      _Phase.create => ('Update Passcode', 'Enter your new passcode'),
      _Phase.confirm => ('Confirm Passcode', 'Confirm new passcode'),
    };

    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: '',
              onBack: _submitting ? null : () => context.pop(),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              // Headline M serif per the Update Passcode frames.
              style: AppTypography.headlineMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            // Dots + error centred in the space above the keypad.
            Expanded(
              child: PasscodePromptField(
                length: kMobilePasscodeLength,
                filled: _entry.length,
                error: _error,
              ),
            ),
            PasscodeNumpad(
              onDigit: _onDigit,
              onBackspace: _onBackspace,
              canDelete: _entry.isNotEmpty,
              onHelp: _phase == _Phase.verify && !_submitting
                  ? _showForgotPasscodeSheet
                  : null,
              enabled: !_submitting,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}
