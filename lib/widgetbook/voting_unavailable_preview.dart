import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../src/core/layout/app_form_factor.dart';
import '../src/core/theme/app_theme.dart';
import '../src/features/voting/screens/mobile/mobile_voting_screens.dart';
import '../src/features/voting/screens/voting_proposal_detail_screen.dart';
import '../src/features/voting/voting_flow_models.dart';
import '../src/features/voting/widgets/mobile/voting_scroll_header.dart';
import 'fixtures/retroactive_q3_2026.dart';

/// Uses the live header and unavailable state without wallet or network access.
class VotingUnavailablePreview extends StatefulWidget {
  const VotingUnavailablePreview({super.key, this.onRetry});

  final VoidCallback? onRetry;

  @override
  State<VotingUnavailablePreview> createState() =>
      _VotingUnavailablePreviewState();
}

class _VotingUnavailablePreviewState extends State<VotingUnavailablePreview> {
  late final _router = GoRouter(
    initialLocation: '/voting/poll/preview',
    routes: [
      GoRoute(
        path: '/voting',
        builder: (_, _) => const Scaffold(body: Text('Vote')),
        routes: [
          GoRoute(
            path: 'poll/:roundId',
            builder: (context, _) {
              const mobile = kAppFormFactor == AppFormFactor.mobile;
              final ballot = VotingActivePollContent(
                showDesktopToolbar: !mobile,
                mobileHeaderBuilder: mobile
                    ? (compact, navigation) => VotingScrollHeader(
                        title: 'Coinholder voting',
                        compact: compact,
                        navigation: navigation,
                        onBack: () => context.pop(),
                      )
                    : null,
                roundId: 'preview',
                title: retroactiveQ3Title,
                snapshotHeight: 3543600,
                description: retroactiveQ3Intro,
                forumUri: null,
                endDate: null,
                votingPowerZatoshi: BigInt.from(37500000),
                votingPowerPreparing: false,
                votingEligibilityConfirmed: false,
                answersEditable: false,
                votingEligibilityMessage: null,
                votingEligibilityErrorMessage: null,
                onVotingEligibilityRetry: () {},
                participationUnavailable: true,
                onParticipationRetry: widget.onRetry ?? () {},
                proposals: retroactiveQ3Proposals,
                draft: const VotingDraftState(),
                onChoice: (_, _) {},
              );
              return Scaffold(
                body: mobile
                    ? MobileVotingScaffold(
                        title: 'Coinholder voting',
                        showHeader: false,
                        child: ballot,
                      )
                    : ballot,
              );
            },
          ),
        ],
      ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.appTheme;
    final media = MediaQuery.of(context);
    return MaterialApp.router(
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      theme: Theme.of(context),
      builder: (context, child) => AppTheme(
        data: theme,
        child: MediaQuery(data: media, child: child!),
      ),
    );
  }
}
