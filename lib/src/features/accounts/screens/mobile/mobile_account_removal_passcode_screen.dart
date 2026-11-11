import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../main.dart' show log;
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/biometric_icon.dart';
import '../../../../providers/app_security_provider.dart';
import '../../../../providers/biometric_unlock_provider.dart';
import '../../../../services/biometric_unlock.dart';
import '../../../onboarding/mobile/mobile_passcode_screen.dart'
    show kMobilePasscodeLength;
import '../../../onboarding/mobile/adaptive_passcode_layout.dart';
import '../../../onboarding/mobile/passcode_widgets.dart';

const double _kBiometricFooterHeight = 36;

class MobileAccountRemovalPasscodeScreen extends ConsumerStatefulWidget {
  const MobileAccountRemovalPasscodeScreen({
    required this.isLastAccount,
    super.key,
  });

  final bool isLastAccount;

  @override
  ConsumerState<MobileAccountRemovalPasscodeScreen> createState() =>
      _MobileAccountRemovalPasscodeScreenState();
}

class _MobileAccountRemovalPasscodeScreenState
    extends ConsumerState<MobileAccountRemovalPasscodeScreen> {
  String _entry = '';
  String? _error;
  bool _checking = false;

  // A popped screen can stay mounted during its exit animation.
  bool get _isCurrentRoute => ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_tryBiometricGate());
    });
  }

  @override
  void dispose() {
    _entry = '';
    super.dispose();
  }

  Future<void> _tryBiometricGate() async {
    if (!mounted || _checking) return;
    final entryAtStart = _entry;
    final BiometricUnlockState biometric;
    try {
      biometric = await ref.read(biometricUnlockProvider.future);
    } catch (e, st) {
      log('MobileAccountRemoval: biometric probe failed: $e\n$st');
      return;
    }
    // Leaving or typing during the probe keeps the prompt from appearing.
    if (!mounted ||
        !_isCurrentRoute ||
        _checking ||
        _entry != entryAtStart ||
        !biometric.usable) {
      return;
    }
    setState(() => _checking = true);
    String? passcode;
    try {
      passcode = await ref
          .read(biometricUnlockProvider.notifier)
          .readPasscode(
            reason: widget.isLastAccount
                ? context.l10n.accountsRemovalResetBiometricReason
                : context.l10n.accountsRemovalRemoveBiometricReason,
          );
    } catch (e, st) {
      log('MobileAccountRemoval: biometric read failed: $e\n$st');
    }
    if (!mounted || !_isCurrentRoute) return;
    if (passcode == null) {
      final now = ref.read(biometricUnlockProvider).value;
      setState(() {
        _entry = '';
        _checking = false;
        if (now != null && !now.enabled) {
          _error = biometric.availability.kind.changedMessage(context.l10n);
        }
      });
      return;
    }
    setState(() {
      _entry = passcode!;
      _error = null;
    });
    await _confirmPasscode();
  }

  void _onDigit(int digit) {
    if (_checking || _entry.length >= kMobilePasscodeLength) return;
    setState(() {
      _entry += '$digit';
      _error = null;
    });
    if (_entry.length == kMobilePasscodeLength) {
      unawaited(_confirmPasscode());
    }
  }

  Future<void> _confirmPasscode() async {
    setState(() => _checking = true);
    try {
      final verified = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(_entry);
      if (!mounted || !_isCurrentRoute) return;
      if (verified) {
        unawaited(AppHaptics.accessGranted());
        _entry = '';
        context.pop(true);
        return;
      }
      unawaited(AppHaptics.error());
      setState(() => _error = context.l10n.settingsIncorrectPasscode);
    } catch (_) {
      if (!mounted || !_isCurrentRoute) return;
      setState(() => _error = context.l10n.settingsPasscodeCheckFailed);
    } finally {
      if (mounted) {
        setState(() {
          _entry = '';
          _checking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final biometric =
        ref.watch(biometricUnlockProvider).value ??
        BiometricUnlockState.initial;
    final biometricFooter = !_checking && biometric.usable
        ? SizedBox(
            key: const ValueKey('mobile_account_removal_biometric_footer'),
            height: _kBiometricFooterHeight,
            child: Center(
              child: PasscodeBiometricButton(
                label: biometric.availability.kind.signInLabel(context.l10n),
                icon: Center(
                  child: BiometricIcon(
                    kind: biometric.availability.kind,
                    size: 13.5,
                    fingerprintSize: 16,
                  ),
                ),
                onPressed: () => unawaited(_tryBiometricGate()),
              ),
            ),
          )
        : null;
    final title = context.l10n.settingsEnterPasscodeTitle;
    const titleKey = ValueKey('mobile_account_removal_passcode');
    final subtitle = widget.isLastAccount
        ? context.l10n.accountsRemovalPasscodeResetSubtitle
        : context.l10n.accountsRemovalPasscodeRemoveSubtitle;
    final prompt = PasscodePromptField(
      length: kMobilePasscodeLength,
      filled: _entry.length,
      error: _error,
      minGap: 0,
    );
    final keypad = PasscodeNumpad(
      onDigit: _onDigit,
      onBackspace: () {
        if (_checking || _entry.isEmpty) return;
        setState(() => _entry = _entry.substring(0, _entry.length - 1));
      },
      canDelete: _entry.isNotEmpty,
      enabled: !_checking,
    );
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(title: '', onBack: () => context.pop(false)),
            Expanded(
              child: AdaptivePasscodeLayout(
                title: title,
                titleKey: titleKey,
                subtitle: subtitle,
                prompt: prompt,
                keypad: keypad,
                footer: biometricFooter,
                footerHeight: biometricFooter == null
                    ? 0
                    : _kBiometricFooterHeight,
                legacyPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.md,
                ),
                legacy: Padding(
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
                                title,
                                key: titleKey,
                                textAlign: TextAlign.center,
                                style: AppTypography.displayLarge.copyWith(
                                  color: colors.text.accent,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s),
                              Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                style: AppTypography.bodyMediumStrong.copyWith(
                                  color: colors.text.primary,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              SizedBox(
                                height: kPasscodePromptDigitsHeight,
                                child: prompt,
                              ),
                            ],
                          ),
                        ),
                      ),
                      keypad,
                      const SizedBox(height: AppSpacing.md),
                      ?biometricFooter,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
