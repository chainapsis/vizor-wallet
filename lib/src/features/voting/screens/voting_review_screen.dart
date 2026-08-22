import 'package:flutter/material.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../voting_review_flow.dart';
import '../widgets/voting_metadata_widgets.dart';
import '../widgets/voting_pane_scroll_area.dart';

class VotingReviewScreen extends StatelessWidget {
  const VotingReviewScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: VotingReviewFlow(
          roundId: roundId,
          builder: (context, view) => switch (view) {
            VotingReviewLoading() ||
            VotingReviewRedirecting() => const VotingPaneStateView(
              backLinkMinWidth: 60,
              child: VotingPaneLoading(),
            ),
            VotingReviewMessage(:final message) => VotingPaneStateView(
              backLinkMinWidth: 60,
              child: _Message(message),
            ),
            VotingReviewContent() => _ReviewBody(view: view),
          },
        ),
      ),
    );
  }
}

class _ReviewBody extends StatelessWidget {
  const _ReviewBody({required this.view});

  final VotingReviewContent view;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AppPaneToolbar(backLinkMinWidth: 60),
        Expanded(
          child: VotingPaneScrollView(
            maxWidth: 560,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            scrollPadding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Review your answers',
                  textAlign: TextAlign.center,
                  style: AppTypography.displaySmall.copyWith(
                    color: context.colors.text.accent,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (view.hasConfirmedVotingEligibility)
                  for (final entry in view.proposals.asMap().entries) ...[
                    VotingProposalCard(
                      proposal: entry.value,
                      fallbackForumUri: view.roundForumUri,
                      selectedChoice: view.draft.choices[entry.value.id],
                      readOnly: true,
                      statusLabel: view.draft.choices[entry.value.id] == null
                          ? 'Skipped'
                          : null,
                      titleCollapsedMaxLines: 1,
                    ),
                    if (entry.key != view.proposals.length - 1)
                      const SizedBox(height: AppSpacing.s),
                  ],
                if (view.hasConfirmedVotingEligibility &&
                    view.draft.isEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  const _Message(
                    'Choose at least one option before submitting.',
                  ),
                ],
                if (view.eligibilityMessage != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _Message(view.eligibilityMessage!),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.xs,
            bottom: AppSpacing.md,
          ),
          child: Center(
            child: AppButton(
              key: const ValueKey('voting_confirm_submit_button'),
              onPressed: view.onSubmit,
              variant: AppButtonVariant.primary,
              minWidth: 240,
              child: const Text('Confirm & submit'),
            ),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: AppTypography.bodyMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
    );
  }
}
