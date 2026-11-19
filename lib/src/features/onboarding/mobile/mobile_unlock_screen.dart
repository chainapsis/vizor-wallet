import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../core/navigation/payment_uri_unlock_claim.dart';
import '../../../core/feedback/app_haptics.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../payment_links/providers/payment_link_intake_provider.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/biometric_unlock_provider.dart';
import '../../../providers/payment_request_flow_provider.dart';
import '../../../providers/mobile_account_visibility_provider.dart';
import '../../../providers/mobile_passcode_auth_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../services/biometric_unlock.dart';
import '../../../services/device_owner_auth.dart';
import '../shared/onboarding_error_messages.dart';
import 'forgot_passcode_sheet.dart';
import 'mobile_passcode_screen.dart' show kMobilePasscodeLength;
import 'passcode_widgets.dart';
import 'adaptive_passcode_layout.dart';

const mobileBiometricSignInBackgroundAsset =
    'assets/illustrations/mobile_onboarding_auth_background.webp';

const _authBackgroundImage = AssetImage(mobileBiometricSignInBackgroundAsset);
const _welcomeBadgeImage = AssetImage(
  'assets/illustrations/welcome_badge_mobile.webp',
);

/// Mobile unlock always collects a passcode before prompting for biometrics.
class MobileUnlockScreen extends ConsumerStatefulWidget {
  const MobileUnlockScreen({super.key});

  @override
  ConsumerState<MobileUnlockScreen> createState() => _MobileUnlockScreenState();
}

class _MobileUnlockScreenState extends ConsumerState<MobileUnlockScreen> {
  var _entry = '';
  var _submitting = false;
  var _enableBiometricOnUnlock = false;
  int _attempt = 0;
  String? _selectedRule;
  OnboardingSubmitError? _error;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _cancelAttempt);
  }

  void _cancelAttempt() {
    _attempt++;
    if (!mounted) return;
    if (_submitting) {
      final wasUnlocked = ref.read(appSecurityProvider).isUnlocked;
      ref.read(appSecurityProvider.notifier).lock();
      ref.read(mobileAccountScopeProvider.notifier).select(null);
      if (wasUnlocked) {
        ref.read(accountProvider.notifier).clearSensitiveStateForLock();
        unawaited(ref.read(syncProvider.notifier).clearSensitiveStateForLock());
      }
    }
    setState(() {
      _entry = '';
      _selectedRule = null;
      _submitting = false;
      _error = null;
    });
  }

  @override
  void dispose() {
    _attempt++;
    _lifecycle.dispose();
    _entry = '';
    super.dispose();
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
    final entered = _entry;
    final attempt = ++_attempt;
    bool current() => mounted && attempt == _attempt;
    final enableBiometric = _enableBiometricOnUnlock;
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
      final proof = await ref
          .read(mobilePasscodeAuthProvider)
          .check(
            code: entered,
            biometricReason: context.l10n.onboardingUnlockBiometricReason,
            isCurrent: current,
            walletOnly: _selectedRule != null,
            selectedRule: _selectedRule,
          );
      if (!current()) return;
      if (proof.needsWalletPasscode) {
        setState(() {
          _selectedRule = proof.ruleId;
          _entry = '';
          _submitting = false;
        });
        return;
      }

      await routerRefresh.pauseWhile(() async {
        accountNotifier.selectMobileAccountBeforeUnlock(proof.ruleId);
        final scope = ref.read(mobileAccountScopeProvider.notifier);
        scope.select(proof.ruleId);
        final isValid = await securityNotifier.unlock(proof.walletPasscode!);
        if (!isValid || !current()) {
          if (isValid) securityNotifier.lock();
          scope.select(null);
          return;
        }

        unlocked = true;
        await accountNotifier.restoreAfterUnlock();
        if (!current() || !ref.read(appSecurityProvider).isUnlocked) return;
        await syncNotifier.refreshAfterUnlock();
        if (!current() || !ref.read(appSecurityProvider).isUnlocked) return;
        // Home does not wait for the sync, whose start can wait out a
        // cancelled one.
        unawaited(startSyncAfterUnlock(syncNotifier));
        if (!current()) return;
        if (enableBiometric) await _enableBiometricForNextUnlock();
        if (!mounted || !current()) return;
        // A native enrollment prompt can outlive the unlocked session (for
        // example, returning after the background auto-lock timeout).
        if (!ref.read(appSecurityProvider).isUnlocked) {
          setState(() {
            _submitting = false;
            _entry = '';
          });
          return;
        }
        // Claim the payment-URI prefill (parked while locked) only now, after
        // the post-unlock work has succeeded. Claiming earlier would drop the
        // payment if any of the awaits above threw or this screen unmounted —
        // the prefill would already be cleared with no way to recover it —
        // and the drain policy inside the claim reads state those awaits
        // settle.
        // Claim first, then pick the destination, then present. Both link
        // kinds can be waiting at once, and they do not compete: the Gift Card
        // owns the route, the ZIP-321 card is a route-agnostic overlay that
        // lands on top of whichever destination that picks.
        final claimed = claimParkedPaymentUriAfterUnlock(ref);
        final hasPendingPaymentLink =
            ref.read(paymentLinkIntakeProvider).pendingLink != null;
        unawaited(AppHaptics.accessGranted());
        context.go(hasPendingPaymentLink ? '/payment-links' : '/home');
        syncNotifier.refreshHomeInBackground();
        final pendingPrefill = claimed.prefill;
        final notice = claimed.notice;
        if (pendingPrefill != null) {
          // The link becomes a card over the wallet the user just unlocked,
          // not a jump into the composer.
          ref
              .read(paymentRequestFlowProvider.notifier)
              .present(pendingPrefill, source: pendingPrefill.requestSource);
        } else if (notice != null) {
          // The link outlived its park window while the user was finding their
          // passcode, or the wallet it landed on cannot open it. Landing with
          // no card and no word is the one silent loss of something the user
          // deliberately asked for. The toast is asked for before this screen
          // is torn down; `showAppToast` renders it on the app-level host,
          // which outlives the navigation.
          showAppToast(
            context,
            notice.text(context.l10n),
            duration: const Duration(seconds: 4),
            iconName: AppIcons.warning,
          );
        }
      });
    } on MobilePasscodeRejected catch (error) {
      if (!current()) return;
      _showUnlockError(
        error.failure == MobilePasscodeFailure.biometric
            ? (l10n) => l10n.accountVisibilityBiometricRequired
            : (l10n) => l10n.passcodeIncorrect,
      );
      return;
    } catch (error) {
      if (!current()) return;
      if (ref.read(appSecurityProvider).isUnlocked) {
        securityNotifier.lock();
        accountNotifier.clearSensitiveStateForLock();
        unawaited(syncNotifier.clearSensitiveStateForLock());
      }
      ref.read(mobileAccountScopeProvider.notifier).select(null);
      _showUnlockError((l10n) => l10n.onboardingUnlockOpenFailed);
      return;
    }

    if (!unlocked && current()) {
      _showUnlockError((l10n) => l10n.passcodeIncorrect);
    }
  }

  void _showUnlockError(String Function(AppLocalizations) message) {
    unawaited(AppHaptics.error());
    setState(() {
      _submitting = false;
      _selectedRule = null;
      _entry = '';
      _error = OnboardingSubmitError.localized(message);
    });
  }

  Future<void> _enableBiometricForNextUnlock() async {
    final biometric = ref.read(biometricUnlockProvider).value;
    if (biometric == null ||
        !biometric.availability.usable ||
        biometric.enabled ||
        !ref.read(appSecurityProvider).isUnlocked) {
      return;
    }
    try {
      final passcode = ref
          .read(appSecurityProvider.notifier)
          .requireSessionPasswordForNativeSecretUse();
      await ref.read(biometricUnlockProvider.notifier).enable(passcode);
    } catch (e) {
      // Optional enrollment must not undo a successful wallet unlock or
      // consume a parked payment before its original destination is ready.
      if (e is BiometricUnlockException &&
          e.kind == BiometricUnlockErrorKind.cancelled) {
        return;
      }
      log('MobileUnlockScreen biometric enable failed: $e');
      if (!mounted || !ref.read(appSecurityProvider).isUnlocked) return;
      showAppToast(
        context,
        context.l10n.onboardingBiometricEnableFailed(
          biometric.availability.kind.inlineLabel(context.l10n),
        ),
      );
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
      final didReset = await resetWalletForForgottenPasscode(ref, context.l10n);
      if (!mounted) return;
      if (!didReset) {
        setState(() {
          _submitting = false;
          _error = null;
        });
        return;
      }
    } on DeviceOwnerAuthException catch (e, st) {
      log('MobileUnlockScreen._resetWallet auth failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = OnboardingSubmitError.text(
          e.kind == DeviceOwnerAuthErrorKind.unavailable
              ? context.l10n.walletResetDeviceAuthRequired
              : context.l10n.walletResetDeviceAuthFailed,
        );
      });
      return;
    } on WalletResetInFlightGiftCardClaimsException catch (e, st) {
      // Not a failed wipe: nothing was deleted, and the user only has to wait.
      log('MobileUnlockScreen._resetWallet held for claim: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = OnboardingSubmitError.localized(
          (l10n) => l10n.walletResetGiftCardInFlight,
        );
      });
      return;
    } catch (e, st) {
      log('MobileUnlockScreen._resetWallet: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = OnboardingSubmitError.localized(
          (l10n) => l10n.onboardingResetAppFailed,
        );
      });
      return;
    }
    router.go('/welcome');
  }

  Widget _buildUnlockFooter(BiometricUnlockState biometric) {
    if (_selectedRule != null) {
      return AppButton(
        key: const ValueKey('mobile_unlock_cancel_separate_passcode'),
        variant: AppButtonVariant.secondary,
        height: 44,
        onPressed: _submitting ? null : _cancelAttempt,
        child: Text(context.l10n.commonCancel),
      );
    }
    if (!biometric.availability.usable || biometric.enabled) {
      return const SizedBox.shrink();
    }
    return PasscodeBiometricOptIn(
      key: const ValueKey('mobile_unlock_biometric_opt_in'),
      label: biometric.availability.kind.useNextTimeLabel(context.l10n),
      selected: _enableBiometricOnUnlock,
      onChanged: _submitting
          ? null
          : (selected) => setState(() => _enableBiometricOnUnlock = selected),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final biometric =
        ref.watch(biometricUnlockProvider).value ??
        BiometricUnlockState.initial;
    final subtitle = _submitting
        ? context.l10n.onboardingUnlockOpening
        : _selectedRule != null
        ? context.l10n.accountVisibilityEnterWalletPasscode
        : context.l10n.onboardingUnlockEnterPasscode;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: AdaptivePasscodeLayout(
          title: context.l10n.commonWelcomeBack,
          subtitle: subtitle,
          prompt: PasscodePromptField(
            length: kMobilePasscodeLength,
            filled: _entry.length,
            error: _error?.resolve(context.l10n),
            minGap: 0,
          ),
          keypad: PasscodeNumpad(
            onDigit: _onDigit,
            onBackspace: _onBackspace,
            canDelete: _entry.isNotEmpty,
            enabled: !_submitting,
            onHelp: _submitting || _selectedRule != null
                ? null
                : _showForgotPasscodeSheet,
          ),
          legacyPadding: const EdgeInsets.symmetric(
            horizontal: kMobilePageMargin,
            vertical: AppSpacing.md,
          ),
          scaleLegacyKeypadToWidth: true,
          footerHeight: 44,
          footer: ConstrainedBox(
            key: const ValueKey('mobile_unlock_biometric_footer'),
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(child: _buildUnlockFooter(biometric)),
          ),
          legacy: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kMobilePageMargin,
              vertical: AppSpacing.md,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final keypadScale = math.min(
                  1.0,
                  constraints.maxWidth / kPasscodeKeypadWidth,
                );
                return CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    context.l10n.commonWelcomeBack,
                                    textAlign: TextAlign.center,
                                    style: AppTypography.displayLarge.copyWith(
                                      color: colors.text.accent,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s),
                                  Text(
                                    subtitle,
                                    textAlign: TextAlign.center,
                                    style: AppTypography.bodyMediumStrong
                                        .copyWith(color: colors.text.primary),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  SizedBox(
                                    height: kPasscodePromptDigitsHeight,
                                    child: PasscodePromptField(
                                      length: kMobilePasscodeLength,
                                      filled: _entry.length,
                                      error: _error?.resolve(context.l10n),
                                      minGap: 0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            height: kPasscodeKeypadHeight * keypadScale,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: SizedBox(
                                width: kPasscodeKeypadWidth,
                                height: kPasscodeKeypadHeight,
                                child: PasscodeNumpad(
                                  onDigit: _onDigit,
                                  onBackspace: _onBackspace,
                                  canDelete: _entry.isNotEmpty,
                                  onHelp: _submitting || _selectedRule != null
                                      ? null
                                      : _showForgotPasscodeSheet,
                                  enabled: !_submitting,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ConstrainedBox(
                            key: const ValueKey(
                              'mobile_unlock_biometric_footer',
                            ),
                            constraints: const BoxConstraints(minHeight: 44),
                            child: Center(child: _buildUnlockFooter(biometric)),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
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
