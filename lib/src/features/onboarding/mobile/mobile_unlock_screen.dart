import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/theme/app_theme.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/router_refresh_provider.dart';
import '../../../providers/sync_provider.dart';
import 'mobile_passcode_screen.dart' show kMobilePasscodeLength;
import 'passcode_widgets.dart';

/// Mobile unlock screen: the six-digit passcode set during onboarding
/// is the wallet password, so unlocking re-enters it on the same serif
/// numpad. (No dedicated unlock frame exists in the mobile Figma yet —
/// this mirrors the passcode-entry frames.)
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
        _error = 'Incorrect passcode. Try again.';
      });
    }
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
            Text(
              'Enter Passcode',
              textAlign: TextAlign.center,
              style: AppTypography.displayLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _submitting ? 'Opening your wallet...' : 'Unlock your wallet.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
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
            const Spacer(),
            PasscodeNumpad(
              onDigit: _onDigit,
              onBackspace: _onBackspace,
              canDelete: _entry.isNotEmpty,
              enabled: !_submitting,
            ),
            const SizedBox(height: AppSpacing.s),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _submitting ? null : () => context.go('/lost-password'),
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(
                      'Forgot passcode?',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
        ),
      ),
    );
  }
}
