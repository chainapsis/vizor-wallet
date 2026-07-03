import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_layout.dart';
import '../../../core/security/password_policy.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/voting/voting_submission_guard_provider.dart';
import '../../../providers/wallet_mutation_guard.dart';
import '../../swap/providers/swap_activity_store.dart';
import '../widgets/confirm_access_card.dart';
import '../widgets/settings_pane_backdrop.dart';
import '../../../../l10n/app_localizations.dart';

/// Full-window uninstall flow: confirm -> password gate -> removing -> done.
///
/// The wipe itself is the existing full-wallet-reset path used by
/// last-account removal (accounts screen); the password gate mirrors the
/// confirmation the account remove modal requires before destroying data.
class SettingsUninstallScreen extends ConsumerStatefulWidget {
  const SettingsUninstallScreen({this.initialStage, super.key});

  /// Preview/test-only stage override (Widgetbook demos). Production entry
  /// always starts at the confirm stage and must go through the gate.
  final SettingsUninstallStage? initialStage;

  @override
  ConsumerState<SettingsUninstallScreen> createState() =>
      _SettingsUninstallScreenState();
}

enum SettingsUninstallStage { confirm, gate, removing, done }

// The wipe itself is pure Dart/Rust and platform-agnostic; only the copy
// references the host platform.
String _wipeSubtitle(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return l10n.settingsUninstallBody(
    Platform.isMacOS
        ? l10n.settingsThisMac
        : Platform.isWindows
        ? l10n.settingsThisPc
        : l10n.settingsThisDevice,
  );
}

String _finishSubtitle(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return Platform.isMacOS
      ? l10n.settingsUninstallFinishMac
      : Platform.isWindows
      ? l10n.settingsUninstallFinishWindows
      : l10n.settingsUninstallFinishOther;
}

class _SettingsUninstallScreenState
    extends ConsumerState<SettingsUninstallScreen>
    with SingleTickerProviderStateMixin {
  String get _wipeFailedMessage =>
      AppLocalizations.of(context).settingsRemoveDataFailed;

  final _passwordController = TextEditingController();
  late final AnimationController _progressController;

  late SettingsUninstallStage _stage =
      widget.initialStage ?? SettingsUninstallStage.confirm;
  String? _confirmError;
  String? _gateError;
  bool _isSubmitting = false;
  bool _isCheckingSwaps = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );
  }

  @override
  void dispose() {
    _progressController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmitGate =>
      !_isSubmitting && isWalletPasswordValid(_passwordController.text);

  bool _blockIfVotingSubmissionInProgress() {
    final guards = ref.read(votingSubmissionGuardProvider);
    if (guards.isEmpty) return false;
    showAppToast(context, guards.first.message);
    return true;
  }

  Future<void> _openGate() async {
    if (_isCheckingSwaps) return;
    if (_blockIfVotingSubmissionInProgress()) return;

    // Same stranded-funds rule as account removal: while any account still
    // has a non-terminal swap with deposit evidence, ZEC may arrive after
    // the wipe and be lost.
    setState(() {
      _isCheckingSwaps = true;
      _confirmError = null;
    });
    try {
      final accounts =
          ref.read(accountProvider).value?.accounts ?? const <AccountInfo>[];
      var pendingSwapCount = 0;
      for (final account in accounts) {
        pendingSwapCount += await ref.read(
          swapPendingIntentCountProvider(account.uuid).future,
        );
      }
      if (!mounted) return;
      if (pendingSwapCount > 0) {

        setState(() {
          _isCheckingSwaps = false;
          _confirmError =
              AppLocalizations.of(context).settingsActiveSwapsBlockUninstall(pendingSwapCount);
        });
        return;
      }
    } catch (e, st) {
      log('SettingsUninstallScreen._openGate: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isCheckingSwaps = false;
        _confirmError =
            AppLocalizations.of(context).settingsSwapCheckFailed;
      });
      return;
    }

    setState(() {
      _isCheckingSwaps = false;
      _stage = SettingsUninstallStage.gate;
      _confirmError = null;
      _gateError = null;
      _passwordController.clear();
    });
  }

  void _cancel() {
    if (_stage == SettingsUninstallStage.gate) {
      setState(() {
        _stage = SettingsUninstallStage.confirm;
        _passwordController.clear();
        _gateError = null;
      });
      return;
    }
    context.go('/settings');
  }

  Future<void> _submitGatePassword() async {
    if (_isSubmitting) return;
    if (!isWalletPasswordValid(_passwordController.text)) {
      final policyError = validateWalletPasswordLocalized(
        _passwordController.text,
        AppLocalizations.of(context),
      );
      if (policyError == null) return;
      setState(() {
        _gateError = policyError;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _gateError = null;
    });

    try {
      final isValid = await ref
          .read(appSecurityProvider.notifier)
          .confirmPassword(_passwordController.text);
      if (!mounted) return;
      if (!isValid) {
        setState(() {
          _gateError = AppLocalizations.of(context).accountsIncorrectPassword;
          _isSubmitting = false;
        });
        return;
      }
      _passwordController.clear();
      await _runUninstall();
    } catch (e, st) {
      log('SettingsUninstallScreen._submitGatePassword: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _gateError = AppLocalizations.of(context).settingsPasswordCheckFailed;
        _isSubmitting = false;
      });
    }
  }

  Future<void> _runUninstall() async {
    if (_blockIfVotingSubmissionInProgress()) {
      setState(() {
        _stage = SettingsUninstallStage.confirm;
        _isSubmitting = false;
      });
      return;
    }

    setState(() {
      _stage = SettingsUninstallStage.removing;
      _isSubmitting = false;
    });
    // Synthetic progress: resetWallet is a single await with no percentage
    // source, so ease toward 90% while it runs and snap to 100% at the end.
    _progressController.value = 0;
    unawaited(_progressController.animateTo(0.9, curve: Curves.easeOutCubic));

    final accountNotifier = ref.read(accountProvider.notifier);

    try {
      await runWithSyncPausedForWalletReset(ref, accountNotifier.resetWallet);
      if (!mounted) return;
      await _progressController.animateTo(
        1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      if (!mounted) return;
      setState(() {
        _stage = SettingsUninstallStage.done;
      });
    } catch (e, st) {
      log('SettingsUninstallScreen._runUninstall: ERROR: $e\n$st');
      if (!mounted) return;
      _progressController.stop();
      setState(() {
        _stage = SettingsUninstallStage.confirm;
        _confirmError = _wipeFailedMessage;
      });
    }
  }

  void _closeApp() {
    // SystemNavigator.pop() does not terminate a Flutter desktop app, so use
    // window_manager to actually close the window. No close interceptors
    // (setPreventClose/onWindowClose) are registered anywhere in the app, so
    // destroy() exits unintercepted.
    if (isDesktopLayoutPlatform) {
      unawaited(windowManager.destroy());
      return;
    }
    unawaited(SystemNavigator.pop());
  }

  @override
  Widget build(BuildContext context) {
    final showBackdrop =
        _stage == SettingsUninstallStage.confirm ||
        _stage == SettingsUninstallStage.gate;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (showBackdrop)
          const Positioned.fill(
            child: SettingsPaneBackdrop(art: SettingsBackdropArt.castle),
          ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: _UninstallPane(
              child: switch (_stage) {
                SettingsUninstallStage.confirm => _UninstallConfirmView(
                  errorText: _confirmError,
                  isCheckingSwaps: _isCheckingSwaps,
                  onUninstall: () {
                    unawaited(_openGate());
                  },
                  onCancel: _cancel,
                ),
                SettingsUninstallStage.gate => _UninstallGateView(
                  passwordController: _passwordController,
                  errorText: _gateError,
                  isSubmitting: _isSubmitting,
                  canSubmit: _canSubmitGate,
                  onChanged: () {
                    if (_gateError == null) {
                      setState(() {});
                      return;
                    }
                    setState(() {
                      _gateError = null;
                    });
                  },
                  onSubmit: _submitGatePassword,
                  onCancel: _cancel,
                ),
                SettingsUninstallStage.removing => _UninstallDataRemovalView(
                  isDone: false,
                  progress: _progressController,
                  onClose: _closeApp,
                ),
                SettingsUninstallStage.done => _UninstallDataRemovalView(
                  isDone: true,
                  progress: _progressController,
                  onClose: _closeApp,
                ),
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _UninstallPane extends StatelessWidget {
  const _UninstallPane({required this.child});

  final Widget child;

  static const double _canvasWidth = 1064;
  static const double _canvasHeight = 672;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

class _UninstallCard extends StatelessWidget {
  const _UninstallCard({
    required this.helmetOpacity,
    required this.title,
    required this.subtitle,
    required this.subtitleWidth,
    required this.action,
  });

  final Animation<double> helmetOpacity;
  final String title;
  final String subtitle;
  final double subtitleWidth;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 396,
      height: 520,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: 348,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _UninstallBadge(helmetOpacity: helmetOpacity),
                const SizedBox(height: AppSpacing.base),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.displayMedium.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: subtitleWidth,
                      child: Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.base),
                action,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UninstallBadge extends StatelessWidget {
  const _UninstallBadge({required this.helmetOpacity});

  /// The shield always stays visible; only the helmet fades.
  final Animation<double> helmetOpacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('settings_uninstall_badge'),
      width: 50,
      height: 50,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: SvgPicture.asset(
              key: const ValueKey('settings_uninstall_badge_shield'),
              'assets/illustrations/uninstall_badge_shield.svg',
            ),
          ),
          FadeTransition(
            key: const ValueKey('settings_uninstall_badge_helmet'),
            opacity: helmetOpacity,
            child: Transform.translate(
              offset: const Offset(-0.63, -3.13),
              child: Image.asset(
                'assets/illustrations/uninstall_badge_helmet.png',
                width: 38.75,
                height: 38.75,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UninstallConfirmView extends StatelessWidget {
  const _UninstallConfirmView({
    required this.errorText,
    required this.isCheckingSwaps,
    required this.onUninstall,
    required this.onCancel,
  });

  final String? errorText;
  final bool isCheckingSwaps;
  final VoidCallback onUninstall;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return _UninstallCard(
      helmetOpacity: const AlwaysStoppedAnimation(1),
      title: AppLocalizations.of(context).settingsUninstallVizor,
      subtitle: _wipeSubtitle(context),
      subtitleWidth: 240,
      action: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              errorText ?? AppLocalizations.of(context).settingsCannotBeUndone,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.destructive,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              onPressed: isCheckingSwaps ? null : onUninstall,
              variant: AppButtonVariant.destructive,
              minWidth: 196,
              leading: AppIcon(
                isCheckingSwaps ? AppIcons.loader : AppIcons.warning,
                size: 20,
                animated: isCheckingSwaps,
              ),
              child: Text(
                isCheckingSwaps
                  ? AppLocalizations.of(context).settingsCheckingSwaps
                  : AppLocalizations.of(context).settingsUninstallVizor,
              ),
            ),
            const SizedBox(height: AppSpacing.s),
            AppButton(
              onPressed: isCheckingSwaps ? null : onCancel,
              variant: AppButtonVariant.ghost,
              minWidth: 196,
              child: Text(AppLocalizations.of(context).commonCancel),
            ),
          ],
        ),
      ),
    );
  }
}

class _UninstallGateView extends StatelessWidget {
  const _UninstallGateView({
    required this.passwordController,
    required this.errorText,
    required this.isSubmitting,
    required this.canSubmit,
    required this.onChanged,
    required this.onSubmit,
    required this.onCancel,
  });

  final TextEditingController passwordController;
  final String? errorText;
  final bool isSubmitting;
  final bool canSubmit;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConfirmAccessCard(
          subtitle: AppLocalizations.of(context).settingsToUninstall,
          controller: passwordController,
          errorText: errorText,
          isSubmitting: isSubmitting,
          canSubmit: canSubmit,
          onChanged: onChanged,
          onSubmit: onSubmit,
        ),
        const SizedBox(height: AppSpacing.s),
        AppButton(
          onPressed: isSubmitting ? null : onCancel,
          variant: AppButtonVariant.ghost,
          minWidth: 196,
          child: Text(AppLocalizations.of(context).commonCancel),
        ),
      ],
    );
  }
}

class _UninstallDataRemovalView extends StatefulWidget {
  const _UninstallDataRemovalView({
    required this.isDone,
    required this.progress,
    required this.onClose,
  });

  final bool isDone;
  final Animation<double> progress;
  final VoidCallback onClose;

  @override
  State<_UninstallDataRemovalView> createState() =>
      _UninstallDataRemovalViewState();
}

class _UninstallDataRemovalViewState extends State<_UninstallDataRemovalView>
    with SingleTickerProviderStateMixin {
  // Done-stage badge motion: keep the helmet visible for 1000ms after the
  // screen copy changes, then fade it out over 500ms. The shield never moves.
  static const _helmetHoldMs = 1000;
  static const _helmetFadeMs = 500;
  static const _titleSlotHeight = 154.0;
  static const _actionSlotHeight = 41.0;
  static const _contentHeight =
      50.0 +
      AppSpacing.base +
      _titleSlotHeight +
      AppSpacing.base +
      _actionSlotHeight;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _helmetHoldMs + _helmetFadeMs),
  );

  late final Animation<double> _helmetOpacity = Tween<double>(begin: 1, end: 0)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(
            _helmetHoldMs / (_helmetHoldMs + _helmetFadeMs),
            1,
            curve: Curves.easeOut,
          ),
        ),
      );

  @override
  void initState() {
    super.initState();
    if (widget.isDone) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant _UninstallDataRemovalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isDone && widget.isDone) {
      _controller.forward(from: 0);
    } else if (oldWidget.isDone && !widget.isDone) {
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = widget.isDone
        ? AppLocalizations.of(context).settingsDataRemoved
        : AppLocalizations.of(context).settingsRemovingData;
    final subtitle = widget.isDone
        ? _finishSubtitle(context)
        : _wipeSubtitle(context);

    return SizedBox(
      width: 420,
      height: 520,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xl,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Center(
          child: SizedBox(
            width: 372,
            height: _contentHeight,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _UninstallBadge(helmetOpacity: _helmetOpacity),
                const SizedBox(height: AppSpacing.base),
                SizedBox(
                  height: _titleSlotHeight,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: widget.isDone ? 308 : 372,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: AppTypography.displayMedium.copyWith(
                                color: colors.text.accent,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            SizedBox(
                              width: 240,
                              child: Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                style: AppTypography.bodyMedium.copyWith(
                                  color: colors.text.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.base),
                SizedBox(
                  height: _actionSlotHeight,
                  child: Center(
                    child: widget.isDone
                        ? AppButton(
                            onPressed: widget.onClose,
                            variant: AppButtonVariant.primary,
                            size: AppButtonSize.mediumLarge,
                            minWidth: 96,
                            child: Text(AppLocalizations.of(context).settingsCloseVizor),
                          )
                        : SizedBox(
                            width: 256,
                            child: AnimatedBuilder(
                              animation: widget.progress,
                              builder: (context, _) {
                                final value = widget.progress.value.clamp(
                                  0.0,
                                  1.0,
                                );
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${(value * 100).round()}%',
                                      textAlign: TextAlign.center,
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: colors.text.accent,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    _UninstallProgressBar(value: value),
                                  ],
                                );
                              },
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UninstallProgressBar extends StatelessWidget {
  const _UninstallProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 196,
      height: 12,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.background.overlay,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value,
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background.inverse,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
        ),
      ),
    );
  }
}
