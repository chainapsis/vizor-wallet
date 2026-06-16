import 'dart:async';

import 'package:flutter/material.dart' show Icon, Icons, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/feedback/app_haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/biometric_unlock_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../services/biometric_unlock.dart';
import 'forgot_passcode_sheet.dart';
import 'mobile_passcode_screen.dart' show kMobilePasscodeLength;
import 'passcode_widgets.dart';

const mobileBiometricSignInBackgroundAsset =
    'assets/illustrations/mobile_onboarding_auth_background.png';

/// Backdrop assets shared by [MobileBiometricSignInView] and the unlock
/// screen's precache, so the warmed [ImageCache] entries match the providers
/// painted behind the Face ID sheet (same key -> cache hit, no blank frame).
const _authBackgroundImage = AssetImage(mobileBiometricSignInBackgroundAsset);
const _welcomeBadgeImage = AssetImage('assets/illustrations/welcome_badge.png');

/// Mobile unlock — Figma `Sign In Passcode` (4885:23041): "Welcome Back",
/// crimson-filling dots, round numpad keys, a bottom biometric retry action,
/// and the numpad's help action opening the Forgot Passcode reset sheet.
class MobileUnlockScreen extends ConsumerStatefulWidget {
  const MobileUnlockScreen({this.autoPromptBiometric = true, super.key});

  /// Production unlock auto-prompts biometric escrow once on entry. Widgetbook
  /// disables this so Face ID / biometric states can be inspected without
  /// invoking platform APIs or immediately submitting the preview passcode.
  final bool autoPromptBiometric;

  @override
  ConsumerState<MobileUnlockScreen> createState() => _MobileUnlockScreenState();
}

class _MobileUnlockScreenState extends ConsumerState<MobileUnlockScreen> {
  var _entry = '';
  var _submitting = false;
  var _biometricPromptShown = false;
  var _biometricFallback = false;
  // True from a successful biometric read through unlock → navigation, so the
  // branded backdrop stays up across submit instead of flipping back to the
  // numpad while the Face ID sheet dismisses.
  var _biometricUnlocking = false;
  var _didPrecacheBackdrop = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didPrecacheBackdrop) return;
    _didPrecacheBackdrop = true;
    // Warm the backdrop assets so the biometric sign-in view paints before the
    // system Face ID sheet covers the screen. Best-effort: a decode failure
    // must never block unlock, and this is fire-and-forget so it can't stall
    // the prompt.
    unawaited(precacheImage(_authBackgroundImage, context, onError: (_, _) {}));
    unawaited(precacheImage(_welcomeBadgeImage, context, onError: (_, _) {}));
  }

  Future<void> _tryBiometricUnlock() async {
    if (_submitting) return;
    final biometric = await ref.read(biometricUnlockProvider.future);
    if (!mounted) return;
    if (!biometric.usable) {
      setState(() => _biometricFallback = true);
      return;
    }

    final wasEnabled = biometric.enabled;
    final passcode = await ref
        .read(biometricUnlockProvider.notifier)
        .readPasscode(reason: 'Unlock your wallet');
    if (!mounted) return;
    if (passcode == null) {
      final now = ref.read(biometricUnlockProvider).value;
      var nextError = _error;
      if (wasEnabled && now != null && !now.enabled) {
        // The escrow was invalidated (biometrics re-enrolled) — explain
        // why the prompt stopped appearing.
        nextError = 'Biometrics changed. Enter your passcode.';
      }
      setState(() {
        _biometricFallback = true;
        _error = nextError;
      });
      return;
    }
    setState(() {
      _biometricUnlocking = true;
      _entry = passcode;
      _error = null;
    });
    await _submit();
  }

  void _scheduleBiometricPrompt(BiometricUnlockState biometric) {
    if (!widget.autoPromptBiometric ||
        _biometricPromptShown ||
        _biometricFallback ||
        _submitting ||
        _entry.isNotEmpty ||
        !biometric.usable) {
      return;
    }
    _biometricPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_tryBiometricUnlock());
    });
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
    final fromBiometric = _biometricUnlocking;
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
        _biometricUnlocking = false;
        // A biometric-initiated submit that fails drops to the numpad + retry.
        if (fromBiometric) _biometricFallback = true;
        _entry = '';
        _error = "Couldn't open your wallet. Please try again.";
      });
      return;
    }

    if (!unlocked && mounted) {
      unawaited(AppHaptics.error());
      setState(() {
        _submitting = false;
        _biometricUnlocking = false;
        if (fromBiometric) _biometricFallback = true;
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
    // Second, irreversible-action gate before the wallet is wiped.
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
    final biometricAsync = ref.watch(biometricUnlockProvider);
    final biometric = biometricAsync.value ?? BiometricUnlockState.initial;
    // While the async availability probe is still resolving on cold launch,
    // trust the bootstrap snapshot's "enabled" hint so the branded backdrop
    // paints on the first frame instead of flashing the numpad before Face ID.
    final enabledHint = ref.watch(biometricUnlockEnabledHintProvider);
    final likelyUsable =
        biometric.usable || (biometricAsync.isLoading && enabledHint);
    final showBiometricSignIn =
        _biometricUnlocking ||
        (widget.autoPromptBiometric &&
            !_biometricFallback &&
            !_submitting &&
            _entry.isEmpty &&
            likelyUsable);
    // Only schedule the real prompt once the probe confirms usability — the
    // hint paints the backdrop early but must not fire Face ID prematurely.
    if (showBiometricSignIn && !_biometricUnlocking) {
      _scheduleBiometricPrompt(biometric);
    }
    return Scaffold(
      backgroundColor: colors.background.window,
      body: showBiometricSignIn
          ? const MobileBiometricSignInView()
          : SafeArea(
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
                              style: AppTypography.bodyMediumStrong.copyWith(
                                color: colors.text.primary,
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
                      onHelp: _submitting ? null : _showForgotPasscodeSheet,
                      enabled: !_submitting,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      key: const ValueKey('mobile_unlock_biometric_footer'),
                      height: 36,
                      child: Center(
                        child: Builder(
                          builder: (context) {
                            if (!biometric.usable) {
                              return const SizedBox.shrink();
                            }
                            return PasscodeBiometricButton(
                              label:
                                  biometric.availability.kind ==
                                      BiometricKind.face
                                  ? 'Sign in with Face ID'
                                  : 'Sign in with biometrics',
                              icon:
                                  biometric.availability.kind ==
                                      BiometricKind.face
                                  ? const Center(
                                      child: AppIcon(
                                        AppIcons.faceId,
                                        size: 13.5,
                                      ),
                                    )
                                  : const Icon(Icons.fingerprint, size: 16),
                              onPressed: _submitting
                                  ? null
                                  : () => unawaited(_tryBiometricUnlock()),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Biometric sign-in backdrop shown behind the native biometric prompt.
/// Figma `Sign In Face ID` (4596:50062 / 4596:50202) also shows iOS chrome and
/// the system prompt layer; those are not app-rendered content.
class MobileBiometricSignInView extends StatelessWidget {
  const MobileBiometricSignInView({super.key});

  static const _figmaFrameWidth = 393.0;
  static const _backgroundWidth = 392.0;
  static const _backgroundHeight = 720.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ColoredBox(
      color: colors.background.window,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = constraints.maxWidth / _figmaFrameWidth;
              return Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: _backgroundWidth * scale,
                  height: _backgroundHeight * scale,
                  child: Image(
                    image: _authBackgroundImage,
                    key: const ValueKey('mobile_biometric_sign_in_background'),
                    fit: BoxFit.fill,
                  ),
                ),
              );
            },
          ),
          Center(
            child: Image(
              image: _welcomeBadgeImage,
              key: const ValueKey('mobile_biometric_sign_in_badge'),
              width: 130,
              height: 130,
            ),
          ),
        ],
      ),
    );
  }
}
