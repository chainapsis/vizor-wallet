import 'dart:async';

import 'package:flutter/material.dart' show Icons, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/feedback/app_haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/biometric_unlock_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../services/biometric_unlock.dart';
import 'forgot_passcode_sheet.dart';
import 'mobile_passcode_screen.dart' show kMobilePasscodeLength;
import 'passcode_widgets.dart';

/// Mobile unlock — Figma `Sign In Passcode` (4596:50000): badge,
/// "Welcome Back", crimson-filling dots, the plum incorrect-passcode
/// message, and the numpad's help action opening the Forgot Passcode
/// reset sheet (4596:50252).
class MobileUnlockScreen extends ConsumerStatefulWidget {
  const MobileUnlockScreen({super.key});

  @override
  ConsumerState<MobileUnlockScreen> createState() => _MobileUnlockScreenState();
}

class _MobileUnlockScreenState extends ConsumerState<MobileUnlockScreen> {
  var _entry = '';
  var _submitting = false;
  var _biometricPromptShown = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-prompt once on entry; cancel/failure leaves the numpad as
    // the fallback and the numpad slot offers a manual retry.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _biometricPromptShown) return;
      _biometricPromptShown = true;
      unawaited(_tryBiometricUnlock());
    });
  }

  Future<void> _tryBiometricUnlock() async {
    if (_submitting) return;
    final biometric = await ref.read(biometricUnlockProvider.future);
    if (!mounted || !biometric.usable) return;

    final wasEnabled = biometric.enabled;
    final passcode = await ref
        .read(biometricUnlockProvider.notifier)
        .readPasscode(reason: 'Unlock your wallet');
    if (!mounted) return;
    if (passcode == null) {
      final now = ref.read(biometricUnlockProvider).value;
      if (wasEnabled && now != null && !now.enabled) {
        // The escrow was invalidated (biometrics re-enrolled) — explain
        // why the prompt stopped appearing.
        setState(() {
          _error = 'Biometrics changed. Enter your passcode.';
        });
      }
      return;
    }
    setState(() {
      _entry = passcode;
      _error = null;
    });
    await _submit();
  }

  void _onDigit(int digit) {
    if (_submitting || _entry.length >= kMobilePasscodeLength) return;
    setState(() {
      _entry += '$digit';
      _error = null;
    });
    if (_entry.length == kMobilePasscodeLength) {
      _submit();
    }
  }

  void _onBackspace() {
    if (_submitting || _entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  /// Mirrors the desktop unlock sequence: validate, then rehydrate the
  /// account address and sync state before entering the app.
  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    final securityNotifier = ref.read(appSecurityProvider.notifier);
    final accountNotifier = ref.read(accountProvider.notifier);
    final syncNotifier = ref.read(syncProvider.notifier);
    final routerRefresh = ref.read(routerRefreshProvider);
    var unlocked = false;

    try {
      await routerRefresh.pauseWhile(() async {
        final isValid = await securityNotifier.unlock(_entry);
        if (!isValid) return;

        unlocked = true;
        await accountNotifier.restoreAfterUnlock();
        await syncNotifier.refreshAfterUnlock();
        await syncNotifier.startSyncAnyway();
        if (!mounted) return;
        context.go('/home');
      });
    } catch (e, st) {
      log('MobileUnlockScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _entry = '';
        _error = "Couldn't open your wallet. Please try again.";
      });
      return;
    }

    if (!unlocked && mounted) {
      unawaited(AppHaptics.error());
      setState(() {
        _submitting = false;
        _entry = '';
        _error = 'Incorrect Passcode';
      });
    }
  }

  Future<void> _showForgotPasscodeSheet() async {
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      builder: (sheetContext) => const ForgotPasscodeSheet(),
    );
    if (confirmed != true || !mounted) return;
    await _resetWallet();
  }

  Future<void> _resetWallet() async {
    setState(() => _submitting = true);
    final router = GoRouter.of(context);
    try {
      await resetWalletForForgottenPasscode(ref);
    } catch (e, st) {
      log('MobileUnlockScreen._resetWallet: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "Couldn't reset the app. Please try again.";
      });
      return;
    }
    router.go('/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            Image.asset(
              'assets/illustrations/welcome_badge.png',
              width: 50,
              height: 50,
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              'Welcome Back',
              textAlign: TextAlign.center,
              style: AppTypography.displayLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            Text(
              _submitting
                  ? 'Opening your wallet...'
                  : 'Enter your passcode to open Vizor',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            PasscodeDots(length: kMobilePasscodeLength, filled: _entry.length),
            SizedBox(
              // Tall enough to hold the error message ~30 px below the
              // dots, where the Sign In Passcode frame places it.
              height: 84,
              child: Center(
                child: _error == null
                    ? null
                    : Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.destructive,
                        ),
                      ),
              ),
            ),
            const Spacer(),
            Builder(
              builder: (context) {
                final biometric =
                    ref.watch(biometricUnlockProvider).value ??
                    BiometricUnlockState.initial;
                return PasscodeNumpad(
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  canDelete: _entry.isNotEmpty,
                  onHelp: _submitting ? null : _showForgotPasscodeSheet,
                  onBiometric: biometric.usable && !_submitting
                      ? () => unawaited(_tryBiometricUnlock())
                      : null,
                  biometricIcon:
                      biometric.availability.kind == BiometricKind.face
                      ? Icons.face
                      : Icons.fingerprint,
                  enabled: !_submitting,
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}
