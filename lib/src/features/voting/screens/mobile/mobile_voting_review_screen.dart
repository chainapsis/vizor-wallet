import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/layout/mobile/mobile_top_scroll_fade.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../voting_review_flow.dart';
import '../../widgets/voting_metadata_widgets.dart';

/// Mobile review screen: read-only recap of the drafted answers with the
/// final submit action. Thin shell over [VotingReviewFlow].
class MobileVotingReviewScreen extends StatelessWidget {
  const MobileVotingReviewScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        bottom: false,
        child: VotingReviewFlow(
          roundId: roundId,
          builder: (context, view) => Column(
            children: [
              MobileTopNav.back(
                title: 'Review your answers',
                onBack: () {
                  if (context.canPop()) {
                    context.pop();
                    return;
                  }
                  context.go('/voting');
                },
              ),
              Expanded(
                child: switch (view) {
                  VotingReviewLoading() || VotingReviewRedirecting() =>
                    const Center(child: CircularProgressIndicator()),
                  VotingReviewMessage(:final message) => _Message(message),
                  VotingReviewContent() => _ReviewBody(view: view),
                },
              ),
            ],
          ),
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
      children: [
        Expanded(
          child: MobileTopScrollFade(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.s,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              children: [
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
        MobileBottomSafeArea(
          bottomPadding: AppSpacing.md,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.s,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: SizedBox(
              width: double.infinity,
              child: AppButton(
                key: const ValueKey('voting_confirm_submit_button'),
                onPressed: view.onSubmit,
                variant: AppButtonVariant.primary,
                size: AppButtonSize.large,
                child: const Text('Confirm & submit'),
              ),
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
