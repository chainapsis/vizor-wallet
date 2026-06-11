import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/storage/app_secure_store.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/app_security_provider.dart';
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

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final didChange = await ref
          .read(appSecurityProvider.notifier)
          .changePassword(
            currentPassword: _currentPasscode!,
            newPassword: _newPasscode!,
          );
      if (!mounted) return;
      if (!didChange) {
        // The verified passcode stopped matching the stored verifier —
        // restart from scratch rather than trusting stale state.
        setState(() {
          _submitting = false;
          _restartFlow('Incorrect Passcode');
        });
        return;
      }
      Navigator.of(context).pop(true);
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

    setState(() => _submitting = true);
    final router = GoRouter.of(context);
    try {
      await resetWalletForForgottenPasscode(ref);
    } catch (e, st) {
      log('MobileChangePasscode._showForgotPasscodeSheet: ERROR: $e\n$st');
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
              onBack: _submitting ? null : () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.displayLarge.copyWith(
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
            const SizedBox(height: AppSpacing.xl),
            PasscodeDots(length: kMobilePasscodeLength, filled: _entry.length),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Center(
                child: _error == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.destructive,
                          ),
                        ),
                      ),
              ),
            ),
            const Spacer(),
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
