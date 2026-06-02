import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatting/duration_format.dart';
import '../../services/voting/resolved_voting_config_extensions.dart';
import 'voting_debug_print.dart';
import 'voting_config_provider.dart';
import 'voting_service_providers.dart';

final votingTreePreSyncProvider = Provider<VotingTreePreSyncService>((ref) {
  return VotingTreePreSyncService(ref);
});

const _activeVotingRoundStatus = '1';

bool shouldPreSyncVotingTree(String status) {
  return status.trim() == _activeVotingRoundStatus;
}

class VotingTreePreSyncService {
  VotingTreePreSyncService(this._ref);

  final Ref _ref;
  final Map<String, Future<void>> _inFlight = {};
  final Set<String> _completed = {};

  Future<void> preSyncRounds(Iterable<String> roundIds) {
    return Future.wait(roundIds.toSet().map(preSyncRound)).then((_) {});
  }

  Future<void> preSyncRound(String roundId) {
    if (roundId.isEmpty) return Future<void>.value();
    return _preSyncRound(roundId);
  }

  Future<void> _preSyncRound(String roundId) async {
    try {
      final config = await _ref.read(votingConfigProvider.future);
      final accountUuid = await _ref
          .read(votingActiveAccountUuidProvider)
          .call();
      if (accountUuid == null) {
        debugPrint(
          '[zcash] Voting: vote tree pre-sync skipped round=$roundId '
          'reason=no-active-account',
        );
        return;
      }
      final dbPath = await _ref.read(votingWalletDbPathProvider).call();
      final primaryApiServer = config.apiServers.primary;
      final key = '$dbPath|$accountUuid|$primaryApiServer|$roundId';
      if (_completed.contains(key)) return;
      final existing = _inFlight[key];
      if (existing != null) {
        await existing;
        return;
      }

      final future = _runPreSync(
        key: key,
        dbPath: dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
        nodeUrl: primaryApiServer.toString(),
      );
      _inFlight[key] = future;
      await future;
    } catch (e) {
      debugPrint(
        '[zcash] Voting: vote tree pre-sync setup failed '
        'round=$roundId error=$e',
      );
    }
  }

  Future<void> _runPreSync({
    required String key,
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required String nodeUrl,
  }) async {
    final timer = Stopwatch()..start();
    debugPrint('[zcash] Voting: vote tree pre-sync start round=$roundId');
    try {
      final height = await _ref
          .read(votingRustApiProvider)
          .syncVoteTree(
            dbPath: dbPath,
            accountUuid: accountUuid,
            roundId: roundId,
            nodeUrl: nodeUrl,
          );
      _completed.add(key);
      debugPrint(
        '[zcash] Voting: vote tree pre-sync completed '
        'round=$roundId height=$height elapsed=${formatElapsedSeconds(timer.elapsed)}',
      );
    } catch (e) {
      debugPrint(
        '[zcash] Voting: vote tree pre-sync failed '
        'round=$roundId elapsed=${formatElapsedSeconds(timer.elapsed)} error=$e',
      );
    } finally {
      _inFlight.remove(key);
    }
  }
}
