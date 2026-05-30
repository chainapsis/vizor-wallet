import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_recovery_service.dart';
import '../../core/config/rpc_endpoint_config.dart';
import '../../core/storage/app_secure_store.dart';
import '../../core/storage/wallet_paths.dart';
import '../../providers/account_provider.dart';
import '../../providers/rpc_endpoint_provider.dart';
import '../../providers/sync_provider.dart';
import '../../rust/api/sync.dart' as rust_sync;
import '../../rust/api/voting.dart' as rust_voting;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/voting_api_client.dart';
import '../../services/voting/voting_config_loader.dart';
import '../../services/voting/voting_endorser_client.dart';
import '../../services/voting/voting_helper_health_tracker.dart';
import '../../services/voting/voting_http.dart';
import 'voting_config_source_provider.dart';

/// Transport shared by the voting service clients.
final votingHttpClientProvider = Provider<VotingHttpClient>((ref) {
  final client = DartIoVotingHttpClient();
  ref.onDispose(client.close);
  return client;
});

/// Loads the hash-pinned static config and dynamic voting config.
final votingConfigLoaderProvider = Provider<VotingConfigLoader>((ref) {
  final source = ref.watch(votingConfigSourceProvider).value;
  return VotingConfigLoader(
    httpClient: ref.watch(votingHttpClientProvider),
    staticConfigSource: source?.staticConfigSource,
  );
});

/// REST client for chain-facing vote server endpoints.
final votingApiClientProvider = Provider.family<VotingApiClient, Uri>((
  ref,
  baseUrl,
) {
  return VotingApiClient(
    baseUrl: baseUrl,
    httpClient: ref.watch(votingHttpClientProvider),
  );
});

/// Tracks helper servers that repeatedly fail so recovery can prefer healthier
/// endpoints without blocking voting when every helper is degraded.
final votingHelperHealthTrackerProvider = Provider<VotingHelperHealthTracker>((
  ref,
) {
  return VotingHelperHealthTracker();
});

/// Optional off-chain endorser source for poll-list badges.
final votingEndorserClientProvider = Provider.family<VotingEndorserClient, Uri>(
  (ref, baseUrl) {
    return VotingEndorserClient(
      endorsedSetUrl: _shieldedVoteUri(baseUrl, const [
        'endorsed-rounds',
        'zodl',
      ]),
      httpClient: ref.watch(votingHttpClientProvider),
    );
  },
);

/// Resolves PIR endpoints before proof generation.
final votingPirResolverProvider = Provider<PirSnapshotResolver>((ref) {
  return PirSnapshotResolver(httpClient: ref.watch(votingHttpClientProvider));
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

/// Narrow interface over Rust voting work used by the session state machine.
///
/// Keeping this boundary explicit lets tests verify sequencing, recovery skips,
/// and progress forwarding without invoking FRB or cryptographic proof work.
abstract interface class VotingRustApi {
  Future<rust_wire.BundleSetupResultView> setupDelegationBundles({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required rust_wire.VotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    int? maxRealNotesPerBundle,
  });

  Future<rust_wire.DelegationPirPrecomputeResultView> precomputeDelegationPir({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_wire.VotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> seedBytes,
    required int bundleIndex,
    int? maxRealNotesPerBundle,
  });

  Stream<rust_voting.ApiDelegationProofEvent>
  buildProveAndSignDelegationPayloadWithProgress({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_wire.VotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> seedBytes,
    required int bundleIndex,
    int? maxRealNotesPerBundle,
  });

  Future<List<int>> generateVotingHotkey({required String network});

  Future<rust_wire.KeystoneDelegationRequestView>
  buildKeystoneDelegationRequest({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required rust_wire.VotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> hotkeySeed,
    required int bundleIndex,
    int? maxRealNotesPerBundle,
  });

  Future<List<int>> extractPcztSighash({required List<int> pcztBytes});

  Future<List<int>> extractSpendAuthSignatureFromSignedPczt({
    required List<int> signedPcztBytes,
    required int actionIndex,
  });

  Future<void> storeKeystoneSignature({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required List<int> sig,
    required List<int> sighash,
    required List<int> rk,
  });

  Future<List<rust_wire.KeystoneSignatureRecordView>> getKeystoneSignatures({
    required String dbPath,
    required String walletId,
    required String roundId,
  });

  Future<int> deleteSkippedBundles({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int keepCount,
  });

  Stream<rust_voting.ApiDelegationProofEvent>
  buildProveDelegationPayloadWithKeystoneSignatureWithProgress({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_wire.VotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> hotkeySeed,
    required int bundleIndex,
    required List<int> keystoneSig,
    required List<int> keystoneSighash,
    int? maxRealNotesPerBundle,
  });

  Future<String> delegationSubmissionWireJson({
    required rust_wire.SignedDelegationPayloadView submission,
  });

  Future<void> storeDelegationTxHash({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
  });

  Future<void> markDelegationSubmitted({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
  });

  Future<void> markDelegationConfirmed({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
    required int vanLeafPosition,
  });

  Future<rust_voting.ApiDelegationConfirmation> confirmDelegationSubmission({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
    required List<rust_voting.ApiTxEvent> events,
  });

  Future<void> storeVanPosition({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int position,
  });

  Future<int> syncVoteTree({
    required String dbPath,
    required String walletId,
    required String roundId,
    required String nodeUrl,
  });

  Future<rust_wire.VanWitnessView> generateVanWitness({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int anchorHeight,
  });

  /// Clear process-local Rust voting caches for a round or wallet.
  ///
  /// A non-null, non-empty `roundId` clears only prepared delegation PCZTs for
  /// that round. `null` performs account-wide cleanup, including vote-tree sync
  /// state for `walletId`.
  Future<void> resetVotingSessionState({
    required String dbPath,
    required String walletId,
    String? roundId,
  });

  Stream<rust_voting.ApiVoteCommitEvent> buildVoteCommitmentsWithProgress({
    required String dbPath,
    required String walletId,
    required String network,
    required String roundId,
    required int bundleIndex,
    required List<int> hotkeySeed,
    required rust_wire.VanWitnessView vanWitness,
    required List<rust_wire.DraftVoteView> draftVotes,
  });

  Future<rust_wire.SignedVoteCommitmentsView> recoverVoteCommitment({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
  });

  Future<String> voteCommitmentWireJson({
    required rust_wire.VoteCommitmentWire commitment,
  });

  Future<String> voteShareWireJson({
    required rust_wire.VoteShareWire share,
    BigInt? vcTreePosition,
    required BigInt submitAt,
  });

  Future<List<rust_wire.ShareSubmissionPlanView>> planShareSubmissions({
    required int shareCount,
    required List<String> serverUrls,
    required BigInt nowSeconds,
    required BigInt voteEndTimeSeconds,
    BigInt? lastMomentBufferSeconds,
    required bool singleShare,
  });

  Future<int> shareTrackingFlags({
    required rust_wire.ShareDelegationRecordView share,
    required BigInt nowSeconds,
    BigInt? voteEndTimeSeconds,
  });

  Future<BigInt?> nextShareTrackingDelaySeconds({
    required List<rust_wire.ShareDelegationRecordView> shares,
    required BigInt nowSeconds,
  });

  Future<String> recoveredVoteShareWireJson({
    required String commitmentBundleJson,
    required int proposalId,
    required int shareIndex,
    required BigInt vcTreePosition,
    required BigInt submitAt,
  });

  Future<void> markVoteSubmitted({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
  });

  Future<void> markVoteConfirmed({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
    required int vanPosition,
    required BigInt vcTreePosition,
  });

  Future<rust_voting.ApiVoteConfirmation> confirmVoteSubmission({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
    required List<rust_voting.ApiTxEvent> events,
  });

  Future<void> recordShareDelegation({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> sentToUrls,
    required BigInt submitAt,
  });

  Future<void> markShareConfirmed({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
  });

  Future<List<int>> deriveHotkey({
    required List<int> seedBytes,
    required String roundId,
    required String accountUuid,
    required String network,
  });
}

/// Production implementation backed by generated FRB calls.
class FrbVotingRustApi implements VotingRustApi {
  const FrbVotingRustApi();

  @override
  Future<rust_wire.BundleSetupResultView> setupDelegationBundles({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required rust_wire.VotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    int? maxRealNotesPerBundle,
  }) {
    return rust_voting.setupDelegationBundles(
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      network: network,
      roundParams: roundParams,
      roundName: roundName,
      sessionJson: sessionJson,
      accountUuid: accountUuid,
      maxRealNotesPerBundle: maxRealNotesPerBundle,
    );
  }

  @override
  Future<rust_wire.DelegationPirPrecomputeResultView> precomputeDelegationPir({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_wire.VotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> seedBytes,
    required int bundleIndex,
    int? maxRealNotesPerBundle,
  }) {
    return rust_voting.precomputeDelegationPir(
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      pirServerUrl: pirServerUrl,
      network: network,
      roundParams: roundParams,
      roundName: roundName,
      sessionJson: sessionJson,
      accountUuid: accountUuid,
      seedBytes: seedBytes,
      bundleIndex: bundleIndex,
      maxRealNotesPerBundle: maxRealNotesPerBundle,
    );
  }

  @override
  Stream<rust_voting.ApiDelegationProofEvent>
  buildProveAndSignDelegationPayloadWithProgress({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_wire.VotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> seedBytes,
    required int bundleIndex,
    int? maxRealNotesPerBundle,
  }) {
    return rust_voting.buildProveAndSignDelegationPayloadWithProgress(
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      pirServerUrl: pirServerUrl,
      network: network,
      roundParams: roundParams,
      roundName: roundName,
      sessionJson: sessionJson,
      accountUuid: accountUuid,
      seedBytes: seedBytes,
      bundleIndex: bundleIndex,
      maxRealNotesPerBundle: maxRealNotesPerBundle,
    );
  }

  @override
  Future<List<int>> generateVotingHotkey({required String network}) {
    return rust_voting.generateVotingHotkey(network: network);
  }

  @override
  Future<rust_wire.KeystoneDelegationRequestView>
  buildKeystoneDelegationRequest({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required rust_wire.VotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> hotkeySeed,
    required int bundleIndex,
    int? maxRealNotesPerBundle,
  }) {
    return rust_voting.buildKeystoneDelegationRequest(
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      network: network,
      roundParams: roundParams,
      roundName: roundName,
      sessionJson: sessionJson,
      accountUuid: accountUuid,
      hotkeySeed: hotkeySeed,
      bundleIndex: bundleIndex,
      maxRealNotesPerBundle: maxRealNotesPerBundle,
    );
  }

  @override
  Future<List<int>> extractPcztSighash({required List<int> pcztBytes}) {
    return rust_voting.extractPcztSighash(pcztBytes: pcztBytes);
  }

  @override
  Future<List<int>> extractSpendAuthSignatureFromSignedPczt({
    required List<int> signedPcztBytes,
    required int actionIndex,
  }) {
    return rust_voting.extractSpendAuthSignatureFromSignedPczt(
      signedPcztBytes: signedPcztBytes,
      actionIndex: actionIndex,
    );
  }

  @override
  Future<void> storeKeystoneSignature({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required List<int> sig,
    required List<int> sighash,
    required List<int> rk,
  }) {
    return rust_voting.storeKeystoneSignature(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      sig: sig,
      sighash: sighash,
      rk: rk,
    );
  }

  @override
  Future<List<rust_wire.KeystoneSignatureRecordView>> getKeystoneSignatures({
    required String dbPath,
    required String walletId,
    required String roundId,
  }) {
    return rust_voting.getKeystoneSignatures(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }

  @override
  Future<int> deleteSkippedBundles({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int keepCount,
  }) {
    return rust_voting.deleteSkippedBundles(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      keepCount: keepCount,
    );
  }

  @override
  Stream<rust_voting.ApiDelegationProofEvent>
  buildProveDelegationPayloadWithKeystoneSignatureWithProgress({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_wire.VotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> hotkeySeed,
    required int bundleIndex,
    required List<int> keystoneSig,
    required List<int> keystoneSighash,
    int? maxRealNotesPerBundle,
  }) {
    return rust_voting
        .buildProveDelegationPayloadWithKeystoneSignatureWithProgress(
          dbPath: dbPath,
          lightwalletdUrl: lightwalletdUrl,
          pirServerUrl: pirServerUrl,
          network: network,
          roundParams: roundParams,
          roundName: roundName,
          sessionJson: sessionJson,
          accountUuid: accountUuid,
          hotkeySeed: hotkeySeed,
          bundleIndex: bundleIndex,
          keystoneSig: keystoneSig,
          keystoneSighash: keystoneSighash,
          maxRealNotesPerBundle: maxRealNotesPerBundle,
        );
  }

  @override
  Future<String> delegationSubmissionWireJson({
    required rust_wire.SignedDelegationPayloadView submission,
  }) {
    return rust_voting.delegationSubmissionWireJson(submission: submission);
  }

  @override
  Future<void> storeDelegationTxHash({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
  }) {
    return rust_voting.storeDelegationTxHash(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      txHash: txHash,
    );
  }

  @override
  Future<void> markDelegationSubmitted({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
  }) {
    return rust_voting.markDelegationSubmitted(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      txHash: txHash,
    );
  }

  @override
  Future<void> markDelegationConfirmed({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
    required int vanLeafPosition,
  }) {
    return rust_voting.markDelegationConfirmed(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      txHash: txHash,
      vanLeafPosition: vanLeafPosition,
    );
  }

  @override
  Future<rust_voting.ApiDelegationConfirmation> confirmDelegationSubmission({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
    required List<rust_voting.ApiTxEvent> events,
  }) {
    return rust_voting.confirmDelegationSubmission(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      txHash: txHash,
      events: events,
    );
  }

  @override
  Future<void> storeVanPosition({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int position,
  }) {
    return rust_voting.storeVanPosition(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      position: position,
    );
  }

  @override
  Future<int> syncVoteTree({
    required String dbPath,
    required String walletId,
    required String roundId,
    required String nodeUrl,
  }) {
    return rust_voting.syncVoteTree(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      nodeUrl: nodeUrl,
    );
  }

  @override
  Future<rust_wire.VanWitnessView> generateVanWitness({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int anchorHeight,
  }) {
    return rust_voting.generateVanWitness(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      anchorHeight: anchorHeight,
    );
  }

  @override
  Future<void> resetVotingSessionState({
    required String dbPath,
    required String walletId,
    String? roundId,
  }) {
    return rust_voting.resetVotingSessionState(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
    );
  }

  @override
  Stream<rust_voting.ApiVoteCommitEvent> buildVoteCommitmentsWithProgress({
    required String dbPath,
    required String walletId,
    required String network,
    required String roundId,
    required int bundleIndex,
    required List<int> hotkeySeed,
    required rust_wire.VanWitnessView vanWitness,
    required List<rust_wire.DraftVoteView> draftVotes,
  }) {
    return rust_voting.buildVoteCommitmentsWithProgress(
      dbPath: dbPath,
      walletId: walletId,
      network: network,
      roundId: roundId,
      bundleIndex: bundleIndex,
      hotkeySeed: hotkeySeed,
      vanWitness: vanWitness,
      draftVotes: draftVotes,
    );
  }

  @override
  Future<rust_wire.SignedVoteCommitmentsView> recoverVoteCommitment({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
  }) {
    return rust_voting.recoverVoteCommitment(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
    );
  }

  @override
  Future<String> voteCommitmentWireJson({
    required rust_wire.VoteCommitmentWire commitment,
  }) {
    return rust_voting.voteCommitmentWireJson(commitment: commitment);
  }

  @override
  Future<String> voteShareWireJson({
    required rust_wire.VoteShareWire share,
    BigInt? vcTreePosition,
    required BigInt submitAt,
  }) {
    return rust_voting.voteShareWireJson(
      share: share,
      vcTreePosition: vcTreePosition,
      submitAt: submitAt,
    );
  }

  @override
  Future<List<rust_wire.ShareSubmissionPlanView>> planShareSubmissions({
    required int shareCount,
    required List<String> serverUrls,
    required BigInt nowSeconds,
    required BigInt voteEndTimeSeconds,
    BigInt? lastMomentBufferSeconds,
    required bool singleShare,
  }) {
    return rust_voting.planShareSubmissions(
      shareCount: shareCount,
      serverUrls: serverUrls,
      nowSeconds: nowSeconds,
      voteEndTimeSeconds: voteEndTimeSeconds,
      lastMomentBufferSeconds: lastMomentBufferSeconds,
      singleShare: singleShare,
    );
  }

  @override
  Future<int> shareTrackingFlags({
    required rust_wire.ShareDelegationRecordView share,
    required BigInt nowSeconds,
    BigInt? voteEndTimeSeconds,
  }) {
    return rust_voting.shareTrackingFlags(
      share: share,
      nowSeconds: nowSeconds,
      voteEndTimeSeconds: voteEndTimeSeconds,
    );
  }

  @override
  Future<BigInt?> nextShareTrackingDelaySeconds({
    required List<rust_wire.ShareDelegationRecordView> shares,
    required BigInt nowSeconds,
  }) {
    return rust_voting.nextShareTrackingDelaySeconds(
      shares: shares,
      nowSeconds: nowSeconds,
    );
  }

  @override
  Future<String> recoveredVoteShareWireJson({
    required String commitmentBundleJson,
    required int proposalId,
    required int shareIndex,
    required BigInt vcTreePosition,
    required BigInt submitAt,
  }) {
    return rust_voting.recoveredVoteShareWireJson(
      commitmentBundleJson: commitmentBundleJson,
      proposalId: proposalId,
      shareIndex: shareIndex,
      vcTreePosition: vcTreePosition,
      submitAt: submitAt,
    );
  }

  @override
  Future<void> markVoteSubmitted({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
  }) {
    return rust_voting.markVoteSubmitted(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      txHash: txHash,
    );
  }

  @override
  Future<void> markVoteConfirmed({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
    required int vanPosition,
    required BigInt vcTreePosition,
  }) {
    return rust_voting.markVoteConfirmed(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      txHash: txHash,
      vanPosition: vanPosition,
      vcTreePosition: vcTreePosition,
    );
  }

  @override
  Future<rust_voting.ApiVoteConfirmation> confirmVoteSubmission({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
    required List<rust_voting.ApiTxEvent> events,
  }) {
    return rust_voting.confirmVoteSubmission(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      txHash: txHash,
      events: events,
    );
  }

  @override
  Future<void> recordShareDelegation({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> sentToUrls,
    required BigInt submitAt,
  }) {
    return rust_voting.recordShareDelegation(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      shareIndex: shareIndex,
      sentToUrls: sentToUrls,
      submitAt: submitAt,
    );
  }

  @override
  Future<void> markShareConfirmed({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
  }) {
    return rust_voting.markShareConfirmed(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      shareIndex: shareIndex,
    );
  }

  @override
  Future<List<int>> deriveHotkey({
    required List<int> seedBytes,
    required String roundId,
    required String accountUuid,
    required String network,
  }) {
    return rust_voting.deriveVotingHotkey(
      seedBytes: seedBytes,
      roundId: roundId,
      accountUuid: accountUuid,
      network: network,
    );
  }
}

Uri _shieldedVoteUri(Uri baseUrl, List<String> pathSegments) {
  final baseSegments = baseUrl.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  return baseUrl.replace(
    pathSegments: [...baseSegments, 'shielded-vote', 'v1', ...pathSegments],
  );
}
