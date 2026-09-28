import 'package:flutter/material.dart';

import '../src/core/theme/app_theme.dart';
import '../src/features/voting/screens/voting_proposal_detail_screen.dart';
import '../src/features/voting/voting_flow_models.dart';
import '../src/features/voting/widgets/mobile/voting_scroll_header.dart';
import '../src/features/voting/widgets/voting_metadata_widgets.dart';
import '../src/features/voting/widgets/voting_pane_scroll_area.dart';

/// Stateful preview of the live ballot, without wallet access or submission.
class VotingNavigationPreview extends StatefulWidget {
  const VotingNavigationPreview({
    super.key,
    this.initialChoices = const {},
    this.proposals,
    this.title = 'Community priorities',
    this.introduction =
        'Help shape the next funding round. Choose the priorities '
        'you support; you can leave questions unanswered.',
  });

  final List<VotingProposalView>? proposals;
  final String title;
  final String introduction;

  final Map<int, int> initialChoices;

  @override
  State<VotingNavigationPreview> createState() =>
      _VotingNavigationPreviewState();
}

class _VotingNavigationPreviewState extends State<VotingNavigationPreview> {
  late VotingDraftState _draft;

  static const _demoTopics = [
    'Community grants',
    'Developer tooling',
    'Wallet usability',
    'Education and documentation',
    'Network research',
    'Security reviews',
    'Local community events',
    'Open-source infrastructure',
    'Accessibility improvements',
    'Ecosystem support',
    'Public progress reports',
    'Next round priorities',
  ];

  late final List<VotingProposalView> _proposals =
      widget.proposals ??
      [
        for (var i = 0; i < _demoTopics.length; i++)
          VotingProposalView(
            id: i + 1,
            title: _demoTopics[i],
            description: i % 3 == 0
                ? 'Should the next round allocate more support to ${_demoTopics[i].toLowerCase()}? '
                      'Consider the benefit to everyday users and the effort needed to maintain this work over time.'
                : 'Should ${_demoTopics[i].toLowerCase()} receive support in the next round?',
            options: const [
              VotingOptionView(index: 1, label: 'Support'),
              VotingOptionView(index: 2, label: 'Oppose'),
              VotingOptionView(index: 3, label: 'Abstain'),
            ],
          ),
      ];

  @override
  void initState() {
    super.initState();
    _draft = VotingDraftState(
      choices: {
        for (final entry in widget.initialChoices.entries)
          _proposals[entry.key].id: entry.value,
      },
    );
  }

  @override
  Widget build(BuildContext context) => VotingActivePollContent(
    showDesktopToolbar: false,
    mobileHeaderBuilder: (compact, navigation) => VotingScrollHeader(
      title: 'Coinholder voting',
      compact: compact,
      navigation: navigation,
      onBack: () {},
    ),
    roundId: 'widgetbook-preview',
    title: widget.title,
    snapshotHeight: 3543600,
    description: widget.introduction,
    forumUri: null,
    endDate: null,
    votingPowerZatoshi: BigInt.from(37500000),
    votingPowerPreparing: false,
    votingEligibilityConfirmed: true,
    answersEditable: true,
    votingEligibilityMessage: null,
    votingEligibilityErrorMessage: null,
    onVotingEligibilityRetry: () {},
    proposals: _proposals,
    draft: _draft,
    onChoice: (id, choice) => setState(() {
      _draft = choice == null
          ? _draft.clearChoice(id)
          : _draft.setChoice(id, choice);
    }),
    onReviewRequested: _review,
  );

  Future<void> _review() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => AppTheme(
          data: this.context.appTheme,
          child: _PreviewReview(proposals: _proposals, draft: _draft),
        ),
      ),
    );
  }
}

/// Read-only answer preview; voting submissions are outside this fixture.
class _PreviewReview extends StatelessWidget {
  const _PreviewReview({required this.proposals, required this.draft});
  final List<VotingProposalView> proposals;
  final VotingDraftState draft;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.background.ground,
    body: Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to voting',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                'Review your answers',
                style: AppTypography.headlineSmall,
              ),
            ),
          ],
        ),
        Expanded(
          child: VotingPaneScrollView(
            maxWidth: 560,
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              children: [
                for (final proposal in proposals) ...[
                  VotingProposalCard(
                    proposal: proposal,
                    selectedChoice: draft.choices[proposal.id],
                    readOnly: true,
                    statusLabel: draft.choices[proposal.id] == null
                        ? 'Skipped'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
