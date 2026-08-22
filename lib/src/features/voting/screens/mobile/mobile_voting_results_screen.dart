import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/layout/mobile/mobile_top_scroll_fade.dart';
import '../../../../core/theme/app_theme.dart';
import '../../voting_results_flow.dart';
import '../../widgets/voting_results_widgets.dart';

/// Mobile tally view of a voting round. Thin shell over [VotingResultsFlow].
class MobileVotingResultsScreen extends StatelessWidget {
  const MobileVotingResultsScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopNav.back(
              title: 'Results',
              onBack: () {
                if (context.canPop()) {
                  context.pop();
                  return;
                }
                context.go('/voting');
              },
            ),
            Expanded(
              child: VotingResultsFlow(
                roundId: roundId,
                builder: (context, view) => switch (view) {
                  VotingResultsLoading() => const Center(
                    child: CircularProgressIndicator(),
                  ),
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
    return MobileTopScrollFade(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          0,
          AppSpacing.sm,
          AppSpacing.md,
        ),
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}
