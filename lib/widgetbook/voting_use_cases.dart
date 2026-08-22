// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/features/voting/screens/mobile/mobile_voting_screens.dart';
import '../src/providers/voting/voting_config_provider.dart';
import '../src/providers/voting/voting_rounds_provider.dart';
import '../src/providers/voting/voting_state.dart';
import '../src/rust/third_party/zcash_voting/config.dart';

Widget buildMobileVotingPollsUseCase(BuildContext context) {
  return ProviderScope(
    overrides: [
      votingConfigProvider.overrideWith(_PreviewVotingConfigNotifier.new),
      votingRoundsProvider.overrideWith(_PreviewVotingRoundsNotifier.new),
    ],
    child: const MobileVotingPollsScreen(),
  );
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
    state = const AsyncData(_previewVotingRounds);
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

const _previewVotingRounds = [
  VotingRoundView(
    roundId: 'community-grants-2026',
    title: 'Community Grants Renewal',
    status: 'active',
    rawJson: {
      'description':
          'Choose how the next community grants pool should support Zcash '
          'builders and public goods.',
      'end_time': '2026-09-02T12:00:00Z',
    },
  ),
  VotingRoundView(
    roundId: 'network-priorities-2026',
    title: 'Network Priorities',
    status: 'closed',
    voted: true,
    rawJson: {
      'description':
          'Rank the ecosystem priorities that should guide the next funding '
          'cycle.',
      'end_time': '2026-08-14T12:00:00Z',
    },
  ),
];
