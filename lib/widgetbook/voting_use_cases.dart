// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:zcash_wallet/src/providers/voting/voting_participation_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/core/layout/app_desktop_shell.dart';
import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/profile_pictures.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/app_back_link.dart';
import '../src/core/widgets/app_button.dart';
import '../src/core/widgets/app_icon.dart';
import '../src/core/widgets/app_pane_modal_overlay.dart';
import '../src/features/voting/screens/mobile/mobile_keystone_voting_signing_screen.dart';
import '../src/features/voting/screens/mobile/mobile_voting_submitted_screen.dart';
import '../src/features/voting/screens/mobile/mobile_voting_submission_progress_screen.dart';
import '../src/features/voting/screens/mobile/mobile_voting_screens.dart';
import '../src/features/voting/screens/voting_proposal_detail_screen.dart';
import '../src/features/voting/screens/voting_results_screen.dart';
import '../src/features/voting/screens/voting_status_screen.dart';
import '../src/features/voting/voting_flow_models.dart';
import '../src/features/voting/widgets/voting_config_settings_panel.dart';
import '../src/features/voting/widgets/voting_metadata_widgets.dart';
import '../src/features/voting/widgets/mobile/mobile_voting_config_settings_sheet.dart';
import '../src/providers/voting/voting_config_provider.dart';
import '../src/providers/voting/voting_config_source_provider.dart';
import '../src/providers/voting/voting_service_providers.dart';
import '../src/providers/voting/voting_poll_eligibility_provider.dart';
import '../src/providers/voting/voting_pir_warmup_provider.dart';
import '../src/providers/voting/voting_round_visibility_provider.dart';
import '../src/providers/voting/voting_rounds_provider.dart';
import '../src/providers/voting/voting_state.dart';
import '../src/providers/voting/voting_submission_job_provider.dart';
import '../src/rust/third_party/zcash_voting/config.dart';
import '../src/services/qr_scanner.dart';
import '../src/services/voting/voting_config_loader.dart';
import 'support/wb_layout.dart';
import 'support/wb_voting_dates.dart';

/// Which shell the voted-poll fixture is framed in. `VotingVotedPollContent`
/// itself branches on `kAppFormFactor`, so this only picks the surrounding
/// chrome, never the content's own metrics.
enum VotingVotedPollFrame { desktop, mobile }

/// Whether every proposal of the submitted vote carries an answer.
enum VotingVotedPollAnswers { allAnswered, someSkipped }

/// Whether the submission date is known.
enum VotingVotedPollVotedAt { date, notAvailable }

/// What the voted receipt reports as this account's voting power.
enum VotingVotedPollPower { amount, preparing, notAvailable }

/// How many proposals the voted round carries.
enum VotingVotedPollProposals { some, none }

/// Shared body of the three voted-poll builders below.
Widget votingVotedPollFixture({
  required VotingVotedPollFrame frame,
  VotingVotedPollAnswers answers = VotingVotedPollAnswers.allAnswered,
  VotingVotedPollVotedAt votedAt = VotingVotedPollVotedAt.date,
  VotingVotedPollPower power = VotingVotedPollPower.amount,
  VotingVotedPollProposals proposals = VotingVotedPollProposals.some,
}) {
  final content = VotingVotedPollContent(
    showDesktopToolbar: false,
    roundTitle: '[TEST] Very Serious Snack Governance 3',
    snapshotHeight: 3543600,
    description:
        'A silly sample round for testing the shielded vote builder '
        'without using real governance content.',
    forumUri: null,
    votingPowerZatoshi: power == VotingVotedPollPower.amount
        ? BigInt.from(37500000)
        : null,
    votingPowerPreparing: power == VotingVotedPollPower.preparing,
    votedAt: votedAt == VotingVotedPollVotedAt.date
        ? DateTime(2026, 8, 24)
        : null,
    proposals: proposals == VotingVotedPollProposals.some
        ? const [_previewSnackProposal]
        : const [],
    // A missing entry is what renders the 'Skipped' status on a proposal.
    choicesByProposalId: answers == VotingVotedPollAnswers.allAnswered
        ? const {1: 1}
        : const {},
    shareStatusNow: _previewVotingShareNow,
  );
  return switch (frame) {
    VotingVotedPollFrame.desktop => _votingDesktopPreviewShell(content),
    VotingVotedPollFrame.mobile => WbFrame(
      layout: WbLayout.mobile,
      child: MobileVotingScaffold(
        title: 'Voted',
        onBack: _previewNoop,
        child: content,
      ),
    ),
  };
}

/// Desktop pane the prop-driven voting panels are previewed in: the real shell
/// with a static sidebar, since these fixtures carry no router.
Widget _votingDesktopPreviewShell(Widget content) {
  return WbDesktopWindowBox(
    child: AppDesktopShell(
      sidebar: const _VotingPreviewSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            const AppPaneToolbar(
              leading: AppBackLink(
                label: 'Vote',
                minWidth: 60,
                onTap: _previewNoop,
              ),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    ),
  );
}

Widget buildDesktopVotingVotedUseCase(BuildContext context) {
  return votingVotedPollFixture(frame: VotingVotedPollFrame.desktop);
}

Widget buildMobileVotingPollsUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [
      votingParticipationUnavailableProvider.overrideWith(
        (ref, roundId) => false,
      ),
      votingPollEligibilityProvider.overrideWith(
        (ref, roundId) async => VotingPollEligibility.eligible,
      ),
      votingConfigProvider.overrideWith(_PreviewVotingConfigNotifier.new),
      votingRoundsProvider.overrideWith(_PreviewVotingRoundsNotifier.new),
      votingConfigSourceProvider.overrideWith(
        _PreviewVotingConfigSourceNotifier.new,
      ),
      showTestVotingRoundsProvider.overrideWith(
        _PreviewShowTestVotingRoundsNotifier.new,
      ),
      // The screen starts a warm-up pass from `initState`, which would resolve
      // a real wallet DB path and call the vote servers.
      votingPirWarmupProvider.overrideWith(_PreviewVotingPirWarmup.new),
    ],
    child: const MobileVotingPollsScreen(),
  );
}

/// States the previews' offline behaviour instead of relying on the preview
/// config's empty server list plus the coordinator's swallowed exception.
class _PreviewVotingPirWarmup extends VotingPirWarmupCoordinator {
  _PreviewVotingPirWarmup(super.ref);

  @override
  Future<void> maybeWarmActiveRounds() async {}
}

/// Matches the four list states in Figma 8045:24064 without wallet I/O.
Widget buildMobileVotingPollsEligibilityUseCase(
  BuildContext context, {
  Future<VotingPollEligibility> Function(String)? loadEligibility,
  bool previouslyUsed = false,
}) {
  return _mobileVotingFullPagePreview(
    context,
    ProviderScope(
      overrides: [
        votingConfigProvider.overrideWith(_PreviewVotingConfigNotifier.new),
        votingRoundsProvider.overrideWith(
          _EligibilityPreviewRoundsNotifier.new,
        ),
        votingConfigSourceProvider.overrideWith(
          _PreviewVotingConfigSourceNotifier.new,
        ),
        showTestVotingRoundsProvider.overrideWith(
          _PreviewShowTestVotingRoundsNotifier.new,
        ),
        votingParticipationUnavailableProvider.overrideWith(
          (ref, roundId) => previouslyUsed && roundId == 'nu7-ineligible',
        ),
        votingPollEligibilityProvider.overrideWith(
          (ref, roundId) async => loadEligibility != null
              ? loadEligibility(roundId)
              : roundId == 'nu7-ineligible'
              ? VotingPollEligibility.ineligible
              : VotingPollEligibility.eligible,
        ),
      ],
      child: const MobileVotingPollsScreen(),
    ),
    size: MediaQuery.sizeOf(context),
  );
}

Widget buildMobileVotingConfigUseCase(BuildContext context) =>
    _buildMobileVotingConfigPreview(context);

Widget buildMobileVotingConfigDefaultUseCase(BuildContext context) =>
    _buildMobileVotingConfigPreview(context, defaultOnly: true);

Widget _buildMobileVotingConfigPreview(
  BuildContext context, {
  bool defaultOnly = false,
}) {
  return votingConfigSettingsFixture(
    sources: defaultOnly
        ? VotingConfigSourcesCase.defaultOnly
        : VotingConfigSourcesCase.savedSource,
    testRounds: defaultOnly,
  );
}

/// Which config-source list the settings surface opens with.
enum VotingConfigSourcesCase { defaultOnly, savedSource, customSelected }

/// How far the saved-source read got.
enum VotingConfigLoadCase { loaded, loading, failed }

/// Whether the source form is open, and on which source. Both surfaces keep
/// this in their own `State`, so the preview presses their real add and edit
/// controls. Editing needs a saved source, so it follows the Sources axis.
enum VotingConfigEditorCase { closed, addingSource, editingSource }

/// Voting config settings: `VotingConfigSettingsPanel` in a desktop pane modal
/// / `MobileVotingConfigSettingsSheet` over the poll list.
Widget votingConfigSettingsFixture({
  WbLayout layout = WbLayout.mobile,
  VotingConfigSourcesCase sources = VotingConfigSourcesCase.savedSource,
  VotingConfigLoadCase config = VotingConfigLoadCase.loaded,
  bool testRounds = false,
  VotingConfigEditorCase editor = VotingConfigEditorCase.closed,
}) {
  // The edit control only exists on a saved source, so the editing case pins
  // the list it needs instead of silently rendering as 'Closed'.
  final sourceList =
      editor == VotingConfigEditorCase.editingSource &&
          sources == VotingConfigSourcesCase.defaultOnly
      ? VotingConfigSourcesCase.savedSource
      : sources;
  return ProviderScope(
    // No retry: Riverpod's backoff would turn the load error back into a
    // spinner.
    retry: (_, _) => null,
    overrides: [
      // Custom-source validation is unavailable in this static preview.
      votingHttpClientProvider.overrideWith(
        (_) => throw StateError('Source validation is preview-only.'),
      ),
      votingParticipationUnavailableProvider.overrideWith(
        (ref, roundId) => false,
      ),
      votingPollEligibilityProvider.overrideWith(
        (ref, roundId) async => VotingPollEligibility.eligible,
      ),
      votingConfigProvider.overrideWith(_PreviewVotingConfigNotifier.new),
      votingRoundsProvider.overrideWith(_PreviewVotingRoundsNotifier.new),
      votingConfigSourceProvider.overrideWith(
        () => _PreviewVotingConfigSourceNotifier(
          initialState: switch (sourceList) {
            VotingConfigSourcesCase.defaultOnly =>
              const VotingConfigSourceState(
                sourceUrl: kDefaultStaticVotingConfigSource,
                isDefault: true,
              ),
            VotingConfigSourcesCase.savedSource => _previewSourceState,
            // The active source is the saved one, so its card carries the
            // 'Active' badge next to the default card's 'Default'.
            VotingConfigSourcesCase.customSelected =>
              const VotingConfigSourceState(
                sourceUrl: _previewSavedSourceUrl,
                isDefault: false,
                savedSources: [_previewSavedSource],
              ),
          },
          loading: config == VotingConfigLoadCase.loading,
          loadError: config == VotingConfigLoadCase.failed
              ? "Couldn't load the saved voting config sources."
              : null,
        ),
      ),
      showTestVotingRoundsProvider.overrideWith(
        () => _PreviewShowTestVotingRoundsNotifier(initialValue: testRounds),
      ),
      // The poll list behind the sheet starts a warm-up pass from `initState`,
      // which would resolve a real wallet DB path and call the vote servers.
      votingPirWarmupProvider.overrideWith(_PreviewVotingPirWarmup.new),
    ],
    child: _votingConfigEditorDriver(
      editor,
      layout,
      layout == WbLayout.mobile
          ? const WbFrame(
              layout: WbLayout.mobile,
              child: _VotingSettingsSheetHost(),
            )
          : WbFrame(
              layout: WbLayout.desktop,
              child: Stack(
                children: [
                  const SizedBox.expand(),
                  AppPaneModalOverlay(
                    onDismiss: _previewNoop,
                    child: VotingConfigSettingsPanel(
                      onClose: _previewNoop,
                      onUpdated: _previewNoop,
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}

/// Own both routes so even an unconditional production pop stays local.
class _VotingSettingsSheetHost extends StatefulWidget {
  const _VotingSettingsSheetHost();

  @override
  State<_VotingSettingsSheetHost> createState() => _VotingSettingsSheetHostState();
}

class _VotingSettingsSheetHostState extends State<_VotingSettingsSheetHost> {
  bool _open = true;

  @override
  Widget build(BuildContext context) => Navigator(
    pages: [
      MaterialPage<void>(
        key: const ValueKey('voting_settings_preview_base'),
        child: Center(
          child: AppButton(
            onPressed: () => setState(() => _open = true),
            child: const Text('Reopen voting settings'),
          ),
        ),
      ),
      if (_open)
        const MaterialPage<void>(
          key: ValueKey('voting_settings_preview_sheet'),
          child: MobileModalOverlay(
            background: MobileVotingPollsScreen(),
            child: MobileVotingConfigSettingsSheet(),
          ),
        ),
    ],
    onDidRemovePage: (_) => setState(() => _open = false),
  );
}

/// Opens the editor through each surface's own control: both label the add
/// button the same way, while the edit action carries a per-layout label.
Widget _votingConfigEditorDriver(
  VotingConfigEditorCase editor,
  WbLayout layout,
  Widget child,
) {
  final label = switch (editor) {
    VotingConfigEditorCase.closed => null,
    VotingConfigEditorCase.addingSource => 'Add custom source',
    VotingConfigEditorCase.editingSource =>
      layout == WbLayout.mobile
          ? 'Edit ${_previewSavedSource.name}'
          : 'Edit saved source',
  };
  return label == null
      ? child
      // Keyed by label: without it a knob change reuses the driver element, so
      // `initState` never re-runs and the previously opened form stays up.
      : VotingPreviewTapOnMount(
          key: ValueKey(label),
          label: label,
          child: child,
        );
}

/// Presses a production control one frame after mount.
///
/// Calls the control's own callback rather than synthesising a pointer, which
/// anything the widgetbook chrome overlays would intercept. [label] is either
/// the control's visible text or its semantic label.
class VotingPreviewTapOnMount extends StatefulWidget {
  const VotingPreviewTapOnMount({
    required this.label,
    required this.child,
    super.key,
  });

  final String label;
  final Widget child;

  @override
  State<VotingPreviewTapOnMount> createState() =>
      _VotingPreviewTapOnMountState();
}

class _VotingPreviewTapOnMountState extends State<VotingPreviewTapOnMount> {
  static const _maxAttempts = 8;
  var _attempts = 0;
  var _done = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _press());
  }

  void _press() {
    if (_done || !mounted) return;
    final onPressed = _pressable();
    if (onPressed == null) {
      if (++_attempts >= _maxAttempts) {
        // Loud in debug: a silent give-up renders as the closed editor, which
        // is exactly the neighbouring option.
        assert(false, 'voting preview never found "${widget.label}"');
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _press());
      WidgetsBinding.instance.scheduleFrame();
      return;
    }
    _done = true;
    onPressed();
  }

  /// The label's own control: the nearest pressable above a matching [Text],
  /// or the first one below a matching [Semantics] label.
  VoidCallback? _pressable() {
    final path = <Element>[];
    VoidCallback? found;
    var stop = false;

    VoidCallback? callbackOf(Widget candidate) {
      if (candidate is AppButton) return candidate.onPressed;
      if (candidate is InkWell) return candidate.onTap;
      if (candidate is GestureDetector) return candidate.onTap;
      return null;
    }

    // The control the label belongs to, whose null callback means 'disabled'.
    // `AppButton` and `InkWell` wrap their own gesture detector, so a bare
    // `GestureDetector` only owns the label when it carries the tap itself.
    bool ownsLabel(Widget candidate) {
      if (candidate is AppButton || candidate is InkWell) return true;
      return candidate is GestureDetector && candidate.onTap != null;
    }

    void descend(Element element) {
      if (found != null) return;
      found = callbackOf(element.widget);
      if (found != null) return;
      element.visitChildren(descend);
    }

    void visit(Element element) {
      if (found != null || stop) return;
      path.add(element);
      final candidate = element.widget;
      if (candidate is Text && candidate.data == widget.label) {
        for (final ancestor in path.reversed) {
          if (!ownsLabel(ancestor.widget)) continue;
          // A disabled control is a no-op: climbing past it would press an
          // enclosing row, and searching on would match a same-label title.
          found = callbackOf(ancestor.widget);
          stop = true;
          break;
        }
      } else if (candidate is Semantics &&
          candidate.properties.label == widget.label) {
        element.visitChildren(descend);
      }
      if (found == null && !stop) element.visitChildren(visit);
      path.removeLast();
    }

    context.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Widget buildMobileVotingVotedUseCase(BuildContext context) {
  return votingVotedPollFixture(frame: VotingVotedPollFrame.mobile);
}

Widget buildMobileVotingVotedCompleteUseCase(BuildContext context) {
  return votingVotedPollFixture(frame: VotingVotedPollFrame.mobile);
}

Widget buildMobileVotingProposalDefaultUseCase(BuildContext context) {
  return _votingProposalCardPreview(proposal: _previewSnackProposal);
}

Widget buildMobileVotingEligibleUseCase(BuildContext context) =>
    votingActivePollFixture(context, eligible: true);

Widget buildMobileVotingIneligibleUseCase(BuildContext context) =>
    votingActivePollFixture(context, eligible: false);

Widget buildMobileVotingPrivacyTrimUseCase(BuildContext context) =>
    votingActivePollFixture(
      context,
      eligible: true,
      votingEligibilityMessage:
          '0.125 ZEC is left out of this vote '
          'to keep your submission less identifiable.',
    );

Widget buildMobileVotingEligibilityErrorUseCase(BuildContext context) =>
    votingActivePollFixture(
      context,
      eligible: false,
      eligibilityUnknown: true,
      votingEligibilityMessage: 'Unable to check voting eligibility.',
    );

/// Which shell the active-poll fixture is framed in. `VotingActivePollContent`
/// branches on `kAppFormFactor` for its own layout, so this only picks the
/// surrounding chrome.
enum VotingActivePollFrame { desktop, mobile }

/// What the active poll reports as this account's voting power. `amount`
/// keeps whatever the eligibility case implies; the other two states are
/// unreachable from eligibility alone.
enum VotingActivePollPower { amount, preparing, unavailable }

/// How much of the draft the voter has answered.
enum VotingActivePollAnswers { none, some, all }

/// How many proposals the previewed round carries.
enum VotingActivePollProposals { one, two, three, none }

/// Shared body of the active-poll builders above: `VotingActivePollContent`
/// with every input as a prop.
Widget votingActivePollFixture(
  BuildContext context, {
  VotingActivePollFrame frame = VotingActivePollFrame.mobile,
  required bool eligible,
  bool eligibilityUnknown = false,
  bool previouslyUsed = false,
  String? votingEligibilityMessage,
  VotingActivePollPower power = VotingActivePollPower.amount,
  VotingActivePollAnswers answers = VotingActivePollAnswers.none,
  VotingActivePollProposals proposals = VotingActivePollProposals.one,
  bool showDescription = true,
  bool showEndDate = true,
}) {
  final proposalList = switch (proposals) {
    VotingActivePollProposals.one => const [_previewNsmProposal],
    VotingActivePollProposals.two => const [
      _previewNsmProposal,
      _previewNu7TimingProposal,
    ],
    VotingActivePollProposals.three => const [
      _previewNsmProposal,
      _previewNu7TimingProposal,
      _previewGrantsProposal,
    ],
    VotingActivePollProposals.none => const <VotingProposalView>[],
  };
  final content = VotingActivePollContent(
    showDesktopToolbar: false,
    participationUnavailable: previouslyUsed,
    onParticipationRetry: _previewNoop,
    roundId: 'preview-nsm',
    title: '[TEST] Very Serious Snack Governance 3',
    snapshotHeight: 3543600,
    description: showDescription
        ? 'A silly sample round for testing the shielded vote builder '
              'without using real governance content.'
        : '',
    forumUri: Uri.parse('https://forum.zcashcommunity.com/t/nsm'),
    endDate: showEndDate ? wbVotingActiveEndDate : null,
    votingPowerZatoshi: power != VotingActivePollPower.amount
        ? null
        : eligibilityUnknown
        ? null
        : eligible
        ? BigInt.from(37500000)
        : BigInt.zero,
    votingPowerPreparing: power == VotingActivePollPower.preparing,
    votingEligibilityConfirmed: eligible,
    answersEditable: eligible,
    votingEligibilityMessage: votingEligibilityMessage,
    votingEligibilityErrorMessage:
        eligible || eligibilityUnknown || previouslyUsed
        ? null
        : 'This account did not have enough eligible '
              'shielded funds at snapshot block 3,543,600. Switch to an eligible account to vote.',
    onVotingEligibilityRetry: _previewNoop,
    proposals: proposalList,
    draft: _activePollDraft(answers, proposalList),
    onChoice: (_, _) {},
  );
  final framed = switch (frame) {
    VotingActivePollFrame.desktop => _votingDesktopPreviewShell(content),
    VotingActivePollFrame.mobile => WbFrame(
      layout: WbLayout.mobile,
      child: MobileVotingScaffold(
        title: 'Coinholder voting',
        onBack: _previewNoop,
        child: content,
      ),
    ),
  };
  return VotingDisplayTimeScope(now: wbVotingReferenceDate, child: framed);
}

VotingDraftState _activePollDraft(
  VotingActivePollAnswers answers,
  List<VotingProposalView> proposals,
) {
  return switch (answers) {
    VotingActivePollAnswers.none => const VotingDraftState(),
    // 'Some' leaves the last proposal open, so it only differs from 'All' on a
    // round with more than one proposal.
    VotingActivePollAnswers.some => VotingDraftState(
      choices: {for (final proposal in proposals.take(1)) proposal.id: 1},
    ),
    VotingActivePollAnswers.all => VotingDraftState(
      choices: {for (final proposal in proposals) proposal.id: 1},
    ),
  };
}

const _previewNu7TimingProposal = VotingProposalView(
  id: 2,
  title: 'NU7 Release Timing',
  zipNumber: 'ZIP-235',
  description: 'When should NU7 activate if a feature misses the deadline?',
  options: [
    VotingOptionView(index: 1, label: 'Activate on schedule'),
    VotingOptionView(index: 2, label: 'Delay activation by one cycle'),
    VotingOptionView(index: 3, label: 'Abstain'),
  ],
);

const _previewGrantsProposal = VotingProposalView(
  id: 3,
  title: 'Community Grants Budget',
  zipNumber: 'ZIP-1016',
  description: 'How much of the block reward should fund community grants?',
  options: [
    VotingOptionView(index: 1, label: 'Keep the current split'),
    VotingOptionView(index: 2, label: 'Raise the grants share'),
    VotingOptionView(index: 3, label: 'Abstain'),
  ],
);

Widget buildMobileVotingIneligibleModalUseCase(BuildContext context) {
  return Stack(
    fit: StackFit.expand,
    children: [
      buildMobileVotingIneligibleUseCase(context),
      ColoredBox(color: context.colors.background.neutralScrim),
      const VotingIneligibleDialog(
        message:
            'Voting requires at least one eligible shielded note bundle '
            'with 0.125 ZEC at snapshot block 3,459,350. '
            'Switch to an eligible account to vote.',
      ),
    ],
  );
}

const _previewNsmProposal = VotingProposalView(
  id: 1,
  title: 'NSM Issuance Smoothing',
  zipNumber: 'ZIP-233 ZIP-234',
  description:
      'The component of the Network Sustainability Mechanism that removes '
      'ZEC from circulation is already approved. How that ZEC is recycled into '
      'future block rewards remains unresolved. In no case will the total supply '
      'of ZEC be affected.\n\nWhich approach do you support?',
  options: [
    VotingOptionView(
      index: 1,
      label:
          'Ship NU7 as soon as possible, removing any feature that is not implemented by the September',
    ),
    VotingOptionView(
      index: 2,
      label:
          'Delay NU7 until every applicable feature approved in this poll is deemed',
    ),
    VotingOptionView(index: 3, label: 'I do not support this NU7 plan.'),
    VotingOptionView(index: 4, label: 'Abstain'),
  ],
);

Widget buildMobileVotingProposalSelectedUseCase(BuildContext context) {
  return _votingProposalCardPreview(
    proposal: _previewSnackProposal,
    selectedChoice: 1,
  );
}

Widget buildMobileVotingResultsUseCase(BuildContext context) {
  return _votingResultCardPreview(
    proposal: _previewSnackResultProposal,
    tally: const {1: 2640.96, 2: 1040.96, 3: 240.96},
    selectedChoice: 2,
    profilePictureId: kDefaultProfilePictureId,
  );
}

Widget buildMobileVotingResultsFullUseCase(BuildContext context) =>
    _buildMobileVotingResultsPreview(context, selectedChoice: 2);

Widget buildMobileVotingResultsWinnerUseCase(BuildContext context) =>
    _buildMobileVotingResultsPreview(context, selectedChoice: 1);

Widget _buildMobileVotingResultsPreview(
  BuildContext context, {
  required int selectedChoice,
}) {
  return _mobileVotingFullPagePreview(
    context,
    MobileVotingScaffold(
      title: 'Voting results',
      child: VotingResultsContent(
        title: '[TEST] Very Serious Snack Governance 3',
        snapshotHeight: 3543600,
        description:
            'A silly sample round for testing the shielded vote builder without using real governance content.',
        forumUri: Uri.parse(
          'https://forum.zcashcommunity.com/t/snack-governance',
        ),
        proposals: const [_previewResultsDesignProposal],
        // Consistent real tally units: 985 + 10 + 5 = 1,000 ZEC.
        tallies: const {
          1: {1: 7880, 2: 80, 3: 40, 4: 0},
        },
        selectedChoices: {1: selectedChoice},
        profilePictureId: kDefaultProfilePictureId,
      ),
    ),
    size: MediaQuery.sizeOf(context),
  );
}

const _previewResultsDesignProposal = VotingProposalView(
  id: 1,
  title: 'Official Snack of the Next Team Sync',
  description:
      'NU7 will be consistent with the results of this poll, assuming each applicable feature is implemented by September 30th.\n\nHow should features that are not ready by the deadline be handled?',
  zipNumber: 'ZIP-2033 ZIP-2033',
  options: [
    VotingOptionView(
      index: 4,
      label:
          'Delay NU7 until every applicable feature approved in this poll is deemed complete.',
    ),
    VotingOptionView(index: 2, label: 'Abstain'),
    VotingOptionView(
      index: 1,
      label:
          'Ship NU7 as soon as possible, removing any feature that is not implemented by the September',
    ),
    VotingOptionView(index: 3, label: 'I do not support this NU7 plan.'),
  ],
);

/// Phone box the submission-progress fixture is framed in; the screen lays
/// itself out against the viewport, so the compact box is its own state.
enum VotingSubmissionViewport { phone, compact }

/// How far the active step has got, independent of which step is active.
///
/// `stepDefault` is what the screen reports for the selected step in
/// production; `unknown` is the indeterminate ring a step with no fraction
/// shows.
enum VotingSubmissionProgressCase {
  stepDefault,
  justStarted,
  quarter,
  mostOfTheWay,
  stepComplete,
  unknown,
}

/// Shared body of the four submission-progress builders below. Each step keeps
/// the determinacy it had as a standalone builder: the two mid-flow steps
/// report a fraction, `finalizing` is indeterminate. A [progress] value
/// overrides that per-step default.
Widget votingSubmissionProgressFixture(
  BuildContext context, {
  required VotingSubmissionProgressStep step,
  VotingSubmissionViewport viewport = VotingSubmissionViewport.phone,
  VotingSubmissionProgressCase? progress,
}) {
  final compact = viewport == VotingSubmissionViewport.compact;
  return _mobileVotingFullPagePreview(
    context,
    MobileVotingSubmissionProgressScreen(
      activeStep: step,
      activeStepProgress: switch (progress ??
          VotingSubmissionProgressCase.stepDefault) {
        VotingSubmissionProgressCase.stepDefault => switch (step) {
          VotingSubmissionProgressStep.provingAuthority => 0.25,
          VotingSubmissionProgressStep.castingVotes => 0.6,
          VotingSubmissionProgressStep.finalizing => null,
        },
        VotingSubmissionProgressCase.justStarted => 0,
        VotingSubmissionProgressCase.quarter => 0.25,
        VotingSubmissionProgressCase.mostOfTheWay => 0.6,
        VotingSubmissionProgressCase.stepComplete => 1,
        VotingSubmissionProgressCase.unknown => null,
      },
    ),
    size: compact ? const Size(375, 667) : const Size(393, 852),
    safeArea: compact
        ? const EdgeInsets.only(top: 47, bottom: 34)
        : const EdgeInsets.only(top: 55),
  );
}

Widget buildMobileVotingSubmissionDelegatingUseCase(BuildContext context) {
  return votingSubmissionProgressFixture(
    context,
    step: VotingSubmissionProgressStep.provingAuthority,
  );
}

Widget buildMobileVotingSubmissionCastingUseCase(BuildContext context) {
  return votingSubmissionProgressFixture(
    context,
    step: VotingSubmissionProgressStep.castingVotes,
  );
}

Widget buildMobileVotingSubmissionCastingCompactUseCase(BuildContext context) {
  return votingSubmissionProgressFixture(
    context,
    step: VotingSubmissionProgressStep.castingVotes,
    viewport: VotingSubmissionViewport.compact,
  );
}

Widget buildMobileVotingSubmissionFinalizingUseCase(BuildContext context) {
  return votingSubmissionProgressFixture(
    context,
    step: VotingSubmissionProgressStep.finalizing,
  );
}

Widget buildMobileVotingSubmittedUseCase(BuildContext context) {
  return _mobileVotingFullPagePreview(
    context,
    MobileVotingSubmittedScreen(onDone: _previewNoop),
  );
}

Widget _mobileVotingFullPagePreview(
  BuildContext context,
  Widget child, {
  Size size = const Size(393, 852),
  EdgeInsets safeArea = const EdgeInsets.only(top: 55),
}) {
  final mediaQuery = MediaQuery.of(context);
  return WbScaleDownBox(
    size: size,
    child: SizedBox(
      width: size.width,
      height: size.height,
      child: MediaQuery(
        data: mediaQuery.copyWith(
          size: size,
          padding: safeArea,
          viewPadding: safeArea,
        ),
        child: child,
      ),
    ),
  );
}

/// How many bundles the mobile signing request covers. The screen turns the
/// count into its context label, and no count at all drops that label.
enum VotingMobileKeystoneBundles { single, batch, uncounted }

/// How many bundle memos the request carries. One memo still renders the
/// pager, with both of its arrows disabled.
enum VotingMobileKeystoneMemos { none, one, pager }

/// Mobile Keystone voting handoff: `MobileKeystoneVotingSigningScreen` with a
/// stub scanner, opening either on the request QR or on the scan step.
Widget votingMobileKeystoneSigningFixture({
  bool startInScanner = false,
  VotingMobileKeystoneBundles bundles = VotingMobileKeystoneBundles.batch,
  VotingMobileKeystoneMemos memos = VotingMobileKeystoneMemos.pager,
  bool canSkip = true,
}) {
  return ProviderScope(
    child: WbFrame(
      layout: WbLayout.mobile,
      child: MobileKeystoneVotingSigningScreen(
        presentation: _previewKeystonePresentation(
          bundles: bundles,
          memos: memos,
          canSkip: canSkip,
        ),
        scannerBuilder: _previewVotingScanner,
        forceScannerActiveForTesting: true,
        startInScannerForTesting: startInScanner,
      ),
    ),
  );
}

Widget buildMobileVotingKeystoneRequestUseCase(BuildContext context) {
  return votingMobileKeystoneSigningFixture();
}

Widget buildMobileVotingKeystoneScannerUseCase(BuildContext context) {
  return votingMobileKeystoneSigningFixture(startInScanner: true);
}

Widget _previewVotingScanner(
  BuildContext context,
  ValueChanged<ScanResult> onComplete,
  ValueChanged<int> onProgress,
  Object? resetToken,
) {
  return const ColoredBox(color: Color(0xFF111515));
}

VotingKeystoneStatusPresentation _previewKeystonePresentation({
  required VotingMobileKeystoneBundles bundles,
  required VotingMobileKeystoneMemos memos,
  required bool canSkip,
}) {
  return VotingKeystoneStatusPresentation(
    bundleIndex: 0,
    urParts: const [_previewVotingKeystoneUr],
    batchMemos: switch (memos) {
      VotingMobileKeystoneMemos.none => const [],
      VotingMobileKeystoneMemos.one => const [_previewVotingKeystoneMemoOne],
      VotingMobileKeystoneMemos.pager => const [
        _previewVotingKeystoneMemoOne,
        _previewVotingKeystoneMemoTwo,
      ],
    },
    batchMessageCount: switch (bundles) {
      VotingMobileKeystoneBundles.single => 1,
      VotingMobileKeystoneBundles.batch => 2,
      VotingMobileKeystoneBundles.uncounted => 0,
    },
    batchTotalCount: switch (bundles) {
      VotingMobileKeystoneBundles.single => 1,
      VotingMobileKeystoneBundles.batch => 3,
      VotingMobileKeystoneBundles.uncounted => 0,
    },
    canSkipRemainingBundles: canSkip,
    onSigned: _previewSignedVotingResponse,
    onSkipRemainingBundles: _previewNoop,
  );
}

const _previewVotingKeystoneMemoOne = VotingKeystoneBatchMemo(
  bundleIndex: 0,
  bundleCount: 3,
  displayMemo: 'Amount: 1.25 ZEC\nProposal: Community grants',
);

const _previewVotingKeystoneMemoTwo = VotingKeystoneBatchMemo(
  bundleIndex: 1,
  bundleCount: 3,
  displayMemo: 'Amount: 0.75 ZEC\nProposal: Network priorities',
);

Future<void> _previewSignedVotingResponse(List<int> _) async {}
void _previewNoop() {}

const _previewVotingKeystoneUr =
    'ur:zcash-sign-batch/1-1/lpadaxcsfwdmfwfwhdcxhdcxfwcxhdcxhdcxfwcx';

final _previewVotingShareNow = DateTime.utc(2026, 8, 23, 12);

class _VotingPreviewSidebar extends StatelessWidget {
  const _VotingPreviewSidebar();

  @override
  Widget build(BuildContext context) {
    return AppDesktopSidebarSurface(
      glass: true,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            const AppSidebarItem(
              label: 'Demo wallet',
              iconName: AppIcons.user,
              leadingGap: AppSpacing.xs,
            ),
            const SizedBox(height: AppSpacing.md),
            AppSidebarItem(
              label: 'Home',
              iconName: AppIcons.home,
              onTap: _previewNoop,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Swap',
              iconName: AppIcons.swapArrows,
              onTap: _previewNoop,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Pay',
              iconName: AppIcons.paid,
              onTap: _previewNoop,
            ),
            const SizedBox(height: AppSpacing.xs),
            const AppSidebarItem(
              label: 'Vote',
              iconName: AppIcons.vote,
              active: true,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Activity',
              iconName: AppIcons.history,
              onTap: _previewNoop,
            ),
            const Spacer(),
            AppSidebarItem(
              label: 'Settings',
              iconName: AppIcons.cog,
              onTap: _previewNoop,
            ),
            const SizedBox(height: AppSpacing.xs),
            AppSidebarItem(
              label: 'Sign out',
              iconName: AppIcons.logOut,
              onTap: _previewNoop,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewVotingConfigNotifier extends VotingConfigNotifier {
  @override
  Future<ResolvedVotingConfig> build() async => _previewVotingConfig;

  @override
  Future<void> refresh() async {}
}

class _PreviewVotingRoundsNotifier extends VotingRoundsNotifier {
  @override
  Future<List<VotingRoundView>> build() async => _previewVotingRounds;

  @override
  Future<void> reload() async {
    state = AsyncData(_previewVotingRounds);
  }
}

class _EligibilityPreviewRoundsNotifier extends VotingRoundsNotifier {
  @override
  Future<List<VotingRoundView>> build() async => _eligibilityPreviewRounds;

  @override
  Future<void> reload() async {
    state = AsyncData(_eligibilityPreviewRounds);
  }
}

final _eligibilityPreviewRounds = [
  for (final id in ['nu7-ineligible', 'nu7-active'])
    VotingRoundView(
      roundId: id,
      title: 'NU7 Scope',
      status: 'active',
      rawJson: {
        'description':
            'This vote concerns the scope of NU7. It is one component of '
            "governance, but it represents the coinholders' view about NSM, supply...",
        'vote_end_time': wbVotingActiveEndTime,
        if (id == 'nu7-ineligible')
          'forum_url': 'https://forum.zcashcommunity.com/t/nu7-scope',
      },
    ),
  for (final round in _previewVotingRounds.skip(1))
    VotingRoundView(
      roundId: round.roundId,
      title: round.title,
      status: round.status,
      voted: round.voted,
      rawJson: {...round.rawJson}..remove('forum_url'),
    ),
];

class _PreviewVotingConfigSourceNotifier extends VotingConfigSourceNotifier {
  _PreviewVotingConfigSourceNotifier({
    this.initialState = _previewSourceState,
    this.loading = false,
    this.loadError,
  });
  final VotingConfigSourceState initialState;
  final bool loading;
  final String? loadError;

  @override
  Future<VotingConfigSourceState> build() async {
    if (loading) return Completer<VotingConfigSourceState>().future;
    final error = loadError;
    if (error != null) throw error;
    return initialState;
  }

  @override
  Future<void> resetDefault() async {
    state = const AsyncData(_previewSourceState);
  }

  @override
  Future<void> setCustom(String sourceUrl) async {}

  @override
  Future<void> saveSource({
    String? id,
    required String name,
    required String sourceUrl,
  }) async {}

  @override
  Future<void> deleteSavedSource(String id) async {}
}

class _PreviewShowTestVotingRoundsNotifier
    extends ShowTestVotingRoundsNotifier {
  _PreviewShowTestVotingRoundsNotifier({this.initialValue = false});
  final bool initialValue;

  @override
  Future<bool> build() async => initialValue;

  @override
  Future<void> setShowTestRounds(bool show) async {
    state = AsyncData(show);
  }
}

const _previewVotingConfig = ResolvedVotingConfig(
  sourceFingerprint: 'preview-source',
  trustedKeyFingerprint: 'preview-key',
  dynamicConfigFingerprint: 'preview-config',
  voteServers: [],
  pirEndpoints: [],
  pirLayout: PirLayout(
    pirDepth: 19,
    tier0Layers: 12,
    tier1Layers: 7,
    polyLen: 4096,
  ),
  supportedVersions: SupportedVersions(
    pir: [],
    voteProtocol: 'preview',
    tally: 'preview',
    voteServer: 'preview',
  ),
  authenticatedRounds: [],
  skippedRoundIds: [],
  conditions: [],
);

const _previewSavedSourceUrl =
    'https://vote.example.org/static.json?checksum=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const _previewSavedSource = SavedVotingConfigSource(
  id: 'community',
  name: 'Community',
  sourceUrl: _previewSavedSourceUrl,
);

const _previewSourceState = VotingConfigSourceState(
  sourceUrl: kDefaultStaticVotingConfigSource,
  isDefault: true,
  savedSources: [_previewSavedSource],
);

final _previewVotingRounds = [
  VotingRoundView(
    roundId: 'snack-governance-active',
    title: '[TEST] Very Serious Snack Governance 3',
    status: 'active',
    rawJson: {
      'description':
          'Welcome\n\nThis poll resolves outstanding NU7 scope questions '
          'following the early-2026 sentiment polling. Already in NU7, '
          'established by prior consensus.',
      'vote_end_time': wbVotingActiveEndTime,
      'forum_url': 'https://forum.zcashcommunity.com/t/snack-governance',
    },
  ),
  VotingRoundView(
    roundId: 'snack-governance-voted',
    title: '[TEST] Very Serious Snack Governance 3',
    status: 'active',
    voted: true,
    rawJson: {
      'description':
          'A silly sample round for testing the shielded vote builder without '
          'using real governance content.',
      'vote_end_time': wbVotingActiveEndTime,
      'forum_url': 'https://forum.zcashcommunity.com/t/snack-governance',
    },
  ),
  VotingRoundView(
    roundId: 'snack-governance-closed',
    title: '[TEST] Very Serious Snack Governance 3',
    status: 'closed',
    rawJson: {
      'description':
          'A silly sample round for testing the shielded vote builder without '
          'using real governance content.',
      'vote_end_time': '2026-08-24T12:00:00Z',
      'forum_url': 'https://forum.zcashcommunity.com/t/snack-governance',
    },
  ),
];

const _previewSnackProposal = VotingProposalView(
  id: 1,
  title: 'Official Snack of the Next Team Sync',
  description:
      'Which snack should be recognized as the official snack of the next '
      'team sync?',
  zipNumber: 'ZIP-2033 ZIP-2033',
  options: [
    VotingOptionView(
      index: 1,
      label: 'Option 1',
      description:
          'Which snack should be recognized as the official snack of the next '
          'team sync...',
    ),
    VotingOptionView(
      index: 2,
      label: 'Option 2',
      description:
          'Which snack should be recognized as the official snack of the next '
          'team sync...',
    ),
    VotingOptionView(
      index: 3,
      label: 'Option 3',
      description:
          'Which snack should be recognized as the official snack of the next '
          'team sync...',
    ),
  ],
);

const _previewSnackResultProposal = VotingProposalView(
  id: 1,
  title: 'Official Snack of the Next Team Sync',
  description:
      'Which snack should be recognized as the official snack of the next '
      'team sync?',
  zipNumber: 'ZIP-2033 ZIP-2033',
  forumUrl: 'https://forum.zcashcommunity.com/t/snack-governance',
  options: [
    VotingOptionView(
      index: 1,
      label: 'Option 1',
      description:
          'Which snack should be recognized as the official snack of the next '
          'team sync...',
    ),
    VotingOptionView(
      index: 2,
      label: 'Option 2',
      description:
          'Which snack should be recognized as the official snack of the next '
          'team sync...',
    ),
    VotingOptionView(
      index: 3,
      label: 'Option 3',
      description:
          'Which snack should be recognized as the official snack of the next '
          'team sync...',
    ),
  ],
);

Widget buildMobileVotingPreviouslyUsedListUseCase(BuildContext context) =>
    buildMobileVotingPollsEligibilityUseCase(context, previouslyUsed: true);
Widget buildMobileVotingPreviouslyUsedDetailUseCase(BuildContext context) =>
    votingActivePollFixture(context, eligible: false, previouslyUsed: true);

// --- Voting cards ----------------------------------------------------------

/// The frame the prop-driven voting cards are previewed in. Both cards branch
/// on `kAppFormFactor` themselves, so this only picks the surrounding chrome.
Widget _votingCardFrame({
  required WbLayout layout,
  required String title,
  required Widget child,
}) {
  final isolatedChild = VotingExternalUriLauncherScope(
    launcher: (_) async {},
    child: child,
  );
  if (layout == WbLayout.mobile) {
    return WbFrame(
      layout: WbLayout.mobile,
      child: MobileVotingScaffold(
        title: title,
        onBack: _previewNoop,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: isolatedChild,
        ),
      ),
    );
  }
  return WbFrame(
    layout: WbLayout.desktop,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: isolatedChild,
        ),
      ),
    ),
  );
}

/// Whether the tally has one top score, a shared one, or no votes at all.
enum VotingResultWinnerCase { single, tie, none }

/// Which row, if any, carries this account's own vote.
enum VotingResultVoteCase { winning, other, none }

/// The share the third option holds, down to the percentages that format
/// specially.
enum VotingResultShareCase { majority, small, tiny, zero }

/// Result card: `VotingResultCard` (desktop tally rows / mobile result rows).
Widget votingResultCardFixture({
  WbLayout layout = WbLayout.mobile,
  VotingResultWinnerCase winner = VotingResultWinnerCase.single,
  VotingResultVoteCase vote = VotingResultVoteCase.other,
  VotingResultShareCase share = VotingResultShareCase.small,
  bool avatar = true,
  bool metadata = true,
}) {
  final third = switch (share) {
    VotingResultShareCase.majority => 3200,
    VotingResultShareCase.small => 40,
    VotingResultShareCase.tiny => 2,
    VotingResultShareCase.zero => 0,
  };
  return _votingResultCardPreview(
    layout: layout,
    proposal: _votingResultCardProposal(metadata: metadata),
    tally: switch (winner) {
      VotingResultWinnerCase.single => {1: 7880, 2: 80, 3: third},
      VotingResultWinnerCase.tie => {1: 4000, 2: 4000, 3: third},
      VotingResultWinnerCase.none => const {1: 0, 2: 0, 3: 0},
    },
    selectedChoice: switch (vote) {
      VotingResultVoteCase.winning => 1,
      VotingResultVoteCase.other => 3,
      VotingResultVoteCase.none => null,
    },
    profilePictureId: avatar ? kDefaultProfilePictureId : null,
  );
}

Widget _votingResultCardPreview({
  WbLayout layout = WbLayout.mobile,
  required VotingProposalView proposal,
  required Map<int, num> tally,
  required int? selectedChoice,
  String? profilePictureId,
}) {
  return _votingCardFrame(
    layout: layout,
    title: 'Voting results',
    child: VotingResultCard(
      proposal: proposal,
      tally: tally,
      selectedChoice: selectedChoice,
      profilePictureId: profilePictureId,
    ),
  );
}

/// No ZIP wording in the title or description, so 'no metadata' really drops
/// the badge row instead of falling back to badges scanned from the text.
VotingProposalView _votingResultCardProposal({required bool metadata}) {
  return VotingProposalView(
    id: 1,
    title: 'Official snack of the next team sync',
    description:
        'Which snack should be recognized as the official snack of the next '
        'team sync?',
    zipNumber: metadata ? 'ZIP-2033 ZIP-2034' : '',
    forumUrl: metadata
        ? 'https://forum.zcashcommunity.com/t/snack-governance'
        : '',
    options: const [
      VotingOptionView(index: 1, label: 'Yes, adopt the proposal'),
      VotingOptionView(index: 2, label: 'No, keep the current plan'),
      VotingOptionView(index: 3, label: 'Abstain'),
    ],
  );
}

/// Whether the card takes answers, shows a submitted one, or is out of reach.
enum VotingProposalCardModeCase { interactive, readOnly, disabled }

/// Which choice the card carries; the missing one has no matching option.
enum VotingProposalCardChoiceCase { none, firstOption, missingOption }

/// The choice tone of the first option, from `votingChoiceTone`.
enum VotingProposalCardToneCase { yes, no, multipleChoice, skipped }

/// Whether the title is plain or collapses to one expandable line.
enum VotingProposalCardTitleCase { plain, collapsible }

/// What the metadata row above the title carries.
enum VotingProposalCardMetadataCase { none, oneBadge, badgesAndForum }

/// Proposal card: `VotingProposalCard` (desktop option rows / mobile options).
Widget votingProposalCardFixture({
  WbLayout layout = WbLayout.mobile,
  VotingProposalCardModeCase mode = VotingProposalCardModeCase.interactive,
  VotingProposalCardChoiceCase choice = VotingProposalCardChoiceCase.none,
  VotingProposalCardToneCase tone = VotingProposalCardToneCase.multipleChoice,
  VotingProposalCardTitleCase title = VotingProposalCardTitleCase.plain,
  VotingProposalCardMetadataCase metadata =
      VotingProposalCardMetadataCase.badgesAndForum,
  bool skippedStatus = false,
}) {
  return _votingProposalCardPreview(
    layout: layout,
    proposal: _votingProposalCardProposal(tone: tone, metadata: metadata),
    // 7 matches no option, which is what synthesizes the 'Choice 7' row.
    selectedChoice: switch (choice) {
      VotingProposalCardChoiceCase.none => null,
      VotingProposalCardChoiceCase.firstOption => 1,
      VotingProposalCardChoiceCase.missingOption => 7,
    },
    enabled: mode != VotingProposalCardModeCase.disabled,
    readOnly: mode == VotingProposalCardModeCase.readOnly,
    statusLabel: skippedStatus ? 'Skipped' : null,
    titleCollapsedMaxLines: title == VotingProposalCardTitleCase.collapsible
        ? 1
        : null,
    fallbackForumUri: metadata == VotingProposalCardMetadataCase.badgesAndForum
        ? Uri.parse('https://forum.zcashcommunity.com/t/snack-governance')
        : null,
    onDisabledOptionTap: mode == VotingProposalCardModeCase.disabled
        ? _previewNoop
        : null,
  );
}

Widget _votingProposalCardPreview({
  WbLayout layout = WbLayout.mobile,
  required VotingProposalView proposal,
  int? selectedChoice,
  bool enabled = true,
  bool readOnly = false,
  String? statusLabel,
  int? titleCollapsedMaxLines,
  Uri? fallbackForumUri,
  VoidCallback? onDisabledOptionTap,
}) {
  return _votingCardFrame(
    layout: layout,
    title: 'Coinholder voting',
    child: VotingProposalCard(
      proposal: proposal,
      selectedChoice: selectedChoice,
      enabled: enabled,
      readOnly: readOnly,
      statusLabel: statusLabel,
      titleCollapsedMaxLines: titleCollapsedMaxLines,
      fallbackForumUri: fallbackForumUri,
      onDisabledOptionTap: onDisabledOptionTap,
    ),
  );
}

VotingProposalView _votingProposalCardProposal({
  required VotingProposalCardToneCase tone,
  required VotingProposalCardMetadataCase metadata,
}) {
  return VotingProposalView(
    id: 1,
    title:
        'Should the next team sync recognize an official snack, and if so '
        'which one?',
    description:
        'Which snack should be recognized as the official snack of the next '
        'team sync?',
    zipNumber: switch (metadata) {
      VotingProposalCardMetadataCase.none => '',
      VotingProposalCardMetadataCase.oneBadge => 'ZIP-233',
      VotingProposalCardMetadataCase.badgesAndForum => 'ZIP-233 ZIP-234',
    },
    options: [
      VotingOptionView(
        index: 1,
        label: switch (tone) {
          VotingProposalCardToneCase.yes => 'Yes, adopt the proposal',
          VotingProposalCardToneCase.no => 'No, keep the current plan',
          VotingProposalCardToneCase.multipleChoice => 'Option 1',
          VotingProposalCardToneCase.skipped => 'Skipped',
        },
        description: 'The option this poll recommends.',
      ),
      const VotingOptionView(
        index: 2,
        label: 'Option 2',
        description: 'A second option with its own description.',
      ),
      // No description: the single-line option row on mobile.
      const VotingOptionView(index: 3, label: 'Abstain'),
    ],
  );
}

/// Ineligible dialog: `VotingIneligibleDialog` on a plain frame, never over a
/// live poll.
Widget votingIneligibleDialogFixture({
  WbLayout layout = WbLayout.mobile,
  bool guidance = true,
}) {
  const reason =
      'Voting requires at least one eligible shielded note bundle '
      'with 0.125 ZEC at snapshot block 3,459,350.';
  return WbFrame(
    layout: layout,
    child: Builder(
      builder: (context) => Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: context.colors.background.neutralScrim),
          VotingIneligibleDialog(
            message: guidance
                ? '$reason Switch to an eligible account to vote.'
                : reason,
          ),
        ],
      ),
    ),
  );
}

/// How many of the round's questions the voter left unanswered.
enum VotingSkippedQuestionsCase { one, some, all }

/// Skipped-questions dialog: `SkippedQuestionsDialog` on a plain frame, never
/// over a live question list.
Widget votingSkippedQuestionsDialogFixture({
  WbLayout layout = WbLayout.mobile,
  VotingSkippedQuestionsCase skipped = VotingSkippedQuestionsCase.some,
}) {
  const total = 12;
  final skippedCount = switch (skipped) {
    VotingSkippedQuestionsCase.one => 1,
    VotingSkippedQuestionsCase.some => 4,
    VotingSkippedQuestionsCase.all => total,
  };
  return WbFrame(
    layout: layout,
    child: Builder(
      builder: (context) => Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: context.colors.background.neutralScrim),
          SkippedQuestionsDialog(skippedCount: skippedCount, totalCount: total),
        ],
      ),
    ),
  );
}

/// Skip-signed-bundles dialog: `SkipSignedBundlesDialog` on a plain frame. The
/// dialog takes no props, so the frame width is its only axis.
Widget votingSkipSignedBundlesDialogFixture({
  WbLayout layout = WbLayout.mobile,
}) {
  return WbFrame(
    layout: layout,
    child: Builder(
      builder: (context) => Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: context.colors.background.neutralScrim),
          const SkipSignedBundlesDialog(),
        ],
      ),
    ),
  );
}
