import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../../providers/sync_provider.dart';
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
  String? _error;

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
      builder: (sheetContext) => const _ForgotPasscodeSheet(),
    );
    if (confirmed != true || !mounted) return;
    await _resetWallet();
  }

  /// Same reset sequence as the desktop lost-password flow: the only
  /// recovery without the passcode is wiping the wallet and importing
  /// again.
  Future<void> _resetWallet() async {
    setState(() => _submitting = true);
    final router = GoRouter.of(context);
    final syncNotifier = ref.read(syncProvider.notifier);
    final accountNotifier = ref.read(accountProvider.notifier);
    try {
      await syncNotifier.clearSensitiveStateForLock();
      await accountNotifier.resetWallet();
      syncNotifier.clearCachedWalletDbPath();
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
            const SizedBox(height: AppSpacing.md),
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
            const SizedBox(height: AppSpacing.md),
            PasscodeDots(length: kMobilePasscodeLength, filled: _entry.length),
            SizedBox(
              height: 44,
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
            PasscodeNumpad(
              onDigit: _onDigit,
              onBackspace: _onBackspace,
              canDelete: _entry.isNotEmpty,
              onHelp: _submitting ? null : _showForgotPasscodeSheet,
              enabled: !_submitting,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

/// Figma `Forgot Passcode` (4596:50252): the reset confirmation sheet.
class _ForgotPasscodeSheet extends StatelessWidget {
  const _ForgotPasscodeSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Forgot Passcode?',
                    style: AppTypography.headlineSmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Close',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(false),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: colors.background.raised,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '✕',
                          style: AppTypography.labelMedium.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "If you can't remember your passcode, the only way to "
              'recover your account is to completely reset the Vizor app, '
              'which means deleting all accounts and requiring you to '
              'import accounts again.',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const ValueKey('mobile_forgot_passcode_reset'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Continue to reset Vizor'),
            ),
            const SizedBox(height: AppSpacing.s),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(false),
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(
                      'Cancel',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
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
