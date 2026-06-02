import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../voting_choice_style.dart';
import '../voting_flow_models.dart';
import '../voting_routes.dart';

class VotingReviewScreen extends ConsumerStatefulWidget {
  const VotingReviewScreen({super.key, required this.roundId});

  final String roundId;

  @override
  ConsumerState<VotingReviewScreen> createState() => _VotingReviewScreenState();
}

class _VotingReviewScreenState extends ConsumerState<VotingReviewScreen> {
  bool _precomputeStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_startPirPrecompute());
    });
  }

  Future<void> _startPirPrecompute() async {
    if (_precomputeStarted) return;
    _precomputeStarted = true;
    try {
      final session = await ref.read(
        votingSessionProvider(widget.roundId).future,
      );
      if (!mounted) return;
      final accountUuid = session.accountUuid;
      if (accountUuid == null) return;
      await ref
          .read(votingSessionProvider(widget.roundId).notifier)
          .precomputeDelegationPir(accountUuid: accountUuid);
    } catch (e) {
      debugPrint('[zcash] Voting: delegation PIR precompute skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(votingSessionProvider(widget.roundId));
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: session.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Message("Couldn't load review: $error"),
          data: (state) {
            final round = state.round;
            final proposals = round == null
                ? <VotingProposalView>[]
                : proposalsFromRound(round);
            final accountUuid = state.accountUuid;
            final draft = accountUuid == null
                ? const VotingDraftState()
                : ref.watch(
                    votingDraftProvider(
                      VotingSessionKey(
                        roundId: widget.roundId,
                        accountUuid: accountUuid,
                      ),
                    ),
                  );
            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: AppRouteBackLink(),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 620),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Review your answers',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.displaySmall.copyWith(
                                    color: context.colors.text.accent,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                for (final proposal in proposals)
                                  _ReviewRow(
                                    title: proposal.title,
                                    value: _reviewValue(proposal, draft),
                                    skipped: draft.choices[proposal.id] == null,
                                  ),
                                if (draft.isEmpty) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  const _Message(
                                    'Choose at least one option before submitting.',
                                  ),
                                ],
                                const SizedBox(height: AppSpacing.md),
                                Center(
                                  child: AppButton(
                                    onPressed: draft.isEmpty
                                        ? null
                                        : () => context.go(
                                            votingStatusRoute(
                                              widget.roundId,
                                              accountUuid: accountUuid,
                                            ),
                                          ),
                                    variant: AppButtonVariant.primary,
                                    minWidth: 240,
                                    child: const Text('Confirm & submit'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

String _reviewValue(VotingProposalView proposal, VotingDraftState draft) {
  final choice = draft.choices[proposal.id];
  if (choice == null) return 'Skipped';
  return proposal.options
      .firstWhere(
        (option) => option.index == choice,
        orElse: () => VotingOptionView(index: choice, label: 'Choice $choice'),
      )
      .label;
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.title,
    required this.value,
    this.skipped = false,
  });

  final String title;
  final String value;
  final bool skipped;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final titleColor = skipped
        ? colors.text.secondary.withValues(alpha: 0.64)
        : colors.text.secondary;
    final valueColor = skipped
        ? colors.text.secondary.withValues(alpha: 0.72)
        : votingChoicePalette(context, value).text;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: skipped
            ? colors.background.neutralSubtleOpacity
            : colors.background.ground.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.bodyMedium.copyWith(color: titleColor),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppTypography.bodyMediumStrong.copyWith(color: valueColor),
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
