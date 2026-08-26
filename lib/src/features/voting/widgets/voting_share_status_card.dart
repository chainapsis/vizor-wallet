import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../voting_share_status.dart';

const _staggeredSharePrivacyExplanation =
    'To protect your privacy, Vizor splits your encrypted vote into shares '
    'that are submitted at different times, making them harder to link.';
const _shareSubmissionContinuesExplanation =
    'You can close Vizor at any time while these servers submit your shares '
    'for you.';

/// High-level status for encrypted vote shares.
///
/// The records are the durable `zcash_voting` recovery records. They contain
/// real delegated shares only, so dummy zero-value shares are not displayed.
class VotingShareStatusCard extends StatefulWidget {
  const VotingShareStatusCard({required this.records, this.now, super.key});

  final List<rust_wire.ShareDelegationRecordView> records;

  /// Fixed current time for deterministic previews and tests.
  final DateTime? now;

  @override
  State<VotingShareStatusCard> createState() => _VotingShareStatusCardState();
}

class _VotingShareStatusCardState extends State<VotingShareStatusCard> {
  static const _estimateRefreshInterval = Duration(minutes: 1);

  Timer? _estimateRefreshTimer;
  late DateTime _estimateNow;

  @override
  void initState() {
    super.initState();
    _estimateNow = widget.now ?? DateTime.now();
    _syncEstimateRefreshTimer();
  }

  @override
  void didUpdateWidget(covariant VotingShareStatusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.now != null) {
      _estimateNow = widget.now!;
    } else {
      final wallClockNow = DateTime.now();
      if (wallClockNow.isAfter(_estimateNow)) {
        _estimateNow = wallClockNow;
      }
    }
    _syncEstimateRefreshTimer();
  }

  @override
  void dispose() {
    _estimateRefreshTimer?.cancel();
    super.dispose();
  }

  void _syncEstimateRefreshTimer() {
    _estimateRefreshTimer?.cancel();
    _estimateRefreshTimer = null;
    if (widget.now != null || widget.records.isEmpty) return;

    final summary = VotingShareStatusSummary.fromRecords(widget.records);
    final latestDueAt = summary.latestPendingDueAtSeconds;
    if (summary.allConfirmed || latestDueAt == null) return;

    final nowSeconds = BigInt.from(
      _estimateNow.toUtc().millisecondsSinceEpoch ~/
          Duration.millisecondsPerSecond,
    );
    final remainingSeconds = latestDueAt - nowSeconds;
    if (remainingSeconds <= BigInt.zero) return;

    final refreshSeconds =
        remainingSeconds < BigInt.from(_estimateRefreshInterval.inSeconds)
        ? remainingSeconds.toInt()
        : _estimateRefreshInterval.inSeconds;
    final delay = Duration(seconds: refreshSeconds);
    final scheduledFor = _estimateNow.add(delay);
    _estimateRefreshTimer = Timer(delay, () {
      if (!mounted) return;
      final wallClockNow = DateTime.now();
      setState(() {
        _estimateNow = wallClockNow.isAfter(scheduledFor)
            ? wallClockNow
            : scheduledFor;
      });
      _syncEstimateRefreshTimer();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.records.isEmpty) return const SizedBox.shrink();

    final colors = context.colors;
    final summary = VotingShareStatusSummary.fromRecords(widget.records);
    final roundedPercent = (summary.confirmedFraction * 100).round();
    final percent = summary.allConfirmed ? 100 : roundedPercent.clamp(0, 99);
    final noun = summary.totalCount == 1 ? 'share' : 'shares';
    const title = 'Submission status';
    final countText =
        '${summary.confirmedCount} of ${summary.totalCount} $noun submitted';
    final showProgress = !summary.allConfirmed;
    final completionEstimate = showProgress
        ? votingShareCompletionEstimateText(summary, now: _estimateNow)
        : null;
    final privacyExplanation = summary.usesStaggeredSubmission
        ? _staggeredSharePrivacyExplanation
        : summary.totalCount == 1
        ? 'Your encrypted vote is submitted as one encrypted share.'
        : 'Your encrypted vote is submitted as encrypted shares.';
    final explanation = showProgress
        ? '$privacyExplanation $_shareSubmissionContinuesExplanation'
        : privacyExplanation;
    final statusIcon = summary.allConfirmed ? AppIcons.checkCircle : null;
    final percentDescription = showProgress
        ? '$percent percent complete'
        : null;

    return Semantics(
      container: true,
      label: [
        title,
        countText,
        ?percentDescription,
        ?completionEstimate,
        explanation,
      ].join('. '),
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('voting_share_status_card'),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.background.raised.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: colors.border.subtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                if (statusIcon != null)
                  AppIcon(
                    statusIcon,
                    key: const ValueKey('voting_share_status_complete_icon'),
                    size: 20,
                    color: colors.icon.success,
                  )
                else
                  Text(
                    '$percent%',
                    key: const ValueKey('voting_share_status_percent'),
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              countText,
              key: const ValueKey('voting_share_status_count'),
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.primary,
              ),
            ),
            if (completionEstimate != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                completionEstimate,
                key: const ValueKey('voting_share_status_completion_estimate'),
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
            if (showProgress) ...[
              const SizedBox(height: AppSpacing.s),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.full),
                child: LinearProgressIndicator(
                  key: const ValueKey('voting_share_status_progress'),
                  minHeight: 4,
                  value: summary.confirmedFraction,
                  color: colors.icon.brandCrimson,
                  backgroundColor: colors.background.neutralSubtleOpacity,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.s),
            Text(
              explanation,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
