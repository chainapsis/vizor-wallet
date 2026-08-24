// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/core/layout/mobile/app_mobile_sheet.dart';
import '../src/core/profile_pictures.dart';
import '../src/features/voting/screens/mobile/mobile_keystone_voting_signing_screen.dart';
import '../src/features/voting/screens/mobile/mobile_voting_submitted_screen.dart';
import '../src/features/voting/screens/mobile/mobile_voting_submission_progress_screen.dart';
import '../src/features/voting/screens/mobile/mobile_voting_screens.dart';
import '../src/features/voting/screens/voting_proposal_detail_screen.dart';
import '../src/features/voting/screens/voting_results_screen.dart';
import '../src/features/voting/screens/voting_status_screen.dart';
import '../src/features/voting/voting_flow_models.dart';
import '../src/features/voting/widgets/voting_metadata_widgets.dart';
import '../src/features/voting/widgets/mobile/mobile_voting_config_settings_sheet.dart';
import '../src/providers/voting/voting_config_provider.dart';
import '../src/providers/voting/voting_config_source_provider.dart';
import '../src/providers/voting/voting_round_visibility_provider.dart';
import '../src/providers/voting/voting_rounds_provider.dart';
import '../src/providers/voting/voting_state.dart';
import '../src/providers/voting/voting_submission_job_provider.dart';
import '../src/rust/third_party/zcash_voting/config.dart';
import '../src/services/qr_scanner.dart';
import '../src/services/voting/voting_config_loader.dart';

Widget buildMobileVotingPollsUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [
      votingConfigProvider.overrideWith(_PreviewVotingConfigNotifier.new),
      votingRoundsProvider.overrideWith(_PreviewVotingRoundsNotifier.new),
      votingConfigSourceProvider.overrideWith(
        _PreviewVotingConfigSourceNotifier.new,
      ),
      showTestVotingRoundsProvider.overrideWith(
        _PreviewShowTestVotingRoundsNotifier.new,
      ),
    ],
    child: const MobileVotingPollsScreen(),
  );
}

Widget buildMobileVotingConfigUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [
      votingConfigProvider.overrideWith(_PreviewVotingConfigNotifier.new),
      votingRoundsProvider.overrideWith(_PreviewVotingRoundsNotifier.new),
      votingConfigSourceProvider.overrideWith(
        _PreviewVotingConfigSourceNotifier.new,
      ),
      showTestVotingRoundsProvider.overrideWith(
        _PreviewShowTestVotingRoundsNotifier.new,
      ),
    ],
    child: const MobileModalOverlay(
      background: MobileVotingPollsScreen(),
      child: MobileVotingConfigSettingsSheet(),
    ),
  );
}

Widget buildMobileVotingVotedUseCase(BuildContext context) {
  return MobileVotingScaffold(
    title: 'Voted',
    child: VotingVotedPollContent(
      showDesktopToolbar: false,
      roundTitle: '[TEST] Very Serious Snack Governance 3',
      snapshotHeight: 3543600,
      description:
          'A silly sample round for testing the shielded vote builder without '
          'using real governance content.',
      forumUri: null,
      votingPowerZatoshi: BigInt.from(37500000),
      votingPowerPreparing: false,
      votedAt: DateTime(2026, 8, 24),
      proposals: const [_previewSnackProposal],
      choicesByProposalId: const {1: 1},
    ),
  );
}

Widget buildMobileVotingProposalDefaultUseCase(BuildContext context) {
  return const MobileVotingScaffold(
    title: 'Coinholder voting',
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: VotingProposalCard(proposal: _previewSnackProposal),
    ),
  );
}

Widget buildMobileVotingProposalSelectedUseCase(BuildContext context) {
  return const MobileVotingScaffold(
    title: 'Coinholder voting',
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: VotingProposalCard(
        proposal: _previewSnackProposal,
        selectedChoice: 1,
      ),
    ),
  );
}

Widget buildMobileVotingResultsUseCase(BuildContext context) {
  return const MobileVotingScaffold(
    title: 'Voting results',
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: VotingResultCard(
        proposal: _previewSnackProposal,
        tally: {1: 2640.96, 2: 1040.96, 3: 240.96},
        selectedChoice: 2,
        profilePictureId: kDefaultProfilePictureId,
      ),
    ),
  );
}

Widget buildMobileVotingSubmissionDelegatingUseCase(BuildContext context) {
  return _mobileVotingFullPagePreview(
    context,
    const MobileVotingSubmissionProgressScreen(
      activeStep: VotingSubmissionProgressStep.delegating,
      activeStepProgress: 0.25,
    ),
  );
}

Widget buildMobileVotingSubmissionCastingUseCase(BuildContext context) {
  return _mobileVotingFullPagePreview(
    context,
    const MobileVotingSubmissionProgressScreen(
      activeStep: VotingSubmissionProgressStep.castingVotes,
      activeStepProgress: 0.6,
    ),
  );
}

Widget buildMobileVotingSubmissionFinalizingUseCase(BuildContext context) {
  return _mobileVotingFullPagePreview(
    context,
    const MobileVotingSubmissionProgressScreen(
      activeStep: VotingSubmissionProgressStep.finalizing,
    ),
  );
}

Widget buildMobileVotingSubmittedUseCase(BuildContext context) {
  return _mobileVotingFullPagePreview(
    context,
    MobileVotingSubmittedScreen(onDone: _previewNoop),
  );
}

Widget _mobileVotingFullPagePreview(BuildContext context, Widget child) {
  final mediaQuery = MediaQuery.of(context);
  const safeArea = EdgeInsets.only(top: 55);
  return SizedBox(
    width: 393,
    height: 852,
    child: MediaQuery(
      data: mediaQuery.copyWith(
        size: const Size(393, 852),
        padding: safeArea,
        viewPadding: safeArea,
      ),
      child: child,
    ),
  );
}

Widget buildMobileVotingKeystoneRequestUseCase(BuildContext context) {
  return ProviderScope(
    child: MobileKeystoneVotingSigningScreen(
      presentation: _previewKeystonePresentation,
      scannerBuilder: _previewVotingScanner,
      forceScannerActiveForTesting: true,
    ),
  );
}

Widget buildMobileVotingKeystoneScannerUseCase(BuildContext context) {
  return ProviderScope(
    child: MobileKeystoneVotingSigningScreen(
      presentation: _previewKeystonePresentation,
      scannerBuilder: _previewVotingScanner,
      forceScannerActiveForTesting: true,
      startInScannerForTesting: true,
    ),
  );
}

Widget _previewVotingScanner(
  BuildContext context,
  ValueChanged<ScanResult> onComplete,
  ValueChanged<int> onProgress,
  Object? resetToken,
) {
  return const ColoredBox(color: Color(0xFF111515));
}

final _previewKeystonePresentation = VotingKeystoneStatusPresentation(
  bundleIndex: 0,
  urParts: const [_previewVotingKeystoneUr],
  batchMemos: const [
    VotingKeystoneBatchMemo(
      bundleIndex: 0,
      bundleCount: 3,
      displayMemo: 'Amount: 1.25 ZEC\nProposal: Community grants',
    ),
    VotingKeystoneBatchMemo(
      bundleIndex: 1,
      bundleCount: 3,
      displayMemo: 'Amount: 0.75 ZEC\nProposal: Network priorities',
    ),
  ],
  batchMessageCount: 2,
  batchTotalCount: 3,
  canSkipRemainingBundles: true,
  onSigned: _previewSignedVotingResponse,
  onSkipRemainingBundles: _previewNoop,
);

Future<void> _previewSignedVotingResponse(List<int> _) async {}
void _previewNoop() {}

const _previewVotingKeystoneUr =
    'ur:zcash-sign-batch/1-1/lpadaxcsfwdmfwfwhdcxhdcxfwcxhdcxhdcxfwcx';

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
    state = const AsyncData(_previewVotingRounds);
  }
}

class _PreviewVotingConfigSourceNotifier extends VotingConfigSourceNotifier {
  @override
  Future<VotingConfigSourceState> build() async => _previewSourceState;

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
  @override
  Future<bool> build() async => false;

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

const _previewSourceState = VotingConfigSourceState(
  sourceUrl: kDefaultStaticVotingConfigSource,
  isDefault: true,
  savedSources: [
    SavedVotingConfigSource(
      id: 'community',
      name: 'Community',
      sourceUrl:
          'https://vote.example.org/static.json?checksum=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    ),
  ],
);

const _previewVotingRounds = [
  VotingRoundView(
    roundId: 'snack-governance-active',
    title: '[TEST] Very Serious Snack Governance 3',
    status: 'active',
    rawJson: {
      'description':
          'Welcome\n\nThis poll resolves outstanding NU7 scope questions '
          'following the early-2026 sentiment polling. Already in NU7, '
          'established by prior consensus.',
      'vote_end_time': '2026-08-24T12:00:00Z',
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
      'vote_end_time': '2026-08-24T12:00:00Z',
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
