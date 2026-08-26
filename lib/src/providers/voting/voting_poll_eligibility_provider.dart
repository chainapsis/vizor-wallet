import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../rust/api/voting.dart' as rust_api;
import '../../services/voting/resolved_voting_config_extensions.dart';
import '../app_security_provider.dart';
import '../sync_provider.dart';
import 'voting_config_provider.dart';
import 'voting_rounds_provider.dart';
import 'voting_service_providers.dart';
import 'voting_state.dart';

enum VotingPollEligibility { unknown, eligible, ineligible }

/// Recheck after sync or lock transitions, not every UI progress tick.
final votingPollEligibilityWalletRevisionProvider = Provider((ref) {
  final locked = ref.watch(
    appSecurityProvider.select((state) => state.requiresUnlock),
  );
  final sync = ref.watch(
    syncProvider.select(
      (state) => (state.value?.isSyncing, state.value?.lastSyncCompletedAt),
    ),
  );
  return (locked: locked, sync: sync);
});

final _eligibilityQueueProvider = Provider((ref) => _EligibilityQueue());

/// A lightweight, account-scoped list preview. Never creates a voting session,
/// bundles, or proofs. Unknown/loading/errors must not be shown as ineligible.
final votingPollEligibilityProvider = FutureProvider.autoDispose
    .family<VotingPollEligibility, String>((ref, roundId) async {
      final revision = ref.watch(votingPollEligibilityWalletRevisionProvider);
      final roundsFuture = ref.watch(votingRoundsProvider.future);
      final accountLookup = ref.watch(votingActiveAccountUuidProvider);
      final configFuture = ref.watch(votingConfigProvider.future);
      final endpoint = ref.watch(votingRpcEndpointConfigProvider);
      final dbLookup = ref.watch(votingWalletDbPathProvider);
      final rust = ref.watch(votingRustApiProvider);
      final readiness = ref.watch(votingWalletSyncReadinessCheckerProvider);
      final queue = ref.watch(_eligibilityQueueProvider);
      if (revision.locked) return VotingPollEligibility.unknown;

      await roundsFuture;
      if (!ref.mounted) return VotingPollEligibility.unknown;
      final config = await configFuture;
      if (!ref.mounted) return VotingPollEligibility.unknown;
      config.assertRoundAuthenticated(roundId);
      final api = ref.watch(votingApiClientProvider(config.apiServers));
      final accountUuid = await accountLookup();
      if (accountUuid == null || !ref.mounted) {
        return VotingPollEligibility.unknown;
      }

      // Serialize visible-row checks so scrolling cannot fan out wallet DB work.
      return queue.run(() async {
        if (!ref.mounted) return VotingPollEligibility.unknown;
        final round = VotingRoundDetails.fromStatus(
          await api.getRoundStatus(roundId),
        );
        if (!ref.mounted) return VotingPollEligibility.unknown;
        final params = await rust.trustedVotingRoundParamsFromConfig(
          config: config,
          roundId: round.roundId,
          snapshotHeight: BigInt.from(round.snapshotHeight),
          ncRoot: round.ncRoot,
          nullifierImtRoot: round.nullifierImtRoot,
        );
        if (!ref.mounted) return VotingPollEligibility.unknown;
        final dbPath = await dbLookup();
        if (!ref.mounted) return VotingPollEligibility.unknown;
        final scan = await readiness.check(
          dbPath: dbPath,
          network: endpoint.networkName,
          snapshotHeight: round.snapshotHeight,
        );
        if (!scan.isReady || !ref.mounted) {
          return VotingPollEligibility.unknown;
        }
        final result = await rust.checkVotingEligibility(
          ctx: rust_api.ApiVotingRoundContext(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: endpoint.networkName,
            roundParams: params,
            roundName: round.title,
            sessionJson: round.sessionJson,
            accountUuid: accountUuid,
            maxRealNotesPerBundle: null,
            pirLayout: config.pirLayout,
          ),
        );
        if (!ref.mounted) return VotingPollEligibility.unknown;
        return result.isEligible
            ? VotingPollEligibility.eligible
            : VotingPollEligibility.ineligible;
      });
    });

class _EligibilityQueue {
  Future<void> _tail = Future.value();

  Future<VotingPollEligibility> run(
    Future<VotingPollEligibility> Function() check,
  ) {
    final result = _tail.then((_) => check());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
