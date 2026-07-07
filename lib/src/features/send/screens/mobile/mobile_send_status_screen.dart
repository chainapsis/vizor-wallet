import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart'
    show kMobileTopNavHeight;
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../services/send_flow.dart';
import 'mobile_send_screen.dart' show MobileSaplingParamsSheet;

enum _MobileSendStatusPhase { sending, pendingBroadcast, succeeded, failed }

// Status circle fills — Figma "Tx Submitted/Complete" (5497:22241).
// The circles keep the same color in both themes (the badge is its own
// surface, not themed content), so these are deliberately one-off
// constants rather than semantic tokens.
const _sendingCircleColor = Color(0xFF2E3232);
const _successCircleColor = Color(0xFF00A460);
const _failureCircleColor = Color(0xFF9338A7);
const _statusIconColor = Color(0xFFFFFFFF);

const _statusCircleSize = 64.0;
const _statusIconSize = 32.0;
const _statusButtonWidth = 230.0;
const _statusSubtitleWidth = 223.0;

const _backgroundImage = AssetImage(
  'assets/illustrations/mobile_send_status_background.png',
);

typedef MobileSendBroadcastRunner =
    Future<SendBroadcastOutcome> Function({
      required WidgetRef ref,
      required SendReviewArgs args,
      KeystoneBroadcastArgs? keystone,
      required Future<bool> Function() confirmSaplingParamsDownload,
      Future<bool> Function()? shouldAbort,
    });

class MobileSendStatusScreen extends ConsumerStatefulWidget {
  const MobileSendStatusScreen({
    required this.args,
    this.keystone,
    this.broadcastRunner,
    super.key,
  });

  final SendReviewArgs args;
  final KeystoneBroadcastArgs? keystone;

  @visibleForTesting
  final MobileSendBroadcastRunner? broadcastRunner;

  @override
  ConsumerState<MobileSendStatusScreen> createState() =>
      _MobileSendStatusScreenState();
}

class _MobileSendStatusScreenState
    extends ConsumerState<MobileSendStatusScreen> {
  var _phase = _MobileSendStatusPhase.sending;
  var _proposalConsumed = false;
  var _discardScheduled = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _proposalConsumed = widget.keystone != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startBroadcast());
    });
  }

  @override
  void dispose() {
    if (_phase != _MobileSendStatusPhase.sending) {
      _scheduleDiscardIfNeeded();
    }
    super.dispose();
  }

  void _scheduleDiscardIfNeeded() {
    if (_proposalConsumed || _discardScheduled) return;
    _discardScheduled = true;
    unawaited(
      discardSendProposal(
        proposalId: widget.args.proposalId,
        sendFlowId: widget.args.sendFlowId,
        logContext: 'MobileSendStatus(dispose)',
      ),
    );
  }

  Future<bool> _confirmSaplingParamsDownload() async {
    if (!mounted) return false;
    final confirmed = await showAppMobileSheet<bool>(
      context: context,
      isDismissible: false,
      builder: (_) => const MobileSaplingParamsSheet(),
    );
    return confirmed == true;
  }

  Future<void> _startBroadcast() async {
    final runner = widget.broadcastRunner ?? runSendBroadcast;
    final outcome = await runner(
      ref: ref,
      args: widget.args,
      keystone: widget.keystone,
      confirmSaplingParamsDownload: _confirmSaplingParamsDownload,
      shouldAbort: () async => !mounted,
    );
    _proposalConsumed = outcome.proposalConsumed;
    if (outcome.phase == SendBroadcastPhase.aborted || !mounted) return;

    setState(() {
      _phase = switch (outcome.phase) {
        SendBroadcastPhase.succeeded => _MobileSendStatusPhase.succeeded,
        SendBroadcastPhase.pendingBroadcast =>
          _MobileSendStatusPhase.pendingBroadcast,
        SendBroadcastPhase.failed => _MobileSendStatusPhase.failed,
        SendBroadcastPhase.aborted => _MobileSendStatusPhase.failed,
      };
      _statusMessage = outcome.statusMessage;
    });
    // Success and failure use custom native haptic patterns without system
    // notification sounds.
    switch (_phase) {
      case _MobileSendStatusPhase.succeeded:
        unawaited(AppHaptics.sendSuccess());
      case _MobileSendStatusPhase.failed:
        unawaited(AppHaptics.sendFailure());
      case _MobileSendStatusPhase.sending:
      case _MobileSendStatusPhase.pendingBroadcast:
        break;
    }
  }

  void _handleBack() {
    if (_phase == _MobileSendStatusPhase.sending) return;
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  bool get _routePopAllowed => _phase != _MobileSendStatusPhase.sending;

  String get _title {
    return switch (_phase) {
      _MobileSendStatusPhase.sending => 'Sending...',
      _MobileSendStatusPhase.pendingBroadcast => 'Queued to send',
      _MobileSendStatusPhase.succeeded => 'Sent!',
      _MobileSendStatusPhase.failed => 'Send failed',
    };
  }

  String get _subtitle {
    final statusMessage = _statusMessage?.trim();
    return switch (_phase) {
      _MobileSendStatusPhase.sending =>
        'Submitting your transaction to the network...',
      _MobileSendStatusPhase.pendingBroadcast =>
        statusMessage == null || statusMessage.isEmpty
            ? 'Your transaction was created and will be submitted '
                  'automatically. Check the Activity page before sending '
                  'again.'
            : statusMessage,
      _MobileSendStatusPhase.succeeded =>
        'It will confirm on-chain shortly. Track it in Activity.',
      _MobileSendStatusPhase.failed =>
        "Nothing was sent, your funds haven't moved. Try again.",
    };
  }

  String? get _buttonLabel {
    return switch (_phase) {
      _MobileSendStatusPhase.sending => null,
      _MobileSendStatusPhase.pendingBroadcast ||
      _MobileSendStatusPhase.succeeded => 'Done',
      _MobileSendStatusPhase.failed => 'Return Home',
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final buttonLabel = _buttonLabel;
    final titleColor = _phase == _MobileSendStatusPhase.failed
        ? colors.text.destructive
        : colors.text.accent;

    return PopScope<void>(
      canPop: _routePopAllowed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: colors.background.window,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Castle backdrop — the 15% opacity and bottom fade are baked
            // into the exported asset, so it renders as-is.
            const Positioned.fill(
              child: Image(
                image: _backgroundImage,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                excludeFromSemantics: true,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  // The design keeps the top-nav slot but hides its content
                  // (no back affordance while the tx is in flight).
                  const SizedBox(height: kMobileTopNavHeight),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.s,
                      ),
                      child: Center(
                        // No phase-derived key here: rekeying the column
                        // would recreate _StatusBadge on every phase change
                        // and skip its transition animations.
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _StatusBadge(phase: _phase),
                            const SizedBox(height: AppSpacing.xl),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    _title,
                                    key: ValueKey(
                                      'mobile_send_status_${_phase.name}',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: AppTypography.displayLarge.copyWith(
                                      color: titleColor,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.s),
                                  LayoutBuilder(
                                    builder: (context, constraints) {
                                      final subtitleMaxWidth =
                                          _phase ==
                                              _MobileSendStatusPhase
                                                  .pendingBroadcast
                                          ? constraints.maxWidth
                                          : math.min(
                                              _statusSubtitleWidth,
                                              constraints.maxWidth,
                                            );
                                      return ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxWidth: subtitleMaxWidth,
                                        ),
                                        child: Text(
                                          _subtitle,
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
                              height: AppButtonSizing.largeHeight,
                              child: buttonLabel == null
                                  ? null
                                  : AppButton(
                                      key: const ValueKey(
                                        'mobile_send_status_button',
                                      ),
                                      onPressed: _handleBack,
                                      expand: true,
                                      child: Text(buttonLabel),
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

/// The 64px status circle plus its Figma-comment animations: a single
/// expanding pulse on success ("circle grow smooth animation") and a
/// damped left-right shake on failure.
class _StatusBadge extends StatefulWidget {
  const _StatusBadge({required this.phase});

  final _MobileSendStatusPhase phase;

  @override
  State<_StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<_StatusBadge>
    with TickerProviderStateMixin {
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  // Pulse end diameter from the Figma keyframe frames (Status Animation
  // at 839 / 1403).
  static const _pulseMaxSize = 1440.0;
  static const _shakeAmplitude = 20.0;

  @override
  void didUpdateWidget(covariant _StatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase == widget.phase) return;
    switch (widget.phase) {
      case _MobileSendStatusPhase.succeeded:
        _ripple.forward(from: 0);
      case _MobileSendStatusPhase.failed:
        _shake.forward(from: 0);
      case _MobileSendStatusPhase.sending:
      case _MobileSendStatusPhase.pendingBroadcast:
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
      _MobileSendStatusPhase.sending ||
      _MobileSendStatusPhase.pendingBroadcast => _sendingCircleColor,
      _MobileSendStatusPhase.succeeded => _successCircleColor,
      _MobileSendStatusPhase.failed => _failureCircleColor,
    };
    final icon = switch (widget.phase) {
      _MobileSendStatusPhase.sending ||
      _MobileSendStatusPhase.pendingBroadcast => const AppIcon(
        AppIcons.loader,
        key: ValueKey('mobile_send_status_icon_loader'),
        size: _statusIconSize,
        color: _statusIconColor,
      ),
      _MobileSendStatusPhase.succeeded => const AppIcon(
        AppIcons.checkCircle,
        key: ValueKey('mobile_send_status_icon_success'),
        size: _statusIconSize,
        color: _statusIconColor,
      ),
      _MobileSendStatusPhase.failed => const AppIcon(
        AppIcons.warning,
        key: ValueKey('mobile_send_status_icon_failed'),
        size: _statusIconSize,
        color: _statusIconColor,
      ),
    };

    return SizedBox(
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
                  widget.phase == _MobileSendStatusPhase.succeeded;
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
                  key: const ValueKey('mobile_send_status_success_ripple'),
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
              return Transform.translate(offset: Offset(dx, 0), child: child);
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

/// One ripple layer: the Figma "Status Animation" ellipse — a radial
/// gradient from transparent center to `#00A460` at the rim, drawn at
/// 60% opacity.
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
