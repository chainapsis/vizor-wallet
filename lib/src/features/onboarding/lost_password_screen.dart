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
import '../../providers/sync_provider.dart';
import 'shared/onboarding_welcome_art.dart';

const double _lostPasswordContentMaxWidth = 420;
const double _lostPasswordCardHorizontalMargin = AppSpacing.s;
const double _lostPasswordCardMinHeight = 509;
const double _lostPasswordActionWidth = 256;
const double _lostPasswordWordmarkWidth = 93;
const double _lostPasswordWordmarkHeight = 35.1;

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
        if (!mounted) return;
        setState(() {
          _isResetting = false;
        });
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

    await syncNotifier.clearSensitiveStateForLock();
    await accountNotifier.resetWallet();
    syncNotifier.clearCachedWalletDbPath();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: _LostPasswordPane(
            child: _LostPasswordContent(
              remainingSeconds: _remainingSeconds,
              canReset: _canReset,
              onCancel: _handleBack,
              onReset: _handleReset,
            ),
          ),
        ),
      ),
    );
  }
}

class _LostPasswordPane extends StatelessWidget {
  const _LostPasswordPane({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? colors.background.ground : colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const topInset = AppSpacing.lg;
          const bottomInset = AppSpacing.md;
          final minHeight = (constraints.maxHeight - topInset - bottomInset)
              .clamp(0.0, double.infinity)
              .toDouble();
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, topInset, 0, bottomInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _lostPasswordContentMaxWidth,
                  ),
                  child: child,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LostPasswordContent extends StatelessWidget {
  const _LostPasswordContent({
    required this.remainingSeconds,
    required this.canReset,
    required this.onCancel,
    required this.onReset,
  });

  final int remainingSeconds;
  final bool canReset;
  final VoidCallback onCancel;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
    );
    final strongStyle = AppTypography.bodyMediumStrong.copyWith(
      color: colors.text.accent,
    );
    final buttonLabel = remainingSeconds > 0
        ? 'Reset after ${remainingSeconds}s...'
        : 'Reset Vizor';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _lostPasswordCardHorizontalMargin,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? colors.background.base : colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.large),
          boxShadow: [
            BoxShadow(
              color: colors.shadows.regular,
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: _lostPasswordCardMinHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Opacity(
                    opacity: 0.5,
                    child: VizorWordmark(
                      width: _lostPasswordWordmarkWidth,
                      height: _lostPasswordWordmarkHeight,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Lost Password?',
                    style: AppTypography.displayMedium.copyWith(
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
                        TextSpan(
                          text: 'import accounts again',
                          style: strongStyle,
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _DestructiveNotice(color: colors.text.destructive),
                  const SizedBox(height: AppSpacing.md),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final actionWidth =
                          constraints.maxWidth < _lostPasswordActionWidth
                          ? constraints.maxWidth
                          : _lostPasswordActionWidth;
                      return SizedBox(
                        width: actionWidth,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppButton(
                              onPressed: canReset ? onReset : null,
                              variant: AppButtonVariant.destructive,
                              minWidth: actionWidth,
                              trailing: const AppIcon(
                                AppIcons.chevronForward,
                                size: 20,
                              ),
                              child: Text(buttonLabel),
                            ),
                            const SizedBox(height: AppSpacing.s),
                            AppButton(
                              onPressed: onCancel,
                              variant: AppButtonVariant.ghost,
                              minWidth: actionWidth,
                              child: const Text('Cancel'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
