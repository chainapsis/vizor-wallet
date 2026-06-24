import 'dart:async';

import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../main.dart' show log;
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_icon.dart';
import '../../providers/account_provider.dart';
import '../../providers/device_owner_auth_provider.dart';
import '../../providers/sync_provider.dart';
import '../../services/device_owner_auth.dart';
import 'shared/onboarding_auth_shell.dart';

class LostPasswordScreen extends ConsumerStatefulWidget {
  const LostPasswordScreen({
    super.key,
    this.initialCountdownSeconds = 3,
    this.countdownEnabled = true,
    this.onBack,
    this.onReset,
  });

  final int initialCountdownSeconds;
  final bool countdownEnabled;
  final VoidCallback? onBack;
  final Future<void> Function()? onReset;

  @override
  ConsumerState<LostPasswordScreen> createState() => _LostPasswordScreenState();
}

class _LostPasswordScreenState extends ConsumerState<LostPasswordScreen> {
  Timer? _countdownTimer;
  late int _remainingSeconds;
  bool _isResetting = false;
  String? _error;

  bool get _canReset => _remainingSeconds <= 0 && !_isResetting;

  @override
  void initState() {
    super.initState();
    _remainingSeconds =
        widget.initialCountdownSeconds < 0 ? 0 : widget.initialCountdownSeconds;
    if (widget.countdownEnabled && _remainingSeconds > 0) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {
          _remainingSeconds -= 1;
          if (_remainingSeconds <= 0) {
            _remainingSeconds = 0;
            _countdownTimer?.cancel();
            _countdownTimer = null;
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _handleBack() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    context.go('/unlock');
  }

  Future<void> _handleReset() async {
    if (!_canReset) return;
    setState(() {
      _isResetting = true;
      _error = null;
    });

    try {
      final verified = await verifyDeviceOwnerForWalletReset(ref);
      if (!mounted) return;
      if (!verified) {
        setState(() {
          _isResetting = false;
          _error = null;
        });
        return;
      }

      final onReset = widget.onReset;
      if (onReset != null) {
        await onReset();
        if (!mounted) return;
        setState(() {
          _isResetting = false;
        });
      } else {
        await _resetWallet();
        if (!mounted) return;
        context.go('/welcome');
      }
    } on DeviceOwnerAuthException catch (e, st) {
      log('LostPasswordScreen._handleReset auth failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isResetting = false;
        _error =
            e.kind == DeviceOwnerAuthErrorKind.unavailable
                ? kWalletResetDeviceAuthRequiredMessage
                : kWalletResetDeviceAuthFailedMessage;
      });
    } catch (e, st) {
      log('LostPasswordScreen._handleReset: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isResetting = false;
      });
    }
  }

  Future<void> _resetWallet() async {
    final syncNotifier = ref.read(syncProvider.notifier);
    final accountNotifier = ref.read(accountProvider.notifier);

    await syncNotifier.clearSensitiveStateForLock();
    try {
      await accountNotifier.resetWallet();
    } finally {
      syncNotifier.clearCachedWalletDbPath();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: OnboardingAuthShell(
          card: OnboardingAuthCard(
            width: _LostPasswordContent.cardWidth,
            height: _LostPasswordContent.cardHeight,
            borderRadius: AppSpacing.md,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: _LostPasswordContent(
              remainingSeconds: _remainingSeconds,
              canReset: _canReset,
              error: _error,
              onBack: _handleBack,
              onReset: _handleReset,
            ),
          ),
        ),
      ),
    );
  }
}

class _LostPasswordContent extends StatelessWidget {
  const _LostPasswordContent({
    required this.remainingSeconds,
    required this.canReset,
    required this.error,
    required this.onBack,
    required this.onReset,
  });

  final int remainingSeconds;
  final bool canReset;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onReset;

  static const double cardWidth = 396;
  static const double cardHeight = 520;
  static const double _buttonGroupWidth = 348;
  static const double _destructiveButtonWidth = 232;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
    );
    final strongStyle = AppTypography.bodyMediumStrong.copyWith(
      color: colors.text.accent,
    );
    final buttonLabel =
        remainingSeconds > 0
            ? 'Reset after ${remainingSeconds}s...'
            : 'Reset Vizor';
    final statusText = error ?? 'This cannot be undone.';

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Figma: this screen's badge sits on a 30% gray shield, unlike the
        // crimson welcome/unlock badge.
        Image.asset(
          'assets/illustrations/lost_password_badge.png',
          width: 50,
          height: 50,
        ),
        const SizedBox(height: AppSpacing.base),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Lost password?',
              style: AppTypography.displayMedium.copyWith(
                color: colors.text.accent,
                height: 48 / 45,
              ),
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            // Line breaks pinned to the design's rendered wrap (348px box).
            Text.rich(
              TextSpan(
                style: bodyStyle,
                children: [
                  const TextSpan(
                    text:
                        "If you've lost your password, the only way to recover\nyour account is to ",
                  ),
                  TextSpan(
                    text: 'completely reset Vizor app',
                    style: strongStyle,
                  ),
                  const TextSpan(
                    text:
                        ', which\nmeans deleting all accounts and requiring you to\n',
                  ),
                  TextSpan(text: 'import accounts again', style: strongStyle),
                  const TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.base),
        SizedBox(
          width: _buttonGroupWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                statusText,
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.destructive,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    onPressed: canReset ? onReset : null,
                    variant: AppButtonVariant.destructive,
                    minWidth: _destructiveButtonWidth,
                    leading: const AppIcon(AppIcons.warning, size: 20),
                    child: Text(buttonLabel),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  AppButton(
                    onPressed: onBack,
                    variant: AppButtonVariant.ghost,
                    minWidth: _destructiveButtonWidth,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
