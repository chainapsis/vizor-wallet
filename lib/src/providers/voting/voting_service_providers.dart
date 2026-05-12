import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_recovery_service.dart';
import '../../core/config/rpc_endpoint_config.dart';
import '../../core/storage/app_secure_store.dart';
import '../../core/storage/wallet_paths.dart';
import '../../providers/account_provider.dart';
import '../../providers/rpc_endpoint_provider.dart';
import '../../rust/api/voting.dart' as rust_voting;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/voting_api_client.dart';
import '../../services/voting/voting_config_loader.dart';
import '../../services/voting/voting_endorser_client.dart';
import '../../services/voting/voting_http.dart';

/// Transport shared by the voting service clients.
final votingHttpClientProvider = Provider<VotingHttpClient>((ref) {
  final client = DartIoVotingHttpClient();
  ref.onDispose(client.close);
  return client;
});

/// Loads the hash-pinned static config and dynamic voting config.
final votingConfigLoaderProvider = Provider<VotingConfigLoader>((ref) {
  return VotingConfigLoader(httpClient: ref.watch(votingHttpClientProvider));
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
  return () async => (await ref.read(accountProvider.future)).activeAccountUuid;
});

/// Current lightwalletd/network configuration for Rust voting calls.
final votingRpcEndpointConfigProvider = Provider<RpcEndpointConfig>((ref) {
  return ref.watch(rpcEndpointProvider);
});

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
  Future<rust_voting.ApiVotingBundleSetupResult> setupDelegationBundles({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
  });

  Future<rust_voting.ApiDelegationPirPrecomputeResult> precomputeDelegationPir({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> seedBytes,
    required int bundleIndex,
  });

  Stream<rust_voting.ApiDelegationProofEvent>
  buildAndProveDelegationBundleWithProgress({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> seedBytes,
    required int bundleIndex,
  });

  Future<void> storeDelegationTxHash({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required String txHash,
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

  Future<rust_voting.ApiVanWitness> generateVanWitness({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int anchorHeight,
  });

  Stream<rust_voting.ApiVoteCommitEvent> buildVoteCommitmentsWithProgress({
    required String dbPath,
    required String walletId,
    required String network,
    required String roundId,
    required int bundleIndex,
    required List<int> hotkeySeed,
    required rust_voting.ApiVanWitness vanWitness,
    required List<rust_voting.ApiDraftVote> draftVotes,
  });

  Future<void> storeVoteTxHash({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
  });

  Future<void> storeCommitmentBundle({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String commitmentBundleJson,
    required BigInt vcTreePosition,
  });

  Future<void> recordShareDelegation({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required int shareIndex,
    required List<String> sentToUrls,
    required List<int> nullifier,
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

  Future<String> computeShareNullifierHex({
    required List<int> voteCommitment,
    required int shareIndex,
    required List<int> primaryBlind,
  });

  Future<List<int>> deriveHotkey({
    required List<int> seedBytes,
    required String roundId,
    required String accountUuid,
  });
}

/// Production implementation backed by generated FRB calls.
class FrbVotingRustApi implements VotingRustApi {
  const FrbVotingRustApi();

  @override
  Future<rust_voting.ApiVotingBundleSetupResult> setupDelegationBundles({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
  }) {
    return rust_voting.setupDelegationBundles(
      dbPath: dbPath,
      lightwalletdUrl: lightwalletdUrl,
      network: network,
      roundParams: roundParams,
      roundName: roundName,
      sessionJson: sessionJson,
      accountUuid: accountUuid,
    );
  }

  @override
  Future<rust_voting.ApiDelegationPirPrecomputeResult> precomputeDelegationPir({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> seedBytes,
    required int bundleIndex,
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
    );
  }

  @override
  Stream<rust_voting.ApiDelegationProofEvent>
  buildAndProveDelegationBundleWithProgress({
    required String dbPath,
    required String lightwalletdUrl,
    required String pirServerUrl,
    required String network,
    required rust_voting.ApiVotingRoundParams roundParams,
    required String roundName,
    String? sessionJson,
    required String accountUuid,
    required List<int> seedBytes,
    required int bundleIndex,
  }) {
    return rust_voting.buildAndProveDelegationBundleWithProgress(
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
    );
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
  Future<rust_voting.ApiVanWitness> generateVanWitness({
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
  Stream<rust_voting.ApiVoteCommitEvent> buildVoteCommitmentsWithProgress({
    required String dbPath,
    required String walletId,
    required String network,
    required String roundId,
    required int bundleIndex,
    required List<int> hotkeySeed,
    required rust_voting.ApiVanWitness vanWitness,
    required List<rust_voting.ApiDraftVote> draftVotes,
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
  Future<void> storeVoteTxHash({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String txHash,
  }) {
    return rust_voting.storeVoteTxHash(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      txHash: txHash,
    );
  }

  @override
  Future<void> storeCommitmentBundle({
    required String dbPath,
    required String walletId,
    required String roundId,
    required int bundleIndex,
    required int proposalId,
    required String commitmentBundleJson,
    required BigInt vcTreePosition,
  }) {
    return rust_voting.storeCommitmentBundle(
      dbPath: dbPath,
      walletId: walletId,
      roundId: roundId,
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      commitmentBundleJson: commitmentBundleJson,
      vcTreePosition: vcTreePosition,
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
    required List<int> nullifier,
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
      nullifier: nullifier,
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
  Future<String> computeShareNullifierHex({
    required List<int> voteCommitment,
    required int shareIndex,
    required List<int> primaryBlind,
  }) {
    return rust_voting.computeShareNullifierHex(
      voteCommitment: voteCommitment,
      shareIndex: shareIndex,
      primaryBlind: primaryBlind,
    );
  }

  @override
  Future<List<int>> deriveHotkey({
    required List<int> seedBytes,
    required String roundId,
    required String accountUuid,
  }) {
    return rust_voting.deriveVotingHotkey(
      seedBytes: seedBytes,
      roundId: roundId,
      accountUuid: accountUuid,
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
