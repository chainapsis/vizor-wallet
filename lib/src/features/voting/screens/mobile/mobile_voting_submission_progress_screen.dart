import 'dart:math' as math;

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_transaction_progress_screen.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../voting_status_screen.dart';

class MobileVotingSubmissionProgressScreen extends StatelessWidget {
  const MobileVotingSubmissionProgressScreen({
    required this.activeStep,
    this.activeStepProgress,
    super.key,
  });

  final VotingSubmissionProgressStep activeStep;
  final double? activeStepProgress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope<void>(
      canPop: false,
      child: Scaffold(
        backgroundColor: colors.background.window,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: Image(
                image: mobileTransactionProgressBackgroundImage,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                excludeFromSemantics: true,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: kMobileTopNavHeight),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const scrollContentHeight = 740.0;
                        return VotingPaneScrollbar(
                          scrollbarKey: const ValueKey(
                            'mobile_voting_submission_progress_scrollbar',
                          ),
                          builder: (context, controller) => SingleChildScrollView(
                            controller: controller,
                            primary: false,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.s,
                              ),
                              child: SizedBox(
                                height: scrollContentHeight,
                                child: Stack(
                                  key: const ValueKey(
                                    'mobile_voting_submission_progress_content',
                                  ),
                                  fit: StackFit.expand,
                                  children: [
                                    Positioned(
                                      top: 30,
                                      left: 0,
                                      right: 0,
                                      child: Text(
                                        'Don’t leave this window.',
                                        textAlign: TextAlign.center,
                                        style: AppTypography.bodyLarge.copyWith(
                                          color: colors.text.accent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 163,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: MobileTransactionProgressBadge(
                                          phase: MobileTransactionProgressPhase
                                              .inProgress,
                                          inProgressCircleColor:
                                              colors.background.inverse,
                                          inProgressIconColor:
                                              colors.icon.inverse,
                                          progressIconKey: const ValueKey(
                                            'mobile_voting_submission_loader',
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 291,
                                      left: 0,
                                      right: 0,
                                      child: Text(
                                        'Submitting votes...',
                                        textAlign: TextAlign.center,
                                        style: AppTypography.displayLarge
                                            .copyWith(
                                              color: colors.text.accent,
                                            ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 380,
                                      left: 0,
                                      right: 0,
                                      child: _VotingSubmissionSteps(
                                        activeStep: activeStep,
                                        activeStepProgress: activeStepProgress,
                                      ),
                                    ),
                                    Positioned(
                                      top: 552,
                                      left: 33,
                                      right: 33,
                                      child: Text(
                                        'Generating zero-knowledge proofs can take '
                                        'about 60 seconds, closing now may lose '
                                        'in-flight proof work.',
                                        textAlign: TextAlign.center,
                                        style: AppTypography.bodyMedium
                                            .copyWith(
                                              color: colors.text.primary,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
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

class _VotingSubmissionSteps extends StatelessWidget {
  const _VotingSubmissionSteps({
    required this.activeStep,
    required this.activeStepProgress,
  });

  final VotingSubmissionProgressStep activeStep;
  final double? activeStepProgress;

  static const _labels = <VotingSubmissionProgressStep, String>{
    VotingSubmissionProgressStep.delegating: 'Delegating voting authority',
    VotingSubmissionProgressStep.castingVotes:
        'Casting votes and submitting shares',
    VotingSubmissionProgressStep.finalizing: 'Finalizing submission',
  };

  @override
  Widget build(BuildContext context) {
    final steps = VotingSubmissionProgressStep.values;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          _VotingSubmissionStepRow(
            key: ValueKey(
              'mobile_voting_submission_step_${steps[index].name}_'
              '${index < activeStep.index
                  ? _VotingSubmissionStepState.complete.name
                  : index == activeStep.index
                  ? _VotingSubmissionStepState.active.name
                  : _VotingSubmissionStepState.pending.name}',
            ),
            label: _labels[steps[index]]!,
            state: index < activeStep.index
                ? _VotingSubmissionStepState.complete
                : index == activeStep.index
                ? _VotingSubmissionStepState.active
                : _VotingSubmissionStepState.pending,
            progress: index == activeStep.index ? activeStepProgress : null,
          ),
          if (index < steps.length - 1)
            _VotingSubmissionStepConnector(
              lineKey: ValueKey(
                'mobile_voting_submission_connector_after_'
                '${steps[index].name}',
              ),
            ),
        ],
      ],
    );
  }
}

enum _VotingSubmissionStepState { complete, active, pending }

class _VotingSubmissionStepRow extends StatelessWidget {
  const _VotingSubmissionStepRow({
    required this.label,
    required this.state,
    required this.progress,
    super.key,
  });

  final String label;
  final _VotingSubmissionStepState state;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeOrComplete = state != _VotingSubmissionStepState.pending;
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: switch (state) {
              _VotingSubmissionStepState.complete => const Center(
                child: _CompletedStepIndicator(),
              ),
              _VotingSubmissionStepState.active => Center(
                child: _ActiveStepIndicator(progress: progress),
              ),
              _VotingSubmissionStepState.pending => Center(
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.border.regular, width: 2),
                  ),
                ),
              ),
            },
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: activeOrComplete
                    ? colors.text.accent
                    : colors.text.muted,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.04,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VotingSubmissionStepConnector extends StatelessWidget {
  const _VotingSubmissionStepConnector({required this.lineKey});

  final Key lineKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: 24,
        height: 20,
        child: Center(
          child: Container(
            key: lineKey,
            width: 1,
            height: 12,
            color: colors.border.regular,
          ),
        ),
      ),
    );
  }
}

class _CompletedStepIndicator extends StatelessWidget {
  const _CompletedStepIndicator();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: colors.icon.success,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: AppIcon(
          AppIcons.check,
          size: 12,
          color: colors.background.window,
        ),
      ),
    );
  }
}

class _ActiveStepIndicator extends StatelessWidget {
  const _ActiveStepIndicator({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final clampedProgress = progress?.clamp(0.0, 1.0).toDouble();
    return Semantics(
      label: 'Active voting submission step progress',
      value: clampedProgress == null
          ? 'Unknown'
          : '${(clampedProgress * 100).round()}%',
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: clampedProgress ?? 0),
        duration: disabled ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, animatedProgress, _) => CustomPaint(
          key: const ValueKey('mobile_voting_submission_active_step'),
          size: const Size.square(20),
          painter: _StepProgressRingPainter(
            progress: animatedProgress,
            ringColor: colors.border.regular,
            progressColor: colors.background.inverse,
          ),
        ),
      ),
    );
  }
}

class _StepProgressRingPainter extends CustomPainter {
  const _StepProgressRingPainter({
    required this.progress,
    required this.ringColor,
    required this.progressColor,
  });

  final double progress;
  final Color ringColor;
  final Color progressColor;

  static const _strokeWidth = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final ringRadius = (size.shortestSide - _strokeWidth) / 2;
    final ringRect = Rect.fromCircle(center: center, radius: ringRadius);
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth,
    );
    if (progress > 0) {
      canvas.drawArc(
        ringRect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        Paint()
          ..color = progressColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _strokeWidth
          ..strokeCap = StrokeCap.butt,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StepProgressRingPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      ringColor != oldDelegate.ringColor ||
      progressColor != oldDelegate.progressColor;
}
