import 'package:flutter/material.dart';

import '../../../core/formatting/date_format.dart';
import '../../../core/formatting/number_format.dart';
import '../../../core/theme/app_theme.dart';
import '../voting_formatters.dart';
import 'voting_metadata_widgets.dart';

/// Round title, snapshot height, end/eligibility meta line, description, and
/// forum link above the proposal cards on the active poll. Shared by the
/// desktop and mobile detail screens.
class VotingPollSummary extends StatelessWidget {
  const VotingPollSummary({
    super.key,
    required this.title,
    required this.snapshotHeight,
    required this.description,
    required this.forumUri,
    required this.endDate,
    required this.votingPowerZatoshi,
    required this.votingPowerPreparing,
    required this.votingEligibilityMessage,
  });

  final String title;
  final int snapshotHeight;
  final String description;
  final Uri? forumUri;
  final DateTime? endDate;
  final BigInt? votingPowerZatoshi;
  final bool votingPowerPreparing;
  final String? votingEligibilityMessage;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasDescription = description.isNotEmpty;
    final descriptionStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
      height: 20 / 14,
      letterSpacing: 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.headlineMedium.copyWith(
                    color: colors.text.accent,
                    fontFamily: 'Geist',
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                    height: 30 / 20,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '#${formatGroupedInteger(snapshotHeight)}',
                style: AppTypography.headlineMedium.copyWith(
                  color: colors.text.accent,
                  fontFamily: 'Geist',
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                  height: 30 / 20,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            VotingMetaText(
              endDate == null
                  ? 'Voting active'
                  : 'Ends ${formatMonthDayYear(endDate!)}',
            ),
            const VotingMetaText('·'),
            VotingPowerMeta(
              zatoshi: votingPowerZatoshi,
              preparing: votingPowerPreparing,
            ),
            if (endDate != null) ...[
              const VotingMetaText('·'),
              VotingMetaText(votingDaysLeftLabel(endDate!)),
            ],
          ],
        ),
        if (votingEligibilityMessage != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            votingEligibilityMessage!,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.secondary,
              height: 16 / 12,
              letterSpacing: 0,
            ),
          ),
        ],
        if (hasDescription) ...[
          const SizedBox(height: AppSpacing.xs),
          VotingExpandableText(text: description, style: descriptionStyle),
        ],
        if (forumUri != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: VotingForumLinkButton(uri: forumUri!),
          ),
        ],
      ],
    );
  }
}

/// Header of the read-only voted view: title, snapshot height, voted/locked
/// meta line, description, and forum link.
class VotingVotedPollHeader extends StatelessWidget {
  const VotingVotedPollHeader({
    super.key,
    required this.title,
    required this.snapshotHeight,
    required this.description,
    required this.forumUri,
    required this.votingPowerZatoshi,
    required this.votingPowerPreparing,
    required this.votedAt,
  });

  final String title;
  final int snapshotHeight;
  final String description;
  final Uri? forumUri;
  final BigInt? votingPowerZatoshi;
  final bool votingPowerPreparing;
  final DateTime? votedAt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final titleStyle = AppTypography.headlineMedium.copyWith(
      color: colors.text.accent,
      fontFamily: 'Geist',
      fontWeight: FontWeight.w600,
      fontSize: 20,
      height: 30 / 20,
      letterSpacing: 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(title, style: titleStyle)),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '#${formatGroupedInteger(snapshotHeight)}',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [
            VotingMetaText(
              votedAt == null
                  ? 'Voted'
                  : 'Voted ${formatMonthDayYear(votedAt!)}',
            ),
            const VotingMetaText('·'),
            VotingPowerMeta(
              zatoshi: votingPowerZatoshi,
              preparing: votingPowerPreparing,
            ),
            const VotingMetaText('·'),
            const VotingMetaText('Vote locked'),
          ],
        ),
        if (description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          VotingExpandableText(
            text: description,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
        if (forumUri != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: VotingForumLinkButton(uri: forumUri!),
          ),
        ],
      ],
    );
  }
}

class VotingMetaText extends StatelessWidget {
  const VotingMetaText(this.value, {super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: AppTypography.bodySmall.copyWith(
        color: context.colors.text.secondary,
        height: 16 / 12,
        letterSpacing: 0,
      ),
    );
  }
}

class VotingPowerMeta extends StatelessWidget {
  const VotingPowerMeta({
    super.key,
    required this.zatoshi,
    required this.preparing,
  });

  final BigInt? zatoshi;
  final bool preparing;

  @override
  Widget build(BuildContext context) {
    final votingPower = zatoshi;
    if (votingPower == null) {
      if (!preparing) {
        return const VotingMetaText('Voting power unavailable');
      }
      final colors = context.colors;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: colors.icon.regular,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          const VotingMetaText('Preparing voting power'),
        ],
      );
    }
    return VotingMetaText('Voting power ${formatVotingPower(votingPower)}');
  }
}

String votingDaysLeftLabel(DateTime endDate) {
  final now = DateTime.now();
  final localEnd = endDate.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final endDay = DateTime(localEnd.year, localEnd.month, localEnd.day);
  final days = endDay.difference(today).inDays;
  if (days <= 0) return 'Ends today';
  if (days == 1) return '1 day left';
  return '$days days left';
}
