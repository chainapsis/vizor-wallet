import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/voting/voting_config_provider.dart';
import '../../providers/voting/voting_rounds_provider.dart';
import '../../providers/voting/voting_session_provider.dart';
import '../../providers/voting/voting_submission_job_provider.dart';
import '../../providers/voting/voting_state.dart';
import 'voting_error_messages.dart';
import 'voting_flow_models.dart';
import 'voting_formatters.dart';
import 'voting_resume_plan.dart';

/// Everything a confirmation scaffold needs to render one state of the
/// submission receipt. Produced by [VotingSubmissionConfirmationFlow];
/// rendered by the form-factor screens.
@immutable
class VotingConfirmationViewModel {
  const VotingConfirmationViewModel({
    required this.confirmed,
    required this.title,
    required this.pollTitle,
    required this.message,
    required this.votingPower,
    this.onDone,
    this.isReturningToPolls = false,
    this.doneEnabled = true,
    this.doneLabel = 'Done',
    this.retryLabel,
    this.onRetry,
    this.returnErrorMessage,
  });

  final bool confirmed;
  final String title;
  final String pollTitle;
  final String message;
  final String votingPower;
  final VoidCallback? onDone;
  final bool isReturningToPolls;
  final bool doneEnabled;
  final String doneLabel;
  final String? retryLabel;
  final VoidCallback? onRetry;
  final String? returnErrorMessage;
}

typedef VotingConfirmationBuilder =
    Widget Function(BuildContext context, VotingConfirmationViewModel? view);

/// Shared state machine behind the submission confirmation screens.
///
/// Owns the voting-power refresh, the poll-list prefetch, and the guarded
/// return-to-polls transition, and hands the resulting view model to a
/// form-factor scaffold via [builder]. A null view model means the session
/// is still loading.
class VotingSubmissionConfirmationFlow extends ConsumerStatefulWidget {
  const VotingSubmissionConfirmationFlow({
    super.key,
    required this.roundId,
    required this.builder,
    this.accountUuid,
  });

  final String roundId;
  final String? accountUuid;
  final VotingConfirmationBuilder builder;

  @override
  ConsumerState<VotingSubmissionConfirmationFlow> createState() =>
      _VotingSubmissionConfirmationFlowState();
}

class _VotingSubmissionConfirmationFlowState
    extends ConsumerState<VotingSubmissionConfirmationFlow> {
  bool _isReturningToPolls = false;
  bool _refreshingVotingPower = false;
  bool _votingPowerRefreshAttempted = false;
  String? _votingPowerRefreshKey;
  BigInt? _refreshedVotingPowerZatoshi;
  bool _refreshedVotingEligibilityConfirmed = false;
  String? _votingPowerRefreshErrorMessage;
  VotingSessionState? _lastSubmissionState;
  String? _pollRefreshKey;
  Future<void>? _pollRefreshFuture;
  String? _returnErrorMessage;

  @override
  void didUpdateWidget(covariant VotingSubmissionConfirmationFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.roundId == widget.roundId &&
        oldWidget.accountUuid == widget.accountUuid) {
      return;
    }
    _refreshingVotingPower = false;
    _votingPowerRefreshAttempted = false;
    _votingPowerRefreshKey = null;
    _refreshedVotingPowerZatoshi = null;
    _refreshedVotingEligibilityConfirmed = false;
    _votingPowerRefreshErrorMessage = null;
    _lastSubmissionState = null;
    _pollRefreshKey = null;
    _pollRefreshFuture = null;
    _returnErrorMessage = null;
  }

  @override
  Widget build(BuildContext context) {
    final jobKey = widget.accountUuid == null || widget.accountUuid!.isEmpty
        ? null
        : VotingSessionKey(
            roundId: widget.roundId,
            accountUuid: widget.accountUuid!,
          );
    final session = jobKey == null
        ? ref.watch(votingSessionProvider(widget.roundId))
        : ref.watch(votingSubmissionJobSessionProvider(jobKey));
    final view = session.when(
      skipLoadingOnRefresh: false,
      loading: () => null,
      error: (error, _) {
        final cachedState = _lastSubmissionState;
        if (cachedState != null) {
          return _buildSubmissionView(
            state: cachedState,
            jobKey: jobKey,
            loadError: error,
          );
        }
        return VotingConfirmationViewModel(
          confirmed: false,
          title: 'Submission not complete',
          pollTitle: 'Token holder voting',
          message:
              "Couldn't load submission details: ${friendlyVotingErrorMessage(error)}",
          votingPower: 'Not available',
        );
      },
      data: (state) {
        return _buildSubmissionView(state: state, jobKey: jobKey);
      },
    );
    return widget.builder(context, view);
  }

  VotingConfirmationViewModel _buildSubmissionView({
    required VotingSessionState state,
    required VotingSessionKey? jobKey,
    Object? loadError,
  }) {
    final pollTitle = state.round?.title.isNotEmpty == true
        ? state.round!.title
        : 'Token holder voting';
    final hasCompletedSubmission = hasCompletedVoteForDisplay(state.roundPlan);
    if (hasCompletedSubmission) {
      _lastSubmissionState = state;
    }
    final hasConfirmedVotingEligibility =
        state.hasConfirmedVotingEligibility ||
        _refreshedVotingEligibilityConfirmed;
    final confirmed = hasCompletedSubmission && hasConfirmedVotingEligibility;
    _maybeRefreshVotingPower(
      confirmed: hasCompletedSubmission,
      state: state,
      jobKey: jobKey,
    );
    _maybePrefetchPollRefresh(
      confirmed: confirmed,
      state: state,
      jobKey: jobKey,
    );

    if (!hasCompletedSubmission) {
      return VotingConfirmationViewModel(
        confirmed: false,
        title: 'Submission not complete',
        pollTitle: pollTitle,
        message:
            'This account has not completed submission for this voting round.',
        votingPower: 'Not available',
      );
    }
    if (!hasConfirmedVotingEligibility) {
      final storedEligibilityError = state.error;
      final storedEligibilityErrorMessage = storedEligibilityError == null
          ? null
          : friendlyVotingErrorText(storedEligibilityError.message);
      final loadErrorMessage = loadError == null
          ? null
          : friendlyVotingErrorMessage(loadError);
      final latestRefreshMessage =
          _votingPowerRefreshErrorMessage ?? loadErrorMessage;
      final retryMessage = _refreshingVotingPower ? null : latestRefreshMessage;
      final canRetry =
          latestRefreshMessage != null &&
          !_refreshingVotingPower &&
          !isVotingEligibilityErrorText(latestRefreshMessage);
      return VotingConfirmationViewModel(
        confirmed: false,
        title: 'Submission not complete',
        pollTitle: pollTitle,
        message:
            retryMessage ??
            storedEligibilityErrorMessage ??
            (_refreshingVotingPower
                ? 'Checking voting eligibility for this account.'
                : 'Voting eligibility has not been confirmed for this account.'),
        votingPower: 'Not available',
        retryLabel: canRetry ? 'Retry' : null,
        onRetry: canRetry
            ? () => _retryVotingPowerRefresh(state, jobKey)
            : null,
      );
    }
    return VotingConfirmationViewModel(
      confirmed: true,
      title: 'Submission confirmed!',
      pollTitle: pollTitle,
      message: 'Your vote was successfully published and cannot be changed.',
      votingPower: _formatVotingPower(
        _refreshedVotingPowerZatoshi ?? state.eligibleWeightZatoshi,
      ),
      isReturningToPolls: _isReturningToPolls,
      doneEnabled: !_isReturningToPolls,
      doneLabel: _isReturningToPolls ? 'Updating...' : 'Done',
      returnErrorMessage: _returnErrorMessage,
      onDone: () => unawaited(_returnToPolls(jobKey)),
    );
  }

  Future<void> _returnToPolls(VotingSessionKey? jobKey) async {
    if (_isReturningToPolls) return;
    setState(() {
      _isReturningToPolls = true;
      _returnErrorMessage = null;
    });
    try {
      await _runPollRefresh();
      if (!mounted) return;
      if (jobKey != null) {
        ref.read(votingSubmissionJobsProvider.notifier).dismiss(jobKey);
      }
      context.go('/voting');
    } catch (error) {
      if (!mounted) return;
      debugPrint(
        '[zcash] Voting: poll list refresh before return failed: $error',
      );
      setState(() {
        _isReturningToPolls = false;
        _returnErrorMessage = "Couldn't update voting rounds. Try again.";
      });
    }
  }

  String _formatVotingPower(BigInt? zatoshi) {
    if (zatoshi == null) return 'Not available';
    return formatVotingPower(zatoshi);
  }

  void _retryVotingPowerRefresh(
    VotingSessionState state,
    VotingSessionKey? jobKey,
  ) {
    if (_refreshingVotingPower) return;
    final refreshKey = _submissionRefreshKey(state: state, jobKey: jobKey);
    setState(() {
      _votingPowerRefreshKey = refreshKey;
      _refreshingVotingPower = true;
      _votingPowerRefreshAttempted = true;
      _votingPowerRefreshErrorMessage = null;
    });
    unawaited(
      _refreshVotingPower(state: state, jobKey: jobKey, key: refreshKey),
    );
  }

  String _submissionRefreshKey({
    required VotingSessionState state,
    required VotingSessionKey? jobKey,
  }) {
    return '${widget.roundId}|${jobKey?.accountUuid ?? state.accountUuid ?? ''}';
  }

  void _maybeRefreshVotingPower({
    required bool confirmed,
    required VotingSessionState state,
    required VotingSessionKey? jobKey,
  }) {
    final refreshKey = _submissionRefreshKey(state: state, jobKey: jobKey);
    if (_votingPowerRefreshKey != refreshKey) {
      _votingPowerRefreshKey = refreshKey;
      _refreshingVotingPower = false;
      _votingPowerRefreshAttempted = false;
      _refreshedVotingPowerZatoshi = null;
      _refreshedVotingEligibilityConfirmed = false;
      _votingPowerRefreshErrorMessage = null;
    }
    if (!confirmed || _refreshingVotingPower || _votingPowerRefreshAttempted) {
      return;
    }

    _refreshingVotingPower = true;
    _votingPowerRefreshAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        _refreshVotingPower(state: state, jobKey: jobKey, key: refreshKey),
      );
    });
  }

  void _maybePrefetchPollRefresh({
    required bool confirmed,
    required VotingSessionState state,
    required VotingSessionKey? jobKey,
  }) {
    final refreshKey = _submissionRefreshKey(state: state, jobKey: jobKey);
    if (_pollRefreshKey != refreshKey) {
      _pollRefreshKey = refreshKey;
      _pollRefreshFuture = null;
      _returnErrorMessage = null;
    }
    if (!confirmed || _pollRefreshFuture != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pollRefreshFuture != null) return;
      unawaited(
        _runPollRefresh().catchError((Object error) {
          debugPrint(
            '[zcash] Voting: poll list prefetch before return failed: $error',
          );
        }),
      );
    });
  }

  Future<void> _runPollRefresh() {
    final inFlight = _pollRefreshFuture;
    if (inFlight != null) return inFlight;

    final refresh = refreshVotingPollList(
      config: ref.read(votingConfigProvider.notifier),
      readRounds: () => ref.read(votingRoundsProvider.notifier),
      shouldReload: () => mounted,
    );
    _pollRefreshFuture = refresh;
    return refresh.then(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _pollRefreshFuture = null;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  Future<void> _refreshVotingPower({
    required VotingSessionState state,
    required VotingSessionKey? jobKey,
    required String key,
  }) async {
    try {
      final notifier = jobKey == null
          ? ref.read(votingSessionProvider(widget.roundId).notifier)
          : ref.read(votingSubmissionSessionProvider(jobKey).notifier);
      final refreshed = await notifier.refreshEligibleWeight();
      if (!mounted || _votingPowerRefreshKey != key) return;
      final refreshedState = jobKey == null
          ? ref.read(votingSessionProvider(widget.roundId)).value
          : ref.read(votingSubmissionSessionProvider(jobKey)).value;
      final refreshedEligibilityConfirmed =
          refreshedState?.hasConfirmedVotingEligibility ?? false;
      final refreshedError = refreshedState?.error;
      setState(() {
        _refreshedVotingEligibilityConfirmed = refreshedEligibilityConfirmed;
        _refreshedVotingPowerZatoshi = refreshedEligibilityConfirmed
            ? refreshed
            : null;
        _votingPowerRefreshErrorMessage =
            refreshedEligibilityConfirmed || refreshedError == null
            ? null
            : friendlyVotingErrorText(refreshedError.message);
      });
    } catch (error) {
      debugPrint(
        '[zcash] Voting: confirmation voting power refresh failed '
        'round=${widget.roundId} account=${state.accountUuid} error=$error',
      );
      if (mounted && _votingPowerRefreshKey == key) {
        setState(() {
          _refreshedVotingEligibilityConfirmed = false;
          _refreshedVotingPowerZatoshi = null;
          _votingPowerRefreshErrorMessage = friendlyVotingErrorText('$error');
        });
      }
    } finally {
      if (mounted && _votingPowerRefreshKey == key) {
        setState(() {
          _refreshingVotingPower = false;
        });
      }
    }
  }
}
