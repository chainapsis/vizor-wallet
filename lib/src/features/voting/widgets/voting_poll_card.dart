import 'package:flutter/material.dart';

import '../../../core/formatting/date_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/voting/voting_state.dart';
import '../voting_flow_models.dart';
import '../voting_poll_ordering.dart';
import 'voting_metadata_widgets.dart';

const _votingBetaLabelAsset = 'assets/illustrations/voting_beta_label.png';
const _votingBetaLabelWidth = 42.0;
const _votingBetaLabelHeight = 24.0;

/// Round-list card shared by the desktop and mobile poll lists. Presentation
/// only: the owning screen decides where the action navigates.
class VotingPollCard extends StatelessWidget {
  const VotingPollCard({
    super.key,
    required this.round,
    required this.onAction,
  });

  final VotingRoundView round;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = round.title.isEmpty ? round.roundId : round.title;
    final description = votingPollCardDescription(round.rawJson);
    final forumUri = votingRoundForumUriFromJson(round.rawJson);
    final state = votingPollCardState(round);
    final dateLabel = votingPollCardDateLabel(round.rawJson, state);

    return Material(
      color: const Color(0x00000000),
      child: Ink(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.background.ground,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: colors.border.subtle),
          boxShadow: [
            BoxShadow(
              color: const Color(0x0A231F20),
              offset: const Offset(0, 1),
              blurRadius: 1,
              spreadRadius: -0.5,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                VotingPollStatusBadge(state: state),
                const Spacer(),
                if (dateLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      dateLabel,
                      textAlign: TextAlign.right,
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.secondary,
                        height: 20 / 14,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
                fontWeight: FontWeight.w600,
                height: 24 / 16,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              description.isEmpty ? round.roundId : description,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.primary,
                height: 20 / 14,
                letterSpacing: 0,
              ),
            ),
            if (forumUri != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: Alignment.centerRight,
                child: VotingForumLinkButton(uri: forumUri),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                key: ValueKey('voting_poll_action_${round.roundId}'),
                onPressed: onAction,
                variant: votingPollCardActionVariant(state),
                size: AppButtonSize.medium,
                child: Text(votingPollCardActionLabel(state)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VotingPollStatusBadge extends StatelessWidget {
  const VotingPollStatusBadge({super.key, required this.state});

  final VotingPollCardState state;

  @override
  Widget build(BuildContext context) {
    final label = _statusLabel(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: _statusBackground(state),
        border: Border.all(color: _statusBorder(state)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(_statusIcon(state), size: 14, color: _statusText(state)),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: AppTypography.labelLarge.copyWith(
              color: _statusText(state),
              height: 20 / 14,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

/// The "Beta" tag rendered beside the Vote title on both form factors.
class VotingBetaLabel extends StatelessWidget {
  const VotingBetaLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: ValueKey('voting_header_beta_label'),
      width: _votingBetaLabelWidth,
      height: _votingBetaLabelHeight,
      child: Image(
        image: AssetImage(_votingBetaLabelAsset),
        fit: BoxFit.contain,
        semanticLabel: 'Beta',
      ),
    );
  }
}

/// Centered title/message/action state shared by the voting screens.
class VotingMessage extends StatelessWidget {
  const VotingMessage({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                onPressed: onAction,
                variant: AppButtonVariant.primary,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String votingPollCardDescription(Map<String, dynamic> json) {
  for (final key in const ['description', 'body', 'summary']) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return '';
}

String? votingPollCardDateLabel(
  Map<String, dynamic> json,
  VotingPollCardState state,
) {
  final start = votingRoundStartDate(json);
  final end = votingRoundEndDate(json);
  if (end != null) {
    final label = switch (state) {
      VotingPollCardState.inProgress ||
      VotingPollCardState.active ||
      VotingPollCardState.voted => 'Closes',
      VotingPollCardState.tallying || VotingPollCardState.closed => 'Closed',
    };
    return '$label ${formatMonthDay(end)}';
  }
  if (start != null) return 'Starts ${formatMonthDay(start)}';
  return null;
}

String _statusLabel(VotingPollCardState state) {
  return switch (state) {
    VotingPollCardState.inProgress => 'In progress',
    VotingPollCardState.active => 'Active',
    VotingPollCardState.voted => 'Voted',
    VotingPollCardState.tallying => 'Tallying',
    VotingPollCardState.closed => 'Closed',
  };
}

String _statusIcon(VotingPollCardState state) {
  return switch (state) {
    VotingPollCardState.voted => AppIcons.check,
    _ => AppIcons.time,
  };
}

Color _statusBackground(VotingPollCardState state) {
  return switch (state) {
    VotingPollCardState.inProgress ||
    VotingPollCardState.active ||
    VotingPollCardState.voted => const Color(0xFFECFDF3),
    VotingPollCardState.tallying => const Color(0xFFFFFAEB),
    VotingPollCardState.closed => const Color(0xFFF4F4F0),
  };
}

Color _statusBorder(VotingPollCardState state) {
  return switch (state) {
    VotingPollCardState.inProgress ||
    VotingPollCardState.active ||
    VotingPollCardState.voted => const Color(0xFFABEFC6),
    VotingPollCardState.tallying => const Color(0xFFFEDF89),
    VotingPollCardState.closed => const Color(0xFFEBEBE6),
  };
}

Color _statusText(VotingPollCardState state) {
  return switch (state) {
    VotingPollCardState.inProgress ||
    VotingPollCardState.active ||
    VotingPollCardState.voted => const Color(0xFF067647),
    VotingPollCardState.tallying => const Color(0xFFB54708),
    VotingPollCardState.closed => const Color(0xFF716C5D),
  };
}

String votingPollCardActionLabel(VotingPollCardState state) {
  return switch (state) {
    VotingPollCardState.inProgress => 'Resume',
    VotingPollCardState.active => 'Start voting',
    VotingPollCardState.voted => 'Review',
    VotingPollCardState.tallying ||
    VotingPollCardState.closed => 'View results',
  };
}

AppButtonVariant votingPollCardActionVariant(VotingPollCardState state) {
  return switch (state) {
    VotingPollCardState.inProgress ||
    VotingPollCardState.active => AppButtonVariant.primary,
    VotingPollCardState.voted ||
    VotingPollCardState.tallying ||
    VotingPollCardState.closed => AppButtonVariant.secondary,
  };
}

enum VotingPollCardState { inProgress, active, voted, tallying, closed }

VotingPollCardState votingPollCardState(VotingRoundView round) {
  return switch (votingPollListStatus(round.status)) {
    VotingPollListStatus.active =>
      round.inProgress
          ? VotingPollCardState.inProgress
          : round.voted
          ? VotingPollCardState.voted
          : VotingPollCardState.active,
    VotingPollListStatus.tallying => VotingPollCardState.tallying,
    VotingPollListStatus.closed => VotingPollCardState.closed,
  };
}
