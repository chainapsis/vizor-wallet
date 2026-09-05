import 'dart:math' as math;

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_transaction_progress_screen.dart';
import '../voting_status_screen.dart';

const _referenceContentHeight = 701.0;
const _minimumContentHeight = 317.0;
const _referenceLayoutTransitionExtent = AppSpacing.xl;
const _minimumResponsiveOuterPadding = AppSpacing.xxs;
const _maximumResponsiveOuterPadding = AppSpacing.sm;

const _noticeHeight = 26.0;
const _statusBadgeHeight = 64.0;
const _titleHeight = 40.0;
const _stepsHeight = 112.0;
const _proofNoticeHeight = 75.0;

const _referenceNoticeTop = 30.0;
const _referenceStatusBadgeTop = 163.0;
const _referenceTitleTop = 291.0;
const _referenceStepsTop = 380.0;
const _referenceProofNoticeTop = 552.0;

const _noticeToStatusBadgeGap =
    _referenceStatusBadgeTop - _referenceNoticeTop - _noticeHeight;
const _statusBadgeToTitleGap =
    _referenceTitleTop - _referenceStatusBadgeTop - _statusBadgeHeight;
const _titleToStepsGap = _referenceStepsTop - _referenceTitleTop - _titleHeight;
const _stepsToProofNoticeGap =
    _referenceProofNoticeTop - _referenceStepsTop - _stepsHeight;
const _referenceBottomGap =
    _referenceContentHeight - _referenceProofNoticeTop - _proofNoticeHeight;
const _referenceInternalGapTotal =
    _noticeToStatusBadgeGap +
    _statusBadgeToTitleGap +
    _titleToStepsGap +
    _stepsToProofNoticeGap;

class MobileVotingSubmissionProgressScreen extends StatelessWidget {
  const MobileVotingSubmissionProgressScreen({
    required this.activeStep,
    this.activeStepProgress,
    this.activeStepDetail,
    this.warning,
    super.key,
  });

  final VotingSubmissionProgressStep activeStep;
  final double? activeStepProgress;
  final String? activeStepDetail;

  /// See [VotingSubmissionProgressPresentation.warning].
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final warning = this.warning;
    final noticeStyle = AppTypography.bodyLarge.copyWith(
      // Same metrics either way, so the measured layout below is unaffected.
      color: warning == null ? colors.text.accent : colors.text.destructive,
      fontWeight: FontWeight.w600,
    );
    final titleStyle = AppTypography.displayLarge.copyWith(
      color: colors.text.accent,
    );
    final proofNoticeStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.primary,
    );
    // A warning outranks the step detail: it is persistent and actionable,
    // while the detail is progress chatter the step list below repeats. The
    // notice height is measured from this string, so the layout adapts.
    final noticeText =
        warning ?? activeStepDetail ?? 'Don’t leave this window.';
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
                        final textDirection = Directionality.of(context);
                        final textScaler = MediaQuery.textScalerOf(context);
                        final contentWidth =
                            constraints.maxWidth - AppSpacing.sm * 2;
                        final noticeHeight = _measureTextHeight(
                          text: noticeText,
                          style: noticeStyle,
                          maxWidth: contentWidth,
                          textDirection: textDirection,
                          textScaler: textScaler,
                        );
                        final titleHeight = _measureTextHeight(
                          text: 'Submitting votes...',
                          style: titleStyle,
                          maxWidth: contentWidth,
                          textDirection: textDirection,
                          textScaler: textScaler,
                        );
                        final proofNoticeHeight = _measureTextHeight(
                          text:
                              'Generating zero-knowledge proofs can take '
                              'about 60 seconds, closing now may lose '
                              'in-flight proof work.',
                          style: proofNoticeStyle,
                          maxWidth: contentWidth - 66,
                          textDirection: textDirection,
                          textScaler: textScaler,
                        );
                        final paddedViewportHeight =
                            constraints.maxHeight - AppSpacing.s * 2;
                        final measuredFixedContentHeight =
                            noticeHeight +
                            _statusBadgeHeight +
                            titleHeight +
                            _stepsHeight +
                            proofNoticeHeight;
                        final contentHeight = math.max(
                          math.max(
                            _minimumContentHeight,
                            measuredFixedContentHeight,
                          ),
                          paddedViewportHeight,
                        );
                        final positions = _VotingSubmissionPositions.forHeight(
                          contentHeight,
                          noticeHeight: noticeHeight,
                          titleHeight: titleHeight,
                          proofNoticeHeight: proofNoticeHeight,
                        );
                        return SingleChildScrollView(
                          key: const ValueKey(
                            'mobile_voting_submission_progress_scroll_view',
                          ),
                          primary: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.s,
                            ),
                            child: SizedBox(
                              height: contentHeight,
                              child: Stack(
                                key: const ValueKey(
                                  'mobile_voting_submission_progress_content',
                                ),
                                fit: StackFit.expand,
                                children: [
                                  Positioned(
                                    top: positions.noticeTop,
                                    left: 0,
                                    right: 0,
                                    child: Text(
                                      noticeText,
                                      key: const ValueKey(
                                        'mobile_voting_submission_notice',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: noticeStyle,
                                    ),
                                  ),
                                  Positioned(
                                    top: positions.statusBadgeTop,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      key: const ValueKey(
                                        'mobile_voting_submission_badge',
                                      ),
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
                                    top: positions.titleTop,
                                    left: 0,
                                    right: 0,
                                    child: Text(
                                      'Submitting votes...',
                                      key: const ValueKey(
                                        'mobile_voting_submission_title',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: titleStyle,
                                    ),
                                  ),
                                  Positioned(
                                    top: positions.stepsTop,
                                    left: 0,
                                    right: 0,
                                    child: _VotingSubmissionSteps(
                                      key: const ValueKey(
                                        'mobile_voting_submission_steps',
                                      ),
                                      activeStep: activeStep,
                                      activeStepProgress: activeStepProgress,
                                    ),
                                  ),
                                  Positioned(
                                    top: positions.proofNoticeTop,
                                    left: 33,
                                    right: 33,
                                    child: Text(
                                      'Generating zero-knowledge proofs can take '
                                      'about 60 seconds, closing now may lose '
                                      'in-flight proof work.',
                                      key: const ValueKey(
                                        'mobile_voting_submission_proof_notice',
                                      ),
                                      textAlign: TextAlign.center,
                                      style: proofNoticeStyle,
                                    ),
                                  ),
                                ],
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

double _measureTextHeight({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required TextDirection textDirection,
  required TextScaler textScaler,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: TextAlign.center,
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  return painter.height;
}

class _VotingSubmissionPositions {
  const _VotingSubmissionPositions({
    required this.noticeTop,
    required this.statusBadgeTop,
    required this.titleTop,
    required this.stepsTop,
    required this.proofNoticeTop,
  });

  factory _VotingSubmissionPositions.forHeight(
    double height, {
    required double noticeHeight,
    required double titleHeight,
    required double proofNoticeHeight,
  }) {
    final usesReferenceMetrics =
        (noticeHeight - _noticeHeight).abs() < 0.5 &&
        (titleHeight - _titleHeight).abs() < 0.5 &&
        (proofNoticeHeight - _proofNoticeHeight).abs() < 0.5;
    final fixedContentHeight =
        noticeHeight +
        _statusBadgeHeight +
        titleHeight +
        _stepsHeight +
        proofNoticeHeight;
    final flexibleHeight = math.max(0.0, height - fixedContentHeight);
    final referenceFlexibleHeight =
        _referenceContentHeight - _minimumContentHeight;
    final outerPaddingScale = math.min(
      1.0,
      flexibleHeight / referenceFlexibleHeight,
    );
    final responsiveOuterPadding =
        _minimumResponsiveOuterPadding +
        (_maximumResponsiveOuterPadding - _minimumResponsiveOuterPadding) *
            outerPaddingScale;
    final availableInternalGap = math.max(
      0.0,
      height - fixedContentHeight - responsiveOuterPadding * 2,
    );
    final gapScale = math.min(
      1.0,
      availableInternalGap / _referenceInternalGapTotal,
    );
    final internalGapHeight = _referenceInternalGapTotal * gapScale;
    final centeredOuterGap = math.max(
      0.0,
      (flexibleHeight - internalGapHeight) / 2,
    );
    final transitionProgress = usesReferenceMetrics
        ? math.min(
            1.0,
            (height - _referenceContentHeight).abs() /
                _referenceLayoutTransitionExtent,
          )
        : 1.0;
    final blendedGaps = <double>[
      _lerpGap(_referenceNoticeTop, centeredOuterGap, transitionProgress),
      _lerpGap(
        _noticeToStatusBadgeGap,
        _noticeToStatusBadgeGap * gapScale,
        transitionProgress,
      ),
      _lerpGap(
        _statusBadgeToTitleGap,
        _statusBadgeToTitleGap * gapScale,
        transitionProgress,
      ),
      _lerpGap(
        _titleToStepsGap,
        _titleToStepsGap * gapScale,
        transitionProgress,
      ),
      _lerpGap(
        _stepsToProofNoticeGap,
        _stepsToProofNoticeGap * gapScale,
        transitionProgress,
      ),
      _lerpGap(_referenceBottomGap, centeredOuterGap, transitionProgress),
    ];
    final blendedGapTotal = blendedGaps.fold<double>(
      0,
      (sum, gap) => sum + gap,
    );
    final normalizationScale = blendedGapTotal == 0
        ? 0.0
        : flexibleHeight / blendedGapTotal;
    final normalizedGaps = [
      for (final gap in blendedGaps) gap * normalizationScale,
    ];
    final noticeTop = normalizedGaps[0];
    final statusBadgeTop = noticeTop + noticeHeight + normalizedGaps[1];
    final titleTop = statusBadgeTop + _statusBadgeHeight + normalizedGaps[2];
    final stepsTop = titleTop + titleHeight + normalizedGaps[3];
    final proofNoticeTop = stepsTop + _stepsHeight + normalizedGaps[4];

    return _VotingSubmissionPositions(
      noticeTop: noticeTop,
      statusBadgeTop: statusBadgeTop,
      titleTop: titleTop,
      stepsTop: stepsTop,
      proofNoticeTop: proofNoticeTop,
    );
  }

  final double noticeTop;
  final double statusBadgeTop;
  final double titleTop;
  final double stepsTop;
  final double proofNoticeTop;
}

double _lerpGap(double reference, double responsive, double progress) =>
    reference + (responsive - reference) * progress;

class _VotingSubmissionSteps extends StatelessWidget {
  const _VotingSubmissionSteps({
    required this.activeStep,
    required this.activeStepProgress,
    super.key,
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
