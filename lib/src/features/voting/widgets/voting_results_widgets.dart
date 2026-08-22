import 'package:flutter/material.dart';

import '../../../core/formatting/number_format.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/theme/app_theme.dart';
import '../voting_choice_style.dart';
import '../voting_flow_models.dart';
import 'voting_metadata_widgets.dart';

const int _ballotDivisorZatoshi = 12500000;

/// Round title, snapshot height, description, and forum link above the
/// per-proposal result cards. Shared by the desktop and mobile results
/// screens.
class VotingResultsHeader extends StatelessWidget {
  const VotingResultsHeader({
    super.key,
    required this.title,
    required this.snapshotHeight,
    required this.description,
    required this.forumUri,
  });

  final String title;
  final int snapshotHeight;
  final String description;
  final Uri? forumUri;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final description = this.description.trim();
    final descriptionStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.secondary,
      height: 20 / 14,
      letterSpacing: 0,
    );
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
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '#${formatGroupedInteger(snapshotHeight)}',
              style: titleStyle.copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        if (description.isNotEmpty) ...[
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

class VotingResultCard extends StatelessWidget {
  const VotingResultCard({
    super.key,
    required this.proposal,
    required this.tally,
    required this.selectedChoice,
  });

  final VotingProposalView proposal;
  final Map<int, num> tally;
  final int? selectedChoice;

  @override
  Widget build(BuildContext context) {
    final total = tally.values.fold<num>(0, (sum, value) => sum + value);
    final winningOption = _singleWinningOption(proposal.options, tally, total);
    final selectedLabel = _optionLabel(proposal.options, selectedChoice);
    final zipBadges = proposal.zipBadges;
    final forumUri = proposal.forumUri;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.background.raised,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        border: Border.all(color: context.colors.border.subtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (zipBadges.isNotEmpty || forumUri != null) ...[
            VotingProposalMetadataRow(zipBadges: zipBadges, forumUri: forumUri),
            const SizedBox(height: AppSpacing.s),
          ],
          Text(
            proposal.title,
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          if (proposal.description.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              proposal.description.trim(),
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (final option in proposal.options)
            _TallyRow(
              label: option.label,
              amount: tally[option.index] ?? 0,
              total: total,
              color: _optionColor(
                context,
                option.label,
                highlighted: option.index == winningOption,
              ),
              highlighted: option.index == winningOption,
            ),
          if (selectedLabel != null || total > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                if (selectedLabel != null)
                  Expanded(
                    child: Text(
                      'Voted: $selectedLabel',
                      style: AppTypography.bodySmall.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (total > 0)
                  Text(
                    'Total: ${_formatTallyZec(total)}',
                    style: AppTypography.bodySmall.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TallyRow extends StatelessWidget {
  const _TallyRow({
    required this.label,
    required this.amount,
    required this.total,
    required this.color,
    required this.highlighted,
  });

  final String label;
  final num amount;
  final num total;
  final Color color;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final pct = total <= 0 ? 0.0 : (amount / total).clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: highlighted ? color : context.colors.text.accent,
                  ),
                ),
              ),
              Text(
                _formatTallyZec(amount),
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: highlighted ? color : context.colors.text.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _TallyProgressBar(value: pct, color: color),
        ],
      ),
    );
  }
}

class _TallyProgressBar extends StatelessWidget {
  const _TallyProgressBar({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      height: 6,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: context.colors.background.overlay),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: clamped,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

int? _singleWinningOption(
  List<VotingOptionView> options,
  Map<int, num> tally,
  num total,
) {
  if (total <= 0) return null;

  num? maxAmount;
  final winners = <int>[];
  for (final option in options) {
    final amount = tally[option.index] ?? 0;
    if (maxAmount == null || amount > maxAmount) {
      maxAmount = amount;
      winners
        ..clear()
        ..add(option.index);
    } else if (amount == maxAmount) {
      winners.add(option.index);
    }
  }
  return maxAmount == null || maxAmount <= 0 || winners.length != 1
      ? null
      : winners.single;
}

String? _optionLabel(List<VotingOptionView> options, int? choice) {
  if (choice == null) return null;
  for (final option in options) {
    if (option.index == choice) return option.label;
  }
  return null;
}

Color _optionColor(
  BuildContext context,
  String label, {
  required bool highlighted,
}) {
  if (!highlighted) return context.colors.text.disabled;
  return votingChoicePalette(context, label).text;
}

String _formatTallyZec(num ballotUnits) {
  // Ballot tallies are multiples of 0.125 ZEC, so they are rounded to two
  // decimals (e.g. 0.125 -> 0.13). This intentionally does not route through
  // ZecAmount, which truncates fractions rather than rounding.
  final zec = ballotUnits * _ballotDivisorZatoshi / zatoshiPerZec.toInt();
  return '${zec.toStringAsFixed(2)} ZEC';
}
