import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/voting/voting_session_provider.dart';
import '../../providers/voting/voting_submission_job_provider.dart';
import '../../providers/voting/voting_state.dart';
import '../../services/voting/pir_snapshot_resolver.dart';
import 'voting_error_messages.dart';
import 'voting_flow_models.dart';
import 'voting_formatters.dart';
import 'voting_resume_plan.dart';
import 'voting_routes.dart';

/// Everything a status scaffold needs to render one frame of the submission.
/// Produced by [VotingStatusFlow]; rendered by the form-factor screens. A
/// null view model from the flow builder means the session is still loading
/// with nothing to report.
@immutable
class VotingStatusViewModel {
  const VotingStatusViewModel({
    required this.phase,
    this.voteSubmissionDetail,
    this.voteSubmissionProgress,
    this.delegationProgress,
    this.completedSubmission = false,
    this.submissionJobComplete = false,
    this.submissionJobInFlight = false,
    this.softwareAccountRequired = false,
    this.isHardwareAccount = false,
    this.keystoneSigningBundleIndex,
    this.canSkipRemainingKeystoneBundles = false,
    this.keystoneUrParts = const [],
    this.keystoneBatchMemos = const [],
    this.keystoneBatchMessageCount = 0,
    this.keystoneBatchTotalCount = 0,
    this.keystoneQrError,
    this.keystoneScanError,
    this.walletScannedHeight,
    this.walletSnapshotHeight,
    this.walletChainTipHeight,
    this.errorMessage,
    this.onRetry,
    this.onClear,
    this.onScanKeystone,
    this.onSkipKeystoneBundles,
  });

  final VotingSessionPhase phase;
  final String? voteSubmissionDetail;
  final double? voteSubmissionProgress;
  final double? delegationProgress;
  final bool completedSubmission;
  final bool submissionJobComplete;
  final bool submissionJobInFlight;
  final bool softwareAccountRequired;
  final bool isHardwareAccount;
  final int? keystoneSigningBundleIndex;
  final bool canSkipRemainingKeystoneBundles;
  final List<String> keystoneUrParts;
  final List<VotingKeystoneBatchMemo> keystoneBatchMemos;
  final int keystoneBatchMessageCount;
  final int keystoneBatchTotalCount;
  final String? keystoneQrError;
  final String? keystoneScanError;
  final int? walletScannedHeight;
  final int? walletSnapshotHeight;
  final int? walletChainTipHeight;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onClear;
  final VoidCallback? onScanKeystone;
  final VoidCallback? onSkipKeystoneBundles;
}

typedef VotingStatusBuilder =
    Widget Function(BuildContext context, VotingStatusViewModel? view);

/// Shared state machine behind the submission status screens.
///
/// Owns the job start scheduling (with generation guards against route
/// changes), the display-phase and progress derivations, the Keystone
/// scan/skip handoffs, retry/clear, and the navigation to the confirmation
/// route when the job completes. The form-factor scaffolds render the
/// resulting view model via [builder]; [confirmSkipRemainingBundles] supplies
/// the shell-appropriate confirmation UI for skipping unsigned Keystone
/// bundles.
class VotingStatusFlow extends ConsumerStatefulWidget {
  const VotingStatusFlow({
    super.key,
    required this.roundId,
    required this.builder,
    required this.confirmSkipRemainingBundles,
    this.accountUuid,
  });

  final String roundId;
  final String? accountUuid;
  final VotingStatusBuilder builder;
  final Future<bool?> Function(BuildContext context)
  confirmSkipRemainingBundles;

  @override
  ConsumerState<VotingStatusFlow> createState() => _VotingStatusFlowState();
}

class _VotingStatusFlowState extends ConsumerState<VotingStatusFlow> {
  bool _startScheduled = false;
  int _startGeneration = 0;
  VotingSessionKey? _jobKey;
  VotingSessionKey? _confirmationNavigationScheduledFor;

  @override
  void initState() {
    super.initState();
    _scheduleStart();
  }

  @override
  void didUpdateWidget(covariant VotingStatusFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roundId == widget.roundId &&
        oldWidget.accountUuid == widget.accountUuid) {
      return;
    }
    _startScheduled = false;
    _jobKey = widget.accountUuid == null
        ? null
        : VotingSessionKey(
            roundId: widget.roundId,
            accountUuid: widget.accountUuid!,
          );
    _confirmationNavigationScheduledFor = null;
    _scheduleStart();
  }

  void _scheduleStart() {
    if (_startScheduled) return;
    _startScheduled = true;
    final generation = ++_startGeneration;
    final roundId = widget.roundId;
    final accountUuid = widget.accountUuid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrentStart(generation, roundId, accountUuid)) return;
      unawaited(
        ref
            .read(votingSubmissionJobsProvider.notifier)
            .start(roundId, accountUuid: accountUuid)
            .then((key) {
              if (!_isCurrentStart(generation, roundId, accountUuid) ||
                  key == null ||
                  !_isCurrentRouteKey(key)) {
                return;
              }
              setState(() {
                _jobKey = key;
              });
            }),
      );
    });
  }

  bool _isCurrentStart(int generation, String roundId, String? accountUuid) {
    return mounted &&
        generation == _startGeneration &&
        widget.roundId == roundId &&
        widget.accountUuid == accountUuid;
  }

  bool _isCurrentRouteKey(VotingSessionKey key) {
    if (!mounted || key.roundId != widget.roundId) return false;
    final accountUuid = widget.accountUuid;
    return accountUuid == null || key.accountUuid == accountUuid;
  }

  VotingSessionKey? _selectedJobKey() {
    return _jobKey ??
        (widget.accountUuid == null
            ? null
            : VotingSessionKey(
                roundId: widget.roundId,
                accountUuid: widget.accountUuid!,
              ));
  }

  Future<void> _scanKeystoneSignature() async {
    final key = _selectedJobKey();
    if (key == null) return;
    final responseCbor = await context.push<List<int>>('/voting/keystone/scan');
    if (!mounted || _selectedJobKey() != key) return;
    if (responseCbor == null || responseCbor.isEmpty) return;
    await ref
        .read(votingSubmissionJobsProvider.notifier)
        .handleKeystoneBatchSignResponse(key, responseCbor);
  }

  Future<void> _skipRemainingKeystoneBundles() async {
    final key = _selectedJobKey();
    if (key == null) return;
    final confirmed = await widget.confirmSkipRemainingBundles(context);
    if (!mounted || _selectedJobKey() != key) return;
    if (confirmed != true) return;
    await ref
        .read(votingSubmissionJobsProvider.notifier)
        .skipRemainingKeystoneBundles(key);
  }

  bool _hasCompletedSubmission(VotingSessionState? session) {
    if (session == null) return false;
    return hasCompletedVoteForDisplay(session.roundPlan);
  }

  bool _hasCompletedCurrentSubmissionProgress(VotingSessionState session) {
    final total = session.voteSubmissionTotalCount;
    if (total > 0 && session.voteSubmissionCompletedCount >= total) {
      return true;
    }
    return (session.voteSubmissionProgress ?? 0) >= 1;
  }

  String _messageFromError(Object error) {
    return friendlyVotingErrorMessage(error);
  }

  @override
  Widget build(BuildContext context) {
    final selectedKey = _selectedJobKey();
    if (selectedKey != null) {
      ref.listen<VotingSubmissionJobState>(
        votingSubmissionJobProvider(selectedKey),
        (previous, next) {
          if (!mounted ||
              previous?.status == VotingSubmissionJobStatus.complete ||
              next.status != VotingSubmissionJobStatus.complete) {
            return;
          }
          _scheduleConfirmationNavigation(selectedKey);
        },
      );
    }
    final startError = ref.watch(
      votingSubmissionJobsProvider.select(
        (state) => state.startErrorForRound(widget.roundId),
      ),
    );
    final job = selectedKey == null
        ? null
        : ref.watch(votingSubmissionJobProvider(selectedKey));
    final session = selectedKey == null
        ? const AsyncValue<VotingSessionState>.loading()
        : ref.watch(votingSubmissionJobSessionProvider(selectedKey));
    if (selectedKey != null &&
        job?.status == VotingSubmissionJobStatus.complete) {
      _scheduleConfirmationNavigation(selectedKey);
    }
    final view = session.when(
      skipLoadingOnRefresh: false,
      loading: () {
        if (startError != null) {
          return VotingStatusViewModel(
            phase: VotingSessionPhase.error,
            errorMessage: startError,
            onRetry: _retry,
          );
        }
        if (job?.status == VotingSubmissionJobStatus.error &&
            job?.key?.roundId == widget.roundId) {
          return VotingStatusViewModel(
            phase: VotingSessionPhase.error,
            errorMessage: job?.errorMessage,
            onRetry: _retry,
            onClear: _clearError,
          );
        }
        return null;
      },
      error: (error, _) => VotingStatusViewModel(
        phase: VotingSessionPhase.error,
        errorMessage: job?.errorMessage ?? _messageFromError(error),
        onRetry: _retry,
        onClear: job?.status == VotingSubmissionJobStatus.error
            ? _clearError
            : null,
      ),
      data: (state) {
        final localError = job?.errorMessage;
        final submissionJobComplete =
            job?.status == VotingSubmissionJobStatus.complete;
        final submissionJobInFlight = job?.isInFlight ?? false;
        final sessionCompleted = _hasCompletedSubmission(state);
        final completedSubmission =
            submissionJobComplete ||
            (!submissionJobInFlight && sessionCompleted) ||
            (submissionJobInFlight &&
                sessionCompleted &&
                _hasCompletedCurrentSubmissionProgress(state));
        final phase = job?.status != VotingSubmissionJobStatus.error
            ? _displayPhase(
                state.phase,
                completedSubmission: completedSubmission,
              )
            : VotingSessionPhase.error;
        return VotingStatusViewModel(
          phase: phase,
          voteSubmissionDetail: _voteSubmissionDetail(state),
          voteSubmissionProgress: _voteSubmissionProgress(
            state,
            completedSubmission: completedSubmission,
          ),
          delegationProgress: _delegationProgress(state),
          completedSubmission: completedSubmission,
          submissionJobComplete: submissionJobComplete,
          submissionJobInFlight: submissionJobInFlight,
          softwareAccountRequired: job?.softwareAccountRequired ?? false,
          isHardwareAccount: state.isHardwareAccount,
          keystoneSigningBundleIndex:
              state.keystoneSigningRequest?.bundleIndex,
          canSkipRemainingKeystoneBundles:
              state.canSkipRemainingKeystoneBundles,
          keystoneUrParts: job?.keystoneUrParts ?? const [],
          keystoneBatchMemos: job?.keystoneBatchMemos ?? const [],
          keystoneBatchMessageCount: job?.keystoneBatchMessageCount ?? 0,
          keystoneBatchTotalCount: job?.keystoneBatchTotalCount ?? 0,
          keystoneQrError: job?.keystoneQrError,
          keystoneScanError: state.keystoneScanError,
          walletScannedHeight: state.walletScannedHeight,
          walletSnapshotHeight: state.walletSnapshotHeight,
          walletChainTipHeight: state.walletChainTipHeight,
          errorMessage: _sessionErrorMessage(state, localError),
          onRetry: _retry,
          onClear: job?.status == VotingSubmissionJobStatus.error
              ? _clearError
              : null,
          onScanKeystone: _scanKeystoneSignature,
          onSkipKeystoneBundles: _skipRemainingKeystoneBundles,
        );
      },
    );
    return widget.builder(context, view);
  }

  VotingSessionPhase _displayPhase(
    VotingSessionPhase phase, {
    required bool completedSubmission,
  }) {
    if (phase == VotingSessionPhase.done && !completedSubmission) {
      return VotingSessionPhase.idle;
    }
    return phase;
  }

  String? _sessionErrorMessage(VotingSessionState state, String? localError) {
    if (localError != null) return localError;
    return _statusErrorMessage(state, fallbackForErrorPhase: false);
  }

  String? _statusErrorMessage(
    VotingSessionState state, {
    bool fallbackForErrorPhase = true,
  }) {
    final error = state.error;
    if (error != null) return friendlyVotingErrorText(error.message);
    final round = state.round;
    if (round != null && state.pirDiagnostics.isNotEmpty) {
      return _pirDiagnosticsErrorMessage(
        expectedSnapshotHeight: round.snapshotHeight,
        diagnostics: state.pirDiagnostics,
      );
    }
    if (!fallbackForErrorPhase || state.phase != VotingSessionPhase.error) {
      return null;
    }
    return _genericVotingStatusErrorMessage;
  }

  static const _genericVotingStatusErrorMessage =
      'Voting could not continue for this account. Retry, or switch to an '
      'eligible account if this account cannot vote in this voting round.';

  String _pirDiagnosticsErrorMessage({
    required int expectedSnapshotHeight,
    required List<PirSnapshotEndpointDiagnostic> diagnostics,
  }) {
    final expected = formatBlockHeight(expectedSnapshotHeight);
    final reportedHeights = diagnostics
        .map((diagnostic) => diagnostic.reportedHeight)
        .nonNulls
        .toSet();
    if (diagnostics.every(
          (diagnostic) => diagnostic.status == PirSnapshotEndpointStatus.behind,
        ) &&
        reportedHeights.isNotEmpty) {
      final highest = formatBlockHeight(
        reportedHeights.reduce((left, right) => left > right ? left : right),
      );
      return 'Voting PIR data is not ready for this voting round yet. Expected '
          'snapshot block $expected; PIR endpoints report $highest.';
    }
    return 'No PIR endpoint matched this voting round snapshot. Expected snapshot '
        'block $expected.';
  }

  String? _shareSubmissionDetail(VotingSessionState state) {
    final key = state.currentVoteKey;
    if (key != null) {
      final message = state.voteProgress[key]?.message;
      if (message != null && message.isNotEmpty) return message;
    }
    final messages = state.voteProgress.values
        .where(
          (progress) =>
              progress.phase == 'submitting_shares' &&
              progress.message != null &&
              progress.message!.isNotEmpty,
        )
        .map((progress) => progress.message!)
        .toList(growable: false);
    return messages.isEmpty ? null : messages.last;
  }

  String? _voteSubmissionDetail(VotingSessionState state) {
    final total = state.voteSubmissionTotalCount;
    if (total > 0) {
      final completed = state.voteSubmissionCompletedCount.clamp(0, total);
      final current = completed >= total ? total : completed + 1;
      return 'Question $current/$total';
    }
    return _shareSubmissionDetail(state);
  }

  double? _voteSubmissionProgress(
    VotingSessionState state, {
    required bool completedSubmission,
  }) {
    if (completedSubmission) return 1;
    final progress = state.voteSubmissionProgress;
    if (progress == null) return null;
    return progress.clamp(0.0, 1.0).toDouble();
  }

  double? _delegationProgress(VotingSessionState state) {
    if (state.phase != VotingSessionPhase.delegating) return null;
    final bundleIndexes = _delegationProgressBundleIndexes(state);
    if (bundleIndexes.isEmpty) return null;

    var completedProgress = 0.0;
    for (final bundleIndex in bundleIndexes) {
      final progress = state.delegationProgress[bundleIndex];
      if (_isDelegationBundleComplete(progress)) {
        completedProgress += 1;
      } else {
        completedProgress +=
            progress?.proofProgress?.clamp(0.0, 1.0).toDouble() ?? 0;
      }
    }
    return (completedProgress / bundleIndexes.length).clamp(0.0, 1.0);
  }

  List<int> _delegationProgressBundleIndexes(VotingSessionState state) {
    final indexes = <int>{
      ...?state.resumePlan?.pendingDelegationBundleIndexes,
      ...state.delegationProgress.keys,
      ?state.currentBundleIndex,
    }.toList()..sort();
    return indexes;
  }

  bool _isDelegationBundleComplete(VotingSessionProgress? progress) {
    return progress?.phase == 'submitted' || progress?.phase == 'confirmed';
  }

  void _retry() {
    final key = _selectedJobKey();
    if (key == null) {
      _startScheduled = false;
      _scheduleStart();
      return;
    }
    unawaited(ref.read(votingSubmissionJobsProvider.notifier).retry(key));
  }

  void _clearError() {
    final key = _selectedJobKey();
    if (key != null) {
      ref.read(votingSubmissionJobsProvider.notifier).dismiss(key);
    }
    context.go('/voting');
  }

  void _scheduleConfirmationNavigation(VotingSessionKey key) {
    if (_confirmationNavigationScheduledFor == key) return;
    _confirmationNavigationScheduledFor = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_selectedJobKey() != key) {
        if (_confirmationNavigationScheduledFor == key) {
          _confirmationNavigationScheduledFor = null;
        }
        return;
      }
      unawaited(_navigateToConfirmation(key));
    });
  }

  Future<void> _navigateToConfirmation(VotingSessionKey key) async {
    try {
      await ref
          .read(votingSubmissionSessionProvider(key).notifier)
          .refreshEligibleWeight();
    } catch (error) {
      debugPrint(
        '[zcash] Voting: pre-confirmation voting power refresh failed '
        'round=${key.roundId} account=${key.accountUuid} error=$error',
      );
    }
    if (!mounted || _selectedJobKey() != key) return;
    context.go(
      votingSubmissionConfirmedRoute(key.roundId, accountUuid: key.accountUuid),
    );
  }
}
