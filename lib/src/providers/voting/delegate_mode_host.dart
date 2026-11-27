import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/proxy/composite_delegate_mode_repository.dart';
import '../../features/voting/proxy/proxy_delegation_providers.dart';
import '../../features/voting/proxy/proxy_delegation_repository.dart';
import '../../features/voting/proxy/proxy_registry_client.dart';
import '../../features/voting/proxy/proxy_registry_providers.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_poll_ordering.dart';
import '../../rust/api/proxy_delegation.dart' as rust_proofs;
import '../../services/voting/resolved_voting_config_extensions.dart';
import '../../services/voting/voting_api_client.dart';
import '../../services/voting/voting_models.dart';
import 'voting_config_provider.dart';
import 'voting_round_visibility_provider.dart';
import 'voting_service_providers.dart';
import 'voting_share_tracking_registry_provider.dart';
import 'voting_state.dart';

/// [DelegateModeHost] over the app: the voting config's vote servers and
/// authenticated rounds, and the registry client's proofs and list.
/// Delegate mode is app-level, so nothing here reads an account.
class AppDelegateModeHost implements DelegateModeHost {
  /// Creates the host.
  AppDelegateModeHost(this._ref);

  final Ref _ref;

  /// The registry client, read per call so a network change takes effect.
  ProxyRegistryClient get _registry => _ref.read(proxyRegistryClientProvider);

  @override
  String get network => _ref.read(proxyRegistryNetworkProvider);

  @override
  Future<String> dbPath() => _ref.read(votingWalletDbPathProvider)();

  @override
  Future<VotingApiClient> voteServers() async {
    final config = await _ref.read(votingConfigProvider.future);
    return _ref.read(votingApiClientProvider(config.apiServers));
  }

  /// The authenticated rounds the vote server reports as proxy rounds,
  /// their title, questions and vote end read as the vote flow reads them,
  /// the round ending last first. Test rounds stay hidden as in the round
  /// list.
  @override
  Future<DelegateModeRounds> rounds() async {
    final config = await _ref.read(votingConfigProvider.future);
    final api = _ref.read(votingApiClientProvider(config.apiServers));
    final showTestRounds = await _ref.read(showTestVotingRoundsProvider.future);
    final rounds = <DelegateModeRound>[];
    var complete = true;
    for (final authenticated in config.authenticatedRounds) {
      final VotingRoundStatus status;
      try {
        status = await api.getRoundStatus(authenticated.roundId);
      } catch (error) {
        debugPrint(
          '[zcash] Delegate mode: round ${authenticated.roundId} '
          'unavailable: ${error.runtimeType}',
        );
        complete = false;
        continue;
      }
      if (!proxyRoundEnabled(status.rawJson)) continue;
      final details = VotingRoundDetails.fromStatus(status);
      final voteEnd = details.voteEndTime;
      if (voteEnd == null) continue;
      if (!showTestRounds && isHiddenTestVotingRoundTitle(details.title)) {
        continue;
      }
      rounds.add(
        DelegateModeRound(
          roundId: authenticated.roundId,
          title: details.title,
          proposals: proposalsFromRound(details),
          voteEnd: voteEnd,
          active:
              votingPollListStatus(details.status) ==
              VotingPollListStatus.active,
        ),
      );
    }
    rounds.sort((a, b) => b.voteEnd.compareTo(a.voteEnd));
    return (rounds: rounds, complete: complete);
  }

  @override
  List<String> verifierApiUrls() => _registry.verifierApiUrls();

  @override
  Future<List<rust_proofs.ApiProvenRegistryEntry>> proveEntries(
    List<int> delegateIndices,
  ) => _registry.proveEntries(delegateIndices);

  @override
  Future<Uint8List?> storeValue(String keyHex) => _registry.storeValue(keyHex);

  @override
  Future<ProxyDelegatePicture?> listPicture(int delegateIndex) =>
      _registry.listPicture(delegateIndex);

  @override
  VoidCallback? beginWork() =>
      _ref.read(votingShareTrackingRegistryProvider).beginBackgroundWork();
}
