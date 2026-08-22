import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../voting_confirmation_flow.dart';
import '../../widgets/voting_receipt_widgets.dart';

/// Mobile submission receipt. Thin shell over
/// [VotingSubmissionConfirmationFlow]; the flow owns the voting-power
/// refresh, the poll-list prefetch, and the guarded return to the poll list.
class MobileVotingSubmissionConfirmationScreen extends StatelessWidget {
  const MobileVotingSubmissionConfirmationScreen({
    super.key,
    required this.roundId,
    this.accountUuid,
  });

  final String roundId;
  final String? accountUuid;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background.window,
      body: SafeArea(
        bottom: false,
        child: VotingSubmissionConfirmationFlow(
          roundId: roundId,
          accountUuid: accountUuid,
          builder: (context, view) => Column(
            children: [
              MobileTopNav.back(
                title: 'Vote',
                // Back is the same guarded exit as Done: refresh the poll
                // list before returning so the round card shows Voted.
                onBack: () {
                  final onDone = view?.onDone;
                  if (view?.doneEnabled == true && onDone != null) {
                    onDone();
                    return;
                  }
                  if (view != null && view.isReturningToPolls) return;
                  context.go('/voting');
                },
              ),
              Expanded(
                child: view == null
                    ? const Center(child: CircularProgressIndicator())
                    : _ConfirmationBody(view: view),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmationBody extends StatelessWidget {
  const _ConfirmationBody({required this.view});

  final VotingConfirmationViewModel view;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.background.inverse,
                        borderRadius: BorderRadius.circular(AppRadii.full),
                      ),
                      child: Icon(
                        Icons.how_to_vote,
                        color: colors.text.inverse,
                        size: 24,
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(-6, 0),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colors.background.utilitySuccessSubtle,
                              colors.background.utilitySuccessStrong,
                            ],
                          ),
                          border: Border.all(
                            color: colors.background.base,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(AppRadii.full),
                        ),
                        child: Icon(
                          view.confirmed ? Icons.verified : Icons.error_outline,
                          color: view.confirmed
                              ? colors.text.success
                              : colors.text.warning,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  view.title,
                  style: AppTypography.headlineMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  view.message,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                VotingReceiptCard(
                  rows: [
                    VotingReceiptRow(
                      label: 'Voting round',
                      value: view.pollTitle,
                    ),
                    VotingReceiptRow(
                      label: 'Voting power',
                      value: view.votingPower,
                    ),
                  ],
                ),
                if (view.returnErrorMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    view.returnErrorMessage!,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.warning,
                    ),
                  ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  key: const ValueKey('voting_submission_done_button'),
                  onPressed: view.doneEnabled
                      ? view.onDone ?? () => context.go('/voting')
                      : null,
                  variant: AppButtonVariant.primary,
                  size: AppButtonSize.large,
                  child: Text(view.doneLabel),
                ),
                if (view.onRetry != null && view.retryLabel != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  AppButton(
                    onPressed: view.onRetry,
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.large,
                    child: Text(view.retryLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
