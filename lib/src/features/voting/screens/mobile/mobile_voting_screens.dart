import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../providers/account_provider.dart';
import 'mobile_keystone_voting_signing_screen.dart';
import '../voting_polls_screen.dart';
import '../voting_proposal_detail_screen.dart';
import '../voting_results_screen.dart';
import '../voting_review_screen.dart';
import '../voting_status_screen.dart';
import '../voting_submission_confirmation_screen.dart';
import '../../widgets/voting_pane_scroll_area.dart';
import '../../widgets/mobile/mobile_voting_config_settings_sheet.dart';

class MobileVotingPollsScreen extends StatelessWidget {
  const MobileVotingPollsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _MobileVotingScaffold(
      title: 'Coinholder voting',
      fallbackPath: '/home',
      trailing: _MobileVotingSettingsButton(
        onTap: () => showMobileVotingConfigSettingsSheet(context),
      ),
      child: const VotingPollsView(showDesktopChrome: false),
    );
  }
}

class MobileVotingProposalDetailScreen extends StatelessWidget {
  const MobileVotingProposalDetailScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    return _MobileVotingScaffold(
      title: 'Coinholder voting',
      child: VotingProposalDetailView(
        roundId: roundId,
        showDesktopToolbar: false,
      ),
    );
  }
}

class MobileVotingReviewScreen extends StatelessWidget {
  const MobileVotingReviewScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    return _MobileVotingScaffold(
      title: 'Review vote',
      child: VotingReviewView(roundId: roundId, showDesktopToolbar: false),
    );
  }
}

class MobileVotingStatusScreen extends StatelessWidget {
  const MobileVotingStatusScreen({
    super.key,
    required this.roundId,
    this.accountUuid,
  });

  final String roundId;
  final String? accountUuid;

  @override
  Widget build(BuildContext context) {
    return VotingStatusView(
      roundId: roundId,
      accountUuid: accountUuid,
      requireCurrentRouteForConfirmation: true,
      contentWrapper: (_, content) => _MobileVotingScaffold(
        title: 'Submit vote',
        horizontalPadding: AppSpacing.sm,
        child: content,
      ),
      keystoneStatusBuilder: (_, presentation) =>
          MobileKeystoneVotingSigningScreen(presentation: presentation),
    );
  }
}

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
    return _MobileVotingScaffold(
      title: 'Vote submitted',
      child: VotingSubmissionConfirmationView(
        roundId: roundId,
        accountUuid: accountUuid,
        showDesktopToolbar: false,
      ),
    );
  }
}

class MobileVotingResultsScreen extends StatelessWidget {
  const MobileVotingResultsScreen({super.key, required this.roundId});

  final String roundId;

  @override
  Widget build(BuildContext context) {
    return _MobileVotingScaffold(
      title: 'Voting results',
      horizontalPadding: AppSpacing.sm,
      child: VotingResultsView(roundId: roundId, showDesktopToolbar: false),
    );
  }
}

/// Account loading/error boundary for the mobile voting route tree. The
/// desktop guard remains desktop-only; both consume the same account state.
class MobileVotingAccountGuard extends ConsumerWidget {
  const MobileVotingAccountGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(accountProvider)
        .when(
          loading: () => const _MobileVotingScaffold(
            title: 'Coinholder voting',
            fallbackPath: '/home',
            child: VotingPaneLoading(),
          ),
          error: (error, _) => _MobileVotingScaffold(
            title: 'Coinholder voting',
            fallbackPath: '/home',
            horizontalPadding: AppSpacing.sm,
            child: Center(
              child: Text(
                "Couldn't load account.\n$error",
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
          ),
          data: (_) => child,
        );
  }
}

class _MobileVotingScaffold extends StatelessWidget {
  const _MobileVotingScaffold({
    required this.title,
    required this.child,
    this.fallbackPath = '/voting',
    this.horizontalPadding = 0,
    this.trailing,
  });

  final String title;
  final Widget child;
  final String fallbackPath;
  final double horizontalPadding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final body = horizontalPadding == 0
        ? child
        : Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: child,
          );
    return Material(
      color: context.colors.background.window,
      child: SafeArea(
        bottom: false,
        child: MobileBottomSafeArea(
          bottomPadding: AppSpacing.md,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MobileTopNav.back(
                title: title,
                trailing: trailing,
                onBack: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(fallbackPath);
                  }
                },
              ),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileVotingSettingsButton extends StatelessWidget {
  const _MobileVotingSettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Voting config settings',
      button: true,
      child: GestureDetector(
        key: const ValueKey('mobile_voting_settings_button'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: AppIcon(
              AppIcons.cog,
              size: 22,
              color: context.colors.icon.accent,
            ),
          ),
        ),
      ),
    );
  }
}
