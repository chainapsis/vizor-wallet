import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../layout/mobile/mobile_top_nav.dart' show kMobileTopNavHeight;
import '../../theme/app_theme.dart';
import '../app_button.dart';
import '../app_icon.dart';

enum MobileTransactionProgressPhase { inProgress, pending, succeeded, failed }

const _sendingCircleColor = Color(0xFF2E3232);
const _successCircleColor = Color(0xFF00A460);
const _failureCircleColor = Color(0xFF9338A7);
const _statusIconColor = Color(0xFFFFFFFF);
const _statusCircleSize = 64.0;
const _statusIconSize = 32.0;
const _statusButtonWidth = 230.0;

const _mobileTransactionProgressBackgroundImage = AssetImage(
  'assets/illustrations/mobile_send_status_background.png',
);

/// Shared full-page presentation for a transaction being submitted.
///
/// The caller owns execution, copy, navigation, and haptics. This widget owns
/// only the common mobile TX-progress shell and its status animations.
class MobileTransactionProgressScreen extends StatelessWidget {
  const MobileTransactionProgressScreen({
    required this.phase,
    required this.title,
    required this.body,
    required this.canPop,
    this.onPopBlocked,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.bodyMaxWidth = 223,
    this.titleKey,
    this.bodyKey,
    this.statusBadgeKey,
    this.progressIconKey,
    this.successIconKey,
    this.failureIconKey,
    this.successRippleKey,
    this.primaryActionKey,
    this.secondaryActionKey,
    super.key,
  });

  final MobileTransactionProgressPhase phase;
  final String title;
  final String body;
  final bool canPop;
  final VoidCallback? onPopBlocked;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final double? bodyMaxWidth;
  final Key? titleKey;
  final Key? bodyKey;
  final Key? statusBadgeKey;
  final Key? progressIconKey;
  final Key? successIconKey;
  final Key? failureIconKey;
  final Key? successRippleKey;
  final Key? primaryActionKey;
  final Key? secondaryActionKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final titleColor = phase == MobileTransactionProgressPhase.failed
        ? colors.text.destructive
        : colors.text.accent;
    final showPrimary = primaryActionLabel != null && onPrimaryAction != null;
    final showSecondary =
        secondaryActionLabel != null && onSecondaryAction != null;

    return PopScope<void>(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onPopBlocked?.call();
      },
      child: Scaffold(
        backgroundColor: colors.background.window,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: Image(
                image: _mobileTransactionProgressBackgroundImage,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                excludeFromSemantics: true,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // The Figma shell reserves the nav slot but hides its
                  // content while the transaction is in flight.
                  const SizedBox(height: kMobileTopNavHeight),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.s,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _MobileTransactionProgressBadge(
                              phase: phase,
                              badgeKey: statusBadgeKey,
                              progressIconKey: progressIconKey,
                              successIconKey: successIconKey,
                              failureIconKey: failureIconKey,
                              successRippleKey: successRippleKey,
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    title,
                                    key: titleKey,
                                    textAlign: TextAlign.center,
                                    style: AppTypography.displayLarge.copyWith(
                                      color: titleColor,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final requestedWidth = bodyMaxWidth;
                                      final maxWidth = requestedWidth == null
                                          ? constraints.maxWidth
                                          : math.min(
                                              requestedWidth,
                                              constraints.maxWidth,
                                            );
                                      return ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: maxWidth,
                                        ),
                                        child: Text(
                                          body,
                                          key: bodyKey,
                                          textAlign: TextAlign.center,
                                          style: AppTypography.bodyMediumStrong
                                              .copyWith(
                                                color: colors.text.primary,
                                              ),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            SizedBox(
                              width: _statusButtonWidth,
                              child: showPrimary || showSecondary
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (showPrimary)
                                          AppButton(
                                            key: primaryActionKey,
                                            onPressed: onPrimaryAction,
                                            expand: true,
                                            constrainContent: true,
                                            child: Text(primaryActionLabel!),
                                          ),
                                        if (showPrimary && showSecondary)
                                          const SizedBox(height: AppSpacing.s),
                                        if (showSecondary)
                                          AppButton(
                                            key: secondaryActionKey,
                                            onPressed: onSecondaryAction,
                                            expand: true,
                                            constrainContent: true,
                                            variant: AppButtonVariant.ghost,
                                            child: Text(secondaryActionLabel!),
                                          ),
                                      ],
                                    )
                                  : const SizedBox(
                                      height: AppButtonSizing.largeHeight,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileTransactionProgressBadge extends StatefulWidget {
  const _MobileTransactionProgressBadge({
    required this.phase,
    this.badgeKey,
    this.progressIconKey,
    this.successIconKey,
    this.failureIconKey,
    this.successRippleKey,
  });

  final MobileTransactionProgressPhase phase;
  final Key? badgeKey;
  final Key? progressIconKey;
  final Key? successIconKey;
  final Key? failureIconKey;
  final Key? successRippleKey;

  @override
  State<_MobileTransactionProgressBadge> createState() =>
      _MobileTransactionProgressBadgeState();
}

class _MobileTransactionProgressBadgeState
    extends State<_MobileTransactionProgressBadge>
    with TickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  static const _pulseMaxSize = 1440.0;
  static const _shakeAmplitude = 20.0;

  @override
  void initState() {
    super.initState();
    _startTerminalAnimation(widget.phase);
  }

  @override
  void didUpdateWidget(covariant _MobileTransactionProgressBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase == widget.phase) return;
    _startTerminalAnimation(widget.phase);
  }

  void _startTerminalAnimation(MobileTransactionProgressPhase phase) {
    switch (phase) {
      case MobileTransactionProgressPhase.succeeded:
        _ripple.forward(from: 0);
      case MobileTransactionProgressPhase.failed:
        _shake.forward(from: 0);
      case MobileTransactionProgressPhase.inProgress:
      case MobileTransactionProgressPhase.pending:
        break;
    }
  }

  @override
  void dispose() {
    _ripple.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final circleColor = switch (widget.phase) {
      MobileTransactionProgressPhase.inProgress ||
      MobileTransactionProgressPhase.pending => _sendingCircleColor,
      MobileTransactionProgressPhase.succeeded => _successCircleColor,
      MobileTransactionProgressPhase.failed => _failureCircleColor,
    };
    final icon = switch (widget.phase) {
      MobileTransactionProgressPhase.inProgress ||
      MobileTransactionProgressPhase.pending => AppIcon(
        AppIcons.loader,
        key:
            widget.progressIconKey ??
            const ValueKey('mobile_transaction_progress_icon_loader'),
        size: _statusIconSize,
        color: _statusIconColor,
      ),
      MobileTransactionProgressPhase.succeeded => AppIcon(
        AppIcons.checkCircle,
        key:
            widget.successIconKey ??
            const ValueKey('mobile_transaction_progress_icon_success'),
        size: _statusIconSize,
        color: _statusIconColor,
      ),
      MobileTransactionProgressPhase.failed => AppIcon(
        AppIcons.warning,
        key:
            widget.failureIconKey ??
            const ValueKey('mobile_transaction_progress_icon_failed'),
        size: _statusIconSize,
        color: _statusIconColor,
      ),
    };

    return SizedBox(
      key: widget.badgeKey,
      width: _statusCircleSize,
      height: _statusCircleSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ripple,
            builder: (context, _) {
              final showPulse =
                  widget.phase == MobileTransactionProgressPhase.succeeded;
              final t = _ripple.value;
              final pulseVisible = showPulse && t > 0 && t < 1;
              if (!pulseVisible) return const SizedBox.shrink();
              final pulseSize = lerpDouble(
                _statusCircleSize,
                _pulseMaxSize,
                Curves.easeOutBack.transform(t),
              )!;
              return IgnorePointer(
                child: _RippleCircle(
                  key:
                      widget.successRippleKey ??
                      const ValueKey(
                        'mobile_transaction_progress_success_ripple',
                      ),
                  size: pulseSize,
                  opacity: 1 - t,
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _shake,
            builder: (context, child) {
              final t = _shake.value;
              final dx = t <= 0 || t >= 1
                  ? 0.0
                  : math.sin(t * math.pi * 5) * _shakeAmplitude * (1 - t);
              return Transform.translate(
                key: const ValueKey(
                  'mobile_transaction_progress_failure_shake',
                ),
                offset: Offset(dx, 0),
                child: child,
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: _statusCircleSize,
              height: _statusCircleSize,
              decoration: BoxDecoration(
                color: circleColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: icon,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RippleCircle extends StatelessWidget {
  const _RippleCircle({required this.size, required this.opacity, super.key});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: (opacity * 0.6).clamp(0.0, 1.0),
      child: OverflowBox(
        minWidth: size,
        maxWidth: size,
        minHeight: size,
        maxHeight: size,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [Color(0x00FFFFFF), _successCircleColor],
            ),
          ),
        ),
      ),
    );
  }
}
