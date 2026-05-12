import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_resume_plan.dart';
import '../../rust/api/voting.dart' as rust_voting;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/voting_api_client.dart';
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

  static final Random _submitAtRandom = Random.secure();

  Future<void> _operation = Future.value();
  final String _roundId;
  final Map<String, Future<void>> _delegationPirPrecomputes = {};
  String? _sessionAccountUuid;

  @override
  Future<VotingSessionState> build() async {
    await _accountUuidForSession();
    final context = await _loadContext(_roundId);
    final rust = ref.read(votingRustApiProvider);
    ref.onDispose(() {
      // Provider disposal is round-scoped: clear abandoned prepared PCZTs but
      // keep account-wide vote-tree sync state reusable across rounds.
      _delegationPirPrecomputes.clear();
      unawaited(
        _resetVotingSessionState(
          rust: rust,
          context: context,
          reason: 'provider-dispose',
        ),
      );
    });
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

  Future<void> precomputeDelegationPir({required List<int> seedBytes}) async {
    final context = await _loadContext(_roundId);
    final pirEndpoint = await _resolvePirEndpoint(context);
    if (pirEndpoint == null) return;

    final rust = ref.read(votingRustApiProvider);
    final bundleSetup = await rust.setupDelegationBundles(
      dbPath: context.dbPath,
      lightwalletdUrl: context.lightwalletdUrl,
      network: context.network,
      roundParams: context.round.toRoundParams(),
      roundName: context.round.title,
      sessionJson: context.round.sessionJson,
      accountUuid: context.accountUuid,
    );
    final plan = await _loadResumePlan(context);
    final pendingBundles = plan.pendingDelegationBundleIndexes.isNotEmpty
        ? plan.pendingDelegationBundleIndexes
        : [for (var i = 0; i < bundleSetup.bundleCount; i++) i];

    for (final bundleIndex in pendingBundles) {
      final key = _delegationPirPrecomputeKey(context, bundleIndex);
      _delegationPirPrecomputes[key] ??= _runDelegationPirPrecompute(
        context: context,
        pirEndpoint: pirEndpoint,
        seedBytes: List<int>.from(seedBytes),
        bundleIndex: bundleIndex,
      );
    }
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
      await _ensureHotkey(context, seedBytes);

      final progress = Map<int, VotingSessionProgress>.from(
        current.delegationProgress,
      );
      final completedBundleIndexes = <int>{};
      final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
      final rust = ref.read(votingRustApiProvider);
      final submittedDelegationsByBundle = {
        for (final record in plan.recoveryState.delegationWorkflows)
          if (record.phase == VotingWorkflowPhase.submittedDelegation &&
              record.txHash != null)
            record.bundleIndex: record.txHash!,
      };
      for (final entry in submittedDelegationsByBundle.entries) {
        final bundleIndex = entry.key;
        final txHash = entry.value;
        final confirmation = await _awaitTxConfirmation(api, txHash);
        if (confirmation == null) {
          _setError(
            'Delegation transaction $txHash for bundle $bundleIndex is still '
            'unconfirmed after repeated checks. Retry to resume confirmation '
            'before continuing.',
          );
          return;
        }
        if (confirmation.code != 0) {
          throw StateError(
            confirmation.log.isEmpty
                ? 'Delegation transaction failed.'
                : confirmation.log,
          );
        }
        final leafIndex = int.tryParse(
          confirmation.event('delegate_vote')?.attribute('leaf_index') ?? '',
        );
        if (leafIndex == null) {
          throw StateError(
            'Missing delegate_vote leaf_index for bundle $bundleIndex.',
          );
        }
        await rust.markDelegationConfirmed(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
          bundleIndex: bundleIndex,
          txHash: txHash,
          vanLeafPosition: leafIndex,
        );
        completedBundleIndexes.add(bundleIndex);
        progress[bundleIndex] = VotingSessionProgress(
          phase: 'confirmed',
          bundleIndex: bundleIndex,
          message: txHash,
        );
      }
      for (final bundleIndex in plan.pendingDelegationBundleIndexes) {
        await _awaitDelegationPirPrecomputeIfRunning(context, bundleIndex);
        final bundleTimer = Stopwatch()..start();
        debugPrint(
          '[zcash] Voting: delegation bundle start '
          'round=${context.round.roundId} bundle=$bundleIndex',
        );
        state = AsyncData(
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.delegating,
            currentBundleIndex: bundleIndex,
          ),
        );
        rust_voting.ApiSignedDelegationPayload? signedDelegationPayload;
        await for (final event
            in rust.buildProveAndSignDelegationPayloadWithProgress(
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
          signedDelegationPayload =
              event.signedDelegationPayload ?? signedDelegationPayload;
          progress[bundleIndex] = VotingSessionProgress(
            phase: event.phase,
            bundleIndex: bundleIndex,
            proofProgress: event.proofProgress,
            message: null,
          );
          state = AsyncData(
            (state.value ?? current).copyWith(delegationProgress: progress),
          );
        }
        debugPrint(
          '[zcash] Voting: delegation proof stream completed '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'elapsed=${_formatElapsed(bundleTimer.elapsed)}',
        );
        final submission = signedDelegationPayload;
        if (submission == null) {
          throw StateError(
            'Delegation proof completed without submission payload.',
          );
        }
        final submitTimer = Stopwatch()..start();
        debugPrint(
          '[zcash] Voting: submitting delegation '
          'round=${context.round.roundId} bundle=$bundleIndex',
        );
        final result = await api.submitDelegation(
          submission: _delegationSubmissionJson(submission),
        );
        debugPrint(
          '[zcash] Voting: delegation submit response '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'txHash=${result.txHash} code=${result.code} '
          'elapsed=${_formatElapsed(submitTimer.elapsed)}',
        );
        if (result.code != 0) {
          throw StateError(
            result.log.isEmpty
                ? 'Delegation transaction was rejected.'
                : result.log,
          );
        }
        await rust.markDelegationSubmitted(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
          bundleIndex: bundleIndex,
          txHash: result.txHash,
        );
        debugPrint(
          '[zcash] Voting: delegation tx hash stored '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'txHash=${result.txHash}',
        );
        final confirmation = await _awaitTxConfirmation(api, result.txHash);
        if (confirmation == null) {
          throw StateError(
            'Transaction ${result.txHash} was not confirmed in time.',
          );
        }
        if (confirmation.code != 0) {
          throw StateError(
            confirmation.log.isEmpty
                ? 'Delegation transaction failed.'
                : confirmation.log,
          );
        }
        final leafIndex = int.tryParse(
          confirmation.event('delegate_vote')?.attribute('leaf_index') ?? '',
        );
        if (leafIndex == null) {
          throw StateError(
            'Missing delegate_vote leaf_index for bundle $bundleIndex.',
          );
        }
        await rust.markDelegationConfirmed(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
          bundleIndex: bundleIndex,
          txHash: result.txHash,
          vanLeafPosition: leafIndex,
        );
        debugPrint(
          '[zcash] Voting: delegation bundle completed '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'leafIndex=$leafIndex total=${_formatElapsed(bundleTimer.elapsed)}',
        );
        completedBundleIndexes.add(bundleIndex);
        progress[bundleIndex] = VotingSessionProgress(
          phase: 'submitted',
          bundleIndex: bundleIndex,
          message: result.txHash,
        );
        state = AsyncData(
          (state.value ?? current).copyWith(delegationProgress: progress),
        );
      }

      final resumeTimer = Stopwatch()..start();
      debugPrint(
        '[zcash] Voting: loading resume plan after delegation '
        'round=${context.round.roundId}',
      );
      final refreshedPlan = await _loadResumePlan(context);
      debugPrint(
        '[zcash] Voting: resume plan after delegation loaded '
        'round=${context.round.roundId} '
        'pendingDelegations=${refreshedPlan.pendingDelegationBundleIndexes.length} '
        'pendingVotes=${refreshedPlan.pendingVoteSubmissionKeys.length} '
        'elapsed=${_formatElapsed(resumeTimer.elapsed)}',
      );
      final nextPhase =
          refreshedPlan.pendingDelegationBundleIndexes
              .where((index) => !completedBundleIndexes.contains(index))
              .isEmpty
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
      if (hotkeySeed == null) {
        _setError(
          'Voting hotkey is missing. Delegate this round before casting votes.',
          cause: const VotingHotkeyUnavailable('missing stored hotkey'),
        );
        return;
      }

      final progress = Map<VotingVoteKey, VotingSessionProgress>.from(
        current.voteProgress,
      );
      final plan = current.resumePlan ?? context.resumePlan;
      final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
      final rust = ref.read(votingRustApiProvider);
      final effectiveDraftVotes = _applyLastMomentMode(
        draftVotes,
        context.round,
      );
      for (final key in plan.submittedVoteConfirmationKeys) {
        final txHash = plan.voteTxHashFor(key);
        final commitmentBundle = plan.commitmentBundleFor(key);
        if (txHash == null || commitmentBundle == null) continue;
        final confirmation = await _awaitTxConfirmation(api, txHash);
        if (confirmation == null) {
          _setError(
            'Vote commitment transaction $txHash for bundle '
            '${key.bundleIndex}, proposal ${key.proposalId} is still '
            'unconfirmed after repeated checks. Retry to resume confirmation '
            'before continuing.',
          );
          return;
        }
        if (confirmation.code != 0) {
          throw StateError(
            confirmation.log.isEmpty
                ? 'Vote commitment transaction failed.'
                : confirmation.log,
          );
        }
        final leafPositions = _castVoteLeafPositions(confirmation);
        await rust.markVoteConfirmed(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
          txHash: txHash,
          vanPosition: leafPositions.vanPosition,
          vcTreePosition: leafPositions.vcTreePosition,
          commitmentBundleJson: commitmentBundle.commitmentBundleJson,
        );
        progress[key] = VotingSessionProgress(
          phase: 'confirmed',
          bundleIndex: key.bundleIndex,
          proposalId: key.proposalId,
          message: txHash,
        );
      }
      final pendingBundles = _pendingVoteBundleIndexes(plan);
      debugPrint(
        '[zcash] Voting: cast votes start '
        'round=${context.round.roundId} bundles=${pendingBundles.length} '
        'proposals=${effectiveDraftVotes.length} '
        'lastMoment=${context.round.isLastMoment()}',
      );
      for (final bundleIndex in pendingBundles) {
        for (final draftVote in effectiveDraftVotes) {
          final voteTimer = Stopwatch()..start();
          state = AsyncData(
            (state.value ?? current).copyWith(
              phase: VotingSessionPhase.syncingVoteTree,
              currentBundleIndex: bundleIndex,
            ),
          );
          debugPrint(
            '[zcash] Voting: vote tree sync start '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId}',
          );
          final syncTimer = Stopwatch()..start();
          final anchorHeight = await ref
              .read(votingRustApiProvider)
              .syncVoteTree(
                dbPath: context.dbPath,
                walletId: context.accountUuid,
                roundId: context.round.roundId,
                nodeUrl: context.config.apiBaseUrl.toString(),
              );
          debugPrint(
            '[zcash] Voting: vote tree sync completed '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId} anchorHeight=$anchorHeight '
            'elapsed=${_formatElapsed(syncTimer.elapsed)}',
          );

          final witnessTimer = Stopwatch()..start();
          debugPrint(
            '[zcash] Voting: VAN witness generation start '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId} anchorHeight=$anchorHeight',
          );
          final witness = await ref
              .read(votingRustApiProvider)
              .generateVanWitness(
                dbPath: context.dbPath,
                walletId: context.accountUuid,
                roundId: context.round.roundId,
                bundleIndex: bundleIndex,
                anchorHeight: anchorHeight,
              );
          debugPrint(
            '[zcash] Voting: VAN witness generation completed '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId} position=${witness.position} '
            'elapsed=${_formatElapsed(witnessTimer.elapsed)}',
          );
          state = AsyncData(
            (state.value ?? current).copyWith(
              phase: VotingSessionPhase.castingVotes,
              currentBundleIndex: bundleIndex,
            ),
          );
          debugPrint(
            '[zcash] Voting: ZKP2 commitment stream start '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId}',
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
                    draftVotes: [draftVote],
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
                proofProgress: event.proofProgress,
              );
              state = AsyncData(
                (state.value ?? current).copyWith(
                  voteProgress: progress,
                  currentVoteKey: key,
                ),
              );
            }
            final commitments = event.commitments;
            if (commitments != null) {
              final vcTreePositions = await _submitVoteCommitments(
                context,
                commitments,
              );
              await _submitCommitmentShares(
                context,
                commitments,
                vcTreePositions: vcTreePositions,
              );
            }
          }
          debugPrint(
            '[zcash] Voting: vote flow completed '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId} '
            'total=${_formatElapsed(voteTimer.elapsed)}',
          );
        }
      }

      final resumeTimer = Stopwatch()..start();
      debugPrint(
        '[zcash] Voting: loading resume plan after vote flow '
        'round=${context.round.roundId}',
      );
      final refreshedPlan = await _loadResumePlan(context);
      debugPrint(
        '[zcash] Voting: resume plan after vote flow loaded '
        'round=${context.round.roundId} '
        'pendingVotes=${refreshedPlan.pendingVoteSubmissionKeys.length} '
        'unconfirmedShares=${refreshedPlan.unconfirmedShareDelegations.length} '
        'elapsed=${_formatElapsed(resumeTimer.elapsed)}',
      );
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

  Future<void> _ensureHotkey(
    _VotingSessionContext context,
    List<int> seedBytes,
  ) async {
    final store = ref.read(votingHotkeyStoreProvider);
    final existing = await store.readHotkey(
      accountUuid: context.accountUuid,
      roundId: context.round.roundId,
    );
    if (existing != null && existing.isNotEmpty) return;
    final hotkey = await ref
        .read(votingRustApiProvider)
        .deriveHotkey(
          seedBytes: seedBytes,
          roundId: context.round.roundId,
          accountUuid: context.accountUuid,
        );
    await store.writeHotkey(
      accountUuid: context.accountUuid,
      roundId: context.round.roundId,
      hotkey: hotkey,
    );
  }

  Future<void> _submitCommitmentShares(
    _VotingSessionContext context,
    rust_voting.ApiSignedVoteCommitments commitments, {
    Map<int, BigInt> vcTreePositions = const {},
  }) async {
    final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
    final rust = ref.read(votingRustApiProvider);
    final serverUrls = context.config.voteServers
        .map((endpoint) => endpoint.url)
        .toList(growable: false);
    if (serverUrls.isEmpty) {
      throw StateError('No vote servers configured for share submission.');
    }

    for (final commitment in commitments.commitments) {
      final vcTreePosition = vcTreePositions[commitment.proposalId];
      for (final payload in commitment.sharePayloads) {
        final acceptedServers = <String>[];
        final submitAt = _scheduledShareSubmitAt(context.round);
        final body = _sharePayloadJson(
          payload,
          vcTreePosition: vcTreePosition,
          submitAt: submitAt,
        );
        for (final serverUrl in serverUrls) {
          try {
            debugPrint(
              '[zcash] Voting: submitting share '
              'proposal=${payload.proposalId} share=${payload.encryptedShare.shareIndex} '
              'server=$serverUrl treePosition=${body['tree_position']} '
              'submitAt=$submitAt',
            );
            await api.submitShare(
              roundId: context.round.roundId,
              serverUrl: serverUrl,
              share: body,
            );
            acceptedServers.add(serverUrl.toString());
            debugPrint(
              '[zcash] Voting: share accepted '
              'proposal=${payload.proposalId} share=${payload.encryptedShare.shareIndex} '
              'server=$serverUrl',
            );
          } catch (e) {
            debugPrint(
              '[zcash] Voting: share rejected '
              'proposal=${payload.proposalId} share=${payload.encryptedShare.shareIndex} '
              'server=$serverUrl error=$e',
            );
            // Try every configured helper. A later recovery pass can resubmit
            // to helpers that did not accept this share.
          }
        }
        if (acceptedServers.isEmpty) {
          throw StateError(
            'No vote server accepted share ${payload.encryptedShare.shareIndex} '
            'for proposal ${payload.proposalId}.',
          );
        }

        final nullifierHex = await rust.computeShareNullifierHex(
          voteCommitment: commitment.voteCommitment,
          shareIndex: payload.encryptedShare.shareIndex,
          primaryBlind: payload.primaryBlind,
        );
        await rust.recordShareDelegation(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
          bundleIndex: commitments.bundleIndex,
          proposalId: payload.proposalId,
          shareIndex: payload.encryptedShare.shareIndex,
          sentToUrls: acceptedServers,
          nullifier: _bytesFromHex(nullifierHex),
          submitAt: BigInt.from(submitAt),
        );
      }
    }
  }

  Future<Map<int, BigInt>> _submitVoteCommitments(
    _VotingSessionContext context,
    rust_voting.ApiSignedVoteCommitments commitments,
  ) async {
    final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
    final rust = ref.read(votingRustApiProvider);
    final vcTreePositions = <int, BigInt>{};
    for (final commitment in commitments.commitments) {
      debugPrint(
        '[zcash] Voting: submitting cast-vote '
        'round=${context.round.roundId} bundle=${commitments.bundleIndex} '
        'proposal=${commitment.proposalId}',
      );
      final result = await api.submitVoteCommitment(
        commitment: _voteCommitmentSubmissionJson(commitment),
      );
      debugPrint(
        '[zcash] Voting: cast-vote response '
        'proposal=${commitment.proposalId} txHash=${result.txHash} '
        'code=${result.code} log=${result.log}',
      );
      if (result.code != 0) {
        throw StateError(
          result.log.isEmpty
              ? 'Vote commitment transaction was rejected.'
              : result.log,
        );
      }
      if (result.txHash.isEmpty) {
        throw StateError('Vote commitment response did not include tx_hash.');
      }
      await rust.markVoteSubmitted(
        dbPath: context.dbPath,
        walletId: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: commitments.bundleIndex,
        proposalId: commitment.proposalId,
        txHash: result.txHash,
      );

      final confirmation = await _awaitTxConfirmation(api, result.txHash);
      if (confirmation == null) {
        throw StateError(
          'Transaction ${result.txHash} was not confirmed in time.',
        );
      }
      if (confirmation.code != 0) {
        throw StateError(
          confirmation.log.isEmpty
              ? 'Vote commitment transaction failed.'
              : confirmation.log,
        );
      }

      final leafPositions = _castVoteLeafPositions(confirmation);
      debugPrint(
        '[zcash] Voting: cast-vote confirmed '
        'proposal=${commitment.proposalId} vanPosition=${leafPositions.vanPosition} '
        'vcTreePosition=${leafPositions.vcTreePosition}',
      );
      await rust.markVoteConfirmed(
        dbPath: context.dbPath,
        walletId: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: commitments.bundleIndex,
        proposalId: commitment.proposalId,
        txHash: result.txHash,
        vanPosition: leafPositions.vanPosition,
        commitmentBundleJson: commitment.commitmentBundleJson,
        vcTreePosition: leafPositions.vcTreePosition,
      );
      vcTreePositions[commitment.proposalId] = leafPositions.vcTreePosition;
    }
    return vcTreePositions;
  }

  Future<VotingTxConfirmation?> _awaitTxConfirmation(
    VotingApiClient api,
    String txHash,
  ) async {
    final polling = ref.read(votingTxConfirmationPollingProvider);
    final attempts = polling.attempts;
    final delay = polling.delay;
    final timer = Stopwatch()..start();
    debugPrint('[zcash] Voting: tx confirmation wait start txHash=$txHash');
    for (var attempt = 0; attempt < attempts; attempt++) {
      final confirmation = await api.getTxConfirmation(txHash);
      if (confirmation != null) {
        debugPrint(
          '[zcash] Voting: tx confirmation found txHash=$txHash '
          'attempt=${attempt + 1} code=${confirmation.code} '
          'elapsed=${_formatElapsed(timer.elapsed)}',
        );
        return confirmation;
      }
      if (attempt + 1 < attempts) {
        if (attempt == 0 || (attempt + 1) % 5 == 0) {
          debugPrint(
            '[zcash] Voting: waiting for tx confirmation '
            'txHash=$txHash attempt=${attempt + 1}/$attempts',
          );
        }
        await Future<void>.delayed(delay);
      }
    }
    debugPrint(
      '[zcash] Voting: tx confirmation wait timed out txHash=$txHash '
      'elapsed=${_formatElapsed(timer.elapsed)}',
    );
    return null;
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

  Future<Uri?> _resolvePirEndpoint(_VotingSessionContext context) async {
    final currentEndpoint = state.value?.pirEndpoint;
    if (currentEndpoint != null) return currentEndpoint;

    try {
      final resolution = await ref
          .read(votingPirResolverProvider)
          .resolve(
            endpoints: context.config.pirEndpointUrls,
            expectedSnapshotHeight: context.round.snapshotHeight,
          );
      return resolution.endpoint;
    } catch (e) {
      debugPrint(
        '[zcash] Voting: delegation PIR precompute skipped '
        'round=${context.round.roundId} reason=pir-resolution-failed error=$e',
      );
      return null;
    }
  }

  Future<void> _runDelegationPirPrecompute({
    required _VotingSessionContext context,
    required Uri pirEndpoint,
    required List<int> seedBytes,
    required int bundleIndex,
  }) async {
    final key = _delegationPirPrecomputeKey(context, bundleIndex);
    final timer = Stopwatch()..start();
    debugPrint(
      '[zcash] Voting: delegation PIR precompute start '
      'round=${context.round.roundId} bundle=$bundleIndex',
    );
    try {
      final result = await ref
          .read(votingRustApiProvider)
          .precomputeDelegationPir(
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
          );
      debugPrint(
        '[zcash] Voting: delegation PIR precompute completed '
        'round=${context.round.roundId} bundle=$bundleIndex '
        'cached=${result.cachedCount} fetched=${result.fetchedCount} '
        'elapsed=${_formatElapsed(timer.elapsed)}',
      );
    } catch (e) {
      debugPrint(
        '[zcash] Voting: delegation PIR precompute failed '
        'round=${context.round.roundId} bundle=$bundleIndex '
        'elapsed=${_formatElapsed(timer.elapsed)} error=$e '
        'reason=cache-miss',
      );
    } finally {
      seedBytes.fillRange(0, seedBytes.length, 0);
      _delegationPirPrecomputes.remove(key);
    }
  }

  Future<void> _awaitDelegationPirPrecomputeIfRunning(
    _VotingSessionContext context,
    int bundleIndex,
  ) async {
    final precompute =
        _delegationPirPrecomputes[_delegationPirPrecomputeKey(
          context,
          bundleIndex,
        )];
    if (precompute == null) return;

    debugPrint(
      '[zcash] Voting: waiting for in-flight delegation PIR precompute '
      'round=${context.round.roundId} bundle=$bundleIndex',
    );
    await precompute;
  }

  static String _delegationPirPrecomputeKey(
    _VotingSessionContext context,
    int bundleIndex,
  ) {
    return '${context.dbPath}|${context.accountUuid}|${context.round.roundId}|$bundleIndex';
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _operation.then((_) async {
      try {
        await action();
      } catch (e, st) {
        debugPrint('[zcash] Voting: session action failed: $e\n$st');
        await _cleanupCurrentSessionState(reason: 'action-failed');
        _setError('Voting session action failed.', cause: e);
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
        'No PIR endpoint matched the voting round snapshot.',
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

    final bundleSetup = await ref
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
        eligibleWeightZatoshi: bundleSetup.eligibleWeightZatoshi,
      ),
    );
  }

  Future<_VotingSessionContext> _loadContext(String roundId) async {
    final config = await ref.read(votingConfigProvider.future);
    final api = ref.read(votingApiClientProvider(config.apiBaseUrl));
    final round = VotingRoundDetails.fromStatus(
      await api.getRoundStatus(roundId),
    );
    final accountUuid = await _accountUuidForSession();
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

  Future<String> _accountUuidForSession() async {
    final existing = _sessionAccountUuid;
    if (existing != null) return existing;

    final accountUuid = await ref.read(votingActiveAccountUuidProvider).call();
    if (accountUuid == null) {
      throw StateError('No active account for voting session.');
    }
    _sessionAccountUuid = accountUuid;
    return accountUuid;
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

  /// Clear process-local state for the current round after an action failure.
  ///
  /// The context is reloaded so cleanup follows the session account and DB path.
  /// If that lookup fails, cleanup is skipped because there is no safe key to
  /// clear.
  Future<void> _cleanupCurrentSessionState({required String reason}) async {
    try {
      final context = await _loadContext(_roundId);
      await _resetVotingSessionState(
        rust: ref.read(votingRustApiProvider),
        context: context,
        reason: reason,
      );
    } catch (e) {
      debugPrint(
        '[zcash] Voting: process-local cleanup skipped '
        'round=$_roundId reason=$reason error=$e',
      );
    }
  }

  /// Clear round-scoped Rust voting caches for this session.
  ///
  /// Passing the round ID intentionally preserves the account-wide vote-tree
  /// sync client while discarding prepared delegation PCZTs for abandoned work.
  static Future<void> _resetVotingSessionState({
    required VotingRustApi rust,
    required _VotingSessionContext context,
    required String reason,
  }) async {
    try {
      await rust.resetVotingSessionState(
        dbPath: context.dbPath,
        walletId: context.accountUuid,
        roundId: context.round.roundId,
      );
      debugPrint(
        '[zcash] Voting: process-local state reset '
        'round=${context.round.roundId} account=${context.accountUuid} '
        'reason=$reason',
      );
    } catch (e) {
      debugPrint(
        '[zcash] Voting: process-local state reset failed '
        'round=${context.round.roundId} account=${context.accountUuid} '
        'reason=$reason error=$e',
      );
    }
  }

  static VotingSessionPhase _phaseForResumePlan(VotingResumePlan plan) {
    if (plan.pendingDelegationBundleIndexes.isNotEmpty ||
        plan.submittedDelegationBundleIndexes.isNotEmpty) {
      return VotingSessionPhase.readyToDelegate;
    }
    if (plan.pendingVoteSubmissionKeys.isNotEmpty ||
        plan.submittedVoteConfirmationKeys.isNotEmpty ||
        plan.incompleteVoteRecoveryKeys.isNotEmpty) {
      return VotingSessionPhase.readyToVote;
    }
    if (plan.hasBlockingShareWork) {
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
    if (plan.votesByKey.isNotEmpty ||
        plan.submittedVoteConfirmationKeys.isNotEmpty) {
      return const {};
    }
    final bundleCount = plan.bundleCount;
    if (bundleCount == 0) return const {};
    return {for (var i = 0; i < bundleCount; i++) i};
  }

  static List<rust_voting.ApiDraftVote> _applyLastMomentMode(
    List<rust_voting.ApiDraftVote> draftVotes,
    VotingRoundDetails round,
  ) {
    if (!round.isLastMoment()) return draftVotes;
    return [
      for (final draft in draftVotes)
        rust_voting.ApiDraftVote(
          proposalId: draft.proposalId,
          choice: draft.choice,
          numOptions: draft.numOptions,
          vcTreePosition: draft.vcTreePosition,
          singleShare: true,
        ),
    ];
  }

  static int _scheduledShareSubmitAt(VotingRoundDetails round) {
    final end = round.voteEndTime;
    final buffer = round.lastMomentBuffer;
    if (end == null || buffer == null || round.isLastMoment()) return 0;

    final now = DateTime.now().toUtc();
    final deadline = end.subtract(buffer);
    if (!deadline.isAfter(now)) return 0;

    final windowSeconds = deadline.difference(now).inSeconds;
    if (windowSeconds <= 0) return 0;
    final delaySeconds = (_submitAtRandom.nextDouble() * windowSeconds).floor();
    return now.millisecondsSinceEpoch ~/ 1000 + delaySeconds;
  }

  static String _hexFromBytes(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> _bytesFromHex(String hex) {
    final normalized = hex.startsWith('0x') ? hex.substring(2) : hex;
    return [
      for (var i = 0; i < normalized.length; i += 2)
        int.parse(normalized.substring(i, i + 2), radix: 16),
    ];
  }

  static Map<String, dynamic> _sharePayloadJson(
    rust_voting.ApiVoteSharePayload payload, {
    BigInt? vcTreePosition,
    required int submitAt,
  }) {
    return {
      'shares_hash': base64Encode(payload.sharesHash),
      'proposal_id': payload.proposalId,
      'vote_decision': payload.voteDecision,
      'enc_share': _wireShareJson(payload.encryptedShare),
      'share_index': payload.encryptedShare.shareIndex,
      'tree_position': _jsonInt(vcTreePosition ?? payload.treePosition),
      'all_enc_shares': payload.allEncryptedShares.map(_wireShareJson).toList(),
      'share_comms': payload.shareComms.map(base64Encode).toList(),
      'primary_blind': base64Encode(payload.primaryBlind),
      'submit_at': submitAt,
    };
  }

  static Map<String, dynamic> _voteCommitmentSubmissionJson(
    rust_voting.ApiSignedVoteCommitment commitment,
  ) {
    return {
      'van_nullifier': base64Encode(commitment.vanNullifier),
      'vote_authority_note_new': base64Encode(commitment.voteAuthorityNoteNew),
      'vote_commitment': base64Encode(commitment.voteCommitment),
      'proposal_id': commitment.proposalId,
      'proof': base64Encode(commitment.proof),
      'vote_round_id': base64Encode(_bytesFromHex(commitment.voteRoundId)),
      'vote_comm_tree_anchor_height': commitment.anchorHeight,
      'r_vpk': base64Encode(commitment.rVpkBytes),
      'vote_auth_sig': base64Encode(commitment.voteAuthSig),
    };
  }

  static Map<String, dynamic> _delegationSubmissionJson(
    rust_voting.ApiSignedDelegationPayload submission,
  ) {
    return {
      'rk': base64Encode(submission.rk),
      'spend_auth_sig': base64Encode(submission.spendAuthSig),
      'sighash': base64Encode(submission.sighash),
      'signed_note_nullifier': base64Encode(submission.nfSigned),
      'cmx_new': base64Encode(submission.cmxNew),
      'van_cmx': base64Encode(submission.govComm),
      'gov_nullifiers': submission.govNullifiers.map(base64Encode).toList(),
      'proof': base64Encode(submission.proof),
      'vote_round_id': base64Encode(_bytesFromHex(submission.voteRoundId)),
    };
  }

  static Map<String, dynamic> _wireShareJson(
    rust_voting.ApiWireEncryptedShare share,
  ) {
    return {
      'c1': base64Encode(share.ciphertext1),
      'c2': base64Encode(share.ciphertext2),
      'share_index': share.shareIndex,
    };
  }

  static ({int vanPosition, BigInt vcTreePosition}) _castVoteLeafPositions(
    VotingTxConfirmation confirmation,
  ) {
    final rawLeafIndex = confirmation
        .event('cast_vote')
        ?.attribute('leaf_index');
    if (rawLeafIndex == null) {
      throw StateError('Missing cast_vote leaf_index.');
    }
    final parts = rawLeafIndex.split(',');
    if (parts.length != 2) {
      throw StateError('Malformed cast_vote leaf_index: $rawLeafIndex');
    }
    final vanPosition = int.tryParse(parts[0].trim());
    final vcTreePosition = BigInt.tryParse(parts[1].trim());
    if (vanPosition == null || vcTreePosition == null) {
      throw StateError('Malformed cast_vote leaf_index: $rawLeafIndex');
    }
    return (vanPosition: vanPosition, vcTreePosition: vcTreePosition);
  }

  static int _jsonInt(BigInt value) {
    if (value > BigInt.from(0x1fffffffffffff)) {
      throw StateError('Value is too large to encode as JSON integer: $value');
    }
    return value.toInt();
  }

  static String _formatElapsed(Duration duration) {
    return '${(duration.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(2)}s';
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

@visibleForTesting
final votingTxConfirmationPollingProvider =
    Provider<VotingTxConfirmationPolling>((ref) {
      return const VotingTxConfirmationPolling(
        attempts: 45,
        delay: Duration(seconds: 2),
      );
    });

@visibleForTesting
class VotingTxConfirmationPolling {
  final int attempts;
  final Duration delay;

  const VotingTxConfirmationPolling({
    required this.attempts,
    required this.delay,
  }) : assert(attempts > 0);
}
