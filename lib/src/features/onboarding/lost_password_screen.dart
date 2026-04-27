import 'dart:async';

import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../main.dart' show log;
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_decorative_divider.dart';
import '../../core/widgets/app_icon.dart';
import '../../providers/account_provider.dart';
import '../../providers/sync_provider.dart';
import '../../rust/api/sync.dart' as rust_sync;
import 'shared/onboarding_welcome_art.dart';

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

  bool get _canReset => _remainingSeconds <= 0 && !_isResetting;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.initialCountdownSeconds < 0
        ? 0
        : widget.initialCountdownSeconds;
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
    });

    try {
      final onReset = widget.onReset;
      if (onReset != null) {
        await onReset();
      } else {
        await _resetWallet();
        if (!mounted) return;
        context.go('/welcome');
      }
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

    syncNotifier.stopSync();
    var waited = 0;
    while (rust_sync.isSyncRunning() && waited < 5000) {
      await Future.delayed(const Duration(milliseconds: 100));
      waited += 100;
    }

    await accountNotifier.resetWallet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: _LostPasswordPane(
            onBack: _handleBack,
            child: _LostPasswordContent(
              remainingSeconds: _remainingSeconds,
              canReset: _canReset,
              onReset: _handleReset,
            ),
          ),
        ),
      ),
    );
  }
}

class _LostPasswordPane extends StatelessWidget {
  const _LostPasswordPane({required this.child, required this.onBack});

  final Widget child;
  final VoidCallback onBack;

  static const double _canvasWidth = 1064;
  static const double _canvasHeight = 672;
  static const double _backdropWidth = 1064;
  static const double _backdropHeight = 672;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final alignment = constraints.maxHeight < _canvasHeight
              ? Alignment.bottomCenter
              : Alignment.center;
          return OverflowBox(
            alignment: alignment,
            minWidth: _canvasWidth,
            maxWidth: _canvasWidth,
            minHeight: _canvasHeight,
            maxHeight: _canvasHeight,
            child: SizedBox(
              width: _canvasWidth,
              height: _canvasHeight,
              child: Stack(
                children: [
                  const Positioned(
                    top: 0,
                    left: 0,
                    width: _backdropWidth,
                    height: _backdropHeight,
                    child: OnboardingWelcomeBackdrop(),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        children: [
                          Align(
                            alignment: Alignment.topLeft,
                            child: _LostPasswordBackButton(onPressed: onBack),
                          ),
                          Expanded(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.base,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: AppSpacing.md,
                                  ),
                                  child: child,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LostPasswordBackButton extends StatelessWidget {
  const _LostPasswordBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.chevronBackward,
                size: AppIconSize.medium,
                color: colors.text.accent,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Back',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
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
    required this.onReset,
  });

  final int remainingSeconds;
  final bool canReset;
  final VoidCallback onReset;

  static const double _contentWidth = 349;
  static const double _buttonWidth = 256;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
    );
    final strongStyle = AppTypography.bodyMediumStrong.copyWith(
      color: colors.text.accent,
    );
    final buttonLabel = remainingSeconds > 0
        ? 'Reset after ${remainingSeconds}s...'
        : 'Reset Vizor';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _contentWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Lost Password?',
                style: AppTypography.displayLarge.copyWith(
                  color: colors.text.accent,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Text.rich(
                TextSpan(
                  style: bodyStyle,
                  children: [
                    const TextSpan(
                      text:
                          "If you've lost your password, the only way to recover your account is to ",
                    ),
                    TextSpan(
                      text: 'completely reset Vizor app',
                      style: strongStyle,
                    ),
                    const TextSpan(
                      text:
                          ', which means deleting all accounts and requiring you to ',
                    ),
                    TextSpan(text: 'import accounts again', style: strongStyle),
                    const TextSpan(text: '.'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const AppDecorativeDivider(width: _buttonWidth),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: _buttonWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                onPressed: canReset ? onReset : null,
                variant: AppButtonVariant.destructive,
                minWidth: _buttonWidth,
                trailing: const AppIcon(AppIcons.chevronForward, size: 20),
                child: Text(buttonLabel),
              ),
              const SizedBox(height: AppSpacing.md),
              _DestructiveNotice(color: colors.text.destructive),
            ],
          ),
        ),
      ],
    );
  }
}

class _DestructiveNotice extends StatelessWidget {
  const _DestructiveNotice({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(AppIcons.warning, size: AppIconSize.medium, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          'This cannot be undone.',
          style: AppTypography.bodyMediumStrong.copyWith(color: color),
        ),
      ],
    );
  }
}
