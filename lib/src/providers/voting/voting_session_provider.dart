import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_resume_plan.dart';
import '../../rust/api/voting.dart' as rust_voting;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/voting_models.dart';
import 'voting_config_provider.dart';
import 'voting_service_providers.dart';
import 'voting_state.dart';

/// Orchestrates one round's voting lifecycle for the UI.
///
/// The notifier is intentionally recovery-first: every public action reloads
/// persisted Rust recovery state before deciding which bundle/proposal/share
/// work is still safe to run. Network/proof actions are serialized through
/// [_enqueue] so repeated button taps cannot overlap Rust wallet mutations.
class VotingSessionNotifier extends AsyncNotifier<VotingSessionState> {
  VotingSessionNotifier(this._roundId);

  Future<void> _operation = Future.value();
  final String _roundId;

  @override
  Future<VotingSessionState> build() async {
    final context = await _loadContext(_roundId);
    return VotingSessionState(
      roundId: _roundId,
      config: context.config,
      round: context.round,
      resumePlan: context.resumePlan,
      phase: _phaseForResumePlan(context.resumePlan),
    );
  }

  Future<void> prepareDelegation() {
    return _enqueue(_prepareDelegationUnlocked);
  }

  Future<void> delegatePendingBundles({required List<int> seedBytes}) {
    return _enqueue(() async {
      var current = await future;
      if (current.pirEndpoint == null) {
        await _prepareDelegationUnlocked();
        current = await future;
        if (current.phase == VotingSessionPhase.error) return;
      }

      final context = await _loadContext(_roundId);
      final plan = current.resumePlan ?? context.resumePlan;
      final pirEndpoint = current.pirEndpoint;
      if (pirEndpoint == null) {
        _setError('PIR endpoint has not been resolved.');
        return;
      }

      final progress = Map<int, VotingSessionProgress>.from(
        current.delegationProgress,
      );
      for (final bundleIndex in plan.pendingDelegationBundleIndexes) {
        state = AsyncData(
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.delegating,
            currentBundleIndex: bundleIndex,
          ),
        );
        await for (final event
            in ref
                .read(votingRustApiProvider)
                .buildAndProveDelegationBundleWithProgress(
                  dbPath: context.dbPath,
                  lightwalletdUrl: context.lightwalletdUrl,
                  pirServerUrl: pirEndpoint.toString(),
                  network: context.network,
                  roundParams: context.round.toRoundParams(),
                  roundName: context.round.title,
                  sessionJson: context.round.sessionJson,
                  accountUuid: context.accountUuid,
                  seedBytes: seedBytes,
                  bundleIndex: bundleIndex,
                )) {
          progress[bundleIndex] = VotingSessionProgress(
            phase: event.phase,
            bundleIndex: bundleIndex,
            message: event.txidHex,
          );
          state = AsyncData(
            (state.value ?? current).copyWith(delegationProgress: progress),
          );
        }
      }

      final refreshedPlan = await _loadResumePlan(context);
      final nextPhase = refreshedPlan.pendingDelegationBundleIndexes.isEmpty
          ? VotingSessionPhase.delegated
          : VotingSessionPhase.readyToDelegate;
      state = AsyncData(
        (state.value ?? current).copyWith(
          phase: nextPhase,
          resumePlan: refreshedPlan,
          delegationProgress: progress,
          clearCurrentBundleIndex: true,
        ),
      );
    });
  }

  Future<void> castVotes({required List<rust_voting.ApiDraftVote> draftVotes}) {
    return _enqueue(() async {
      final current = await future;
      final context = await _loadContext(_roundId);
      final hotkeySeed = await ref
          .read(votingHotkeyStoreProvider)
          .readHotkey(
            accountUuid: context.accountUuid,
            roundId: context.round.roundId,
          );

      state = AsyncData(
        current.copyWith(phase: VotingSessionPhase.syncingVoteTree),
      );
      final anchorHeight = await ref
          .read(votingRustApiProvider)
          .syncVoteTree(
            dbPath: context.dbPath,
            walletId: context.accountUuid,
            roundId: context.round.roundId,
            nodeUrl: context.config.apiBaseUrl.toString(),
          );

      final progress = Map<VotingVoteKey, VotingSessionProgress>.from(
        current.voteProgress,
      );
      final pendingBundles = _pendingVoteBundleIndexes(
        current.resumePlan ?? context.resumePlan,
      );
      for (final bundleIndex in pendingBundles) {
        final witness = await ref
            .read(votingRustApiProvider)
            .generateVanWitness(
              dbPath: context.dbPath,
              walletId: context.accountUuid,
              roundId: context.round.roundId,
              bundleIndex: bundleIndex,
              anchorHeight: anchorHeight,
            );
        state = AsyncData(
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.castingVotes,
            currentBundleIndex: bundleIndex,
          ),
        );
        await for (final event
            in ref
                .read(votingRustApiProvider)
                .buildVoteCommitmentsWithProgress(
                  dbPath: context.dbPath,
                  walletId: context.accountUuid,
                  network: context.network,
                  roundId: context.round.roundId,
                  bundleIndex: bundleIndex,
                  hotkeySeed: hotkeySeed,
                  vanWitness: witness,
                  draftVotes: draftVotes,
                )) {
          final proposalId = event.proposalId;
          if (proposalId != null) {
            final key = VotingVoteKey(
              bundleIndex: event.bundleIndex ?? bundleIndex,
              proposalId: proposalId,
            );
            progress[key] = VotingSessionProgress(
              phase: event.phase,
              bundleIndex: key.bundleIndex,
              proposalId: proposalId,
            );
            state = AsyncData(
              (state.value ?? current).copyWith(
                voteProgress: progress,
                currentVoteKey: key,
              ),
            );
          }
        }
      }

      final refreshedPlan = await _loadResumePlan(context);
      state = AsyncData(
        (state.value ?? current).copyWith(
          phase: VotingSessionPhase.submittingShares,
          resumePlan: refreshedPlan,
          voteProgress: progress,
          clearCurrentBundleIndex: true,
          clearCurrentVoteKey: true,
        ),
      );
    });
  }

  Future<void> submitPendingShares() {
    return _enqueue(() async {
      final current = await future;
      final context = await _loadContext(_roundId);
      final plan = current.resumePlan ?? context.resumePlan;
      state = AsyncData(
        current.copyWith(phase: VotingSessionPhase.submittingShares),
      );

      for (final share in plan.unconfirmedShareDelegations) {
        if (share.sentToUrls.isEmpty) continue;
        final status = await ref
            .read(votingApiClientProvider(context.config.apiBaseUrl))
            .getShareStatus(
              roundId: share.roundId,
              serverUrl: Uri.parse(share.sentToUrls.first),
              shareId: _hexFromBytes(share.nullifier),
            );
        if (status.status == 'confirmed') {
          await ref
              .read(votingRustApiProvider)
              .markShareConfirmed(
                dbPath: context.dbPath,
                walletId: context.accountUuid,
                roundId: share.roundId,
                bundleIndex: share.bundleIndex,
                proposalId: share.proposalId,
                shareIndex: share.shareIndex,
              );
        }
      }

      final refreshedPlan = await _loadResumePlan(context);
      state = AsyncData(
        (state.value ?? current).copyWith(
          phase: refreshedPlan.hasPendingWork
              ? _phaseForResumePlan(refreshedPlan)
              : VotingSessionPhase.done,
          resumePlan: refreshedPlan,
        ),
      );
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _operation.then((_) async {
      try {
        await action();
      } catch (e) {
        _setError('Voting session action failed.', cause: e);
        rethrow;
      }
    });
    _operation = next.catchError((_) {});
    return next;
  }

  Future<void> _prepareDelegationUnlocked() async {
    final current = await future;
    final context = await _loadContext(_roundId);
    state = AsyncData(
      current.copyWith(
        phase: VotingSessionPhase.resolvingPir,
        config: context.config,
        round: context.round,
        resumePlan: context.resumePlan,
        clearError: true,
      ),
    );

    final resolver = ref.read(votingPirResolverProvider);
    late final PirSnapshotResolution resolution;
    try {
      resolution = await resolver.resolve(
        endpoints: context.config.pirEndpointUrls,
        expectedSnapshotHeight: context.round.snapshotHeight,
      );
    } on PirSnapshotNoMatchingEndpoint catch (e) {
      _setError(
        'No PIR endpoint matched snapshot height ${e.expectedSnapshotHeight}.',
        cause: e,
        pirDiagnostics: e.diagnostics,
      );
      return;
    } catch (e) {
      _setError('Failed to resolve PIR endpoint.', cause: e);
      return;
    }

    state = AsyncData(
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.loadingWitnesses,
        pirEndpoint: resolution.endpoint,
        pirDiagnostics: resolution.diagnostics,
        config: context.config,
        round: context.round,
        resumePlan: context.resumePlan,
      ),
    );

    await ref
        .read(votingRustApiProvider)
        .setupDelegationBundles(
          dbPath: context.dbPath,
          lightwalletdUrl: context.lightwalletdUrl,
          network: context.network,
          roundParams: context.round.toRoundParams(),
          roundName: context.round.title,
          sessionJson: context.round.sessionJson,
          accountUuid: context.accountUuid,
        );
    final refreshedPlan = await _loadResumePlan(context);
    state = AsyncData(
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.readyToDelegate,
        resumePlan: refreshedPlan,
      ),
    );
  }

  Future<_VotingSessionContext> _loadContext(String roundId) async {
    final config = await ref.read(votingConfigProvider.future);
    final api = ref.read(votingApiClientProvider(config.apiBaseUrl));
    final round = VotingRoundDetails.fromStatus(
      await api.getRoundStatus(roundId),
    );
    final accountUuid = await ref.read(votingActiveAccountUuidProvider).call();
    if (accountUuid == null) {
      throw StateError('No active account for voting session.');
    }
    final endpoint = ref.read(votingRpcEndpointConfigProvider);
    final dbPath = await ref.read(votingWalletDbPathProvider).call();
    final context = _VotingSessionContext(
      dbPath: dbPath,
      accountUuid: accountUuid,
      network: endpoint.networkName,
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      config: config,
      round: round,
      resumePlan: await ref
          .read(votingRecoveryServiceProvider)
          .loadResumePlan(
            dbPath: dbPath,
            walletId: accountUuid,
            roundId: round.roundId,
          ),
    );
    return context;
  }

  Future<VotingResumePlan> _loadResumePlan(_VotingSessionContext context) {
    return ref
        .read(votingRecoveryServiceProvider)
        .loadResumePlan(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
        );
  }

  void _setError(
    String message, {
    Object? cause,
    List<PirSnapshotEndpointDiagnostic> pirDiagnostics = const [],
  }) {
    final current = state.value ?? VotingSessionState(roundId: _roundId);
    state = AsyncData(
      current.copyWith(
        phase: VotingSessionPhase.error,
        error: VotingSessionError(
          message: message,
          cause: cause,
          pirDiagnostics: pirDiagnostics,
        ),
        pirDiagnostics: pirDiagnostics,
      ),
    );
  }

  static VotingSessionPhase _phaseForResumePlan(VotingResumePlan plan) {
    if (plan.pendingDelegationBundleIndexes.isNotEmpty) {
      return VotingSessionPhase.readyToDelegate;
    }
    if (plan.pendingVoteSubmissionKeys.isNotEmpty ||
        plan.incompleteVoteRecoveryKeys.isNotEmpty) {
      return VotingSessionPhase.readyToVote;
    }
    if (plan.unconfirmedShareDelegations.isNotEmpty) {
      return VotingSessionPhase.submittingShares;
    }
    return VotingSessionPhase.done;
  }

  static Set<int> _pendingVoteBundleIndexes(VotingResumePlan plan) {
    if (plan.pendingVoteSubmissionKeys.isNotEmpty) {
      return plan.pendingVoteSubmissionKeys
          .map((key) => key.bundleIndex)
          .toSet();
    }
    final bundleCount = plan.bundleCount;
    if (bundleCount == 0) return const {};
    return {for (var i = 0; i < bundleCount; i++) i};
  }

  static String _hexFromBytes(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _VotingSessionContext {
  final String dbPath;
  final String accountUuid;
  final String network;
  final String lightwalletdUrl;
  final VotingConfig config;
  final VotingRoundDetails round;
  final VotingResumePlan resumePlan;

  const _VotingSessionContext({
    required this.dbPath,
    required this.accountUuid,
    required this.network,
    required this.lightwalletdUrl,
    required this.config,
    required this.round,
    required this.resumePlan,
  });
}

final votingSessionProvider =
    AsyncNotifierProvider.family<
      VotingSessionNotifier,
      VotingSessionState,
      String
    >(VotingSessionNotifier.new);
