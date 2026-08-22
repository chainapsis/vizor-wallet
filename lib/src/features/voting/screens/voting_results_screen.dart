import 'package:flutter/material.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../voting_results_flow.dart';
import '../widgets/voting_pane_scroll_area.dart';
import '../widgets/voting_results_widgets.dart';

class VotingResultsScreen extends StatelessWidget {
  const VotingResultsScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPaneToolbar(),
            Expanded(
              child: VotingResultsFlow(
                roundId: roundId,
                builder: (context, view) => switch (view) {
                  VotingResultsLoading() => const VotingPaneLoading(),
                  VotingResultsMessage(:final message) => _Message(message),
                  VotingResultsPending() => const _Message(
                    'Results pending...',
                  ),
                  VotingResultsContent() => _ResultsBody(content: view),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsBody extends StatelessWidget {
  const _ResultsBody({required this.content});

  final VotingResultsContent content;

  @override
  Widget build(BuildContext context) {
    return VotingPaneScrollView(
      maxWidth: 560,
      scrollPadding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VotingResultsHeader(
            title: content.title,
            snapshotHeight: content.snapshotHeight,
            description: content.description,
            forumUri: content.forumUri,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Results',
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          if (content.entries.isEmpty)
            const _Message('No proposals in this round.')
          else
            for (var index = 0; index < content.entries.length; index++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == content.entries.length - 1
                      ? 0
                      : AppSpacing.s,
                ),
                child: VotingResultCard(
                  key: ValueKey(
                    'voting-result-card-${content.entries[index].proposal.id}',
                  ),
                  proposal: content.entries[index].proposal,
                  tally: content.entries[index].tally,
                  selectedChoice: content.entries[index].selectedChoice,
                ),
              ),
        ],
      ),
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
