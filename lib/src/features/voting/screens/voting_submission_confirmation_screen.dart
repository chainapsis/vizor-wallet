import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../voting_confirmation_flow.dart';
import '../widgets/voting_pane_scroll_area.dart';
import '../widgets/voting_receipt_widgets.dart';

class VotingSubmissionConfirmationScreen extends StatelessWidget {
  const VotingSubmissionConfirmationScreen({
    super.key,
    required this.roundId,
    this.accountUuid,
  });

  final String roundId;
  final String? accountUuid;

  @override
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: VotingSubmissionConfirmationFlow(
          roundId: roundId,
          accountUuid: accountUuid,
          builder: (context, view) {
            if (view == null) {
              return const VotingPaneStateView(child: VotingPaneLoading());
            }
            return _ConfirmationScaffold(view: view);
          },
        ),
      ),
    );
  }
}

class _ConfirmationScaffold extends StatelessWidget {
  const _ConfirmationScaffold({required this.view});

  final VotingConfirmationViewModel view;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPaneToolbar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
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
                                borderRadius: BorderRadius.circular(
                                  AppRadii.full,
                                ),
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
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.full,
                                  ),
                                ),
                                child: Icon(
                                  view.confirmed
                                      ? Icons.verified
                                      : Icons.error_outline,
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
                        const Spacer(flex: 2),
                        SizedBox(
                          width: double.infinity,
                          child: AppButton(
                            key: const ValueKey(
                              'voting_submission_done_button',
                            ),
                            onPressed: view.doneEnabled
                                ? view.onDone ?? () => context.go('/voting')
                                : null,
                            variant: AppButtonVariant.primary,
                            child: Text(view.doneLabel),
                          ),
                        ),
                        if (view.onRetry != null &&
                            view.retryLabel != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          SizedBox(
                            width: double.infinity,
                            child: AppButton(
                              onPressed: view.onRetry,
                              variant: AppButtonVariant.secondary,
                              child: Text(view.retryLabel!),
                            ),
                          ),
                        ],
                        if (view.returnErrorMessage != null) ...[
                          const SizedBox(height: AppSpacing.xs),
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
              ),
            ),
          ],
        ),
        if (view.isReturningToPolls)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0x4D000000)),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppIcon(
                          AppIcons.loader,
                          size: 20,
                          color: Color(0xFFFFFFFF),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          'Updating voting rounds...',
                          style: AppTypography.bodyMediumStrong.copyWith(
                            color: const Color(0xFFFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
