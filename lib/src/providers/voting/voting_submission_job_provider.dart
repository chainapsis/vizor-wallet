import '../../features/ledger/services/ledger_device_selection.dart';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/linux_keyring_coordinator.dart';
import '../../core/storage/linux_secret_operation_guard.dart';
import '../../features/keystone/services/keystone_batch_signing.dart';
import '../../features/voting/voting_message.dart';
import '../../features/ledger/services/ledger_failure_guidance.dart';
import '../../features/ledger/services/ledger_signing_service.dart';
import '../../features/voting/proxy/proxy_delegation_presentation.dart';
import '../../features/voting/proxy/proxy_delegation_repository.dart';
import '../../features/voting/proxy/proxy_delegator_client.dart';
import '../../features/voting/voting_flow_models.dart';
import '../../features/voting/voting_resume_plan.dart';
import '../../rust/api/keystone.dart' as rust_keystone;
import '../../rust/third_party/zcash_voting/delegate.dart' as rust_delegate;
import '../../rust/third_party/zcash_voting/wire.dart' as rust_wire;
import '../../services/voting/voting_retry.dart';
import '../../services/voting/voting_rust_exception.dart';
import '../account_provider.dart';
import '../rpc_endpoint_provider.dart';
import 'proxy_delegator_host.dart';
import 'voting_session_provider.dart';
import 'voting_service_providers.dart';
import 'voting_state.dart';
import 'voting_share_tracking_registry_provider.dart';
import 'voting_submission_guard_provider.dart';

enum VotingSubmissionJobStatus {
  idle,
  running,
  waitingForKeystone,
  waitingForLedger,
  complete,
  error,
}

/// Which flow a submission job runs.
enum VotingSubmissionJobKind {
  /// The ballot: delegation of the account's notes, casts and shares.
  ballot,

  /// A committed proxy allocation: its batches and DC shares (plan section
  /// 4.5, Job).
  proxy,
}

/// Where a proxy delegation job stands.
enum ProxyJobStage {
  /// Proving the batches.
  preparing,

  /// Waiting for a hardware signature on a batch's registration.
  signing,

  /// A batch is on its way to the voting chain.
  submitting,

  /// Delivering the landed DCs' shares, or waiting for background share
  /// tracking to confirm share 0's reveal.
  handingOff,

  /// The chain refused a sent batch; the job keeps sending it until it lands
  /// or `vote_end` passes.
  refused,

  /// Every delegation is handed off, with every immediate share 0 revealed.
  complete,

  /// The round closed before a delegation was handed off.
  notCounted,

  /// `vote_end` passed before the job could complete.
  expired,
}

/// Why a proxy job ended without its delegation being sent.
enum ProxyJobTerminalReason { notCounted, expired }

/// The pacing of a proxy job's cycles.
@immutable
class ProxyJobCycleDelays {
  /// Creates the delays.
  const ProxyJobCycleDelays({
    this.working = const Duration(seconds: 5),
    this.waiting = const Duration(seconds: 30),
    this.retry = const Duration(seconds: 10),
  });

  /// Between cycles while batches or shares are moving.
  final Duration working;

  /// Between cycles while the chain refuses a sent batch.
  final Duration waiting;

  /// After a cycle failed for a reason a later one can overcome, or left a
  /// submission pending ([VotingProxyDriveOutcome.chainPending]).
  final Duration retry;
}

/// The pacing proxy jobs use; tests shorten it.
final proxyJobCycleDelaysProvider = Provider<ProxyJobCycleDelays>(
  (_) => const ProxyJobCycleDelays(),
);

/// The clock submission jobs judge `vote_end` by; tests replace it.
final votingSubmissionJobClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// Reads zcash_voting's delegation progress for a job's round and account.
typedef ProxyJobProgressReader =
    Future<ApiProxyDelegationProgress?> Function(VotingSessionKey key);

/// zcash_voting's `proxy::progress` for a job, through the delegator client
/// bound to the job's pinned session.
final proxyJobProgressReaderProvider = Provider<ProxyJobProgressReader>((ref) {
  final clients = <VotingSessionKey, ProxyDelegatorClient>{};
  return (key) => (clients[key] ??= ProxyDelegatorClient(
    host: SessionProxyDelegatorHost(ref, key: key),
  )).progress(key.roundId);
});

/// Display metadata for requests included in the currently shown Keystone QR.
@immutable
class VotingKeystoneBatchMemo {
  const VotingKeystoneBatchMemo({
    required this.bundleIndex,
    required this.bundleCount,
    required this.displayMemo,
  });

  final int bundleIndex;
  final int bundleCount;
  final String displayMemo;
}

@immutable
class VotingSubmissionJobState {
  const VotingSubmissionJobState({
    this.key,
    this.status = VotingSubmissionJobStatus.idle,
    this.generation = 0,
    this.errorMessage,
    this.retryable = true,
    this.softwareAccountRequired = false,
    this.keystoneUrParts = const [],
    this.keystoneBatchMemos = const [],
    this.keystoneBatchMessageCount = 0,
    this.keystoneBatchTotalCount = 0,
    this.keystoneQrError,
    this.ledgerDisplayMemo,
    this.ledgerBundleIndex,
    this.ledgerBundleCount = 0,
    this.ledgerRequestRebuilt = false,
    this.pendingDraftVotes,
    this.pendingProposalIds = const [],
    this.pendingRecoveryWithoutDraft = false,
    this.kind = VotingSubmissionJobKind.ballot,
    this.proxyStage,
    this.proxyProgress,
    this.terminalReason,
  });

  final VotingSessionKey? key;
  final VotingSubmissionJobStatus status;
  final int generation;
  final VotingMessage? errorMessage;

  /// False when retrying would resend a request the signer already refused.
  final bool retryable;
  final bool softwareAccountRequired;
  final List<String> keystoneUrParts;
  final List<VotingKeystoneBatchMemo> keystoneBatchMemos;
  final int keystoneBatchMessageCount;
  final int keystoneBatchTotalCount;
  final String? keystoneQrError;
  final String? ledgerDisplayMemo;
  final int? ledgerBundleIndex;
  final int ledgerBundleCount;
  final bool ledgerRequestRebuilt;
  final List<VotingDraftVote>? pendingDraftVotes;
  final List<int> pendingProposalIds;
  final bool pendingRecoveryWithoutDraft;

  /// Which flow the job runs.
  final VotingSubmissionJobKind kind;

  /// A proxy job's stage; null for a ballot job.
  final ProxyJobStage? proxyStage;

  /// zcash_voting's latest view of the round's delegation, when the job
  /// has read one.
  final ApiProxyDelegationProgress? proxyProgress;

  /// Why a proxy job ended without its delegation being sent.
  final ProxyJobTerminalReason? terminalReason;

  bool get hasVisibleJob =>
      key != null && status != VotingSubmissionJobStatus.idle;

  bool get isInFlight =>
      status == VotingSubmissionJobStatus.running ||
      status == VotingSubmissionJobStatus.waitingForKeystone ||
      status == VotingSubmissionJobStatus.waitingForLedger;

  VotingSubmissionJobState copyWith({
    VotingSessionKey? key,
    VotingSubmissionJobStatus? status,
    int? generation,
    VotingMessage? errorMessage,
    bool clearErrorMessage = false,
    bool? retryable,
    bool? softwareAccountRequired,
    List<String>? keystoneUrParts,
    List<VotingKeystoneBatchMemo>? keystoneBatchMemos,
    int? keystoneBatchMessageCount,
    int? keystoneBatchTotalCount,
    String? keystoneQrError,
    bool clearKeystoneQrError = false,
    String? ledgerDisplayMemo,
    bool clearLedgerDisplayMemo = false,
    int? ledgerBundleIndex,
    bool clearLedgerBundleIndex = false,
    int? ledgerBundleCount,
    bool? ledgerRequestRebuilt,
    List<VotingDraftVote>? pendingDraftVotes,
    bool clearPendingDraftVotes = false,
    List<int>? pendingProposalIds,
    bool? pendingRecoveryWithoutDraft,
    VotingSubmissionJobKind? kind,
    ProxyJobStage? proxyStage,
    ApiProxyDelegationProgress? proxyProgress,
    bool clearProxyProgress = false,
    ProxyJobTerminalReason? terminalReason,
  }) {
    return VotingSubmissionJobState(
      key: key ?? this.key,
      status: status ?? this.status,
      generation: generation ?? this.generation,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      retryable: retryable ?? this.retryable,
      softwareAccountRequired:
          softwareAccountRequired ?? this.softwareAccountRequired,
      keystoneUrParts: keystoneUrParts ?? this.keystoneUrParts,
      keystoneBatchMemos: keystoneBatchMemos ?? this.keystoneBatchMemos,
      keystoneBatchMessageCount:
          keystoneBatchMessageCount ?? this.keystoneBatchMessageCount,
      keystoneBatchTotalCount:
          keystoneBatchTotalCount ?? this.keystoneBatchTotalCount,
      keystoneQrError: clearKeystoneQrError
          ? null
          : keystoneQrError ?? this.keystoneQrError,
      ledgerDisplayMemo: clearLedgerDisplayMemo
          ? null
          : ledgerDisplayMemo ?? this.ledgerDisplayMemo,
      ledgerBundleIndex: clearLedgerBundleIndex
          ? null
          : ledgerBundleIndex ?? this.ledgerBundleIndex,
      ledgerBundleCount: ledgerBundleCount ?? this.ledgerBundleCount,
      ledgerRequestRebuilt: ledgerRequestRebuilt ?? this.ledgerRequestRebuilt,
      pendingDraftVotes: clearPendingDraftVotes
          ? null
          : pendingDraftVotes ?? this.pendingDraftVotes,
      pendingProposalIds: pendingProposalIds ?? this.pendingProposalIds,
      pendingRecoveryWithoutDraft:
          pendingRecoveryWithoutDraft ?? this.pendingRecoveryWithoutDraft,
      kind: kind ?? this.kind,
      proxyStage: proxyStage ?? this.proxyStage,
      proxyProgress: clearProxyProgress
          ? null
          : proxyProgress ?? this.proxyProgress,
      terminalReason: terminalReason ?? this.terminalReason,
    );
  }
}

@immutable
class VotingSubmissionJobsState {
  const VotingSubmissionJobsState({
    this.jobKeys = const [],
    this.startErrorsByRoundId = const {},
  });

  final List<VotingSessionKey> jobKeys;
  final Map<String, VotingMessage> startErrorsByRoundId;

  bool get hasJobs => jobKeys.isNotEmpty;

  VotingMessage? startErrorForRound(String roundId) =>
      startErrorsByRoundId[roundId];

  VotingSubmissionJobsState copyWith({
    List<VotingSessionKey>? jobKeys,
    Map<String, VotingMessage>? startErrorsByRoundId,
  }) {
    return VotingSubmissionJobsState(
      jobKeys: jobKeys ?? this.jobKeys,
      startErrorsByRoundId: startErrorsByRoundId ?? this.startErrorsByRoundId,
    );
  }

  VotingSubmissionJobsState addJobKey(VotingSessionKey key) {
    if (jobKeys.contains(key)) {
      return clearStartError(key.roundId);
    }
    return copyWith(
      jobKeys: [...jobKeys, key],
      startErrorsByRoundId: _withoutStartError(key.roundId),
    );
  }

  VotingSubmissionJobsState setStartError(
    String roundId,
    VotingMessage message,
  ) {
    return copyWith(
      startErrorsByRoundId: {...startErrorsByRoundId, roundId: message},
    );
  }

  VotingSubmissionJobsState clearStartError(String roundId) {
    if (!startErrorsByRoundId.containsKey(roundId)) return this;
    return copyWith(startErrorsByRoundId: _withoutStartError(roundId));
  }

  VotingSubmissionJobsState removeJobKey(VotingSessionKey key) {
    if (!jobKeys.contains(key)) return this;
    return copyWith(
      jobKeys: [
        for (final jobKey in jobKeys)
          if (jobKey != key) jobKey,
      ],
    );
  }

  Map<String, VotingMessage> _withoutStartError(String roundId) {
    return {
      for (final entry in startErrorsByRoundId.entries)
        if (entry.key != roundId) entry.key: entry.value,
    };
  }
}

class VotingSubmissionJobsNotifier extends Notifier<VotingSubmissionJobsState> {
  @override
  VotingSubmissionJobsState build() => const VotingSubmissionJobsState();

  Future<VotingSessionKey?> start(String roundId, {String? accountUuid}) async {
    final String? resolvedAccountUuid;
    try {
      resolvedAccountUuid = accountUuid ?? await _activeAccountUuid();
    } catch (error) {
      state = state.setStartError(roundId, votingMessageForError(error));
      return null;
    }
    if (resolvedAccountUuid == null) {
      state = state.setStartError(
        roundId,
        const VotingNotice(VotingNoticeKind.noActiveAccount),
      );
      return null;
    }

    final key = VotingSessionKey(
      roundId: roundId,
      accountUuid: resolvedAccountUuid,
    );
    state = state.addJobKey(key);
    await ref.read(votingSubmissionJobProvider(key).notifier).start();
    return key;
  }

  Future<void> retry(VotingSessionKey key) async {
    state = state.addJobKey(key);
    await ref.read(votingSubmissionJobProvider(key).notifier).retry();
  }

  /// Starts the round's proxy delegation job for [accountUuid], or the
  /// active account, as [VotingSubmissionJobNotifier.startProxy] decides.
  /// Returns the job's key, or null when no account is active.
  Future<VotingSessionKey?> startProxy(
    String roundId, {
    String? accountUuid,
  }) async {
    final String? resolvedAccountUuid;
    try {
      resolvedAccountUuid = accountUuid ?? await _activeAccountUuid();
    } catch (error) {
      state = state.setStartError(roundId, votingMessageForError(error));
      return null;
    }
    if (resolvedAccountUuid == null) return null;
    final key = VotingSessionKey(
      roundId: roundId,
      accountUuid: resolvedAccountUuid,
    );
    state = state.addJobKey(key);
    await ref.read(votingSubmissionJobProvider(key).notifier).startProxy();
    return key;
  }

  Future<void> cancelLedgerSigning(VotingSessionKey key) {
    return ref
        .read(votingSubmissionJobProvider(key).notifier)
        .cancelLedgerSigning();
  }

  void dismiss(VotingSessionKey key) {
    final jobProvider = votingSubmissionJobProvider(key);
    if (ref.read(jobProvider).isInFlight) return;
    ref.read(jobProvider.notifier).dismiss();
    ref.invalidate(votingSessionProvider(key.roundId));
    state = state.removeJobKey(key);
  }

  Future<void> handleKeystoneBatchSignResponse(
    VotingSessionKey key,
    List<int> responseCbor,
  ) {
    return ref
        .read(votingSubmissionJobProvider(key).notifier)
        .handleKeystoneBatchSignResponse(responseCbor);
  }

  Future<void> skipRemainingKeystoneBundles(VotingSessionKey key) {
    return ref
        .read(votingSubmissionJobProvider(key).notifier)
        .skipRemainingKeystoneBundles();
  }

  Future<String?> _activeAccountUuid() async {
    final votingAccountUuid = await ref
        .read(votingActiveAccountUuidProvider)
        .call();
    if (votingAccountUuid != null) return votingAccountUuid;
    final immediate = ref.read(accountProvider).value?.activeAccountUuid;
    if (immediate != null) return immediate;
    return (await ref.read(accountProvider.future)).activeAccountUuid;
  }
}

class VotingKeystoneSigningRound {
  const VotingKeystoneSigningRound._({
    required this.batchRequest,
    required this.requests,
  });

  final KeystoneBatchSigningRequest batchRequest;
  final List<rust_delegate.KeystoneSigningRequest> requests;

  static Future<VotingKeystoneSigningRound> prepare(
    VotingSessionKey key,
    List<rust_delegate.KeystoneSigningRequest> requests,
  ) async {
    final baseRequestId = _votingKeystoneRequestId(key, requests);
    final allMessages = _votingKeystoneBatchMessages(requests);
    final roundCounts = await rust_keystone.zcashSignBatchRoundMessageCounts(
      requestId: baseRequestId,
      messages: keystoneBatchMessageInputs(allMessages),
      maxMessages: _votingKeystoneBatchMaxMessages,
    );
    if (roundCounts.isEmpty || roundCounts.first <= 0) {
      throw StateError('Keystone returned an invalid voting batch plan.');
    }
    final messageCount = roundCounts.first;
    if (messageCount > requests.length) {
      throw StateError('Keystone voting batch plan exceeds the request.');
    }
    final roundRequests = requests.sublist(0, messageCount);
    final batchRequest = await buildPreparedKeystoneBatchSigningRequest(
      requestId: baseRequestId,
      messages: _votingKeystoneBatchMessages(roundRequests),
    );
    return VotingKeystoneSigningRound._(
      batchRequest: batchRequest,
      requests: roundRequests,
    );
  }

  Future<List<VotingKeystoneBatchSignature>> decodeSignatures(
    List<int> responseCbor,
  ) async {
    final decoded = await batchRequest.decodeTypedResponse(responseCbor);
    if (decoded.results.length != requests.length) {
      throw StateError(
        'Keystone returned a different number of voting signatures than requested.',
      );
    }

    final batchSignatures = <VotingKeystoneBatchSignature>[];
    for (var index = 0; index < requests.length; index++) {
      final request = requests[index];
      final result = decoded.results[index];
      // Compact responses carry ordered signature lists without message IDs.
      // Rust checks the request ID and count before restoring request order.
      if (result.sigs.length != 1) {
        throw StateError(
          'Keystone returned signatures that do not match this voting request.',
        );
      }
      final signature = result.sigs.single;
      batchSignatures.add(
        VotingKeystoneBatchSignature(
          bundleIndex: request.bundleIndex,
          pool: signature.pool,
          actionIndex: signature.actionIndex,
          signature: signature.sig,
        ),
      );
    }
    return batchSignatures;
  }
}

class VotingSubmissionJobNotifier extends Notifier<VotingSubmissionJobState> {
  VotingSubmissionJobNotifier(this._key);

  final VotingSessionKey _key;
  VotingSubmissionGuard? _guard;
  ProviderSubscription<AsyncValue<VotingSessionState>>? _sessionSubscription;
  VotingSessionKey? _retainedSessionKey;
  Timer? _completionPollTimer;
  Future<void>? _immediateConfirmationCheck;
  Future<void>? _expiryConfirmationCheck;
  VotingKeystoneSigningRound? _keystoneSigningRound;
  int _nextGeneration = 0;
  Timer? _proxyCycleTimer;
  bool _proxyCycleRunning = false;
  bool _proxyCycleAgain = false;
  bool _proxyFinalCheckDone = false;
  int _proxyProgressReads = 0;
  Future<void>? _ballotProxyDrive;
  DateTime? _lastBallotProxyDriveAt;
  Timer? _proxyKeepAliveTimer;
  ProviderSubscription<AsyncValue<VotingSessionState>>? _proxyKeepAliveSession;
  bool _proxyKeepAliveFinalDrive = false;

  /// Whether this job start already sent casts that stopped for a signature
  /// back to signing (see [_routeCastsToSigning]).
  bool _castSigningRerouted = false;

  /// Bundles a ballot job's batch signing also signs, for the casts that
  /// follow the batches (see [keptBundlesSigningFirstCast]).
  List<int> _keptCastSigningBundles = const [];

  @override
  VotingSubmissionJobState build() {
    ref.onDispose(() {
      _completionPollTimer?.cancel();
      _completionPollTimer = null;
      _cancelProxyCycle();
      _stopProxyKeepAlive();
      _releaseSessionSubscription();
    });
    listenSelf((_, next) => _followJobForProxyKeepAlive(next));
    return VotingSubmissionJobState(key: _key);
  }

  /// Starts the ballot job, unless one is visible.
  ///
  /// A proxy job hands the round over (the last-moment hand-off into the
  /// vote flow): its cycles stop and the ballot job, which sends any batch
  /// not yet landed first (see [_sendProxyBatchesFirst]) and whose round runs
  /// then drive the rest of the proxy work, completes only once that work is
  /// settled. A proxy
  /// job waiting for a hardware signature keeps the round, because the vote
  /// status screen is where that signature is collected, and so does one
  /// whose account has no ballot to add (see [_hasBallotToAdd]). A vote job
  /// that then fails or waits for a hardware signature keeps the DC shares
  /// moving (see [_followJobForProxyKeepAlive]).
  Future<void> start() async {
    if (_isHandOverableProxyJob(state) && !await _hasBallotToAdd()) {
      await startProxy();
      return;
    }
    final current = state;
    if (_isHandOverableProxyJob(current)) {
      _cancelProxyCycle();
      _startJob(_key);
      return;
    }
    if (current.hasVisibleJob) return;
    _startJob(_key);
  }

  /// Whether [job] is a proxy job a vote job may take the round from: one
  /// not waiting for a hardware signature.
  static bool _isHandOverableProxyJob(VotingSubmissionJobState job) =>
      job.kind == VotingSubmissionJobKind.proxy &&
      job.status != VotingSubmissionJobStatus.waitingForKeystone &&
      job.status != VotingSubmissionJobStatus.waitingForLedger;

  /// Whether the account has a ballot for a vote job to cast: drafted
  /// answers, or votes the plan still owes, including recorded answers an
  /// unlanded batch withholds. Without one, as when the delegates took
  /// everything, a vote job would only stall the proxy work, so the proxy
  /// job keeps the round.
  Future<bool> _hasBallotToAdd() async {
    try {
      final draft = await ref
          .read(votingDraftProvider(_key).notifier)
          .ensureLoaded();
      if (!draft.isEmpty) return true;
    } catch (_) {
      return true;
    }
    final plan = _sessionForJob(_key)?.roundPlan;
    return roundPlanOwesBallotCasts(plan) ||
        voteCarryingBundleIndexes(plan).isNotEmpty;
  }

  Future<void> retry() async {
    _releaseGuard();
    _keystoneSigningRound = null;
    if (state.kind == VotingSubmissionJobKind.proxy) {
      state = VotingSubmissionJobState(
        key: _key,
        proxyProgress: state.proxyProgress,
      );
      _startProxyJob(_key);
      return;
    }
    state = VotingSubmissionJobState(key: _key);
    _startJob(_key);
  }

  /// Starts the round's proxy delegation job (plan section 4.5, Job).
  ///
  /// A job in flight, of either kind, keeps running and only reads progress
  /// again: a ballot job drives the round's proxy work too. A proxy job that
  /// failed short of a terminal outcome starts again; a finished one reads
  /// progress again.
  Future<void> startProxy() async {
    final current = state;
    final restart =
        current.status == VotingSubmissionJobStatus.idle ||
        (current.kind == VotingSubmissionJobKind.proxy &&
            current.status == VotingSubmissionJobStatus.error &&
            current.terminalReason == null);
    if (restart) {
      _startProxyJob(_key);
      return;
    }
    await _refreshProxyProgress(key: _key, generation: current.generation);
  }

  Future<void> cancelLedgerSigning() async {
    final current = state;
    if (current.status != VotingSubmissionJobStatus.waitingForLedger) return;
    final key = current.key;
    if (key == null) return;

    // Invalidate first: a device result racing cancellation cannot be
    // persisted or advance this job after the user has cancelled it.
    final generation = ++_nextGeneration;
    _cancelCompletionPoll();
    _releaseGuard();
    _releaseSessionSubscription();
    _keystoneSigningRound = null;
    state = VotingSubmissionJobState(
      key: key,
      status: VotingSubmissionJobStatus.error,
      generation: generation,
      errorMessage: const VotingNotice(VotingNoticeKind.ledgerCancelled),
      kind: current.kind,
      proxyStage: current.proxyStage,
      proxyProgress: current.proxyProgress,
    );
    try {
      await ref.read(ledgerOperationCancellerProvider)();
    } catch (error) {
      debugPrint('[zcash] Voting: Ledger cancellation failed: $error');
    }
  }

  /// Clears a job that is not in flight. A failed vote job whose round
  /// still owes proxy work hands it back to a proxy job, so dismissing the
  /// vote's error never stops DC share delivery.
  void dismiss() {
    if (state.isInFlight) return;
    final handBack =
        _stallsProxyWork(state) &&
        roundPlanHasProxyWork(_sessionForJob(_key)?.roundPlan);
    _cancelCompletionPoll();
    _cancelProxyCycle();
    _releaseGuard();
    _releaseSessionSubscription();
    _keystoneSigningRound = null;
    state = VotingSubmissionJobState(key: _key, generation: ++_nextGeneration);
    if (handBack) _startProxyJob(_key);
  }

  void _startJob(VotingSessionKey key) {
    _cancelCompletionPoll();
    _castSigningRerouted = false;
    _keptCastSigningBundles = const [];
    _replaceGuard(accountUuid: key.accountUuid, roundId: key.roundId);
    _retainSession(key);
    _keystoneSigningRound = null;
    final sessionNotifier = ref.read(
      votingSubmissionSessionProvider(key).notifier,
    );
    sessionNotifier.clearVoteSubmissionProgressForJobStart();
    final generation = ++_nextGeneration;
    state = VotingSubmissionJobState(
      key: key,
      status: VotingSubmissionJobStatus.running,
      generation: generation,
      proxyProgress: state.proxyProgress,
    );
    unawaited(_run(key: key, generation: generation));
  }

  /// Starts a proxy job for [key]: its first cycle runs now.
  void _startProxyJob(VotingSessionKey key) {
    _cancelCompletionPoll();
    _cancelProxyCycle();
    _keptCastSigningBundles = const [];
    _replaceGuard(accountUuid: key.accountUuid, roundId: key.roundId);
    _retainSession(key);
    _keystoneSigningRound = null;
    _proxyFinalCheckDone = false;
    final generation = ++_nextGeneration;
    state = VotingSubmissionJobState(
      key: key,
      status: VotingSubmissionJobStatus.running,
      generation: generation,
      kind: VotingSubmissionJobKind.proxy,
      proxyStage: ProxyJobStage.preparing,
      proxyProgress: state.proxyProgress,
    );
    unawaited(_runProxyCycle(key: key, generation: generation));
  }

  Future<void> handleKeystoneBatchSignResponse(List<int> responseCbor) async {
    final job = state;
    final key = job.key;
    final signingRound = _keystoneSigningRound;
    if (key == null ||
        !job.isInFlight ||
        responseCbor.isEmpty ||
        signingRound == null) {
      return;
    }
    final generation = job.generation;
    final sessionNotifier = ref.read(
      votingSubmissionSessionProvider(key).notifier,
    );
    late final List<VotingKeystoneBatchSignature> batchSignatures;
    try {
      batchSignatures = await signingRound.decodeSignatures(responseCbor);
      if (!_isCurrentJob(key: key, generation: generation)) return;
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      await sessionNotifier.reportKeystoneScanError(
        const VotingNotice(VotingNoticeKind.keystoneResultMismatch),
      );
      return;
    }

    try {
      await sessionNotifier.handleKeystoneBatchSignatures(batchSignatures);
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final session = _sessionForJob(key);
      if (session == null) return;
      if (session.phase == VotingSessionPhase.error) {
        _failFromSession(key: key, generation: generation, session: session);
        return;
      }
      final requests = session.keystoneSigningRequests;
      if (requests.isNotEmpty) {
        // Validation and persistence failures are recoverable scan errors. Keep
        // the current request ID and QR so the same Keystone response can be
        // scanned again instead of replacing the active signing round.
        if (session.keystoneScanError != null) return;
        await _updateKeystoneQr(
          key: key,
          generation: generation,
          requests: requests,
        );
        return;
      }
      await _submitAfterHardwareSignatures(
        sessionNotifier,
        key: key,
        generation: generation,
      );
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _failJob(
        key: key,
        generation: generation,
        message: _messageFromError(error),
      );
    }
  }

  Future<void> skipRemainingKeystoneBundles() async {
    final job = state;
    final key = job.key;
    if (key == null || !job.isInFlight) return;
    final generation = job.generation;
    try {
      _setRunning(key: key, generation: generation);
      final sessionNotifier = ref.read(
        votingSubmissionSessionProvider(key).notifier,
      );
      await sessionNotifier.skipRemainingKeystoneBundles();
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final session = _sessionForJob(key);
      if (session?.phase == VotingSessionPhase.error) {
        _failFromSession(key: key, generation: generation, session: session!);
        return;
      }
      await _submitAfterHardwareSignatures(
        sessionNotifier,
        key: key,
        generation: generation,
      );
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _failJob(
        key: key,
        generation: generation,
        message: _messageFromError(error),
      );
    }
  }

  Future<void> _run({
    required VotingSessionKey key,
    required int generation,
  }) async {
    try {
      final sessionProvider = votingSubmissionSessionProvider(key);
      final sessionNotifier = ref.read(sessionProvider.notifier);
      final loadedSession = await ref.read(sessionProvider.future);
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final round = loadedSession.round;
      if (round == null) {
        _failJob(
          key: key,
          generation: generation,
          message: const VotingNotice(VotingNoticeKind.roundDetailsUnavailable),
        );
        return;
      }

      final proposals = proposalsFromRound(round);
      VotingDraftState draft;
      try {
        draft = await ref
            .read(votingDraftProvider(key).notifier)
            .ensureLoaded();
      } catch (_) {
        if (!_isCurrentJob(key: key, generation: generation)) return;
        final activeSession = await _ensureEligibilityForCompletedSession(
          key: key,
          generation: generation,
          sessionNotifier: sessionNotifier,
          session: loadedSession,
        );
        if (activeSession == null) return;
        if (_canCompleteSessionAfterDraftLoadFailure(activeSession)) {
          _completeJob(key: key, generation: generation);
          return;
        }
        rethrow;
      }
      if (!_isCurrentJob(key: key, generation: generation)) return;
      if (_canCompleteSessionWithoutDraft(loadedSession, draft)) {
        _completeJob(key: key, generation: generation);
        return;
      }
      if (round.voteEndTime == null) {
        _failJob(
          key: key,
          generation: generation,
          message: const VotingNotice(VotingNoticeKind.roundEndTimeUnavailable),
        );
        return;
      }

      await sessionNotifier.ensureWalletReadyForVoting();
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final afterWalletSync = _sessionForJob(key);
      if (afterWalletSync?.phase == VotingSessionPhase.error ||
          afterWalletSync?.phase == VotingSessionPhase.waitingForWalletSync) {
        if (afterWalletSync?.phase == VotingSessionPhase.error) {
          _failFromSession(
            key: key,
            generation: generation,
            session: afterWalletSync!,
          );
        }
        return;
      }

      var activeSession = afterWalletSync ?? loadedSession;
      final completedEligibilitySession =
          await _ensureEligibilityForCompletedSession(
            key: key,
            generation: generation,
            sessionNotifier: sessionNotifier,
            session: activeSession,
          );
      if (completedEligibilitySession == null) return;
      activeSession = completedEligibilitySession;
      if (!draft.isEmpty && !activeSession.hasConfirmedVotingEligibility) {
        await sessionNotifier.ensureVotingEligibility();
        if (!_isCurrentJob(key: key, generation: generation)) return;
        final afterEligibilityCheck = _sessionForJob(key);
        if (afterEligibilityCheck?.phase == VotingSessionPhase.error) {
          _failFromSession(
            key: key,
            generation: generation,
            session: afterEligibilityCheck!,
          );
          return;
        }
        activeSession = afterEligibilityCheck ?? activeSession;
      }
      if (_canCompleteSessionWithoutDraft(activeSession, draft)) {
        _completeJob(key: key, generation: generation);
        return;
      }
      final userDraftVotes = _draftForSession(
        draft,
        activeSession,
      ).toDraftVotes(proposals);
      final recoveredDraftVotes =
          userDraftVotes.isEmpty && _roundPlanHasNoOpenProposals(activeSession)
          ? _draftVotesFromRoundPlan(activeSession.roundPlan, proposals)
          : const <VotingDraftVote>[];
      final draftVotes = userDraftVotes.isNotEmpty
          ? userDraftVotes
          : recoveredDraftVotes;
      final intentProposalIds = userDraftVotes.isNotEmpty
          ? _proposalIdsForDraftIntents(activeSession, proposals)
          : const <int>[];
      final canRecoverWithoutDraft = _canRecoverWithoutDraft(activeSession);
      final canPollDelegationWithoutDraft = _canPollDelegationWithoutDraft(
        activeSession,
      );
      if ((draftVotes.isNotEmpty ||
              _hasRemainingVoteOrShareWork(activeSession) ||
              canPollDelegationWithoutDraft) &&
          !activeSession.hasConfirmedVotingEligibility) {
        await sessionNotifier.ensureVotingEligibility();
        if (!_isCurrentJob(key: key, generation: generation)) return;
        final afterEligibilityCheck = _sessionForJob(key);
        if (afterEligibilityCheck?.phase == VotingSessionPhase.error) {
          _failFromSession(
            key: key,
            generation: generation,
            session: afterEligibilityCheck!,
          );
          return;
        }
        activeSession = afterEligibilityCheck ?? activeSession;
      }
      if (roundPlanHasUnlandedProxyBatch(activeSession.roundPlan)) {
        // One hardware signing covers the batches and the casts after them.
        _keptCastSigningBundles = draftVotes.isEmpty
            ? const []
            : keptBundlesSigningFirstCast(activeSession.roundPlan);
        await _sendProxyBatchesFirst(key: key, generation: generation);
        return;
      }
      final nothingLeftPlan = activeSession.roundPlan;
      if (roundPlanNothingLeftToVote(nothingLeftPlan) &&
          !nothingLeftPlan!.nextSteps.any(isVoteNextStep)) {
        // Delegates took every bundle's weight: no ballot is cast, so the
        // job only waits, through the completion poll that drives proxy
        // work, for the delegations to settle. A vote the chain lifecycle
        // already owns falls through to be driven as recovery.
        if (_canCompleteSubmission(activeSession)) {
          _completeJob(key: key, generation: generation);
        } else {
          _scheduleCompletionPoll(key: key, generation: generation);
        }
        return;
      }
      var needsDelegation = _sessionNeedsDelegation(activeSession);
      var needsDelegationSigning = _sessionNeedsDelegationSigning(
        activeSession,
      );
      if (draftVotes.isEmpty &&
          !canRecoverWithoutDraft &&
          !canPollDelegationWithoutDraft) {
        _failJob(
          key: key,
          generation: generation,
          message: const VotingNotice(VotingNoticeKind.noVoteChosen),
        );
        return;
      }

      // The ballot is recorded before either account type branches, because
      // the plan every branch below reads is derived from it: the SDK plans a
      // bundle's delegation only while that bundle still has a vote to cast,
      // so a round whose intents are not yet durable reports no delegation
      // work and no bundle needing a signature. A Keystone voter took that as
      // "nothing to sign", showed no QR, and reached the cast with a
      // delegation that now needed a device signature nobody had asked for;
      // a fresh hardware round could not be voted at all.
      //
      // `recordBallotIntents` is idempotent and persists the bundle plan
      // first, so this is also what gives a fresh round the rows the
      // delegation flags are computed from.
      if (draftVotes.isNotEmpty &&
          (needsDelegation || needsDelegationSigning)) {
        await sessionNotifier.recordBallotIntents(
          draftVotes: draftVotes,
          allProposalIds: intentProposalIds,
        );
        if (!_isCurrentJob(key: key, generation: generation)) return;
        final afterIntents = _sessionForJob(key);
        if (afterIntents?.phase == VotingSessionPhase.error) {
          _failFromSession(
            key: key,
            generation: generation,
            session: afterIntents!,
          );
          return;
        }
        activeSession = afterIntents ?? activeSession;
        // Widened, never narrowed: recording the ballot can only add work — a
        // bundle with a vote to cast now owes the delegation that carries it —
        // so a round that already owed delegation still owes it, and a plan
        // that reports less than the pre-ballot one did must not be read as
        // the round having been relieved of it.
        needsDelegation =
            needsDelegation || _sessionNeedsDelegation(activeSession);
        needsDelegationSigning =
            needsDelegationSigning ||
            _sessionNeedsDelegationSigning(activeSession);
      }

      if (activeSession.isHardwareAccount && needsDelegationSigning) {
        _storePendingHardwareState(
          key: key,
          generation: generation,
          draftVotes: draftVotes,
          intentProposalIds: intentProposalIds,
          pendingRecoveryWithoutDraft:
              canRecoverWithoutDraft || canPollDelegationWithoutDraft,
        );
        if (activeSession.isLedgerAccount) {
          await _prepareAndSignWithLedger(
            sessionNotifier,
            key: key,
            generation: generation,
          );
        } else {
          await _prepareKeystoneSigning(
            sessionNotifier,
            key: key,
            generation: generation,
          );
        }
        return;
      }

      if (activeSession.isHardwareAccount &&
          (draftVotes.isNotEmpty || needsDelegation)) {
        if (needsDelegation) {
          _storePendingHardwareState(
            key: key,
            generation: generation,
            draftVotes: draftVotes,
            intentProposalIds: intentProposalIds,
            pendingRecoveryWithoutDraft:
                canRecoverWithoutDraft || canPollDelegationWithoutDraft,
          );
          await _submitAfterHardwareSignatures(
            sessionNotifier,
            key: key,
            generation: generation,
            signerKind: activeSession.hardwareSignerKind,
          );
        } else {
          await _submitVotesAndShares(
            sessionNotifier,
            key: key,
            generation: generation,
            draftVotes: draftVotes,
            intentProposalIds: intentProposalIds,
            initialSession: activeSession,
          );
        }
        return;
      }
      String? softwareMnemonic;
      LinuxSecretOperationGuard? secretGuard;
      // Gated on `needsDelegation`, not `needsDelegationSigning`: the SDK
      // round driver can need the seed to advance an in-flight delegation,
      // which is why 17ca6f0b7 widened this. The guard follows the same
      // condition as the secret it protects.
      if (!activeSession.isHardwareAccount && needsDelegation) {
        secretGuard = LinuxSecretOperationGuard(
          store: ref.read(linuxSecretOperationStoreProvider),
          coordinator: ref.read(linuxKeyringCoordinatorProvider),
          isRequestCurrent: () =>
              _isCurrentJob(key: key, generation: generation),
          readAccounts: () => ref.read(accountProvider).value,
          accountUuid: key.accountUuid,
        );
        final softwareSecret = await ref
            .read(accountProvider.notifier)
            .getSoftwareWalletSecretForAccount(key.accountUuid);
        if (!_isCurrentJob(key: key, generation: generation)) return;
        secretGuard.check();
        softwareMnemonic = softwareSecret?.encodeForStorage();
        if (softwareMnemonic == null || softwareMnemonic.isEmpty) {
          _failJob(
            key: key,
            generation: generation,
            message: const VotingNotice(
              VotingNoticeKind.softwareAccountRequired,
            ),
            softwareAccountRequired: true,
          );
          return;
        }
      }
      if (needsDelegation) {
        if (!_isCurrentJob(key: key, generation: generation)) return;
        // The ballot is already durable: it is recorded above, before either
        // account type branches, because the delegation work this drives is
        // planned from it.
        secretGuard?.check();
        await sessionNotifier.delegatePendingBundles(
          mnemonic: softwareMnemonic,
        );
        if (!_isCurrentJob(key: key, generation: generation)) return;
        final afterDelegation = _sessionForJob(key);
        if (afterDelegation?.phase == VotingSessionPhase.error) {
          _failFromSession(
            key: key,
            generation: generation,
            session: afterDelegation!,
          );
          return;
        }
        if (_completeJobIfSubmissionDone(
          key: key,
          generation: generation,
          session: afterDelegation,
          requireNoUnconfirmedShares: true,
        )) {
          return;
        }
      }
      final afterDelegation = _sessionForJob(key);
      await _submitVotesAndShares(
        sessionNotifier,
        key: key,
        generation: generation,
        draftVotes: draftVotes,
        intentProposalIds: intentProposalIds,
        initialSession: afterDelegation ?? activeSession,
      );
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _failJob(
        key: key,
        generation: generation,
        message: _messageFromError(error),
      );
    }
  }

  /// Sends the round's proxy batches before the ballot: a ballot job runs
  /// proxy cycles, which carry the account's signer and collect a hardware
  /// signature, until no batch is left unlanded (see
  /// [roundPlanHasUnlandedProxyBatch]); [_settleProxyCycle] then runs the
  /// ballot again. The SDK withholds a bundle's casts until its batch lands,
  /// and the casts' own round runs carry no signer that could send it.
  Future<void> _sendProxyBatchesFirst({
    required VotingSessionKey key,
    required int generation,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    _cancelCompletionPoll();
    await _runProxyCycle(key: key, generation: generation);
  }

  /// Runs one proxy cycle, or marks another to follow the running one.
  Future<void> _runProxyCycle({
    required VotingSessionKey key,
    required int generation,
  }) async {
    if (_proxyCycleRunning) {
      _proxyCycleAgain = true;
      return;
    }
    _proxyCycleRunning = true;
    try {
      do {
        _proxyCycleAgain = false;
        await _proxyCycle(key: key, generation: generation);
      } while (_proxyCycleAgain &&
          _isCurrentJob(key: key, generation: generation) &&
          state.status == VotingSubmissionJobStatus.running);
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      // A request that got no answer is no verdict: the next cycle asks
      // again, so a restored job delivers once the network returns.
      if (isRetryableVotingError(error) || isVotingTransportError(error)) {
        _scheduleProxyCycle(
          key: key,
          generation: generation,
          delay: ref.read(proxyJobCycleDelaysProvider).retry,
        );
        return;
      }
      _failJob(
        key: key,
        generation: generation,
        message: _messageFromError(error),
      );
    } finally {
      _proxyCycleRunning = false;
    }
  }

  /// One proxy cycle: collect a hardware signature when the plan needs one,
  /// otherwise drive the round's proxy work once.
  ///
  /// A hardware account follows the vote flow's signing: the request is
  /// built for every bundle whose batch signs its registration, and the
  /// device's answer comes back through [_submitAfterHardwareSignatures],
  /// which drives the round. With every signature already stored, signing
  /// preparation goes straight on to that drive.
  Future<void> _proxyCycle({
    required VotingSessionKey key,
    required int generation,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final sessionProvider = votingSubmissionSessionProvider(key);
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final loaded = await ref.read(sessionProvider.future);
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final session = _sessionForJob(key) ?? loaded;
    if (session.isHardwareAccount &&
        (session.roundPlan?.needsDelegationSigning ?? false)) {
      _storePendingHardwareState(
        key: key,
        generation: generation,
        draftVotes: const [],
        intentProposalIds: const [],
        pendingRecoveryWithoutDraft: true,
      );
      state = state.copyWith(proxyStage: ProxyJobStage.signing);
      final alsoSign = state.kind == VotingSubmissionJobKind.ballot
          ? _keptCastSigningBundles
          : const <int>[];
      if (session.isLedgerAccount) {
        await _prepareAndSignWithLedger(
          sessionNotifier,
          key: key,
          generation: generation,
          alsoSign: alsoSign,
        );
      } else {
        await _prepareKeystoneSigning(
          sessionNotifier,
          key: key,
          generation: generation,
          alsoSign: alsoSign,
        );
      }
      return;
    }
    await _driveProxy(key: key, generation: generation);
  }

  /// Drives the round's proxy work once, reads zcash_voting's progress and
  /// decides what the job does next.
  ///
  /// A software account hands over its mnemonic only while a batch still
  /// proves or signs its bundle's registration.
  Future<void> _driveProxy({
    required VotingSessionKey key,
    required int generation,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final sessionNotifier = ref.read(
      votingSubmissionSessionProvider(key).notifier,
    );
    final session = _sessionForJob(key);
    if (session == null) return;
    final plan = session.roundPlan;
    String? mnemonic;
    if (!session.isHardwareAccount &&
        (delegationBundleIndexesNeedingSigning(plan).isNotEmpty ||
            roundPlanProxyNeedsRegistrationProof(plan))) {
      final secretGuard = LinuxSecretOperationGuard(
        store: ref.read(linuxSecretOperationStoreProvider),
        coordinator: ref.read(linuxKeyringCoordinatorProvider),
        isRequestCurrent: () => _isCurrentJob(key: key, generation: generation),
        readAccounts: () => ref.read(accountProvider).value,
        accountUuid: key.accountUuid,
      );
      final softwareSecret = await ref
          .read(accountProvider.notifier)
          .getSoftwareWalletSecretForAccount(key.accountUuid);
      if (!_isCurrentJob(key: key, generation: generation)) return;
      secretGuard.check();
      mnemonic = softwareSecret?.encodeForStorage();
      if (mnemonic == null || mnemonic.isEmpty) {
        _failJob(
          key: key,
          generation: generation,
          message: const VotingNotice(VotingNoticeKind.softwareAccountRequired),
          softwareAccountRequired: true,
        );
        return;
      }
    }
    if (state.proxyStage == ProxyJobStage.signing) {
      state = state.copyWith(proxyStage: ProxyJobStage.preparing);
    }
    final outcome = await sessionNotifier.driveProxyDelegation(
      mnemonic: mnemonic,
      hardwareSigner: session.isHardwareAccount
          ? session.hardwareSignerKind
          : null,
      onStepFinished: () =>
          unawaited(_refreshProxyProgress(key: key, generation: generation)),
    );
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final read = await _refreshProxyProgress(key: key, generation: generation);
    if (!_isCurrentJob(key: key, generation: generation)) return;
    // The job is settled only by a progress read that answered.
    if (!read) {
      _scheduleProxyCycle(
        key: key,
        generation: generation,
        delay: ref.read(proxyJobCycleDelaysProvider).retry,
      );
      return;
    }
    _settleProxyCycle(key: key, generation: generation, outcome: outcome);
  }

  /// Decides what follows a drive: complete, end, fail, or schedule the next
  /// cycle, from zcash_voting's progress as the progress screen reads it.
  void _settleProxyCycle({
    required VotingSessionKey key,
    required int generation,
    required VotingProxyDriveOutcome outcome,
  }) {
    final delays = ref.read(proxyJobCycleDelaysProvider);
    final failure = proxyJobBlockingFailure(outcome.failures);
    if (failure != null) {
      _failJob(
        key: key,
        generation: generation,
        message: _messageFromError(failure),
      );
      return;
    }
    // The next cycle collects the signatures the run stopped for.
    if (outcome.needsSignatures) {
      _scheduleProxyCycle(
        key: key,
        generation: generation,
        delay: delays.retry,
      );
      return;
    }
    final plan = _sessionForJob(key)?.roundPlan;
    final voteEnd = _sessionForJob(key)?.round?.voteEndTime;
    final now = ref.read(votingSubmissionJobClockProvider)();
    final closed = voteEnd != null && !now.isBefore(voteEnd);
    // A ballot job sent its batches first (see [_sendProxyBatchesFirst]):
    // once every one landed, its casts follow while the round is open.
    if (state.kind == VotingSubmissionJobKind.ballot &&
        !closed &&
        !roundPlanHasUnlandedProxyBatch(plan)) {
      _cancelProxyCycle();
      unawaited(_run(key: key, generation: generation));
      return;
    }
    final progress = state.proxyProgress;
    if (progress == null || voteEnd == null) {
      _failJob(
        key: key,
        generation: generation,
        message: progress == null
            ? const VotingNotice(VotingNoticeKind.proxyNoDelegation)
            : const VotingNotice(VotingNoticeKind.roundEndTimeUnavailable),
      );
      return;
    }
    switch (proxyProgressOutcome(progress, now: now, voteEnd: voteEnd)) {
      case ProxyProgressComplete():
        _endProxyJob(key: key, generation: generation);
      case ProxyProgressNotCounted():
        _endProxyJob(
          key: key,
          generation: generation,
          reason: ProxyJobTerminalReason.notCounted,
        );
      case ProxyProgressExpired():
        // One final check first: confirming a handed-off share 0's reveal is
        // allowed after `vote_end`, as the vote path's final immediate-share
        // check is, though share tracking has stopped.
        if (!_proxyFinalCheckDone) {
          _proxyFinalCheckDone = true;
          unawaited(
            _finalProxyCheck(
              key: key,
              generation: generation,
              progress: progress,
            ),
          );
          return;
        }
        _endProxyJob(
          key: key,
          generation: generation,
          reason: ProxyJobTerminalReason.expired,
        );
      case ProxyProgressRefused():
        state = state.copyWith(proxyStage: ProxyJobStage.refused);
        _scheduleProxyCycle(
          key: key,
          generation: generation,
          delay: delays.waiting,
        );
      case ProxyProgressRunning(:final step):
        state = state.copyWith(
          proxyStage: switch (step) {
            ProxyProgressStep.preparing => ProxyJobStage.preparing,
            ProxyProgressStep.submitting => ProxyJobStage.submitting,
            ProxyProgressStep.handingOff => ProxyJobStage.handingOff,
          },
        );
        final retrying =
            outcome.chainPending ||
            outcome.chainTerminal ||
            outcome.failures.isNotEmpty;
        _scheduleProxyCycle(
          key: key,
          generation: generation,
          delay: retrying ? delays.retry : delays.working,
        );
    }
  }

  /// The proxy job's one check after `vote_end`: while an at-once share 0's
  /// reveal is unconfirmed, it confirms what the helpers revealed, then runs
  /// the last cycle, whose progress read completes or expires the job.
  Future<void> _finalProxyCheck({
    required VotingSessionKey key,
    required int generation,
    required ApiProxyDelegationProgress progress,
  }) async {
    if (progress.plannedImmediate && !progress.immediateRevealConfirmed) {
      try {
        await ref
            .read(votingSubmissionSessionProvider(key).notifier)
            .refreshDcShareZeroConfirmations();
      } catch (error, stackTrace) {
        debugPrint(
          '[zcash] Voting: final DC share 0 confirmation failed: '
          '$error\n$stackTrace',
        );
      }
    }
    if (!_isCurrentJob(key: key, generation: generation)) return;
    _scheduleProxyCycle(key: key, generation: generation, delay: Duration.zero);
  }

  /// Ends a proxy job: complete when every delegation is handed off, failed
  /// for `vote_end` or a closed round.
  void _endProxyJob({
    required VotingSessionKey key,
    required int generation,
    ProxyJobTerminalReason? reason,
  }) {
    _cancelProxyCycle();
    switch (reason) {
      case null:
        _completeJob(key: key, generation: generation);
        state = state.copyWith(proxyStage: ProxyJobStage.complete);
      case ProxyJobTerminalReason.notCounted:
        _failJob(
          key: key,
          generation: generation,
          message: const VotingNotice(VotingNoticeKind.proxyNotCounted),
          retryable: false,
        );
        state = state.copyWith(
          proxyStage: ProxyJobStage.notCounted,
          terminalReason: reason,
        );
      case ProxyJobTerminalReason.expired:
        _failJob(
          key: key,
          generation: generation,
          message: const VotingNotice(VotingNoticeKind.immediateShareExpired),
          retryable: false,
        );
        state = state.copyWith(
          proxyStage: ProxyJobStage.expired,
          terminalReason: reason,
        );
    }
  }

  /// Runs the next proxy cycle after [delay].
  void _scheduleProxyCycle({
    required VotingSessionKey key,
    required int generation,
    required Duration delay,
  }) {
    _proxyCycleTimer?.cancel();
    _proxyCycleTimer = Timer(delay, () {
      _proxyCycleTimer = null;
      if (!_isCurrentJob(key: key, generation: generation) ||
          state.status != VotingSubmissionJobStatus.running) {
        return;
      }
      unawaited(_runProxyCycle(key: key, generation: generation));
    });
  }

  /// Stops scheduling proxy cycles.
  void _cancelProxyCycle() {
    _proxyCycleTimer?.cancel();
    _proxyCycleTimer = null;
    _proxyCycleAgain = false;
  }

  /// Reads zcash_voting's progress for [key] into the job state and returns
  /// whether the read answered. A failed read keeps the last snapshot: the
  /// next cycle reads again.
  Future<bool> _refreshProxyProgress({
    required VotingSessionKey key,
    required int generation,
  }) async {
    final read = ++_proxyProgressReads;
    final ApiProxyDelegationProgress? progress;
    try {
      progress = await ref.read(proxyJobProgressReaderProvider)(key);
    } catch (error) {
      debugPrint(
        '[zcash] Voting: proxy progress read failed: '
        '${describeProxyDelegationError(error)}',
      );
      return false;
    }
    if (!ref.mounted ||
        read != _proxyProgressReads ||
        state.generation != generation) {
      return true;
    }
    state = state.copyWith(
      proxyProgress: progress,
      clearProxyProgress: progress == null,
    );
    return true;
  }

  /// Drives a ballot job's round's outstanding proxy work while it waits to
  /// complete: no background tracking delivers DC shares. At most one drive
  /// runs, and one starts at most every working delay. Returns the drive,
  /// or null when none started.
  Future<void>? _startBallotProxyDrive({
    required VotingSessionKey key,
    required int generation,
  }) {
    if (_ballotProxyDrive != null) return null;
    final now = ref.read(votingSubmissionJobClockProvider)();
    final last = _lastBallotProxyDriveAt;
    if (last != null &&
        now.difference(last) < ref.read(proxyJobCycleDelaysProvider).working) {
      return null;
    }
    _lastBallotProxyDriveAt = now;
    late final Future<void> drive;
    drive =
        () async {
          try {
            final session = _sessionForJob(key);
            await ref
                .read(votingSubmissionSessionProvider(key).notifier)
                .driveProxyDelegation(
                  hardwareSigner: (session?.isHardwareAccount ?? false)
                      ? session?.hardwareSignerKind
                      : null,
                );
            if (!_isCurrentJob(key: key, generation: generation)) return;
            await _refreshProxyProgress(key: key, generation: generation);
          } catch (error) {
            debugPrint('[zcash] Voting: ballot proxy drive failed: $error');
          }
        }().whenComplete(() {
          if (identical(_ballotProxyDrive, drive)) _ballotProxyDrive = null;
        });
    _ballotProxyDrive = drive;
    unawaited(drive);
    return drive;
  }

  /// Whether [job] leaves its round's proxy work without a driver: a vote
  /// job that failed, which ran the round's drives (see [start]), or a job
  /// of either kind waiting for a hardware signature.
  static bool _stallsProxyWork(VotingSubmissionJobState job) =>
      job.status == VotingSubmissionJobStatus.waitingForKeystone ||
      job.status == VotingSubmissionJobStatus.waitingForLedger ||
      (job.kind == VotingSubmissionJobKind.ballot &&
          job.status == VotingSubmissionJobStatus.error);

  /// Keeps DC shares moving while [job] stalls the round's proxy work, on a
  /// timed drive every working delay, and stops once the job runs again,
  /// completes or is dismissed.
  void _followJobForProxyKeepAlive(VotingSubmissionJobState job) {
    final key = job.key;
    if (key == null || !_stallsProxyWork(job)) {
      _stopProxyKeepAlive();
      return;
    }
    if (_proxyKeepAliveTimer != null ||
        !roundPlanHasProxyWork(_sessionForJob(key)?.roundPlan)) {
      return;
    }
    // The job let go of its session; the drives need it alive.
    _proxyKeepAliveSession = ref.listen<AsyncValue<VotingSessionState>>(
      votingSubmissionSessionProvider(key),
      (_, _) {},
    );
    _proxyKeepAliveFinalDrive = false;
    _proxyKeepAliveTimer = Timer.periodic(
      ref.read(proxyJobCycleDelaysProvider).working,
      (_) => _proxyKeepAliveTick(key),
    );
  }

  /// One keep-alive drive, under a drainable background-work lease so
  /// account deletion and reset wait for it. After `vote_end` one last
  /// drive runs, as the proxy job's does.
  void _proxyKeepAliveTick(VotingSessionKey key) {
    final job = state;
    final session = _sessionForJob(key);
    if (job.key != key ||
        !_stallsProxyWork(job) ||
        !roundPlanHasProxyWork(session?.roundPlan)) {
      _stopProxyKeepAlive();
      return;
    }
    final voteEnd = session?.round?.voteEndTime;
    final ended =
        voteEnd != null &&
        !ref.read(votingSubmissionJobClockProvider)().isBefore(voteEnd);
    if (ended && _proxyKeepAliveFinalDrive) {
      _stopProxyKeepAlive();
      return;
    }
    final release = ref
        .read(votingShareTrackingRegistryProvider)
        .beginBackgroundWork(accountUuid: key.accountUuid);
    if (release == null) {
      _stopProxyKeepAlive();
      return;
    }
    final drive = _startBallotProxyDrive(key: key, generation: job.generation);
    if (drive == null) {
      release();
      return;
    }
    if (ended) _proxyKeepAliveFinalDrive = true;
    unawaited(drive.whenComplete(release));
  }

  /// Stops the keep-alive drives.
  void _stopProxyKeepAlive() {
    _proxyKeepAliveTimer?.cancel();
    _proxyKeepAliveTimer = null;
    _proxyKeepAliveSession?.close();
    _proxyKeepAliveSession = null;
  }

  Future<void> _prepareKeystoneSigning(
    VotingSessionNotifier sessionNotifier, {
    required VotingSessionKey key,
    required int generation,
    List<int> alsoSign = const [],
  }) async {
    await sessionNotifier.prepareKeystoneSigning(alsoSign: alsoSign);
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final session = _sessionForJob(key);
    if (session == null) return;
    if (session.phase == VotingSessionPhase.error) {
      _failFromSession(key: key, generation: generation, session: session);
      return;
    }
    final requests = session.keystoneSigningRequests;
    if (requests.isNotEmpty) {
      await _updateKeystoneQr(
        key: key,
        generation: generation,
        requests: requests,
      );
      return;
    }
    await _submitAfterHardwareSignatures(
      sessionNotifier,
      key: key,
      generation: generation,
    );
  }

  Future<void> _prepareAndSignWithLedger(
    VotingSessionNotifier sessionNotifier, {
    required VotingSessionKey key,
    required int generation,
    List<int> alsoSign = const [],
  }) => LedgerConnectionScope().run(() async {
    await sessionNotifier.prepareLedgerSigning(alsoSign: alsoSign);
    if (!_isCurrentJob(key: key, generation: generation)) return;

    int? rebuiltBundle;
    while (true) {
      final session = _sessionForJob(key);
      if (session == null) return;
      if (session.phase == VotingSessionPhase.error) {
        _failFromSession(key: key, generation: generation, session: session);
        return;
      }
      final request = session.ledgerSigningRequest;
      if (request == null) break;

      state = state.copyWith(
        status: VotingSubmissionJobStatus.waitingForLedger,
        ledgerDisplayMemo: request.displayMemo,
        ledgerRequestRebuilt: request.bundleIndex == rebuiltBundle,
        ledgerBundleIndex: request.bundleIndex,
        ledgerBundleCount: request.bundleCount,
        keystoneUrParts: const [],
        keystoneBatchMemos: const [],
        keystoneBatchMessageCount: 0,
        keystoneBatchTotalCount: 0,
        clearKeystoneQrError: true,
        clearErrorMessage: true,
      );

      final List<LedgerVotingSignature> signatures;
      try {
        signatures = await ref.read(ledgerVotingPcztSignerProvider)(
          key.accountUuid,
          request.redactedPcztBytes,
        );
      } catch (error) {
        if (!_isCurrentJob(key: key, generation: generation)) return;
        if (error is LedgerIronwoodDataRejected &&
            rebuiltBundle != request.bundleIndex) {
          try {
            final repaired = await sessionNotifier
                .recoverRejectedLedgerDelegation(
                  bundleIndex: request.bundleIndex,
                  rejectedSighash: request.pcztSighash,
                  isCurrentJob: () =>
                      _isCurrentJob(key: key, generation: generation),
                );
            if (repaired) {
              rebuiltBundle = request.bundleIndex;
              continue;
            }
          } catch (repairError) {
            if (!_isCurrentJob(key: key, generation: generation)) return;
            final cause = votingRustExceptionOf(repairError) ?? repairError;
            _failJob(
              key: key,
              generation: generation,
              message: _messageFromError(cause),
              retryable: isRetryableVotingError(cause),
            );
            return;
          }
          if (!_isCurrentJob(key: key, generation: generation)) return;
        }
        _failJob(
          key: key,
          generation: generation,
          message: VotingLedgerFailure(
            error,
            networkName: ref.read(rpcEndpointProvider).networkName,
          ),
          retryable: LedgerRequestFailure.fromError(error).retryable,
        );
        return;
      }
      if (!_isCurrentJob(key: key, generation: generation)) return;
      await sessionNotifier.handleLedgerSignatures(signatures);
      if (!_isCurrentJob(key: key, generation: generation)) return;
    }

    await _submitAfterHardwareSignatures(
      sessionNotifier,
      key: key,
      generation: generation,
      signerKind: HardwareSignerKind.ledger,
    );
  });

  Future<void> _updateKeystoneQr({
    required VotingSessionKey key,
    required int generation,
    required List<rust_delegate.KeystoneSigningRequest> requests,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    if (requests.isEmpty) {
      throw const VotingMessageException(
        VotingNotice(VotingNoticeKind.keystoneNoSigningRequest),
      );
    }
    _keystoneSigningRound = null;
    state = state.copyWith(
      status: VotingSubmissionJobStatus.waitingForKeystone,
      clearLedgerDisplayMemo: true,
      clearLedgerBundleIndex: true,
      ledgerBundleCount: 0,
      keystoneUrParts: const [],
      keystoneBatchMemos: const [],
      keystoneBatchMessageCount: 0,
      keystoneBatchTotalCount: requests.length,
      clearKeystoneQrError: true,
    );
    try {
      final round = await VotingKeystoneSigningRound.prepare(key, requests);
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _keystoneSigningRound = round;
      final roundRequests = round.requests;
      state = state.copyWith(
        status: VotingSubmissionJobStatus.waitingForKeystone,
        keystoneUrParts: round.batchRequest.urParts,
        keystoneBatchMemos: [
          for (final request in roundRequests)
            VotingKeystoneBatchMemo(
              bundleIndex: request.bundleIndex,
              bundleCount: request.bundleCount,
              displayMemo: request.displayMemo,
            ),
        ],
        keystoneBatchMessageCount: roundRequests.length,
        keystoneBatchTotalCount: requests.length,
        clearKeystoneQrError: true,
      );
    } catch (error) {
      if (!_isCurrentJob(key: key, generation: generation)) return;
      _failJob(
        key: key,
        generation: generation,
        message: VotingKeystoneQrFailure(_messageFromError(error)),
      );
    }
  }

  Future<void> _submitAfterHardwareSignatures(
    VotingSessionNotifier sessionNotifier, {
    required VotingSessionKey key,
    required int generation,
    HardwareSignerKind? signerKind,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    // A ballot job signed for a batch it sends first (see
    // [_sendProxyBatchesFirst]).
    if (state.kind == VotingSubmissionJobKind.proxy ||
        roundPlanHasUnlandedProxyBatch(_sessionForJob(key)?.roundPlan)) {
      _setRunning(key: key, generation: generation);
      await _driveProxy(key: key, generation: generation);
      return;
    }
    final draftVotes = state.pendingDraftVotes;
    if (draftVotes == null ||
        (draftVotes.isEmpty && !state.pendingRecoveryWithoutDraft)) {
      _failJob(
        key: key,
        generation: generation,
        message: const VotingNotice(VotingNoticeKind.noVoteChosen),
      );
      return;
    }
    _setRunning(key: key, generation: generation);
    final beforeDelegation = _sessionForJob(key);
    if (_sessionNeedsDelegation(beforeDelegation)) {
      if (signerKind == HardwareSignerKind.ledger) {
        await sessionNotifier.delegatePendingBundlesWithLedgerSignatures();
      } else {
        await sessionNotifier.delegatePendingBundlesWithKeystoneSignatures();
      }
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final afterDelegation = _sessionForJob(key);
      if (afterDelegation?.phase == VotingSessionPhase.error) {
        _failFromSession(
          key: key,
          generation: generation,
          session: afterDelegation!,
        );
        return;
      }
      if (_completeJobIfSubmissionDone(
        key: key,
        generation: generation,
        session: afterDelegation,
        requireNoUnconfirmedShares: true,
      )) {
        return;
      }
      await _submitVotesAndShares(
        sessionNotifier,
        key: key,
        generation: generation,
        draftVotes: draftVotes,
        intentProposalIds: state.pendingProposalIds,
        initialSession: afterDelegation ?? beforeDelegation,
      );
      return;
    }
    await _submitVotesAndShares(
      sessionNotifier,
      key: key,
      generation: generation,
      draftVotes: draftVotes,
      intentProposalIds: state.pendingProposalIds,
      initialSession: beforeDelegation,
    );
  }

  Future<void> _submitVotesAndShares(
    VotingSessionNotifier sessionNotifier, {
    required VotingSessionKey key,
    required int generation,
    required List<VotingDraftVote> draftVotes,
    required List<int> intentProposalIds,
    VotingSessionState? initialSession,
  }) async {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    var votePollingSession = _sessionForJob(key) ?? initialSession;
    // Casting now would cast nothing in a bundle its batch still holds, and
    // the confirmation below would then ask about a share never made.
    if (roundPlanHasUnlandedProxyBatch(votePollingSession?.roundPlan)) {
      await _sendProxyBatchesFirst(key: key, generation: generation);
      return;
    }
    final canContinueWithoutDraft =
        votePollingSession != null &&
        (_canRecoverWithoutDraft(votePollingSession) ||
            _canPollDelegationWithoutDraft(votePollingSession) ||
            _hasCompletedSubmissionArtifacts(votePollingSession));
    if (draftVotes.isEmpty &&
        (votePollingSession == null || !canContinueWithoutDraft)) {
      _failJob(
        key: key,
        generation: generation,
        message: const VotingNotice(VotingNoticeKind.noVoteChosen),
      );
      return;
    }
    final hasVoteOrShareWork =
        draftVotes.isNotEmpty ||
        (votePollingSession != null &&
            _hasRemainingVoteOrShareWork(votePollingSession));
    if (hasVoteOrShareWork &&
        !(votePollingSession?.hasConfirmedVotingEligibility ?? false)) {
      await sessionNotifier.ensureVotingEligibility();
      if (!_isCurrentJob(key: key, generation: generation)) return;
      final afterEligibilityCheck = _sessionForJob(key);
      if (afterEligibilityCheck?.phase == VotingSessionPhase.error) {
        _failFromSession(
          key: key,
          generation: generation,
          session: afterEligibilityCheck!,
        );
        return;
      }
      votePollingSession = afterEligibilityCheck ?? votePollingSession;
    }
    if (draftVotes.isNotEmpty || _sessionNeedsVotePolling(votePollingSession)) {
      await sessionNotifier.castVotes(
        draftVotes: draftVotes,
        allProposalIds: intentProposalIds,
      );
    }
    if (!_isCurrentJob(key: key, generation: generation)) return;
    var done = _sessionForJob(key);
    if (done?.phase == VotingSessionPhase.error) {
      _failFromSession(key: key, generation: generation, session: done!);
      return;
    }
    if (sessionNotifier.castsAwaitSignatures) {
      await _routeCastsToSigning(key: key, generation: generation);
      return;
    }
    if (done != null) {
      final completedEligibilitySession =
          await _ensureEligibilityForCompletedSession(
            key: key,
            generation: generation,
            sessionNotifier: sessionNotifier,
            session: done,
          );
      if (completedEligibilitySession == null) return;
      done = completedEligibilitySession;
    }
    if (_canCompleteSubmission(done)) {
      _completeJob(key: key, generation: generation);
      return;
    }
    if (done != null && _hasRemainingVoteOrShareWork(done)) {
      // Shares with no definite placement are still recovery work, but the SDK
      // drives it now: starting the run returns immediately and this poll sees
      // placement progress on its next tick. Awaiting instead would block the
      // job for as long as the round has shares to track.
      await sessionNotifier.startShareTracking();
    } else {
      // Once all shares are placed, finalization depends only on the
      // designated immediate share, which answers without waiting for the
      // tracking cadence.
      await sessionNotifier.refreshImmediateShareConfirmation();
    }
    if (!_isCurrentJob(key: key, generation: generation)) return;
    done = _sessionForJob(key);
    if (done?.phase == VotingSessionPhase.error) {
      _failFromSession(key: key, generation: generation, session: done!);
      return;
    }
    if (done != null) {
      final completedEligibilitySession =
          await _ensureEligibilityForCompletedSession(
            key: key,
            generation: generation,
            sessionNotifier: sessionNotifier,
            session: done,
          );
      if (completedEligibilitySession == null) return;
      done = completedEligibilitySession;
    }
    if (!_canCompleteSubmission(done)) {
      if (_hasExpiredUnconfirmedImmediateShare(done)) {
        _startExpiryConfirmationCheck(key: key, generation: generation);
        return;
      }
      _scheduleCompletionPoll(key: key, generation: generation);
      return;
    }
    _completeJob(key: key, generation: generation);
  }

  /// Sends a ballot whose signerless casts stopped for a signature back
  /// through [_run], which collects it from the seed or the device. Once per
  /// job start: casts that stop again fail the job with
  /// [VotingNoticeKind.castsNeedSignature] instead of ending quietly.
  Future<void> _routeCastsToSigning({
    required VotingSessionKey key,
    required int generation,
  }) async {
    if (_castSigningRerouted) {
      _failJob(
        key: key,
        generation: generation,
        message: const VotingNotice(VotingNoticeKind.castsNeedSignature),
      );
      return;
    }
    _castSigningRerouted = true;
    await _run(key: key, generation: generation);
  }

  void _storePendingHardwareState({
    required VotingSessionKey key,
    required int generation,
    required List<VotingDraftVote> draftVotes,
    required List<int> intentProposalIds,
    required bool pendingRecoveryWithoutDraft,
  }) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    state = state.copyWith(
      pendingDraftVotes: draftVotes,
      pendingProposalIds: intentProposalIds,
      pendingRecoveryWithoutDraft: pendingRecoveryWithoutDraft,
    );
  }

  void _setRunning({required VotingSessionKey key, required int generation}) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    _keystoneSigningRound = null;
    state = state.copyWith(
      status: VotingSubmissionJobStatus.running,
      clearLedgerDisplayMemo: true,
      clearLedgerBundleIndex: true,
      ledgerBundleCount: 0,
      keystoneUrParts: const [],
      keystoneBatchMemos: const [],
      keystoneBatchMessageCount: 0,
      keystoneBatchTotalCount: 0,
      clearKeystoneQrError: true,
      clearErrorMessage: true,
    );
  }

  void _completeJob({required VotingSessionKey key, required int generation}) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    _cancelCompletionPoll();
    // Register live helper-share tracking before releasing the submission
    // guard. Account delete/reset drain through the registry; they must not
    // observe an unguarded in-flight pass.
    _pinLiveShareTracking(key);
    _releaseGuard();
    _releaseSessionSubscription();
    ref.invalidate(votingSessionProvider(key.roundId));
    _keystoneSigningRound = null;
    state = state.copyWith(
      status: VotingSubmissionJobStatus.complete,
      clearErrorMessage: true,
      softwareAccountRequired: false,
      keystoneUrParts: const [],
      keystoneBatchMemos: const [],
      keystoneBatchMessageCount: 0,
      keystoneBatchTotalCount: 0,
      clearKeystoneQrError: true,
      clearPendingDraftVotes: true,
      pendingProposalIds: const [],
      pendingRecoveryWithoutDraft: false,
    );
  }

  void _failFromSession({
    required VotingSessionKey key,
    required int generation,
    required VotingSessionState session,
  }) {
    _failJob(
      key: key,
      generation: generation,
      message:
          _statusErrorMessage(session) ??
          const VotingNotice(VotingNoticeKind.statusGeneric),
    );
  }

  void _failJob({
    required VotingSessionKey key,
    required int generation,
    required VotingMessage message,
    bool retryable = true,
    bool softwareAccountRequired = false,
  }) {
    if (!_isCurrentJob(key: key, generation: generation)) return;
    _cancelCompletionPoll();
    _releaseGuard();
    _releaseSessionSubscription();
    _keystoneSigningRound = null;
    state = state.copyWith(
      status: VotingSubmissionJobStatus.error,
      errorMessage: message,
      retryable: retryable,
      softwareAccountRequired: softwareAccountRequired,
      keystoneUrParts: const [],
      keystoneBatchMemos: const [],
      keystoneBatchMessageCount: 0,
      keystoneBatchTotalCount: 0,
      clearKeystoneQrError: true,
      clearPendingDraftVotes: true,
      pendingProposalIds: const [],
      pendingRecoveryWithoutDraft: false,
    );
  }

  VotingSessionState? _sessionForJob(VotingSessionKey key) {
    final session = ref.read(votingSubmissionSessionProvider(key)).value;
    if (session?.accountUuid != key.accountUuid) return null;
    return session;
  }

  bool _isCurrentJob({required VotingSessionKey key, required int generation}) {
    if (!ref.mounted) return false;
    final current = state;
    return current.generation == generation && current.key == key;
  }

  void _replaceGuard({required String accountUuid, required String roundId}) {
    _releaseGuard();
    _guard = ref
        .read(votingSubmissionGuardProvider.notifier)
        .acquire(accountUuid: accountUuid, roundId: roundId);
  }

  void _retainSession(VotingSessionKey key) {
    if (_retainedSessionKey == key && _sessionSubscription != null) return;
    _releaseSessionSubscription();
    _retainedSessionKey = key;
    // Keep the session provider alive while the background job owns submission.
    _sessionSubscription = ref.listen<AsyncValue<VotingSessionState>>(
      votingSubmissionSessionProvider(key),
      (_, _) {},
      fireImmediately: true,
    );
  }

  void _releaseSessionSubscription() {
    _sessionSubscription?.close();
    _sessionSubscription = null;
    _retainedSessionKey = null;
  }

  void _releaseGuard() {
    final guard = _guard;
    if (guard == null) return;
    _guard = null;
    ref.read(votingSubmissionGuardProvider.notifier).release(guard);
  }

  void _pinLiveShareTracking(VotingSessionKey key) {
    final hasUnconfirmedShares =
        _sessionForJob(key)?.roundPlan?.hasUnconfirmedShares ?? false;
    if (!hasUnconfirmedShares) return;
    final sessionNotifier = ref.read(
      votingSubmissionSessionProvider(key).notifier,
    );
    sessionNotifier.pinAutomaticShareTracking();
    // Helper reveal is background work. Awaiting it in the job keeps the
    // status screen on "Finalizing submission" for accepted-but-unrevealed
    // shares. The registry, not the job guard, is the drain barrier.
    unawaited(
      sessionNotifier.startShareTracking().catchError((
        Object error,
        StackTrace stack,
      ) {
        debugPrint(
          '[zcash] Voting: background share tracking failed: $error\n$stack',
        );
      }),
    );
  }

  void _scheduleCompletionPoll({
    required VotingSessionKey key,
    required int generation,
  }) {
    _completionPollTimer?.cancel();
    _completionPollTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isCurrentJob(key: key, generation: generation) ||
          !state.isInFlight) {
        timer.cancel();
        if (identical(_completionPollTimer, timer)) _completionPollTimer = null;
        return;
      }
      final session = _sessionForJob(key);
      if (session?.phase == VotingSessionPhase.error) {
        _failFromSession(key: key, generation: generation, session: session!);
        return;
      }
      if (_canCompleteSubmission(session)) {
        _completeJob(key: key, generation: generation);
        return;
      }
      if (_hasExpiredUnconfirmedImmediateShare(session)) {
        _startExpiryConfirmationCheck(key: key, generation: generation);
        return;
      }
      if (roundPlanHasProxyWork(session?.roundPlan)) {
        _startBallotProxyDrive(key: key, generation: generation);
      }
      _startImmediateConfirmationCheck(key: key, generation: generation);
    });
  }

  void _startImmediateConfirmationCheck({
    required VotingSessionKey key,
    required int generation,
  }) {
    if (_immediateConfirmationCheck != null) return;
    late final Future<void> check;
    check =
        _refreshImmediateShareForCompletion(
          key: key,
          generation: generation,
        ).whenComplete(() {
          if (identical(_immediateConfirmationCheck, check)) {
            _immediateConfirmationCheck = null;
          }
        });
    _immediateConfirmationCheck = check;
    unawaited(check);
  }

  Future<void> _refreshImmediateShareForCompletion({
    required VotingSessionKey key,
    required int generation,
  }) async {
    try {
      await ref
          .read(votingSubmissionSessionProvider(key).notifier)
          .refreshImmediateShareConfirmation();
    } catch (error, stackTrace) {
      debugPrint(
        '[zcash] Voting: immediate-share confirmation check failed: '
        '$error\n$stackTrace',
      );
    }
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final session = _sessionForJob(key);
    if (_canCompleteSubmission(session)) {
      _completeJob(key: key, generation: generation);
    }
  }

  void _startExpiryConfirmationCheck({
    required VotingSessionKey key,
    required int generation,
  }) {
    if (_expiryConfirmationCheck != null ||
        _immediateConfirmationCheck != null) {
      return;
    }
    _cancelCompletionPoll();
    late final Future<void> check;
    check =
        _refreshImmediateShareBeforeExpiryFailure(
          key: key,
          generation: generation,
        ).whenComplete(() {
          if (identical(_expiryConfirmationCheck, check)) {
            _expiryConfirmationCheck = null;
          }
        });
    _expiryConfirmationCheck = check;
    unawaited(check);
  }

  Future<void> _refreshImmediateShareBeforeExpiryFailure({
    required VotingSessionKey key,
    required int generation,
  }) async {
    var confirmed = false;
    try {
      confirmed = await ref
          .read(votingSubmissionSessionProvider(key).notifier)
          .refreshImmediateShareConfirmation();
    } catch (error, stackTrace) {
      debugPrint(
        '[zcash] Voting: final immediate-share confirmation failed: '
        '$error\n$stackTrace',
      );
    }
    if (!_isCurrentJob(key: key, generation: generation)) return;
    final session = _sessionForJob(key);
    if ((confirmed && !roundPlanHasProxyWork(session?.roundPlan)) ||
        _canCompleteSubmission(session)) {
      _completeJob(key: key, generation: generation);
      return;
    }
    _failForExpiredImmediateShare(key: key, generation: generation);
  }

  void _cancelCompletionPoll() {
    _completionPollTimer?.cancel();
    _completionPollTimer = null;
  }

  /// Whether the ballot is done: eligibility confirmed, every vote and
  /// share submitted, the round's immediate share confirmed, and, when the
  /// round has a proxy allocation, its proxy work settled too.
  bool _canCompleteSubmission(VotingSessionState? session) {
    if (session == null) return false;
    return session.hasConfirmedVotingEligibility &&
        _hasCompletedSubmissionArtifacts(session) &&
        hasConfirmedImmediateShare(session.roundPlan) &&
        !roundPlanHasProxyWork(session.roundPlan);
  }

  /// Whether `vote_end` passed with the round's immediate share unconfirmed
  /// or its proxy work unsettled.
  bool _hasExpiredUnconfirmedImmediateShare(
    VotingSessionState? session, {
    DateTime? now,
  }) {
    if (session == null ||
        (hasConfirmedImmediateShare(session.roundPlan) &&
            !roundPlanHasProxyWork(session.roundPlan))) {
      return false;
    }
    final voteEnd = session.round?.voteEndTime;
    return voteEnd != null &&
        !(now ?? ref.read(votingSubmissionJobClockProvider)()).isBefore(
          voteEnd,
        );
  }

  void _failForExpiredImmediateShare({
    required VotingSessionKey key,
    required int generation,
  }) {
    _failJob(
      key: key,
      generation: generation,
      message: const VotingNotice(VotingNoticeKind.immediateShareExpired),
    );
  }

  Future<VotingSessionState?> _ensureEligibilityForCompletedSession({
    required VotingSessionKey key,
    required int generation,
    required VotingSessionNotifier sessionNotifier,
    required VotingSessionState session,
  }) async {
    if (session.hasConfirmedVotingEligibility ||
        !_hasCompletedSubmissionArtifacts(session)) {
      return session;
    }
    await sessionNotifier.ensureVotingEligibility();
    if (!_isCurrentJob(key: key, generation: generation)) return null;
    final afterEligibilityCheck = _sessionForJob(key);
    if (afterEligibilityCheck?.phase == VotingSessionPhase.error) {
      _failFromSession(
        key: key,
        generation: generation,
        session: afterEligibilityCheck!,
      );
      return null;
    }
    return afterEligibilityCheck ?? session;
  }

  /// Whether the ballot's votes and shares are all submitted. A round with
  /// nothing left to vote has no ballot to submit, so only its remaining
  /// work counts.
  bool _hasCompletedSubmissionArtifacts(VotingSessionState? session) {
    if (session == null) return false;
    return (hasCompletedVoteForDisplay(session.roundPlan) ||
            roundPlanNothingLeftToVote(session.roundPlan)) &&
        !_hasRemainingVoteOrShareWork(session);
  }

  bool _completeJobIfSubmissionDone({
    required VotingSessionKey key,
    required int generation,
    required VotingSessionState? session,
    bool requireNoUnconfirmedShares = false,
  }) {
    if (requireNoUnconfirmedShares &&
        (session?.roundPlan?.hasUnconfirmedShares ?? false)) {
      return false;
    }
    if (!_canCompleteSubmission(session)) return false;
    _completeJob(key: key, generation: generation);
    return true;
  }

  bool _canCompleteSessionWithoutDraft(
    VotingSessionState session,
    VotingDraftState draft,
  ) {
    if (!_canCompleteSubmission(session)) return false;
    if (draft.isEmpty) return true;
    final roundPlan = session.roundPlan;
    if (roundPlan == null) return false;
    final openProposalIds = roundPlan.openProposals.toSet();
    return draft.choices.keys.every(
      (proposalId) => !openProposalIds.contains(proposalId),
    );
  }

  bool _canCompleteSessionAfterDraftLoadFailure(VotingSessionState session) {
    return _canCompleteSubmission(session) &&
        _roundPlanHasNoOpenProposals(session);
  }

  VotingDraftState _draftForSession(
    VotingDraftState draft,
    VotingSessionState session,
  ) {
    final roundPlan = session.roundPlan;
    if (roundPlan == null) return draft;
    final openProposalIds = roundPlan.openProposals.toSet();
    return VotingDraftState(
      choices: {
        for (final entry in draft.choices.entries)
          if (openProposalIds.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  List<int> _proposalIdsForDraftIntents(
    VotingSessionState session,
    List<VotingProposalView> proposals,
  ) {
    final proposalIds = proposals.map((proposal) => proposal.id).toList();
    final roundPlan = session.roundPlan;
    if (roundPlan == null) return proposalIds;
    final openProposalIds = roundPlan.openProposals.toSet();
    return [
      for (final proposalId in proposalIds)
        if (openProposalIds.contains(proposalId)) proposalId,
    ];
  }

  VotingMessage _messageFromError(Object error) => votingMessageForError(error);

  VotingMessage? _statusErrorMessage(VotingSessionState state) {
    final error = state.error;
    if (error != null) return normalizedVotingMessage(error.message);
    if (state.phase != VotingSessionPhase.error) return null;
    return const VotingNotice(VotingNoticeKind.statusGeneric);
  }

  bool _canRecoverWithoutDraft(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    return roundPlan != null &&
        _roundPlanHasNoOpenProposals(session) &&
        roundPlan.hasRecoverableVoteOrShareWork;
  }

  bool _roundPlanHasNoOpenProposals(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    return roundPlan != null && roundPlan.openProposals.isEmpty;
  }

  bool _hasRemainingVoteOrShareWork(VotingSessionState session) {
    return session.roundPlan?.hasRemainingVoteOrShareWork ?? false;
  }

  /// Whether delegation work can continue without ballot choices.
  ///
  /// A delegation already on the wire is driven to its chain outcome
  /// regardless of the draft. A bundle that has not been sent yet is not: the
  /// round's ballot comes first, so a round with any unsigned bundle left
  /// still asks for a vote.
  ///
  /// The in-flight flag is read on its own rather than through
  /// `needsDelegationSigning`, which the SDK also sets for an in-flight
  /// delegation because advancing one re-signs it.
  bool _canPollDelegationWithoutDraft(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    if (roundPlan == null || !roundPlan.hasInFlightDelegation) return false;
    // A submission the chain-submission lifecycle owns — submitting, tracking,
    // or recovering — already carries its signature, so it is not signing work
    // standing between this round and a poll. The planner says so itself: a
    // bundle in that state is planned as an advance, never as a delegation to
    // produce, so it is absent here. This used to be filtered out by phase in
    // Dart, which is what left a rejected delegation unable to be retried
    // without re-picking every vote when the filter and the planner disagreed.
    return delegationBundleIndexesNeedingSigning(roundPlan).isEmpty;
  }

  /// Whether this session still owes delegation work.
  ///
  /// A bundle the plan lists any delegation step for — including one already
  /// on the wire, which is advanced to its chain outcome regardless of the
  /// draft — or a round whose bundles have not been set up yet.
  ///
  /// [_canPollDelegationWithoutDraft] is deliberately not consulted here: it
  /// requires an in-flight delegation, which already makes
  /// [_planNeedsDelegation] true, so it could only ever agree. It answers a
  /// different question — whether work may proceed with no ballot choices —
  /// and is asked where that is what the caller needs to know.
  bool _sessionNeedsDelegation(VotingSessionState? session) {
    final roundPlan = session?.roundPlan;
    return _planNeedsDelegation(roundPlan) ||
        roundPlanNeedsDraftSetup(roundPlan);
  }

  bool _sessionNeedsDelegationSigning(VotingSessionState session) {
    final roundPlan = session.roundPlan;
    return roundPlan != null &&
        (roundPlan.needsDelegationSigning ||
            roundPlanNeedsDraftSetup(roundPlan));
  }

  bool _sessionNeedsVotePolling(VotingSessionState? session) {
    if (session == null) return false;
    return _planNeedsVotePolling(session.roundPlan);
  }

  bool _planNeedsDelegation(rust_wire.RoundPlanView? roundPlan) {
    if (roundPlan == null) return false;
    // Both flags are the planner's own summary, so this is reading its answer
    // rather than restating its rules. `delegationBundlesNeedingWork` covers
    // the same three step kinds and is the per-bundle form, but a round-level
    // question is better asked at the round level: the bundle list is for code
    // that acts on a particular bundle.
    return roundPlan.needsDelegationSigning || roundPlan.hasInFlightDelegation;
  }

  bool _planNeedsVotePolling(rust_wire.RoundPlanView? roundPlan) {
    return roundPlan?.needsVotePolling ?? false;
  }

  List<VotingDraftVote> _draftVotesFromRoundPlan(
    rust_wire.RoundPlanView? roundPlan,
    List<VotingProposalView> proposals,
  ) {
    if (roundPlan == null) return const [];
    final choicesByProposal = <int, int>{};
    for (final step in roundPlan.nextSteps) {
      if (step.kind != rust_wire.NextStepKind.castVote) continue;
      choicesByProposal.putIfAbsent(step.proposalId, () => step.choice);
    }
    if (choicesByProposal.isEmpty) return const [];
    return [
      for (final proposal in proposals)
        if (choicesByProposal[proposal.id] != null)
          VotingDraftVote(
            proposalId: proposal.id,
            choice: choicesByProposal[proposal.id]!,
            numOptions: proposal.options.length,
          ),
    ];
  }
}

/// The first of [failures] that a later proxy cycle cannot overcome, if
/// any: a transport failure, a busy store, an incomplete helper delivery or
/// the vote end (which the progress decides) is retried or settled.
VotingRoundStepFailure? proxyJobBlockingFailure(
  List<VotingRoundStepFailure> failures,
) {
  for (final failure in failures) {
    switch (failure.failure.kind) {
      case rust_wire.RoundStepFailureKindView.transport ||
          rust_wire.RoundStepFailureKindView.busy ||
          rust_wire.RoundStepFailureKindView.helperDeliveryIncomplete ||
          rust_wire.RoundStepFailureKindView.voteEnded:
        continue;
      default:
        return failure;
    }
  }
  return null;
}

const _votingKeystoneBatchMaxMessages = 40;

String _votingKeystoneMessageId(int bundleIndex) =>
    'voting-bundle-$bundleIndex';

String _votingKeystoneRequestId(
  VotingSessionKey key,
  List<rust_delegate.KeystoneSigningRequest> requests,
) {
  final material = <int>[
    ...utf8.encode('vizor-voting-batch-v1'),
    0,
    ...utf8.encode(key.accountUuid),
    0,
    ...utf8.encode(key.roundId),
  ];
  for (final request in requests) {
    material
      ..add(0)
      ..addAll(utf8.encode(request.bundleIndex.toString()))
      ..add(0)
      ..addAll(request.pcztSighash);
  }
  return 'vizor-vote-${sha256.convert(material)}';
}

List<KeystonePreparedBatchMessage> _votingKeystoneBatchMessages(
  List<rust_delegate.KeystoneSigningRequest> requests,
) => [
  for (final request in requests)
    KeystonePreparedBatchMessage(
      id: _votingKeystoneMessageId(request.bundleIndex),
      redactedPczt: request.redactedPcztBytes,
      expectedSignatureCount: 1,
    ),
];

final votingSubmissionJobsProvider =
    NotifierProvider<VotingSubmissionJobsNotifier, VotingSubmissionJobsState>(
      VotingSubmissionJobsNotifier.new,
    );

final votingSubmissionJobProvider =
    NotifierProvider.family<
      VotingSubmissionJobNotifier,
      VotingSubmissionJobState,
      VotingSessionKey
    >(VotingSubmissionJobNotifier.new);

final votingSubmissionJobSessionProvider = Provider.autoDispose
    .family<AsyncValue<VotingSessionState>, VotingSessionKey>((ref, key) {
      return ref.watch(votingSubmissionSessionProvider(key));
    });
