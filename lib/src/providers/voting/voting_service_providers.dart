import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_recovery_service.dart';
import '../../core/config/rpc_endpoint_config.dart';
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

/// Secret hotkey access, filled in by ZCA-391.
final votingHotkeyStoreProvider = Provider<VotingHotkeyStore>((ref) {
  return const UnavailableVotingHotkeyStore();
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

/// Reads per-account, per-round voting hotkeys.
///
/// Production storage is intentionally blocked on ZCA-391 so this interface can
/// be tested now without inventing secure-storage behavior in the provider task.
abstract interface class VotingHotkeyStore {
  Future<List<int>> readHotkey({
    required String accountUuid,
    required String roundId,
  });
}

/// Raised when a flow reaches hotkey-dependent work before ZCA-391 is wired.
class VotingHotkeyUnavailable implements Exception {
  final String message;

  const VotingHotkeyUnavailable([
    this.message = 'Voting hotkey storage is not available yet.',
  ]);

  @override
  String toString() => 'VotingHotkeyUnavailable: $message';
}

/// Placeholder production adapter until secure hotkey storage lands.
class UnavailableVotingHotkeyStore implements VotingHotkeyStore {
  const UnavailableVotingHotkeyStore();

  @override
  Future<List<int>> readHotkey({
    required String accountUuid,
    required String roundId,
  }) {
    throw const VotingHotkeyUnavailable();
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
}

Uri _shieldedVoteUri(Uri baseUrl, List<String> pathSegments) {
  final baseSegments = baseUrl.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList();
  return baseUrl.replace(
    pathSegments: [...baseSegments, 'shielded-vote', 'v1', ...pathSegments],
  );
}
