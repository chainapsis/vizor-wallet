import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/voting/voting_resume_plan.dart';
import '../../features/voting/voting_share_timing.dart';
import '../../rust/api/voting.dart' as rust_voting;
import '../../services/voting/pir_snapshot_resolver.dart';
import '../../services/voting/voting_api_client.dart';
import '../../services/voting/voting_helper_health_tracker.dart';
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
  final Map<String, Future<void>> _delegationPirPrecomputes = {};
  Timer? _shareTrackingTimer;
  String? _sessionAccountUuid;
  bool? _sessionIsHardwareAccount;

  @override
  Future<VotingSessionState> build() async {
    await _accountUuidForSession();
    final context = await _loadContext(_roundId);
    final rust = ref.read(votingRustApiProvider);
    ref.onDispose(() {
      // Provider disposal is round-scoped: clear abandoned prepared PCZTs but
      // keep account-wide vote-tree sync state reusable across rounds.
      _delegationPirPrecomputes.clear();
      _shareTrackingTimer?.cancel();
      unawaited(
        _resetVotingSessionState(
          rust: rust,
          context: context,
          reason: 'provider-dispose',
        ),
      );
    });
    final initialState = VotingSessionState(
      roundId: _roundId,
      accountUuid: context.accountUuid,
      isHardwareAccount: context.isHardwareAccount,
      config: context.config,
      round: context.round,
      resumePlan: context.resumePlan,
      phase: _phaseForResumePlan(context.resumePlan),
    );
    _scheduleShareTracking(context, context.resumePlan);
    return initialState;
  }

  Future<void> prepareDelegation() {
    return _enqueue(_prepareDelegationUnlocked);
  }

  Future<void> ensureWalletReadyForVoting() {
    return _enqueue(() async {
      final context = await _loadContext(_roundId);
      await _waitUntilWalletReadyForVoting(context);
    });
  }

  Future<void> precomputeDelegationPir({required List<int> seedBytes}) async {
    final context = await _loadContext(_roundId);
    await _waitUntilWalletReadyForVoting(context);
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
        if (current.phase == VotingSessionPhase.error ||
            current.phase == VotingSessionPhase.waitingForWalletSync) {
          return;
        }
      }

      final context = await _loadContext(_roundId);
      if (context.isHardwareAccount) {
        _setError('Sign delegation bundles with Keystone before submitting.');
        return;
      }
      final plan = current.resumePlan ?? context.resumePlan;
      final pirEndpoint = current.pirEndpoint;
      if (pirEndpoint == null) {
        _setError('PIR endpoint has not been resolved.');
        return;
      }
      await _ensureHotkey(context, seedBytes: seedBytes);

      final progress = Map<int, VotingSessionProgress>.from(
        current.delegationProgress,
      );
      final rust = ref.read(votingRustApiProvider);
      final completedBundleIndexes = await _confirmSubmittedDelegations(
        context: context,
        plan: plan,
        progress: progress,
      );
      if (completedBundleIndexes == null) return;
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
          final proofProgress = _monotonicProofProgress(
            progress[bundleIndex]?.proofProgress,
            event.proofProgress,
          );
          progress[bundleIndex] = VotingSessionProgress(
            phase: event.phase,
            bundleIndex: bundleIndex,
            proofProgress: proofProgress,
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
        final result = await _submitAndConfirmDelegation(
          context: context,
          bundleIndex: bundleIndex,
          submission: submission,
        );
        debugPrint(
          '[zcash] Voting: delegation bundle completed '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'leafIndex=${result.leafIndex} total=${_formatElapsed(bundleTimer.elapsed)}',
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

  Future<void> prepareKeystoneSigning() {
    return _enqueue(_prepareKeystoneSigningUnlocked);
  }

  Future<void> handleKeystoneSignedPczt(List<int> signedPcztBytes) {
    return _enqueue(() async {
      final current = await future;
      final request = current.keystoneSigningRequest;
      if (request == null) {
        _setError('No Keystone signing request is waiting for a signature.');
        return;
      }

      final context = await _loadContext(_roundId);
      final rust = ref.read(votingRustApiProvider);
      final signatures = Map<int, rust_voting.ApiKeystoneSignatureRecord>.from(
        current.keystoneSignatures,
      );
      if (signatures.isEmpty) {
        signatures.addAll(await _loadKeystoneSignatures(context));
      }

      final scannedSighash = await rust.extractPcztSighash(
        pcztBytes: signedPcztBytes,
      );
      final duplicate = signatures.values.any(
        (record) => _bytesEqual(record.sighash, scannedSighash),
      );
      if (duplicate) {
        state = AsyncData(
          current.copyWith(
            phase: VotingSessionPhase.keystoneSigning,
            keystoneSignatures: signatures,
            keystoneScanError:
                'This Keystone signature was already scanned. Open the next signature on Keystone and scan again.',
          ),
        );
        return;
      }
      if (!_bytesEqual(request.pcztSighash, scannedSighash)) {
        state = AsyncData(
          current.copyWith(
            phase: VotingSessionPhase.keystoneSigning,
            keystoneSignatures: signatures,
            keystoneScanError:
                'This signature is for a different voting bundle. Scan the signature for bundle ${request.bundleIndex + 1}.',
          ),
        );
        return;
      }

      final signature = await rust.extractSpendAuthSignatureFromSignedPczt(
        signedPcztBytes: signedPcztBytes,
        actionIndex: request.actionIndex,
      );
      await rust.storeKeystoneSignature(
        dbPath: context.dbPath,
        walletId: context.accountUuid,
        roundId: context.round.roundId,
        bundleIndex: request.bundleIndex,
        sig: signature,
        sighash: scannedSighash,
        rk: request.rk,
      );
      await _prepareKeystoneSigningUnlocked();
    });
  }

  Future<void> skipRemainingKeystoneBundles() {
    return _enqueue(() async {
      final current = await future;
      final context = await _loadContext(_roundId);
      if (!context.isHardwareAccount) {
        _setError('Keystone voting is only available for hardware accounts.');
        return;
      }

      final plan = current.resumePlan ?? context.resumePlan;
      final signatures = await _loadKeystoneSignatures(context);
      final signedPrefixCount = resolvedKeystoneBundlePrefixCount(
        plan: plan,
        signatures: signatures,
      );
      if (signedPrefixCount <= 0) {
        _setError(
          'Sign at least one Keystone bundle before skipping the rest.',
        );
        return;
      }
      if (signedPrefixCount >= plan.bundleCount) {
        state = AsyncData(
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.readyToDelegate,
            resumePlan: plan,
            keystoneSignatures: signatures,
            clearKeystoneSigningRequest: true,
            clearKeystoneScanError: true,
            clearCurrentBundleIndex: true,
            clearError: true,
          ),
        );
        return;
      }

      debugPrint(
        '[zcash] Voting: Keystone skipping remaining bundles '
        'round=${context.round.roundId} keepCount=$signedPrefixCount '
        'bundleCount=${plan.bundleCount}',
      );
      await ref
          .read(votingRustApiProvider)
          .deleteSkippedBundles(
            dbPath: context.dbPath,
            walletId: context.accountUuid,
            roundId: context.round.roundId,
            keepCount: signedPrefixCount,
          );
      final refreshedPlan = await _loadResumePlan(context);
      final retainedSignatures = {
        for (final entry in signatures.entries)
          if (entry.key < signedPrefixCount) entry.key: entry.value,
      };
      state = AsyncData(
        (state.value ?? current).copyWith(
          phase: VotingSessionPhase.readyToDelegate,
          resumePlan: refreshedPlan,
          keystoneSignatures: retainedSignatures,
          clearKeystoneSigningRequest: true,
          clearKeystoneScanError: true,
          clearCurrentBundleIndex: true,
          clearError: true,
        ),
      );
    });
  }

  Future<void> delegatePendingBundlesWithKeystoneSignatures() {
    return _enqueue(() async {
      var current = await future;
      if (current.pirEndpoint == null) {
        await _prepareDelegationUnlocked();
        current = await future;
        if (current.phase == VotingSessionPhase.error ||
            current.phase == VotingSessionPhase.waitingForWalletSync) {
          return;
        }
      }

      final context = await _loadContext(_roundId);
      if (!context.isHardwareAccount) {
        _setError('Keystone voting is only available for hardware accounts.');
        return;
      }
      final plan = current.resumePlan ?? context.resumePlan;
      final pirEndpoint = current.pirEndpoint;
      if (pirEndpoint == null) {
        _setError('PIR endpoint has not been resolved.');
        return;
      }

      final hotkeySeed = await _ensureHotkey(context);
      final signatures = await _loadKeystoneSignatures(context);
      final progress = Map<int, VotingSessionProgress>.from(
        current.delegationProgress,
      );
      final completedBundleIndexes = await _confirmSubmittedDelegations(
        context: context,
        plan: plan,
        progress: progress,
      );
      if (completedBundleIndexes == null) return;

      final rust = ref.read(votingRustApiProvider);
      for (final bundleIndex in plan.pendingDelegationBundleIndexes) {
        final signature = signatures[bundleIndex];
        if (signature == null) {
          _setError(
            'Sign delegation bundle ${bundleIndex + 1} with Keystone before submitting.',
          );
          return;
        }

        final bundleTimer = Stopwatch()..start();
        debugPrint(
          '[zcash] Voting: Keystone delegation bundle start '
          'round=${context.round.roundId} bundle=$bundleIndex',
        );
        state = AsyncData(
          (state.value ?? current).copyWith(
            phase: VotingSessionPhase.delegating,
            keystoneSignatures: signatures,
            clearKeystoneSigningRequest: true,
            clearKeystoneScanError: true,
            currentBundleIndex: bundleIndex,
          ),
        );

        rust_voting.ApiSignedDelegationPayload? signedDelegationPayload;
        await for (final event
            in rust
                .buildProveDelegationPayloadWithKeystoneSignatureWithProgress(
                  dbPath: context.dbPath,
                  lightwalletdUrl: context.lightwalletdUrl,
                  pirServerUrl: pirEndpoint.toString(),
                  network: context.network,
                  roundParams: context.round.toRoundParams(),
                  roundName: context.round.title,
                  sessionJson: context.round.sessionJson,
                  accountUuid: context.accountUuid,
                  hotkeySeed: hotkeySeed,
                  bundleIndex: bundleIndex,
                  keystoneSig: signature.sig,
                  keystoneSighash: signature.sighash,
                )) {
          signedDelegationPayload =
              event.signedDelegationPayload ?? signedDelegationPayload;
          final proofProgress = _monotonicProofProgress(
            progress[bundleIndex]?.proofProgress,
            event.proofProgress,
          );
          progress[bundleIndex] = VotingSessionProgress(
            phase: event.phase,
            bundleIndex: bundleIndex,
            proofProgress: proofProgress,
            message: null,
          );
          state = AsyncData(
            (state.value ?? current).copyWith(delegationProgress: progress),
          );
        }
        debugPrint(
          '[zcash] Voting: Keystone delegation proof stream completed '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'elapsed=${_formatElapsed(bundleTimer.elapsed)}',
        );
        final submission = signedDelegationPayload;
        if (submission == null) {
          throw StateError(
            'Delegation proof completed without submission payload.',
          );
        }
        _verifyKeystoneDelegationSignature(
          submission: submission,
          signature: signature,
          bundleIndex: bundleIndex,
        );
        final result = await _submitAndConfirmDelegation(
          context: context,
          bundleIndex: bundleIndex,
          submission: submission,
        );
        debugPrint(
          '[zcash] Voting: Keystone delegation bundle completed '
          'round=${context.round.roundId} bundle=$bundleIndex '
          'leafIndex=${result.leafIndex} total=${_formatElapsed(bundleTimer.elapsed)}',
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

      final refreshedPlan = await _loadResumePlan(context);
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
          keystoneSignatures: signatures,
          clearKeystoneSigningRequest: true,
          clearKeystoneScanError: true,
          clearCurrentBundleIndex: true,
        ),
      );
    });
  }

  Future<void> castVotes({required List<rust_voting.ApiDraftVote> draftVotes}) {
    return _enqueue(() async {
      final current = await future;
      final context = await _loadContext(_roundId);
      await _waitUntilWalletReadyForVoting(context);
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
      final effectiveDraftVotes = VotingShareTimingPolicy.applyLastMomentMode(
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
      final pendingBundles = _pendingVoteBundleIndexes(plan).toList()..sort();
      final totalQuestions = effectiveDraftVotes.length;
      final totalBundleTasks = pendingBundles.length * totalQuestions;
      var completedBundleTasks = 0;
      var completedQuestions = 0;
      debugPrint(
        '[zcash] Voting: cast votes start '
        'round=${context.round.roundId} bundles=${pendingBundles.length} '
        'proposals=${effectiveDraftVotes.length} '
        'lastMoment=${context.round.isLastMoment()}',
      );
      for (final draftVote in effectiveDraftVotes) {
        for (final bundleIndex in pendingBundles) {
          final voteTimer = Stopwatch()..start();
          final key = VotingVoteKey(
            bundleIndex: bundleIndex,
            proposalId: draftVote.proposalId,
          );
          state = AsyncData(
            (state.value ?? current).copyWith(
              phase: VotingSessionPhase.syncingVoteTree,
              currentBundleIndex: bundleIndex,
              currentVoteKey: key,
              voteSubmissionCompletedCount: completedQuestions,
              voteSubmissionTotalCount: totalQuestions,
              voteSubmissionProgress: _voteSubmissionProgress(
                completedBundleTasks: completedBundleTasks,
                totalBundleTasks: totalBundleTasks,
              ),
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
              currentVoteKey: key,
              voteSubmissionCompletedCount: completedQuestions,
              voteSubmissionTotalCount: totalQuestions,
              voteSubmissionProgress: _voteSubmissionProgress(
                completedBundleTasks: completedBundleTasks,
                totalBundleTasks: totalBundleTasks,
              ),
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
              final eventKey = VotingVoteKey(
                bundleIndex: event.bundleIndex ?? bundleIndex,
                proposalId: proposalId,
              );
              final proofProgress = _monotonicProofProgress(
                progress[eventKey]?.proofProgress,
                event.proofProgress,
              );
              progress[eventKey] = VotingSessionProgress(
                phase: event.phase,
                bundleIndex: eventKey.bundleIndex,
                proposalId: proposalId,
                proofProgress: proofProgress,
              );
              state = AsyncData(
                (state.value ?? current).copyWith(
                  phase: VotingSessionPhase.castingVotes,
                  voteProgress: progress,
                  currentVoteKey: eventKey,
                  voteSubmissionCompletedCount: completedQuestions,
                  voteSubmissionTotalCount: totalQuestions,
                  voteSubmissionProgress: _voteSubmissionProgress(
                    completedBundleTasks: completedBundleTasks,
                    totalBundleTasks: totalBundleTasks,
                    currentBundleProgress: proofProgress,
                  ),
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
                singleShare: draftVote.singleShare,
                completedQuestions: completedQuestions,
                totalQuestions: totalQuestions,
                voteSubmissionProgress: _voteSubmissionProgress(
                  completedBundleTasks: completedBundleTasks,
                  totalBundleTasks: totalBundleTasks,
                  currentBundleProgress: _monotonicProofProgress(
                    progress[key]?.proofProgress,
                    0.95,
                  ),
                ),
              );
            }
          }
          completedBundleTasks++;
          progress[key] = VotingSessionProgress(
            phase: 'completed',
            bundleIndex: key.bundleIndex,
            proposalId: key.proposalId,
          );
          state = AsyncData(
            (state.value ?? current).copyWith(
              phase: VotingSessionPhase.castingVotes,
              voteProgress: progress,
              currentVoteKey: key,
              voteSubmissionCompletedCount: completedQuestions,
              voteSubmissionTotalCount: totalQuestions,
              voteSubmissionProgress: _voteSubmissionProgress(
                completedBundleTasks: completedBundleTasks,
                totalBundleTasks: totalBundleTasks,
              ),
            ),
          );
          debugPrint(
            '[zcash] Voting: vote flow completed '
            'round=${context.round.roundId} bundle=$bundleIndex '
            'proposal=${draftVote.proposalId} '
            'total=${_formatElapsed(voteTimer.elapsed)}',
          );
        }
        if (pendingBundles.isNotEmpty) {
          completedQuestions++;
          state = AsyncData(
            (state.value ?? current).copyWith(
              phase: VotingSessionPhase.castingVotes,
              voteProgress: progress,
              voteSubmissionCompletedCount: completedQuestions,
              voteSubmissionTotalCount: totalQuestions,
              voteSubmissionProgress: _voteSubmissionProgress(
                completedBundleTasks: completedBundleTasks,
                totalBundleTasks: totalBundleTasks,
              ),
            ),
          );
        }
      }
      if (pendingBundles.isEmpty) {
        completedQuestions = totalQuestions;
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
          voteSubmissionCompletedCount: completedQuestions,
          voteSubmissionTotalCount: totalQuestions,
          voteSubmissionProgress: _voteSubmissionProgress(
            completedBundleTasks: completedBundleTasks,
            totalBundleTasks: totalBundleTasks,
          ),
          clearCurrentBundleIndex: true,
          clearCurrentVoteKey: true,
        ),
      );
      _scheduleShareTracking(context, refreshedPlan);
    });
  }

  Future<List<int>> _ensureHotkey(
    _VotingSessionContext context, {
    List<int>? seedBytes,
    bool allowHardwareGeneration = false,
  }) async {
    final existing = await _readStoredHotkey(context);
    if (existing != null && existing.isNotEmpty) return existing;

    final rust = ref.read(votingRustApiProvider);
    late final List<int> hotkey;
    if (context.isHardwareAccount) {
      if (!allowHardwareGeneration) {
        throw const VotingHotkeyUnavailable(
          'missing stored Keystone voting hotkey',
        );
      }
      hotkey = await rust.generateVotingHotkey();
    } else {
      hotkey = await rust.deriveHotkey(
        seedBytes: seedBytes ?? (throw StateError('Missing wallet seed.')),
        roundId: context.round.roundId,
        accountUuid: context.accountUuid,
      );
    }
    await ref
        .read(votingHotkeyStoreProvider)
        .writeHotkey(
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
          hotkey: hotkey,
        );
    return hotkey;
  }

  Future<List<int>?> _readStoredHotkey(_VotingSessionContext context) async {
    final existing = await ref
        .read(votingHotkeyStoreProvider)
        .readHotkey(
          accountUuid: context.accountUuid,
          roundId: context.round.roundId,
        );
    if (existing == null || existing.isEmpty) return null;
    return existing;
  }

  Future<void> _submitCommitmentShares(
    _VotingSessionContext context,
    rust_voting.ApiSignedVoteCommitments commitments, {
    Map<int, BigInt> vcTreePositions = const {},
    required bool singleShare,
    required int completedQuestions,
    required int totalQuestions,
    required double? voteSubmissionProgress,
  }) async {
    final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
    final rust = ref.read(votingRustApiProvider);
    final helperHealth = ref.read(votingHelperHealthTrackerProvider);
    final serverUrls = context.config.voteServers
        .map((endpoint) => endpoint.url.toString())
        .toList(growable: false);
    if (serverUrls.isEmpty) {
      throw StateError('No vote servers configured for share submission.');
    }

    final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final voteEnd = context.round.voteEndTime;
    final voteEndSeconds = voteEnd == null
        ? nowSeconds
        : voteEnd.toUtc().millisecondsSinceEpoch ~/ 1000;
    final lastMomentBufferSeconds = context.round.lastMomentBuffer == null
        ? null
        : BigInt.from(context.round.lastMomentBuffer!.inSeconds);
    final bundleProgressMessage = _bundleProgressMessage(
      bundleIndex: commitments.bundleIndex,
      bundleCount: context.resumePlan.bundleCount,
    );

    for (final commitment in commitments.commitments) {
      final vcTreePosition = vcTreePositions[commitment.proposalId];
      final plans = await rust.planShareSubmissions(
        shareCount: commitment.sharePayloads.length,
        serverUrls: serverUrls,
        nowSeconds: BigInt.from(nowSeconds),
        voteEndTimeSeconds: BigInt.from(voteEndSeconds),
        lastMomentBufferSeconds: lastMomentBufferSeconds,
        singleShare: singleShare,
      );
      if (plans.length != commitment.sharePayloads.length) {
        throw StateError(
          'Share submission policy returned ${plans.length} plan(s) for '
          '${commitment.sharePayloads.length} payload(s).',
        );
      }

      for (
        var payloadIndex = 0;
        payloadIndex < commitment.sharePayloads.length;
        payloadIndex++
      ) {
        final payload = commitment.sharePayloads[payloadIndex];
        final plan = plans[payloadIndex];
        final acceptedServers = <String>[];
        final targetCount = plan.targetCount
            .clamp(1, serverUrls.length)
            .toInt();
        final candidateServers = _plannedShareServers(
          plannedServers: plan.targetServers,
          fallbackServers: helperHealth.candidateServers(serverUrls),
        );
        final body = await _wireJsonMap(
          rust.voteShareWireJson(
            payload: payload,
            vcTreePosition: vcTreePosition,
            submitAt: plan.submitAt,
          ),
        );
        _setShareSubmissionProgress(
          bundleIndex: commitments.bundleIndex,
          proposalId: payload.proposalId,
          message: bundleProgressMessage,
          completedQuestions: completedQuestions,
          totalQuestions: totalQuestions,
          voteSubmissionProgress: voteSubmissionProgress,
        );
        for (final serverUrl in candidateServers) {
          if (acceptedServers.length >= targetCount) break;
          try {
            debugPrint(
              '[zcash] Voting: submitting share '
              'proposal=${payload.proposalId} share=${payload.encryptedShare.shareIndex} '
              'server=$serverUrl treePosition=${body['tree_position']} '
              'submitAt=${plan.submitAt} target=$targetCount',
            );
            await api.submitShare(
              roundId: context.round.roundId,
              serverUrl: Uri.parse(serverUrl),
              share: body,
            );
            helperHealth.recordSuccess(serverUrl);
            acceptedServers.add(serverUrl);
            debugPrint(
              '[zcash] Voting: share accepted '
              'proposal=${payload.proposalId} share=${payload.encryptedShare.shareIndex} '
              'server=$serverUrl accepted=${acceptedServers.length}/$targetCount',
            );
          } catch (e) {
            debugPrint(
              '[zcash] Voting: share rejected '
              'proposal=${payload.proposalId} share=${payload.encryptedShare.shareIndex} '
              'server=$serverUrl error=$e',
            );
            helperHealth.recordFailure(serverUrl);
            // Recovery retries helpers that did not accept this share.
          }
        }
        if (acceptedServers.isEmpty) {
          throw StateError(
            'No vote server accepted share ${payload.encryptedShare.shareIndex} '
            'for proposal ${payload.proposalId}.',
          );
        }
        if (acceptedServers.length < targetCount) {
          debugPrint(
            '[zcash] Voting: share accepted by fewer helpers than planned '
            'proposal=${payload.proposalId} '
            'share=${payload.encryptedShare.shareIndex} '
            'accepted=${acceptedServers.length}/$targetCount',
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
          submitAt: plan.submitAt,
        );
      }
    }
  }

  String? _bundleProgressMessage({
    required int bundleIndex,
    required int bundleCount,
  }) {
    if (bundleCount <= 1) return null;
    return '${bundleIndex + 1}/$bundleCount';
  }

  double? _voteSubmissionProgress({
    required int completedBundleTasks,
    required int totalBundleTasks,
    double? currentBundleProgress,
  }) {
    if (totalBundleTasks <= 0) return null;
    final currentProgress = (currentBundleProgress ?? 0).clamp(0.0, 1.0);
    return ((completedBundleTasks + currentProgress) / totalBundleTasks)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double? _monotonicProofProgress(double? previous, double? next) {
    final previousValue = previous?.clamp(0.0, 1.0).toDouble();
    final nextValue = next?.clamp(0.0, 1.0).toDouble();
    if (nextValue == null) return previousValue;
    if (previousValue == null) return nextValue;
    return nextValue < previousValue ? previousValue : nextValue;
  }

  List<String> _plannedShareServers({
    required List<String> plannedServers,
    required Iterable<String> fallbackServers,
  }) {
    final ordered = <String>{};
    for (final server in plannedServers) {
      if (server.trim().isNotEmpty) ordered.add(server);
    }
    for (final server in fallbackServers) {
      if (server.trim().isNotEmpty) ordered.add(server);
    }
    return ordered.toList(growable: false);
  }

  void _setShareSubmissionProgress({
    required int bundleIndex,
    required int proposalId,
    required String? message,
    required int completedQuestions,
    required int totalQuestions,
    required double? voteSubmissionProgress,
  }) {
    final current = state.value;
    if (current == null) return;
    final key = VotingVoteKey(bundleIndex: bundleIndex, proposalId: proposalId);
    final progress = Map<VotingVoteKey, VotingSessionProgress>.from(
      current.voteProgress,
    );
    progress[key] = VotingSessionProgress(
      phase: 'submitting_shares',
      bundleIndex: bundleIndex,
      proposalId: proposalId,
      message: message,
    );
    state = AsyncData(
      current.copyWith(
        phase: VotingSessionPhase.castingVotes,
        voteProgress: progress,
        currentVoteKey: key,
        voteSubmissionCompletedCount: completedQuestions,
        voteSubmissionTotalCount: totalQuestions,
        voteSubmissionProgress: voteSubmissionProgress,
      ),
    );
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
        commitment: await _wireJsonMap(
          rust.voteCommitmentWireJson(commitment: commitment),
        ),
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

  Future<Map<int, rust_voting.ApiKeystoneSignatureRecord>>
  _loadKeystoneSignatures(_VotingSessionContext context) async {
    final records = await ref
        .read(votingRustApiProvider)
        .getKeystoneSignatures(
          dbPath: context.dbPath,
          walletId: context.accountUuid,
          roundId: context.round.roundId,
        );
    return {for (final record in records) record.bundleIndex: record};
  }

  Future<Set<int>?> _confirmSubmittedDelegations({
    required _VotingSessionContext context,
    required VotingResumePlan plan,
    required Map<int, VotingSessionProgress> progress,
  }) async {
    final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
    final rust = ref.read(votingRustApiProvider);
    final completedBundleIndexes = <int>{};
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
        return null;
      }
      if (confirmation.code != 0) {
        throw StateError(
          confirmation.log.isEmpty
              ? 'Delegation transaction failed.'
              : confirmation.log,
        );
      }
      final leafIndex = _delegationLeafIndex(confirmation, bundleIndex);
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
    return completedBundleIndexes;
  }

  Future<({String txHash, int leafIndex})> _submitAndConfirmDelegation({
    required _VotingSessionContext context,
    required int bundleIndex,
    required rust_voting.ApiSignedDelegationPayload submission,
  }) async {
    final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
    final rust = ref.read(votingRustApiProvider);
    final submitTimer = Stopwatch()..start();
    debugPrint(
      '[zcash] Voting: submitting delegation '
      'round=${context.round.roundId} bundle=$bundleIndex',
    );
    final result = await api.submitDelegation(
      submission: await _wireJsonMap(
        rust.delegationSubmissionWireJson(submission: submission),
      ),
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
    final leafIndex = _delegationLeafIndex(confirmation, bundleIndex);
    await rust.markDelegationConfirmed(
      dbPath: context.dbPath,
      walletId: context.accountUuid,
      roundId: context.round.roundId,
      bundleIndex: bundleIndex,
      txHash: result.txHash,
      vanLeafPosition: leafIndex,
    );
    return (txHash: result.txHash, leafIndex: leafIndex);
  }

  static int _delegationLeafIndex(
    VotingTxConfirmation confirmation,
    int bundleIndex,
  ) {
    final leafIndex = int.tryParse(
      confirmation.event('delegate_vote')?.attribute('leaf_index') ?? '',
    );
    if (leafIndex == null) {
      throw StateError(
        'Missing delegate_vote leaf_index for bundle $bundleIndex.',
      );
    }
    return leafIndex;
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
      _shareTrackingTimer?.cancel();
      _shareTrackingTimer = null;
      final current = await future;
      final context = await _loadContext(_roundId);
      final plan = await _loadResumePlan(context);
      state = AsyncData(
        current.copyWith(
          phase: VotingSessionPhase.submittingShares,
          resumePlan: plan,
        ),
      );

      final api = ref.read(votingApiClientProvider(context.config.apiBaseUrl));
      final helperHealth = ref.read(votingHelperHealthTrackerProvider);
      final configuredServerUrls = context.config.voteServers
          .map((endpoint) => endpoint.url.toString())
          .toList(growable: false);
      final nowSeconds = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final voteEnd = context.round.voteEndTime;
      final voteEndSeconds = voteEnd == null
          ? null
          : voteEnd.millisecondsSinceEpoch ~/ 1000;
      for (final share in plan.unconfirmedShareDelegations) {
        // A share is recoverable once any helper accepted it, but every
        // configured helper should eventually receive it for redundancy.
        final acceptedUrls = LinkedHashSet<String>.of(share.sentToUrls);
        final readyForStatusCheck =
            VotingShareTimingPolicy.isShareReadyForStatusCheck(
              share,
              nowSeconds: nowSeconds,
            );
        final overdueForRetry =
            voteEndSeconds != null &&
            VotingShareTimingPolicy.shouldResubmitShare(
              share,
              nowSeconds: nowSeconds,
              voteEndTimeSeconds: voteEndSeconds,
            );

        if (!readyForStatusCheck && !overdueForRetry) continue;

        if (acceptedUrls.isNotEmpty && readyForStatusCheck) {
          // Helpers can reveal at slightly different times. Confirmation by any
          // helper is enough to advance the local workflow for this share.
          final confirmed = await _shareConfirmedByAnyHelper(
            api: api,
            helperHealth: helperHealth,
            share: share,
            serverUrls: acceptedUrls,
          );
          if (confirmed) {
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
            continue;
          }
        }

        final missingUrls = configuredServerUrls
            .where((serverUrl) => !acceptedUrls.contains(serverUrl))
            .toList(growable: false);
        if (overdueForRetry && missingUrls.isNotEmpty) {
          final newUrls = await _resubmitShareToMissingHelpers(
            api: api,
            context: context,
            plan: plan,
            share: share,
            serverUrls: missingUrls,
          );
          if (newUrls.isNotEmpty) {
            await ref
                .read(votingRecoveryServiceProvider)
                .addSentServersForShare(
                  dbPath: context.dbPath,
                  walletId: context.accountUuid,
                  share: share,
                  newUrls: newUrls,
                );
            acceptedUrls.addAll(newUrls);
          }
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
      _scheduleShareTracking(context, refreshedPlan);
    });
  }

  /// Retries an already-generated share against helpers missing from
  /// `sent_to_urls` and returns only the helpers that accepted the retry.
  Future<List<String>> _resubmitShareToMissingHelpers({
    required VotingApiClient api,
    required _VotingSessionContext context,
    required VotingResumePlan plan,
    required rust_voting.ApiShareDelegationRecord share,
    required List<String> serverUrls,
  }) async {
    final rust = ref.read(votingRustApiProvider);
    final key = VotingVoteKey(
      bundleIndex: share.bundleIndex,
      proposalId: share.proposalId,
    );
    final commitmentBundle = plan.commitmentBundleFor(key);
    if (commitmentBundle == null) {
      debugPrint(
        '[zcash] Voting: share resubmit skipped; missing commitment bundle '
        'round=${share.roundId} bundle=${share.bundleIndex} '
        'proposal=${share.proposalId} share=${share.shareIndex}',
      );
      return const [];
    }
    final Map<String, dynamic> body;
    try {
      body = await _wireJsonMap(
        rust.recoveredVoteShareWireJson(
          commitmentBundleJson: commitmentBundle.commitmentBundleJson,
          proposalId: share.proposalId,
          shareIndex: share.shareIndex,
          vcTreePosition: commitmentBundle.vcTreePosition,
          submitAt: BigInt.zero,
        ),
      );
    } catch (e) {
      debugPrint(
        '[zcash] Voting: share resubmit skipped; invalid recovery payload '
        'round=${share.roundId} bundle=${share.bundleIndex} '
        'proposal=${share.proposalId} share=${share.shareIndex} error=$e',
      );
      return const [];
    }
    final shareId = _hexFromBytes(share.nullifier);
    final acceptedUrls = <String>[];
    final helperHealth = ref.read(votingHelperHealthTrackerProvider);
    for (final serverUrl in helperHealth.candidateServers(serverUrls)) {
      try {
        await api.resubmitShare(
          roundId: context.round.roundId,
          serverUrl: Uri.parse(serverUrl),
          shareId: shareId,
          share: body,
        );
        helperHealth.recordSuccess(serverUrl);
        acceptedUrls.add(serverUrl);
        debugPrint(
          '[zcash] Voting: share resubmitted '
          'round=${share.roundId} bundle=${share.bundleIndex} '
          'proposal=${share.proposalId} share=${share.shareIndex} '
          'server=$serverUrl',
        );
      } catch (e) {
        debugPrint(
          '[zcash] Voting: share resubmit failed '
          'round=${share.roundId} bundle=${share.bundleIndex} '
          'proposal=${share.proposalId} share=${share.shareIndex} '
          'server=$serverUrl error=$e',
        );
        helperHealth.recordFailure(serverUrl);
      }
    }
    return acceptedUrls;
  }

  void _scheduleShareTracking(
    _VotingSessionContext context,
    VotingResumePlan plan,
  ) {
    _shareTrackingTimer?.cancel();
    _shareTrackingTimer = null;
    if (plan.unconfirmedShareDelegations.isEmpty) return;

    final delay = VotingShareTimingPolicy.nextTrackingDelay(
      plan.unconfirmedShareDelegations,
      context.round,
    );
    if (delay == null) return;

    // Keep immediate-ready shares asynchronous so build/state updates settle
    // before recovery polling re-enters the serialized operation queue.
    final scheduledDelay = delay < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : delay;
    _shareTrackingTimer = Timer(scheduledDelay, () {
      _shareTrackingTimer = null;
      unawaited(submitPendingShares());
    });
  }

  Future<bool> _shareConfirmedByAnyHelper({
    required VotingApiClient api,
    required VotingHelperHealthTracker helperHealth,
    required rust_voting.ApiShareDelegationRecord share,
    required Iterable<String> serverUrls,
  }) async {
    final shareId = _hexFromBytes(share.nullifier);
    for (final serverUrl in helperHealth.candidateServers(serverUrls)) {
      try {
        final status = await api.getShareStatus(
          roundId: share.roundId,
          serverUrl: Uri.parse(serverUrl),
          shareId: shareId,
        );
        helperHealth.recordSuccess(serverUrl);
        if (status.status == 'confirmed') return true;
      } catch (e) {
        debugPrint(
          '[zcash] Voting: share status check failed '
          'round=${share.roundId} bundle=${share.bundleIndex} '
          'proposal=${share.proposalId} share=${share.shareIndex} '
          'server=$serverUrl error=$e',
        );
        helperHealth.recordFailure(serverUrl);
      }
    }
    return false;
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
        _setError(_actionErrorMessage(e), cause: e);
      }
    });
    _operation = next.catchError((_) {});
    return next;
  }

  static String _actionErrorMessage(Object error) {
    final text = error.toString().trim();
    for (final prefix in const [
      'Exception: ',
      'StateError: ',
      'Bad state: ',
      'VotingHotkeyUnavailable: ',
    ]) {
      if (text.startsWith(prefix)) {
        return text.substring(prefix.length);
      }
    }
    return text.isEmpty ? 'Voting session action failed.' : text;
  }

  Future<void> _prepareKeystoneSigningUnlocked() async {
    var current = await future;
    var context = await _loadContext(_roundId);
    if (!context.isHardwareAccount) {
      _setError('Keystone voting is only available for hardware accounts.');
      return;
    }
    await _waitUntilWalletReadyForVoting(context);

    if (current.pirEndpoint == null) {
      await _prepareDelegationUnlocked();
      current = await future;
      if (current.phase == VotingSessionPhase.error) return;
      context = await _loadContext(_roundId);
    }

    final plan = current.resumePlan ?? context.resumePlan;
    final signatures = await _loadKeystoneSignatures(context);
    int? nextUnsignedBundle;
    for (final bundleIndex in plan.pendingDelegationBundleIndexes) {
      if (!signatures.containsKey(bundleIndex)) {
        nextUnsignedBundle = bundleIndex;
        break;
      }
    }
    final existingHotkey = await _readStoredHotkey(context);
    if (existingHotkey == null &&
        (signatures.isNotEmpty || _hasHotkeyBoundRecoveryState(plan))) {
      throw const VotingHotkeyUnavailable(
        'missing stored Keystone voting hotkey',
      );
    }

    if (nextUnsignedBundle == null) {
      state = AsyncData(
        (state.value ?? current).copyWith(
          phase: VotingSessionPhase.readyToDelegate,
          isHardwareAccount: true,
          resumePlan: plan,
          keystoneSignatures: signatures,
          clearKeystoneSigningRequest: true,
          clearKeystoneScanError: true,
          clearCurrentBundleIndex: true,
          clearError: true,
        ),
      );
      return;
    }

    final hotkeySeed =
        existingHotkey ??
        await _ensureHotkey(context, allowHardwareGeneration: true);

    state = AsyncData(
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.keystoneSigning,
        isHardwareAccount: true,
        resumePlan: plan,
        keystoneSignatures: signatures,
        currentBundleIndex: nextUnsignedBundle,
        clearKeystoneSigningRequest: true,
        clearKeystoneScanError: true,
        clearError: true,
      ),
    );

    final request = await ref
        .read(votingRustApiProvider)
        .buildKeystoneDelegationRequest(
          dbPath: context.dbPath,
          lightwalletdUrl: context.lightwalletdUrl,
          network: context.network,
          roundParams: context.round.toRoundParams(),
          roundName: context.round.title,
          sessionJson: context.round.sessionJson,
          accountUuid: context.accountUuid,
          hotkeySeed: hotkeySeed,
          bundleIndex: nextUnsignedBundle,
        );

    state = AsyncData(
      (state.value ?? current).copyWith(
        phase: VotingSessionPhase.keystoneSigning,
        isHardwareAccount: true,
        eligibleWeightZatoshi: request.eligibleWeightZatoshi,
        keystoneSigningRequest: request,
        keystoneSignatures: signatures,
        currentBundleIndex: nextUnsignedBundle,
        clearKeystoneScanError: true,
        clearError: true,
      ),
    );
  }

  Future<void> _prepareDelegationUnlocked() async {
    final current = await future;
    final context = await _loadContext(_roundId);
    await _waitUntilWalletReadyForVoting(context);
    state = AsyncData(
      current.copyWith(
        phase: VotingSessionPhase.resolvingPir,
        config: context.config,
        round: context.round,
        resumePlan: context.resumePlan,
        isHardwareAccount: context.isHardwareAccount,
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
        isHardwareAccount: context.isHardwareAccount,
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
        isHardwareAccount: context.isHardwareAccount,
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
    final isHardwareAccount = await _isHardwareAccountForSession();
    final endpoint = ref.read(votingRpcEndpointConfigProvider);
    final dbPath = await ref.read(votingWalletDbPathProvider).call();
    final context = _VotingSessionContext(
      dbPath: dbPath,
      accountUuid: accountUuid,
      isHardwareAccount: isHardwareAccount,
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

  Future<bool> _isHardwareAccountForSession() async {
    final existing = _sessionIsHardwareAccount;
    if (existing != null) return existing;

    final accountUuid = await _accountUuidForSession();
    final isHardware = await ref
        .read(votingAccountIsHardwareProvider)
        .call(accountUuid);
    _sessionIsHardwareAccount = isHardware;
    return isHardware;
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

  Future<void> _waitUntilWalletReadyForVoting(
    _VotingSessionContext context,
  ) async {
    var loggedWait = false;
    while (true) {
      final readiness = await ref
          .read(votingWalletSyncReadinessCheckerProvider)
          .check(
            dbPath: context.dbPath,
            network: context.network,
            snapshotHeight: context.round.snapshotHeight,
          );
      if (readiness.isReady) {
        _setWalletSyncReadinessState(
          context: context,
          readiness: readiness,
          waiting: false,
        );
        return;
      }

      if (!loggedWait) {
        loggedWait = true;
        debugPrint(
          '[zcash] Voting: waiting for wallet scan before voting '
          'round=${context.round.roundId} '
          'scanned=${readiness.scannedHeight} '
          'snapshot=${readiness.snapshotHeight}',
        );
      }
      _setWalletSyncReadinessState(
        context: context,
        readiness: readiness,
        waiting: true,
      );
      try {
        ref.read(votingWalletSyncStarterProvider).call();
      } catch (e) {
        debugPrint('[zcash] Voting: wallet sync start skipped: $e');
      }
      await Future<void>.delayed(
        ref.read(votingWalletSyncPollIntervalProvider),
      );
    }
  }

  void _setWalletSyncReadinessState({
    required _VotingSessionContext context,
    required VotingWalletSyncReadiness readiness,
    required bool waiting,
  }) {
    final current = state.value ?? VotingSessionState(roundId: _roundId);
    final phase = waiting
        ? VotingSessionPhase.waitingForWalletSync
        : current.phase == VotingSessionPhase.waitingForWalletSync
        ? VotingSessionPhase.idle
        : current.phase;
    state = AsyncData(
      current.copyWith(
        phase: phase,
        config: context.config,
        round: context.round,
        resumePlan: context.resumePlan,
        isHardwareAccount: context.isHardwareAccount,
        walletScannedHeight: readiness.scannedHeight,
        walletSnapshotHeight: readiness.snapshotHeight,
        walletChainTipHeight: readiness.chainTipHeight,
        clearWalletSyncReadiness: !waiting,
        clearError: true,
      ),
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

  static Future<Map<String, dynamic>> _wireJsonMap(
    Future<String> wireJson,
  ) async {
    final decoded = jsonDecode(await wireJson);
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Rust voting wire JSON is not an object.');
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

  static void _verifyKeystoneDelegationSignature({
    required rust_voting.ApiSignedDelegationPayload submission,
    required rust_voting.ApiKeystoneSignatureRecord signature,
    required int bundleIndex,
  }) {
    if (!_bytesEqual(submission.rk, signature.rk) ||
        !_bytesEqual(submission.spendAuthSig, signature.sig) ||
        !_bytesEqual(submission.sighash, signature.sighash)) {
      throw StateError(
        'Keystone signature did not match delegation bundle $bundleIndex.',
      );
    }
  }

  static bool _hasHotkeyBoundRecoveryState(VotingResumePlan plan) {
    final delegationWorkflowRequiresHotkey = plan
        .recoveryState
        .delegationWorkflows
        .any((record) => record.phase != VotingWorkflowPhase.prepared);
    return delegationWorkflowRequiresHotkey ||
        plan.recoveryState.delegationTxHashes.isNotEmpty ||
        plan.votesByKey.isNotEmpty ||
        plan.votePhasesByKey.isNotEmpty ||
        plan.voteTxHashesByKey.isNotEmpty ||
        plan.commitmentBundlesByKey.isNotEmpty ||
        plan.shareDelegations.isNotEmpty ||
        plan.unconfirmedShareDelegations.isNotEmpty;
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static String _formatElapsed(Duration duration) {
    return '${(duration.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(2)}s';
  }
}

class _VotingSessionContext {
  final String dbPath;
  final String accountUuid;
  final bool isHardwareAccount;
  final String network;
  final String lightwalletdUrl;
  final VotingConfig config;
  final VotingRoundDetails round;
  final VotingResumePlan resumePlan;

  const _VotingSessionContext({
    required this.dbPath,
    required this.accountUuid,
    required this.isHardwareAccount,
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
