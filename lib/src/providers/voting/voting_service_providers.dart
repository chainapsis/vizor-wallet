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
import '../../rust/third_party/zcash_voting/config.dart' as rust_config;
import '../../rust/third_party/zcash_voting/delegate.dart' as rust_delegate;
import '../../rust/third_party/zcash_voting/vote.dart' as rust_vote;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_voting;
import '../../services/voting/pir_snapshot_resolver.dart';
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

/// Delay before retrying a failed automatic helper-share tracking pass.
final votingShareTrackingFailureRetryDelayProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 15);
});

/// Timeout for PIR `/root` probe requests.
final votingPirProbeTimeoutProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 10);
});

/// Baseline policy for transient voting transport errors.
final votingTransportRetryPolicyProvider = Provider<VotingRetryPolicy>((ref) {
  return VotingRetryPolicy.transientHttp(
    name: 'voting-transport',
    delays: const [Duration(milliseconds: 300), Duration(seconds: 1)],
  );
});

/// Retry policy for PIR endpoint probes.
final votingPirProbeRetryPolicyProvider = Provider<VotingRetryPolicy>((ref) {
  return VotingRetryPolicy.transientHttp(
    name: 'voting-pir-probe',
    delays: const [Duration.zero],
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
final votingPirResolverProvider = Provider<PirSnapshotResolver>((ref) {
  final rust = ref.watch(votingRustApiProvider);
  return PirSnapshotResolver(
    httpClient: ref.watch(votingHttpClientProvider),
    selectEndpoint:
        ({
          required diagnostics,
          required expectedSnapshotHeight,
          required matchIndex,
        }) {
          final endpoint = rust.selectPirSnapshotEndpoint(
            diagnostics: [
              for (final diagnostic in diagnostics)
                rust_api.ApiPirSnapshotEndpointDiagnostic(
                  endpoint: diagnostic.endpoint.toString(),
                  status: _apiPirSnapshotStatus(diagnostic.status),
                  reportedHeight: diagnostic.reportedHeight == null
                      ? null
                      : BigInt.from(diagnostic.reportedHeight!),
                  httpStatusCode: diagnostic.httpStatusCode,
                  message: diagnostic.message,
                ),
            ],
            expectedSnapshotHeight: BigInt.from(expectedSnapshotHeight),
            matchIndex: BigInt.from(matchIndex),
          );
          return endpoint == null ? null : Uri.parse(endpoint);
        },
    timeout: ref.watch(votingPirProbeTimeoutProvider),
    retryPolicy: ref.watch(votingPirProbeRetryPolicyProvider),
  );
});

rust_api.ApiPirSnapshotEndpointStatus _apiPirSnapshotStatus(
  PirSnapshotEndpointStatus status,
) {
  return switch (status) {
    PirSnapshotEndpointStatus.matched =>
      rust_api.ApiPirSnapshotEndpointStatus.matched,
    PirSnapshotEndpointStatus.behind =>
      rust_api.ApiPirSnapshotEndpointStatus.behind,
    PirSnapshotEndpointStatus.ahead =>
      rust_api.ApiPirSnapshotEndpointStatus.ahead,
    PirSnapshotEndpointStatus.missingHeight =>
      rust_api.ApiPirSnapshotEndpointStatus.missingHeight,
    PirSnapshotEndpointStatus.malformedJson =>
      rust_api.ApiPirSnapshotEndpointStatus.malformedJson,
    PirSnapshotEndpointStatus.nonSuccessStatus =>
      rust_api.ApiPirSnapshotEndpointStatus.nonSuccessStatus,
    PirSnapshotEndpointStatus.timeoutOrNetworkError =>
      rust_api.ApiPirSnapshotEndpointStatus.timeoutOrNetworkError,
  };
}

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

/// Account-and-round helper state shared by initial delivery and tracking.
abstract interface class VotingHelperDeliveryContext {
  String get dbPath;

  String get accountUuid;

  String get roundId;

  bool get isDisposed;

  void dispose();
}

/// Cancellable handle for one account-and-round helper-share tracking pass.
///
/// Cancellation and disposal are synchronous so a destructive drain can stop
/// an FRB call that has been dispatched but has not started executing yet.
abstract interface class VotingShareTrackingPassHandle {
  String get accountUuid;

  String get roundId;

  bool get isCancelled;

  bool get isDisposed;

  void cancel();

  void dispose();
}

/// Cancellable host-epoch token for one SDK-owned chain advancement episode.
abstract interface class VotingChainSubmissionPassHandle {
  String get accountUuid;

  String get roundId;

  bool get isCancelled;

  bool get isDisposed;

  void setOperationEpoch(BigInt operationEpoch);

  void cancel();

  void dispose();
}

/// Narrow interface over Rust voting work used by the session state machine.
///
/// Keeping this boundary explicit lets tests verify sequencing, recovery skips,
/// and progress forwarding without invoking FRB or cryptographic proof work.
abstract interface class VotingRustApi {
  VotingChainSubmissionPassHandle beginChainSubmissionPass({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required String network,
    required List<String> endpoints,
    required BigInt operationEpoch,
  });

  Future<rust_api.ApiChainSubmissionCallResult> advanceChainDelegation({
    required VotingChainSubmissionPassHandle passHandle,
    required int bundleIndex,
    required rust_voting.SignedDelegationPayloadView submission,
    required rust_api.ApiChainRecoveryMode recoveryMode,
  });

  Future<rust_api.ApiChainSubmissionCallResult> advanceChainVote({
    required VotingChainSubmissionPassHandle passHandle,
    required int bundleIndex,
    required int proposalId,
    required rust_api.ApiChainRecoveryMode recoveryMode,
  });

  Future<rust_api.ApiChainSubmissionCallResult> advanceChainVoteBatch({
    required VotingChainSubmissionPassHandle passHandle,
    required int bundleIndex,
    required int proposalId,
    required rust_api.ApiChainRecoveryMode recoveryMode,
  });

  /// Selects an exact-height PIR endpoint using the SDK's protocol policy.
  String? selectPirSnapshotEndpoint({
    required List<rust_api.ApiPirSnapshotEndpointDiagnostic> diagnostics,
    required BigInt expectedSnapshotHeight,
    required BigInt matchIndex,
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

  Stream<rust_api.ApiDelegationProofEvent>
  buildProveAndSignDelegationPayloadWithProgress({
    required rust_api.ApiVotingRoundContext ctx,
    required List<String> pirServerUrls,
    required String mnemonic,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
  });

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

  Stream<rust_api.ApiDelegationProofEvent>
  buildProveDelegationPayloadWithKeystoneSignatureWithProgress({
    required rust_api.ApiVotingRoundContext ctx,
    required List<String> pirServerUrls,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
    required List<int> keystoneSig,
    required List<int> keystoneSighash,
  });

  Future<int> syncVoteTree({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required String nodeUrl,
  });

  Future<rust_vote.VanWitness> generateVanWitness({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int anchorHeight,
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

  Stream<rust_api.ApiVoteCommitEvent> buildVoteCommitmentsWithProgress({
    required String dbPath,
    required String accountUuid,
    required String network,
    required String roundId,
    required int bundleIndex,
    required List<int> storedHotkeySecret,
    required rust_vote.VanWitness vanWitness,
    required List<rust_voting.DraftVote> draftVotes,
    required int maxProofConcurrency,
  });

  Future<rust_api.ApiSignedVoteCommitments> recoverVoteCommitment({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
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

  /// Runs one helper confirm-or-retry pass for a round inside the crate.
  ///
  /// Helper polling, the two-distinct-helper confirmation quorum, overdue
  /// resubmission, and all durable writes happen in Rust. Dart supplies timing
  /// and cancellation only.
  Future<rust_api.ApiShareTrackingReport> trackPendingShares({
    required VotingShareTrackingPassHandle passHandle,
    required List<String> configuredHelperUrls,
    required BigInt nowSeconds,
    BigInt? voteEndTimeSeconds,
  });

  /// Checks and persists quorum confirmation for exactly one helper share.
  Future<bool> confirmShareWithHelpers({
    required VotingShareTrackingPassHandle passHandle,
    required List<String> configuredHelperUrls,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required BigInt nowSeconds,
  });

  /// Creates account-and-round helper state shared by delivery and tracking.
  VotingHelperDeliveryContext createVotingHelperDeliveryContext({
    required String dbPath,
    required String accountUuid,
    required String roundId,
  });

  /// Creates a cancellable pass handle bound to a helper delivery context.
  VotingShareTrackingPassHandle beginShareTrackingPass({
    required VotingHelperDeliveryContext context,
  });

  /// Canonicalizes and probes the complete configured helper fleet.
  Future<rust_api.ApiVotingHelperPreflight> preflightVotingHelpers({
    required VotingHelperDeliveryContext context,
    required List<String> configuredHelperUrls,
  });

  /// Plans and durably persists every helper share before vote broadcast.
  Future<void> prepareCommittedShareDelivery({
    required VotingHelperDeliveryContext context,
    required int bundleIndex,
    required int proposalId,
    required rust_api.ApiVotingHelperPreflight preflight,
    required BigInt nowSeconds,
    required BigInt voteEndTimeSeconds,
    required List<int> proposalIds,
    BigInt? lastMomentBufferSeconds,
  });

  /// Submits every incomplete share from an existing durable delivery plan.
  Future<rust_api.ApiShareBatchDeliveryReport> submitPreparedSharesToHelpers({
    required VotingHelperDeliveryContext context,
    required int bundleIndex,
    required int proposalId,
    required List<String> configuredHelperUrls,
    required BigInt nowSeconds,
  });

  Future<BigInt?> nextShareTrackingDelaySeconds({
    required List<rust_voting.ShareDelegationRecordView> shares,
    required BigInt nowSeconds,
  });
}

final class _FrbVotingHelperDeliveryContext
    implements VotingHelperDeliveryContext {
  _FrbVotingHelperDeliveryContext({
    required this.dbPath,
    required this.accountUuid,
    required this.roundId,
    required rust_api.VotingHelperDeliveryContext inner,
  }) : _inner = inner;

  @override
  final String dbPath;

  @override
  final String accountUuid;

  @override
  final String roundId;

  final rust_api.VotingHelperDeliveryContext _inner;

  @override
  bool get isDisposed => _inner.isDisposed;

  rust_api.VotingHelperDeliveryContext get inner {
    if (isDisposed) {
      throw StateError('Voting helper delivery context has been disposed.');
    }
    return _inner;
  }

  @override
  void dispose() {
    if (isDisposed) return;
    _inner.dispose();
  }
}

final class _FrbVotingShareTrackingPassHandle
    implements VotingShareTrackingPassHandle {
  _FrbVotingShareTrackingPassHandle({
    required this.accountUuid,
    required this.roundId,
    required rust_api.VotingShareTrackingPassHandle inner,
  }) : _inner = inner;

  @override
  final String accountUuid;

  @override
  final String roundId;

  final rust_api.VotingShareTrackingPassHandle _inner;
  bool _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  bool get isDisposed => _inner.isDisposed;

  rust_api.VotingShareTrackingPassHandle get inner {
    if (isDisposed) {
      throw StateError('Share tracking pass handle has been disposed.');
    }
    return _inner;
  }

  @override
  void cancel() {
    if (_isCancelled || isDisposed) return;
    _inner.cancel();
    _isCancelled = true;
  }

  @override
  void dispose() {
    if (isDisposed) return;
    _inner.dispose();
  }
}

final class _FrbVotingChainSubmissionPassHandle
    implements VotingChainSubmissionPassHandle {
  _FrbVotingChainSubmissionPassHandle({
    required this.accountUuid,
    required this.roundId,
    required rust_api.VotingChainSubmissionPassHandle inner,
  }) : _inner = inner;

  @override
  final String accountUuid;

  @override
  final String roundId;

  final rust_api.VotingChainSubmissionPassHandle _inner;
  bool _isCancelled = false;

  @override
  bool get isCancelled => _isCancelled;

  @override
  bool get isDisposed => _inner.isDisposed;

  rust_api.VotingChainSubmissionPassHandle get inner {
    if (isDisposed) {
      throw StateError('Chain submission pass handle has been disposed.');
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
    if (_isCancelled || isDisposed) return;
    _inner.cancel();
    _isCancelled = true;
  }

  @override
  void dispose() {
    if (isDisposed) return;
    _inner.dispose();
  }
}

/// Production implementation backed by generated FRB calls.
class FrbVotingRustApi implements VotingRustApi {
  const FrbVotingRustApi();

  @override
  VotingChainSubmissionPassHandle beginChainSubmissionPass({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required String network,
    required List<String> endpoints,
    required BigInt operationEpoch,
  }) {
    return _FrbVotingChainSubmissionPassHandle(
      accountUuid: accountUuid,
      roundId: roundId,
      inner: rust_api.beginChainSubmissionPass(
        dbPath: dbPath,
        accountUuid: accountUuid,
        roundId: roundId,
        network: network,
        endpoints: endpoints,
        operationEpoch: operationEpoch,
      ),
    );
  }

  @override
  Future<rust_api.ApiChainSubmissionCallResult> advanceChainDelegation({
    required VotingChainSubmissionPassHandle passHandle,
    required int bundleIndex,
    required rust_voting.SignedDelegationPayloadView submission,
    required rust_api.ApiChainRecoveryMode recoveryMode,
  }) {
    final handle = passHandle as _FrbVotingChainSubmissionPassHandle;
    return rust_api.advanceChainDelegation(
      handle: handle.inner,
      bundleIndex: bundleIndex,
      submission: submission,
      recoveryMode: recoveryMode,
    );
  }

  @override
  Future<rust_api.ApiChainSubmissionCallResult> advanceChainVote({
    required VotingChainSubmissionPassHandle passHandle,
    required int bundleIndex,
    required int proposalId,
    required rust_api.ApiChainRecoveryMode recoveryMode,
  }) {
    final handle = passHandle as _FrbVotingChainSubmissionPassHandle;
    return rust_api.advanceChainVote(
      handle: handle.inner,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      recoveryMode: recoveryMode,
    );
  }

  @override
  Future<rust_api.ApiChainSubmissionCallResult> advanceChainVoteBatch({
    required VotingChainSubmissionPassHandle passHandle,
    required int bundleIndex,
    required int proposalId,
    required rust_api.ApiChainRecoveryMode recoveryMode,
  }) {
    final handle = passHandle as _FrbVotingChainSubmissionPassHandle;
    return rust_api.advanceChainVoteBatch(
      handle: handle.inner,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      recoveryMode: recoveryMode,
    );
  }

  @override
  String? selectPirSnapshotEndpoint({
    required List<rust_api.ApiPirSnapshotEndpointDiagnostic> diagnostics,
    required BigInt expectedSnapshotHeight,
    required BigInt matchIndex,
  }) {
    return rust_api.selectPirSnapshotEndpoint(
      diagnostics: diagnostics,
      expectedSnapshotHeight: expectedSnapshotHeight,
      matchIndex: matchIndex,
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
    return rust_api.trustedVotingRoundParamsFromConfig(
      resolvedConfig: config,
      roundId: roundId,
      snapshotHeight: snapshotHeight,
      ncRoot: ncRoot,
      nullifierImtRoot: nullifierImtRoot,
    );
  }

  @override
  Future<rust_api.ApiBundleLayout> setupDelegationBundles({
    required rust_api.ApiVotingRoundContext ctx,
  }) {
    return rust_api.setupDelegationBundles(ctx: ctx);
  }

  @override
  Future<rust_api.ApiVotingEligibility> checkVotingEligibility({
    required rust_api.ApiVotingRoundContext ctx,
  }) {
    return rust_api.checkVotingEligibility(ctx: ctx);
  }

  @override
  Future<rust_api.ApiSnapshotBundlePrecomputeResult> precomputeSnapshotBundles({
    required rust_api.ApiVotingRoundContext ctx,
    required String pirServerUrl,
  }) {
    return rust_api.precomputeSnapshotBundles(
      ctx: ctx,
      pirServerUrl: pirServerUrl,
    );
  }

  @override
  Future<bool> precomputeDelegationProof({
    required rust_api.ApiVotingRoundContext ctx,
    required List<String> pirServerUrls,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
  }) {
    return rust_api.precomputeDelegationProof(
      ctx: ctx,
      pirServerUrls: pirServerUrls,
      storedHotkeySecret: storedHotkeySecret,
      bundleIndex: bundleIndex,
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
    return rust_api.warmPirProofCache(
      dbPath: dbPath,
      accountUuid: accountUuid,
      network: network,
      lightwalletdUrl: lightwalletdUrl,
      snapshotHeight: snapshotHeight,
      pirServerUrl: pirServerUrl,
      pirLayout: pirLayout,
      keepRoots: keepRoots,
    );
  }

  @override
  void warmVotingProvingCaches() {
    rust_api.warmVotingProvingCaches();
  }

  @override
  Stream<rust_api.ApiDelegationProofEvent>
  buildProveAndSignDelegationPayloadWithProgress({
    required rust_api.ApiVotingRoundContext ctx,
    required List<String> pirServerUrls,
    required String mnemonic,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
  }) {
    return rust_api.buildProveAndSignDelegationPayloadWithProgress(
      ctx: ctx,
      pirServerUrls: pirServerUrls,
      mnemonic: mnemonic,
      storedHotkeySecret: storedHotkeySecret,
      bundleIndex: bundleIndex,
    );
  }

  @override
  Future<List<int>> generateVotingHotkey({required String network}) {
    return rust_api.generateVotingHotkey(network: network);
  }

  @override
  Future<List<rust_delegate.KeystoneSigningRequest>>
  buildKeystoneDelegationRequests({
    required rust_api.ApiVotingRoundContext ctx,
    required List<int> storedHotkeySecret,
    required List<int> bundleIndices,
  }) {
    return rust_api.buildKeystoneDelegationRequests(
      ctx: ctx,
      storedHotkeySecret: storedHotkeySecret,
      bundleIndices: bundleIndices,
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
    return rust_api.storeKeystoneSignaturesBatch(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      signatures: signatures,
    );
  }

  @override
  Future<List<rust_voting.KeystoneSignatureRecord>> getKeystoneSignatures({
    required String dbPath,
    required String accountUuid,
    required String roundId,
  }) {
    return rust_api.getKeystoneSignatures(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
    );
  }

  @override
  Future<int> deleteSkippedBundles({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int keepCount,
  }) {
    return rust_api.deleteSkippedBundles(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      keepCount: keepCount,
    );
  }

  @override
  Stream<rust_api.ApiDelegationProofEvent>
  buildProveDelegationPayloadWithKeystoneSignatureWithProgress({
    required rust_api.ApiVotingRoundContext ctx,
    required List<String> pirServerUrls,
    required List<int> storedHotkeySecret,
    required int bundleIndex,
    required List<int> keystoneSig,
    required List<int> keystoneSighash,
  }) {
    return rust_api
        .buildProveDelegationPayloadWithKeystoneSignatureWithProgress(
          ctx: ctx,
          pirServerUrls: pirServerUrls,
          storedHotkeySecret: storedHotkeySecret,
          bundleIndex: bundleIndex,
          keystoneSig: keystoneSig,
          keystoneSighash: keystoneSighash,
        );
  }

  @override
  Future<int> syncVoteTree({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required String nodeUrl,
  }) {
    return rust_api.syncVoteTree(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      nodeUrl: nodeUrl,
    );
  }

  @override
  Future<rust_vote.VanWitness> generateVanWitness({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int anchorHeight,
  }) {
    return rust_api.generateVanWitness(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      bundleIndex: bundleIndex,
      anchorHeight: anchorHeight,
    );
  }

  @override
  Future<void> resetVotingSessionState({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  }) {
    return rust_api.resetVotingSessionState(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
    );
  }

  @override
  Future<void> resetVoteTree({
    required String dbPath,
    required String accountUuid,
    String? roundId,
  }) {
    return rust_api.resetVoteTree(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
    );
  }

  @override
  Stream<rust_api.ApiVoteCommitEvent> buildVoteCommitmentsWithProgress({
    required String dbPath,
    required String accountUuid,
    required String network,
    required String roundId,
    required int bundleIndex,
    required List<int> storedHotkeySecret,
    required rust_vote.VanWitness vanWitness,
    required List<rust_voting.DraftVote> draftVotes,
    required int maxProofConcurrency,
  }) {
    return rust_api.buildVoteCommitmentsWithProgress(
      dbPath: dbPath,
      accountUuid: accountUuid,
      network: network,
      roundId: roundId,
      bundleIndex: bundleIndex,
      storedHotkeySecret: storedHotkeySecret,
      vanWitness: vanWitness,
      draftVotes: draftVotes,
      maxProofConcurrency: maxProofConcurrency,
    );
  }

  @override
  Future<rust_api.ApiSignedVoteCommitments> recoverVoteCommitment({
    required String dbPath,
    required String accountUuid,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
  }) {
    return rust_api.recoverVoteCommitment(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
    );
  }

  @override
  BigInt? lastMomentBufferSeconds({
    required BigInt ceremonyStartSeconds,
    required BigInt voteEndTimeSeconds,
  }) {
    return rust_api.lastMomentBufferSeconds(
      ceremonyStartSeconds: ceremonyStartSeconds,
      voteEndTimeSeconds: voteEndTimeSeconds,
    );
  }

  @override
  bool isLastMoment({
    required BigInt nowSeconds,
    required BigInt ceremonyStartSeconds,
    required BigInt voteEndTimeSeconds,
  }) {
    return rust_api.isLastMoment(
      nowSeconds: nowSeconds,
      ceremonyStartSeconds: ceremonyStartSeconds,
      voteEndTimeSeconds: voteEndTimeSeconds,
    );
  }

  @override
  Future<rust_api.ApiShareTrackingReport> trackPendingShares({
    required VotingShareTrackingPassHandle passHandle,
    required List<String> configuredHelperUrls,
    required BigInt nowSeconds,
    BigInt? voteEndTimeSeconds,
  }) {
    if (passHandle is! _FrbVotingShareTrackingPassHandle) {
      throw ArgumentError.value(
        passHandle,
        'passHandle',
        'Expected an FRB share tracking pass handle',
      );
    }
    return rust_api.trackPendingShares(
      passHandle: passHandle.inner,
      configuredHelperUrls: configuredHelperUrls,
      nowSeconds: nowSeconds,
      voteEndTimeSeconds: voteEndTimeSeconds,
    );
  }

  @override
  Future<bool> confirmShareWithHelpers({
    required VotingShareTrackingPassHandle passHandle,
    required List<String> configuredHelperUrls,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required BigInt nowSeconds,
  }) {
    if (passHandle is! _FrbVotingShareTrackingPassHandle) {
      throw ArgumentError.value(
        passHandle,
        'passHandle',
        'Expected an FRB voting share tracking pass handle',
      );
    }
    return rust_api.confirmShareWithHelpers(
      passHandle: passHandle.inner,
      configuredHelperUrls: configuredHelperUrls,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      shareIndex: shareIndex,
      nowSeconds: nowSeconds,
    );
  }

  @override
  VotingHelperDeliveryContext createVotingHelperDeliveryContext({
    required String dbPath,
    required String accountUuid,
    required String roundId,
  }) => _FrbVotingHelperDeliveryContext(
    dbPath: dbPath,
    accountUuid: accountUuid,
    roundId: roundId,
    inner: rust_api.createVotingHelperDeliveryContext(
      dbPath: dbPath,
      accountUuid: accountUuid,
      roundId: roundId,
    ),
  );

  @override
  VotingShareTrackingPassHandle beginShareTrackingPass({
    required VotingHelperDeliveryContext context,
  }) {
    if (context is! _FrbVotingHelperDeliveryContext) {
      throw ArgumentError.value(
        context,
        'context',
        'Expected an FRB voting helper delivery context',
      );
    }
    return _FrbVotingShareTrackingPassHandle(
      accountUuid: context.accountUuid,
      roundId: context.roundId,
      inner: rust_api.beginShareTrackingPass(context: context.inner),
    );
  }

  @override
  Future<rust_api.ApiVotingHelperPreflight> preflightVotingHelpers({
    required VotingHelperDeliveryContext context,
    required List<String> configuredHelperUrls,
  }) {
    if (context is! _FrbVotingHelperDeliveryContext) {
      throw ArgumentError.value(
        context,
        'context',
        'Expected an FRB voting helper delivery context',
      );
    }
    return rust_api.preflightVotingHelpers(
      context: context.inner,
      configuredHelperUrls: configuredHelperUrls,
    );
  }

  @override
  Future<void> prepareCommittedShareDelivery({
    required VotingHelperDeliveryContext context,
    required int bundleIndex,
    required int proposalId,
    required rust_api.ApiVotingHelperPreflight preflight,
    required BigInt nowSeconds,
    required BigInt voteEndTimeSeconds,
    required List<int> proposalIds,
    BigInt? lastMomentBufferSeconds,
  }) {
    if (context is! _FrbVotingHelperDeliveryContext) {
      throw ArgumentError.value(
        context,
        'context',
        'Expected an FRB voting helper delivery context',
      );
    }
    return rust_api.prepareCommittedShareDelivery(
      context: context.inner,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      preflight: preflight,
      nowSeconds: nowSeconds,
      voteEndTimeSeconds: voteEndTimeSeconds,
      proposalIds: proposalIds,
      lastMomentBufferSeconds: lastMomentBufferSeconds,
    );
  }

  @override
  Future<rust_api.ApiShareBatchDeliveryReport> submitPreparedSharesToHelpers({
    required VotingHelperDeliveryContext context,
    required int bundleIndex,
    required int proposalId,
    required List<String> configuredHelperUrls,
    required BigInt nowSeconds,
  }) {
    if (context is! _FrbVotingHelperDeliveryContext) {
      throw ArgumentError.value(
        context,
        'context',
        'Expected an FRB voting helper delivery context',
      );
    }
    return rust_api.submitPreparedSharesToHelpers(
      context: context.inner,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      configuredHelperUrls: configuredHelperUrls,
      nowSeconds: nowSeconds,
    );
  }

  @override
  Future<BigInt?> nextShareTrackingDelaySeconds({
    required List<rust_voting.ShareDelegationRecordView> shares,
    required BigInt nowSeconds,
  }) {
    return rust_api.nextShareTrackingDelaySeconds(
      shares: shares,
      nowSeconds: nowSeconds,
    );
  }
}
