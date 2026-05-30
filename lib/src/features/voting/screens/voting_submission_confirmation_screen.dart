import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../../../providers/voting/voting_submission_job_provider.dart';
import '../voting_flow_models.dart';
import '../voting_formatters.dart';
import '../voting_resume_plan.dart';

class VotingSubmissionConfirmationScreen extends ConsumerWidget {
  const VotingSubmissionConfirmationScreen({
    super.key,
    required this.roundId,
    this.accountUuid,
  });

  final String roundId;
  final String? accountUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobKey = accountUuid == null || accountUuid!.isEmpty
        ? null
        : VotingSessionKey(roundId: roundId, accountUuid: accountUuid!);
    final session = jobKey == null
        ? ref.watch(votingSessionProvider(roundId))
        : ref.watch(votingSubmissionJobSessionProvider(jobKey));
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: SensitivePrivacyOverlay(
          sensitiveContentVisible: true,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: session.when(
              skipLoadingOnRefresh: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ConfirmationScaffold(
                confirmed: false,
                title: 'Submission Not Complete',
                pollTitle: 'Coinholder Poll',
                message: "Couldn't load submission details: $error",
                votingPower: 'Not available',
              ),
              data: (state) {
                final pollTitle = state.round?.title.isNotEmpty == true
                    ? state.round!.title
                    : 'Coinholder Poll';
                if (!hasCompletedVoteForDisplay(
                  roundPlan: state.roundPlan,
                  resumePlan: state.resumePlan,
                )) {
                  return _ConfirmationScaffold(
                    confirmed: false,
                    title: 'Submission Not Complete',
                    pollTitle: pollTitle,
                    message:
                        'This account has not completed submission for this poll.',
                    votingPower: 'Not available',
                  );
                }
                return _ConfirmationScaffold(
                  confirmed: true,
                  title: 'Submission Confirmed!',
                  pollTitle: pollTitle,
                  message:
                      'Your vote was successfully published and cannot be changed.',
                  votingPower: state.eligibleWeightZatoshi == null
                      ? 'Not available'
                      : formatVotingPower(state.eligibleWeightZatoshi!),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmationScaffold extends StatelessWidget {
  const _ConfirmationScaffold({
    required this.confirmed,
    required this.title,
    required this.pollTitle,
    required this.message,
    required this.votingPower,
  });

  final bool confirmed;
  final String title;
  final String pollTitle;
  final String message;
  final String votingPower;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(alignment: Alignment.centerLeft, child: AppRouteBackLink()),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
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
                            confirmed ? Icons.verified : Icons.error_outline,
                            color: confirmed
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
                    title,
                    style: AppTypography.headlineMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    message,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ReceiptCard(
                    rows: [
                      _ReceiptRow(label: 'Poll', value: pollTitle),
                      _ReceiptRow(label: 'Voting power', value: votingPower),
                    ],
                  ),
                  const Spacer(flex: 2),
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      onPressed: () => context.go('/voting'),
                      variant: AppButtonVariant.primary,
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.rows});

  final List<_ReceiptRow> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.background.raised.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.border.subtle),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.s,
              ),
              child: rows[i],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}
