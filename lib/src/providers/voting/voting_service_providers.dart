import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_recovery_service.dart';
import '../../core/config/rpc_endpoint_config.dart';
import '../../core/storage/app_secure_store.dart';
import '../../core/storage/wallet_paths.dart';
import '../../providers/account_provider.dart';
import '../../providers/rpc_endpoint_provider.dart';
import '../../providers/sync_provider.dart';
import '../../rust/api/sync.dart' as rust_sync;
import '../../rust/api/voting.dart' as rust_api;
import '../../rust/api/voting_session.dart' as rust_session;
import '../../rust/third_party/zcash_voting/config.dart' as rust_config;
import '../../rust/third_party/zcash_voting/delegate.dart' as rust_delegate;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_voting;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/voting_rust_exception.dart';
import '../../services/voting/resolved_voting_config_extensions.dart';
import '../../services/voting/voting_api_client.dart';
import '../../services/voting/voting_config_loader.dart';
import '../../services/voting/voting_endpoint_mapper.dart';
import '../../services/voting/voting_http.dart';
import '../../services/voting/voting_retry.dart';
import 'voting_config_source_provider.dart';

/// Transport shared by the voting service clients.
final votingEndpointMapperProvider = Provider<VotingEndpointMapper>((ref) {
  return VotingEndpointMapper.forBuild();
});

final votingHttpClientProvider = Provider<VotingHttpClient>((ref) {
  final directClient = DartIoVotingHttpClient();
  ref.onDispose(directClient.close);
  return MappedVotingHttpClient(
    directClient,
    ref.watch(votingEndpointMapperProvider),
  );
});

/// Loads the hash-pinned static config and dynamic voting config.
final votingConfigLoaderProvider = Provider<VotingConfigLoader>((ref) {
  final source = ref.watch(votingConfigSourceProvider).value;
  return VotingConfigLoader(
    httpClient: ref.watch(votingHttpClientProvider),
    sourceUrl: source?.sourceUrl,
    timeout: ref.watch(votingConfigLoaderTimeoutProvider),
  );
});

/// Static/dynamic config fetch timeout.
final votingConfigLoaderTimeoutProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 10);
});

/// Timeout for chain-facing vote server endpoints.
final votingApiRequestTimeoutProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 10);
});

/// First delay before re-arming share tracking after a run stopped on a
/// condition a later run could clear.
///
/// The SDK already retries inside a run, so reaching this means the fleet has
/// been unreachable for a while; consecutive re-arms back off from here.
final votingShareTrackingFailureRetryDelayProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 15);
});

/// Ceiling for that backoff, so a long outage settles into a slow retry
/// instead of either hammering the fleet or giving up on the round.
final votingShareTrackingMaxRetryDelayProvider = Provider<Duration>((ref) {
  return const Duration(minutes: 10);
});

/// Baseline policy for transient voting transport errors.
final votingTransportRetryPolicyProvider = Provider<VotingRetryPolicy>((ref) {
  return VotingRetryPolicy.transientHttp(
    name: 'voting-transport',
    delays: const [Duration(milliseconds: 300), Duration(seconds: 1)],
  );
});

/// Retry policy used by voting config refresh/load.
final votingConfigRetryPolicyProvider = Provider<VotingRetryPolicy>((ref) {
  return ref.watch(votingTransportRetryPolicyProvider);
});

/// Retry policy used by rounds list reload.
final votingRoundsRetryPolicyProvider = Provider<VotingRetryPolicy>((ref) {
  return ref.watch(votingTransportRetryPolicyProvider);
});

/// Retry policy for chain reads (rounds/status/tally/tx).
final votingApiReadRetryPolicyProvider = Provider<VotingRetryPolicy>((ref) {
  return ref.watch(votingTransportRetryPolicyProvider);
});

/// REST client for chain-facing vote server endpoints.
final votingApiClientProvider =
    Provider.family<VotingApiClient, VotingApiServerSet>((ref, servers) {
      return VotingApiClient(
        baseUrl: servers.primary,
        fallbackBaseUrls: servers.failovers,
        httpClient: ref.watch(votingHttpClientProvider),
        timeout: ref.watch(votingApiRequestTimeoutProvider),
        readRetryPolicy: ref.watch(votingApiReadRetryPolicyProvider),
      );
    });

/// Resolves PIR endpoints before proof generation.
///
/// Probing and selection both run in Rust, so this provider only exists as
/// the seam tests replace.
final votingPirResolverProvider = Provider<PirSnapshotResolver>((ref) {
  return PirSnapshotResolver(mapper: ref.watch(votingEndpointMapperProvider));
});

/// Adapter over durable Rust recovery/share-tracking state.
final votingRecoveryServiceProvider = Provider<VotingRecoveryService>((ref) {
  return const VotingRecoveryService();
});

/// Injectable wrapper around generated Rust voting bindings.
final votingRustApiProvider = Provider<VotingRustApi>((ref) {
  return const FrbVotingRustApi();
});

/// Secret hotkey access. Bytes are app-encrypted in platform secure storage.
final votingHotkeyStoreProvider = Provider<VotingHotkeyStore>((ref) {
  return AppSecureStoreVotingHotkeyStore(AppSecureStore.instance);
});

/// Test seam for wallet DB path resolution.
final votingWalletDbPathProvider = Provider<Future<String> Function()>((ref) {
  return getWalletDbPath;
});

/// Test seam for active account lookup.
final votingActiveAccountUuidProvider = Provider<Future<String?> Function()>((
  ref,
) {
  final activeAccountUuid = ref.watch(
    accountProvider.select((value) => value.value?.activeAccountUuid),
  );
  return () async {
    if (activeAccountUuid != null) return activeAccountUuid;
    return (await ref.read(accountProvider.future)).activeAccountUuid;
  };
});

/// Test seam for account hardware classification.
final votingAccountIsHardwareProvider = Provider<Future<bool> Function(String)>(
  (ref) {
    return (accountUuid) async {
      final accountState = await ref.read(accountProvider.future);
      for (final account in accountState.accounts) {
        if (account.uuid == accountUuid) return account.isHardware;
      }
      return false;
    };
  },
);

/// Current lightwalletd/network configuration for Rust voting calls.
final votingRpcEndpointConfigProvider = Provider<RpcEndpointConfig>((ref) {
  return ref.watch(rpcEndpointProvider);
});

/// Starts foreground wallet sync when voting needs the wallet to catch up.
final votingWalletSyncStarterProvider = Provider<void Function()>((ref) {
  return () => ref.read(syncProvider.notifier).startSync();
});

/// Delay between contiguous scan readiness checks while waiting to vote.
final votingWalletSyncPollIntervalProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 2);
});

/// Upper bound for waiting on wallet scan readiness before surfacing retryable
/// session error state.
final votingWalletSyncMaxWaitProvider = Provider<Duration>((ref) {
  return const Duration(minutes: 3);
});

/// Checks whether wallet scan progress has reached a voting snapshot height.
final votingWalletSyncReadinessCheckerProvider =
    Provider<VotingWalletSyncReadinessChecker>((ref) {
      return const FrbVotingWalletSyncReadinessChecker();
    });

class VotingWalletSyncReadiness {
  const VotingWalletSyncReadiness({
    required this.scannedHeight,
    required this.snapshotHeight,
    required this.chainTipHeight,
  });

  final int scannedHeight;
  final int snapshotHeight;
  final int chainTipHeight;

  bool get isReady => scannedHeight >= snapshotHeight;

  int get blocksRemaining {
    final remaining = snapshotHeight - scannedHeight;
    return remaining > 0 ? remaining : 0;
  }
}

abstract interface class VotingWalletSyncReadinessChecker {
  Future<VotingWalletSyncReadiness> check({
    required String dbPath,
    required String network,
    required int snapshotHeight,
  });
}

class FrbVotingWalletSyncReadinessChecker
    implements VotingWalletSyncReadinessChecker {
  const FrbVotingWalletSyncReadinessChecker();

  @override
  Future<VotingWalletSyncReadiness> check({
    required String dbPath,
    required String network,
    required int snapshotHeight,
  }) async {
    final status = await rust_sync.getSyncStatus(
      dbPath: dbPath,
      network: network,
    );
    return VotingWalletSyncReadiness(
      scannedHeight: status.scannedHeight.toInt(),
      snapshotHeight: snapshotHeight,
      chainTipHeight: status.chainTipHeight.toInt(),
    );
  }
}

abstract interface class VotingHotkeyStore {
  Future<List<int>?> readHotkey({
    required String accountUuid,
    required String roundId,
  });

  Future<void> writeHotkey({
    required String accountUuid,
    required String roundId,
    required List<int> hotkey,
  });

  Future<void> deleteHotkey({
    required String accountUuid,
    required String roundId,
  });
}

class VotingHotkeyUnavailable implements Exception {
  const VotingHotkeyUnavailable(this.message);

  final String message;

  @override
  String toString() => 'VotingHotkeyUnavailable: $message';
}

class AppSecureStoreVotingHotkeyStore implements VotingHotkeyStore {
  const AppSecureStoreVotingHotkeyStore(this._store);

  final AppSecureStore _store;

  @override
  Future<List<int>?> readHotkey({
    required String accountUuid,
    required String roundId,
  }) {
    return _store.readVotingHotkey(accountUuid: accountUuid, roundId: roundId);
  }

  @override
  Future<void> writeHotkey({
    required String accountUuid,
    required String roundId,
    required List<int> hotkey,
  }) {
    return _store.writeVotingHotkey(
      accountUuid: accountUuid,
      roundId: roundId,
      hotkey: hotkey,
    );
  }

  @override
  Future<void> deleteHotkey({
    required String accountUuid,
    required String roundId,
  }) {
    return _store.deleteVotingHotkey(
      accountUuid: accountUuid,
      roundId: roundId,
    );
  }
}

/// SDK-owned execution of one round for one account.
///
/// The SDK interprets the plan and runs each step (proving, chain episodes,
/// confirmation, helper delivery); Dart keeps scheduling, cancellation, the
/// network route, and secret custody. Every method throws
/// `VotingErrorView` for SDK failures.
abstract interface class VotingRoundSession {
  String get accountUuid;

  String get roundId;

  bool get isDisposed;

  void setOperationEpoch(BigInt operationEpoch);

  /// Cancels every step in flight or queued on this session.
  void cancel();

  void dispose();

  Future<rust_voting.RoundPlanView> plan();

  Future<rust_voting.RoundPlanView> setBallotIntents(
    List<rust_session.ApiBallotIntent> intents,
  );

  /// Clears durable intents for proposals outside the round's roster.
  ///
  /// The SDK withholds casting while `RoundPlanView.unrosteredIntents` is
  /// non-empty, so these must be cleared before a cast can be planned.
  Future<rust_voting.RoundPlanView> clearBallotIntents(List<int> proposalIds);

  /// Drives the round to quiescence, streaming events then exactly one report.
  ///
  /// The SDK owns the loop: it plans, dispatches, overlaps independent
  /// bundles, isolates failures per bundle, and stops at the first state only
  /// this app can resolve. `host` is a template whose clock the bridge
  /// restamps per dispatch.
  Stream<rust_session.ApiRoundRunEvent> runRound({
    rust_session.ApiDelegationSignerInput? signer,
    rust_session.ApiRoundDrivePolicy? policy,
  });

  Future<List<rust_delegate.KeystoneSigningRequest>> keystoneSigningRequests(
    List<int> bundleIndices,
  );

  /// Tracks this round's helper shares to confirmation, streaming events then
  /// exactly one report.
  ///
  /// The SDK owns the loop and its cadence: it repeats a tracking pass on the
  /// delay each pass computes, stops at vote end, and reports why it stopped.
  /// Dart keeps only the conditions the SDK cannot see — app lock, account and
  /// round identity — and stops a run through [cancel].
  Stream<rust_session.ApiShareTrackingRunEvent> runShareTracking({
    rust_session.ApiShareTrackingDrivePolicy? policy,
  });

  /// Re-reads whether this round's designated immediate share is confirmed.
  ///
  /// Answers now rather than on the tracking cadence, and never resubmits a
  /// share or picks a new helper, so it stays safe after the round has ended.
  Future<bool> confirmImmediateShare({
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
  });
}

/// Narrow interface over Rust voting work used by the session state machine.
///
/// Keeping this boundary explicit lets tests verify sequencing, recovery skips,
/// and progress forwarding without invoking FRB or cryptographic proof work.
abstract interface class VotingRustApi {
  /// Opens a session bound to `ctx`'s account and round.
  ///
  /// `binding` fixes the round's endpoints, roster and timing for the
  /// session's life, so no later call can supply a different fleet for the
  /// same round. A configuration change replaces those values, and the app
  /// answers it by rebuilding the session.
  VotingRoundSession openRoundSession({
    required rust_api.ApiVotingRoundContext ctx,
    required rust_session.ApiRoundSessionBinding binding,
    List<int>? storedHotkeySecret,
    required BigInt operationEpoch,
  });

  Future<rust_voting.VotingRoundParams> trustedVotingRoundParamsFromConfig({
    required rust_config.ResolvedVotingConfig config,
    required String roundId,
    required BigInt snapshotHeight,
    required List<int> ncRoot,
    required List<int> nullifierImtRoot,
  });

  Future<rust_api.ApiBundleLayout> setupDelegationBundles({
    required rust_api.ApiVotingRoundContext ctx,
  });

  Future<rust_api.ApiVotingEligibility> checkVotingEligibility({
    required rust_api.ApiVotingRoundContext ctx,
  });

  Future<rust_api.ApiSnapshotBundlePrecomputeResult> precomputeSnapshotBundles({
    required rust_api.ApiVotingRoundContext ctx,
    required String pirServerUrl,
  });

  /// Generate and persist ZKP1 without signing or submitting the delegation.
  ///
  /// Returns whether this call generated the proof. A previously persisted
  /// proof is reused and returns false.
  Future<bool> precomputeDelegationProof({
    required rust_api.ApiVotingRoundContext ctx,
    required List<String> pirServerUrls,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
  });

  /// Bundle-independent background PIR proof cache warm-up.
  ///
  /// Needs no hotkey, round rows, or bundles — only a wallet scanned to the
  /// snapshot height and a PIR endpoint serving it. `keepRoots` should hold
  /// every active round's `nullifier_imt_root`; the served root is kept
  /// automatically.
  Future<rust_api.ApiPirCacheWarmupResult> warmPirProofCache({
    required String dbPath,
    required String accountUuid,
    required String network,
    required String lightwalletdUrl,
    required BigInt snapshotHeight,
    required String pirServerUrl,
    required rust_config.PirLayout pirLayout,
    required List<Uint8List> keepRoots,
  });

  /// Fire-and-forget Halo2 proving-key warm-up for voting proofs.
  void warmVotingProvingCaches();

  Future<List<int>> generateVotingHotkey({required String network});

  Future<List<rust_delegate.KeystoneSigningRequest>>
  buildKeystoneDelegationRequests({
    required rust_api.ApiVotingRoundContext ctx,
    required List<int> storedHotkeySecret,
    required List<int> bundleIndices,
  });

  Future<rust_api.ApiKeystoneSignatureBatchResult>
  storeKeystoneSignaturesBatch({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required List<rust_api.ApiKeystoneSignatureInput> signatures,
  });

  Future<List<rust_voting.KeystoneSignatureRecord>> getKeystoneSignatures({
    required String dbPath,
    required String accountUuid,
    required String roundId,
  });

  Future<int> deleteSkippedBundles({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int keepCount,
  });

  Future<int> syncVoteTree({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required String nodeUrl,
  });

  /// Clear only the process-local vote-tree sync cache for a round or account.
  ///
  /// A non-null, non-empty `roundId` clears that round's tree sync cache.
  /// `null` (or empty) performs account-wide vote-tree cleanup for `accountUuid`.
  Future<void> resetVoteTree({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  });

  /// Clear process-local Rust voting caches for a round or account.
  ///
  /// A non-null, non-empty `roundId` clears round-scoped vote-tree sync cache
  /// and unsigned delegation setup fields. `null` (or empty) performs
  /// account-wide cleanup for `accountUuid`.
  Future<void> resetVotingSessionState({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  });

  BigInt? lastMomentBufferSeconds({
    required BigInt ceremonyStartSeconds,
    required BigInt voteEndTimeSeconds,
  });

  bool isLastMoment({
    required BigInt nowSeconds,
    required BigInt ceremonyStartSeconds,
    required BigInt voteEndTimeSeconds,
  });
}

final class _FrbVotingRoundSession implements VotingRoundSession {
  _FrbVotingRoundSession({
    required this.accountUuid,
    required this.roundId,
    required rust_session.VotingRoundSession inner,
  }) : _inner = inner;

  @override
  final String accountUuid;

  @override
  final String roundId;

  final rust_session.VotingRoundSession _inner;

  @override
  bool get isDisposed => _inner.isDisposed;

  rust_session.VotingRoundSession get inner {
    if (isDisposed) {
      throw StateError('Voting round session has been disposed.');
    }
    return _inner;
  }

  @override
  void setOperationEpoch(BigInt operationEpoch) {
    if (isDisposed) return;
    _inner.setOperationEpoch(operationEpoch: operationEpoch);
  }

  @override
  void cancel() {
    if (isDisposed) return;
    _inner.cancel();
  }

  @override
  void dispose() {
    if (isDisposed) return;
    _inner.dispose();
  }

  @override
  Future<rust_voting.RoundPlanView> plan() => _typed(() => inner.plan());

  @override
  Future<rust_voting.RoundPlanView> setBallotIntents(
    List<rust_session.ApiBallotIntent> intents,
  ) => _typed(() => inner.setBallotIntents(intents: intents));

  @override
  Future<rust_voting.RoundPlanView> clearBallotIntents(List<int> proposalIds) =>
      _typed(() => inner.clearBallotIntents(proposalIds: proposalIds));

  @override
  Stream<rust_session.ApiRoundRunEvent> runRound({
    rust_session.ApiDelegationSignerInput? signer,
    rust_session.ApiRoundDrivePolicy? policy,
  }) => _typedStream(inner.runRound(signer: signer, policy: policy));

  @override
  Future<List<rust_delegate.KeystoneSigningRequest>> keystoneSigningRequests(
    List<int> bundleIndices,
  ) =>
      _typed(() => inner.keystoneSigningRequests(bundleIndices: bundleIndices));

  @override
  Stream<rust_session.ApiShareTrackingRunEvent> runShareTracking({
    rust_session.ApiShareTrackingDrivePolicy? policy,
  }) => _typedStream(inner.runShareTracking(policy: policy));

  @override
  Future<bool> confirmImmediateShare({
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
  }) => _typed(
    () => inner.confirmImmediateShare(
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      shareIndex: shareIndex,
    ),
  );
}

/// Production implementation backed by generated FRB calls.
/// Rethrows a bridge `VotingErrorView` as [VotingRustException] so callers
/// classify it by kind and its message survives `toString`.
Future<T> _typed<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on rust_voting.VotingErrorView catch (error) {
    throw VotingRustException(error);
  }
}

T _typedSync<T>(T Function() call) {
  try {
    return call();
  } on rust_voting.VotingErrorView catch (error) {
    throw VotingRustException(error);
  }
}

Stream<T> _typedStream<T>(Stream<T> stream) {
  return stream.handleError(
    (Object error) =>
        throw VotingRustException(error as rust_voting.VotingErrorView),
    test: (error) => error is rust_voting.VotingErrorView,
  );
}

class FrbVotingRustApi implements VotingRustApi {
  const FrbVotingRustApi();

  @override
  VotingRoundSession openRoundSession({
    required rust_api.ApiVotingRoundContext ctx,
    required rust_session.ApiRoundSessionBinding binding,
    List<int>? storedHotkeySecret,
    required BigInt operationEpoch,
  }) {
    return _FrbVotingRoundSession(
      accountUuid: ctx.accountUuid,
      roundId: ctx.roundParams.voteRoundId,
      inner: _typedSync(
        () => rust_session.openVotingRoundSession(
          ctx: ctx,
          binding: binding,
          storedHotkeySecret: storedHotkeySecret == null
              ? null
              : Uint8List.fromList(storedHotkeySecret),
          operationEpoch: operationEpoch,
        ),
      ),
    );
  }

  @override
  Future<rust_voting.VotingRoundParams> trustedVotingRoundParamsFromConfig({
    required rust_config.ResolvedVotingConfig config,
    required String roundId,
    required BigInt snapshotHeight,
    required List<int> ncRoot,
    required List<int> nullifierImtRoot,
  }) {
    return _typed(
      () => rust_api.trustedVotingRoundParamsFromConfig(
        resolvedConfig: config,
        roundId: roundId,
        snapshotHeight: snapshotHeight,
        ncRoot: ncRoot,
        nullifierImtRoot: nullifierImtRoot,
      ),
    );
  }

  @override
  Future<rust_api.ApiBundleLayout> setupDelegationBundles({
    required rust_api.ApiVotingRoundContext ctx,
  }) {
    return _typed(() => rust_api.setupDelegationBundles(ctx: ctx));
  }

  @override
  Future<rust_api.ApiVotingEligibility> checkVotingEligibility({
    required rust_api.ApiVotingRoundContext ctx,
  }) {
    return _typed(() => rust_api.checkVotingEligibility(ctx: ctx));
  }

  @override
  Future<rust_api.ApiSnapshotBundlePrecomputeResult> precomputeSnapshotBundles({
    required rust_api.ApiVotingRoundContext ctx,
    required String pirServerUrl,
  }) {
    return _typed(
      () => rust_api.precomputeSnapshotBundles(
        ctx: ctx,
        pirServerUrl: pirServerUrl,
      ),
    );
  }

  @override
  Future<bool> precomputeDelegationProof({
    required rust_api.ApiVotingRoundContext ctx,
    required List<String> pirServerUrls,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
  }) {
    return _typed(
      () => rust_api.precomputeDelegationProof(
        ctx: ctx,
        pirServerUrls: pirServerUrls,
        storedHotkeySecret: storedHotkeySecret,
        bundleIndex: bundleIndex,
      ),
    );
  }

  @override
  Future<rust_api.ApiPirCacheWarmupResult> warmPirProofCache({
    required String dbPath,
    required String accountUuid,
    required String network,
    required String lightwalletdUrl,
    required BigInt snapshotHeight,
    required String pirServerUrl,
    required rust_config.PirLayout pirLayout,
    required List<Uint8List> keepRoots,
  }) {
    return _typed(
      () => rust_api.warmPirProofCache(
        dbPath: dbPath,
        accountUuid: accountUuid,
        network: network,
        lightwalletdUrl: lightwalletdUrl,
        snapshotHeight: snapshotHeight,
        pirServerUrl: pirServerUrl,
        pirLayout: pirLayout,
        keepRoots: keepRoots,
      ),
    );
  }

  @override
  void warmVotingProvingCaches() {
    rust_api.warmVotingProvingCaches();
  }

  @override
  Future<List<int>> generateVotingHotkey({required String network}) {
    return _typed(() => rust_api.generateVotingHotkey(network: network));
  }

  @override
  Future<List<rust_delegate.KeystoneSigningRequest>>
  buildKeystoneDelegationRequests({
    required rust_api.ApiVotingRoundContext ctx,
    required List<int> storedHotkeySecret,
    required List<int> bundleIndices,
  }) {
    return _typed(
      () => rust_api.buildKeystoneDelegationRequests(
        ctx: ctx,
        storedHotkeySecret: storedHotkeySecret,
        bundleIndices: bundleIndices,
      ),
    );
  }

  @override
  Future<rust_api.ApiKeystoneSignatureBatchResult>
  storeKeystoneSignaturesBatch({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required List<rust_api.ApiKeystoneSignatureInput> signatures,
  }) {
    return _typed(
      () => rust_api.storeKeystoneSignaturesBatch(
        dbPath: dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
        signatures: signatures,
      ),
    );
  }

  @override
  Future<List<rust_voting.KeystoneSignatureRecord>> getKeystoneSignatures({
    required String dbPath,
    required String accountUuid,
    required String roundId,
  }) {
    return _typed(
      () => rust_api.getKeystoneSignatures(
        dbPath: dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
      ),
    );
  }

  @override
  Future<int> deleteSkippedBundles({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int keepCount,
  }) {
    return _typed(
      () => rust_api.deleteSkippedBundles(
        dbPath: dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
        keepCount: keepCount,
      ),
    );
  }

  @override
  Future<int> syncVoteTree({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required String nodeUrl,
  }) {
    return _typed(
      () => rust_api.syncVoteTree(
        dbPath: dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
        nodeUrl: nodeUrl,
      ),
    );
  }

  @override
  Future<void> resetVotingSessionState({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  }) {
    return _typed(
      () => rust_api.resetVotingSessionState(
        dbPath: dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
      ),
    );
  }

  @override
  Future<void> resetVoteTree({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  }) {
    return _typed(
      () => rust_api.resetVoteTree(
        dbPath: dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
      ),
    );
  }

  @override
  BigInt? lastMomentBufferSeconds({
    required BigInt ceremonyStartSeconds,
    required BigInt voteEndTimeSeconds,
  }) {
    return _typedSync(
      () => rust_api.lastMomentBufferSeconds(
        ceremonyStartSeconds: ceremonyStartSeconds,
        voteEndTimeSeconds: voteEndTimeSeconds,
      ),
    );
  }

  @override
  bool isLastMoment({
    required BigInt nowSeconds,
    required BigInt ceremonyStartSeconds,
    required BigInt voteEndTimeSeconds,
  }) {
    return _typedSync(
      () => rust_api.isLastMoment(
        nowSeconds: nowSeconds,
        ceremonyStartSeconds: ceremonyStartSeconds,
        voteEndTimeSeconds: voteEndTimeSeconds,
      ),
    );
  }
}
