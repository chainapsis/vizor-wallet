import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_poll_ordering.dart';
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/resolved_voting_config_extensions.dart';
import 'voting_config_provider.dart';
import 'voting_service_providers.dart';
import 'voting_state.dart';

/// Upper bound for waiting on wallet scan readiness before giving up on one
/// background warm-up pass. The pass is retried on the next screen entry.
final votingPirWarmupSyncMaxWaitProvider = Provider<Duration>((ref) {
  return ref.watch(votingWalletSyncMaxWaitProvider);
});

/// Minimum time between successful warm-up passes for the same account.
///
/// Entering the polls list and immediately opening a round would otherwise
/// fire a second list/status/PIR-resolve burst. Failed or skipped passes are
/// not gated by this interval so the next screen entry can retry immediately.
final votingPirWarmupMinIntervalProvider = Provider<Duration>((ref) {
  return const Duration(minutes: 1);
});

/// App-scoped background PIR proof cache warm-up.
///
/// The voting session provider is round-scoped and disposed on navigation, so
/// this coordinator owns the warm-up lifecycle instead: entering the polls or
/// round-detail screen triggers one pass over the active rounds. Concurrent
/// triggers share one in-flight pass, a successful pass is not re-listed for
/// the same account within [votingPirWarmupMinIntervalProvider], and in-flight
/// work per `(dbPath, account, snapshotHeight)` is deduplicated across
/// triggers.
final votingPirWarmupProvider = Provider<VotingPirWarmupCoordinator>((ref) {
  return VotingPirWarmupCoordinator(ref);
});

/// Warms the bundle-independent PIR nullifier-proof cache for active rounds.
///
/// For every authenticated round with active status, this resolves a PIR
/// endpoint serving exactly the round's snapshot height, waits for the wallet
/// to be scanned to that height, then fetches and caches the eligible notes'
/// IMT non-membership proofs in the voting sidecar. The delegation prove path
/// reads the same cache, so proofs warmed here are never refetched when the
/// user later delegates; only the per-bundle padded-slot nullifiers remain.
///
/// Deliberately unlike the session provider's round snapshot preparation, this
/// path reads no hotkey, mints nothing, and creates no round or bundle rows —
/// it is safe for accounts that are merely browsing and for Keystone accounts.
/// Every failure is a logged skip; the prove-path network fallback still
/// covers correctness.
class VotingPirWarmupCoordinator {
  VotingPirWarmupCoordinator(this._ref);

  final Ref _ref;

  /// In-flight warm-ups keyed by `dbPath|accountUuid|snapshotHeight`.
  final Map<String, Future<bool>> _inFlight = {};

  /// Snapshot heights already warmed this session, same key shape. A warmed
  /// snapshot is retried only after an app restart or account switch changes
  /// the key; failed passes are not recorded and retry on the next trigger.
  final Set<String> _completed = {};

  /// Whole-pass single-flight so polls and round-detail entry share one
  /// list/status/PIR-resolve burst instead of starting two in parallel.
  Future<void>? _passInFlight;

  DateTime? _lastSuccessfulPassAt;
  String? _lastSuccessfulPassAccountUuid;

  @visibleForTesting
  Map<String, Future<bool>> get inFlightForTesting => _inFlight;

  /// Runs one warm-up pass over the currently active rounds.
  ///
  /// Never throws: every failure path logs and returns. The returned future
  /// completes when the pass (including any newly started warm-ups) is done,
  /// which tests await; screens call this fire-and-forget.
  ///
  /// Concurrent callers join the in-flight pass. A second trigger for the
  /// same account within [votingPirWarmupMinIntervalProvider] is a no-op
  /// after a successful pass; a failed pass retries on the next trigger.
  Future<void> maybeWarmActiveRounds() {
    final inFlight = _passInFlight;
    if (inFlight != null) return inFlight;

    final pass = _startPass();
    _passInFlight = pass;
    return pass;
  }

  Future<void> _startPass() async {
    try {
      final accountUuid = await _ref
          .read(votingActiveAccountUuidProvider)
          .call();
      if (accountUuid == null) return;

      final minInterval = _ref.read(votingPirWarmupMinIntervalProvider);
      final lastSuccess = _lastSuccessfulPassAt;
      if (lastSuccess != null &&
          _lastSuccessfulPassAccountUuid == accountUuid &&
          DateTime.now().difference(lastSuccess) < minInterval) {
        debugPrint(
          '[zcash] Voting: PIR cache warmup skipped reason=min-interval',
        );
        return;
      }

      if (await _warmActiveRounds()) {
        _lastSuccessfulPassAt = DateTime.now();
        _lastSuccessfulPassAccountUuid = accountUuid;
      }
    } catch (error) {
      debugPrint('[zcash] Voting: PIR cache warmup pass failed: $error');
    } finally {
      _passInFlight = null;
    }
  }

  Future<bool> _warmActiveRounds() async {
    final accountUuid = await _ref.read(votingActiveAccountUuidProvider).call();
    if (accountUuid == null) return false;
    final dbPath = await _ref.read(votingWalletDbPathProvider).call();

    final config = await _ref.read(votingConfigProvider.future);
    final api = _ref.read(votingApiClientProvider(config.apiServers));
    final authenticatedRoundIds = config.authenticatedRounds
        .map((round) => round.roundId)
        .toSet();

    final rounds = await api.listRounds();
    final activeRounds = <VotingRoundDetails>[];
    var statusFailed = false;
    for (final round in rounds) {
      if (!authenticatedRoundIds.contains(round.roundId)) continue;
      if (votingPollListStatus(round.status) != VotingPollListStatus.active) {
        continue;
      }
      try {
        final status = await api.getRoundStatus(round.roundId);
        activeRounds.add(VotingRoundDetails.fromStatus(status));
      } catch (error) {
        statusFailed = true;
        debugPrint(
          '[zcash] Voting: PIR cache warmup skipped round=${round.roundId} '
          'reason=round-status-failed error=$error',
        );
      }
    }
    if (activeRounds.isEmpty) return !statusFailed;

    // Every active round's expected root survives pruning, no matter which
    // snapshot this pass ends up warming.
    final keepRoots = [
      for (final round in activeRounds)
        Uint8List.fromList(round.nullifierImtRoot),
    ];

    final warmups = <Future<bool>>[];
    final seenHeights = <int>{};
    for (final round in activeRounds) {
      if (!seenHeights.add(round.snapshotHeight)) continue;
      final key = '$dbPath|$accountUuid|${round.snapshotHeight}';
      if (_completed.contains(key)) continue;
      final warmup = _inFlight[key] ??= _warmSnapshot(
        key: key,
        dbPath: dbPath,
        accountUuid: accountUuid,
        round: round,
        keepRoots: keepRoots,
      );
      warmups.add(warmup);
    }
    final results = await Future.wait(warmups);
    return !statusFailed && results.every((succeeded) => succeeded);
  }

  Future<bool> _warmSnapshot({
    required String key,
    required String dbPath,
    required String accountUuid,
    required VotingRoundDetails round,
    required List<Uint8List> keepRoots,
  }) async {
    final timer = Stopwatch()..start();
    try {
      final config = await _ref.read(votingConfigProvider.future);
      final endpoint = _ref.read(votingRpcEndpointConfigProvider);

      final Uri pirEndpoint;
      try {
        final resolution = await _ref
            .read(votingPirResolverProvider)
            .resolve(
              endpoints: config.pirEndpointUrls,
              expectedSnapshotHeight: round.snapshotHeight,
            );
        pirEndpoint = resolution.endpoint;
      } on PirSnapshotNoMatchingEndpoint {
        // The PIR fleet is not serving this snapshot (yet); quiet skip, the
        // next screen entry retries.
        debugPrint(
          '[zcash] Voting: PIR cache warmup skipped '
          'round=${round.roundId} snapshot=${round.snapshotHeight} '
          'reason=pir-height-mismatch',
        );
        return false;
      }

      final ready = await _waitForWalletScannedToSnapshot(
        dbPath: dbPath,
        network: endpoint.networkName,
        snapshotHeight: round.snapshotHeight,
      );
      if (!ready) {
        debugPrint(
          '[zcash] Voting: PIR cache warmup skipped '
          'round=${round.roundId} snapshot=${round.snapshotHeight} '
          'reason=wallet-sync-timeout',
        );
        return false;
      }

      // The account may have switched while waiting; warming the old
      // account's sidecar would be wasted (though harmless) work.
      final activeNow = await _ref.read(votingActiveAccountUuidProvider).call();
      if (activeNow != accountUuid) {
        debugPrint(
          '[zcash] Voting: PIR cache warmup skipped '
          'round=${round.roundId} reason=account-switched',
        );
        return false;
      }

      final result = await _ref
          .read(votingRustApiProvider)
          .warmPirProofCache(
            dbPath: dbPath,
            accountUuid: accountUuid,
            network: endpoint.networkName,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            snapshotHeight: BigInt.from(round.snapshotHeight),
            pirServerUrl: _ref
                .read(votingEndpointMapperProvider)
                .map(pirEndpoint)
                .toString(),
            pirLayout: config.pirLayout,
            keepRoots: keepRoots,
          );
      final rootMatches = listEquals(
        result.servedRoot,
        Uint8List.fromList(round.nullifierImtRoot),
      );
      debugPrint(
        '[zcash] Voting: PIR cache warmup completed '
        'round=${round.roundId} snapshot=${round.snapshotHeight} '
        'notes=${result.noteCount} cached=${result.cachedCount} '
        'fetched=${result.fetchedCount} pruned=${result.prunedCount} '
        'rootMatchesRound=$rootMatches '
        'elapsed=${timer.elapsed.inMilliseconds}ms',
      );
      if (!rootMatches) {
        // Height matched but the served IMT root is not the round's expected
        // root; the cached proofs are still keyed by their own root, so the
        // prove path simply won't find them (stale-root, not corruption).
        debugPrint(
          '[zcash] Voting: PIR cache warmup served root does not match '
          'round=${round.roundId} nullifier_imt_root; proofs cached under '
          'the served root only',
        );
        return false;
      }
      _completed.add(key);
      return true;
    } catch (error) {
      debugPrint(
        '[zcash] Voting: PIR cache warmup failed '
        'round=${round.roundId} snapshot=${round.snapshotHeight} '
        'elapsed=${timer.elapsed.inMilliseconds}ms error=$error '
        'reason=cache-miss',
      );
      return false;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<bool> _waitForWalletScannedToSnapshot({
    required String dbPath,
    required String network,
    required int snapshotHeight,
  }) async {
    final checker = _ref.read(votingWalletSyncReadinessCheckerProvider);
    final pollInterval = _ref.read(votingWalletSyncPollIntervalProvider);
    final maxWait = _ref.read(votingPirWarmupSyncMaxWaitProvider);
    final deadline = Stopwatch()..start();
    while (true) {
      final readiness = await checker.check(
        dbPath: dbPath,
        network: network,
        snapshotHeight: snapshotHeight,
      );
      if (readiness.isReady) return true;
      if (deadline.elapsed >= maxWait) return false;
      await Future<void>.delayed(pollInterval);
    }
  }
}
