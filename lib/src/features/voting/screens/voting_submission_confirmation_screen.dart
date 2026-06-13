import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/voting/voting_config_provider.dart';
import '../../../providers/voting/voting_rounds_provider.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../../../providers/voting/voting_submission_job_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../voting_error_messages.dart';
import '../voting_flow_models.dart';
import '../voting_formatters.dart';
import '../voting_resume_plan.dart';

class VotingSubmissionConfirmationScreen extends ConsumerStatefulWidget {
  const VotingSubmissionConfirmationScreen({
    super.key,
    required this.roundId,
    this.accountUuid,
  });

  final String roundId;
  final String? accountUuid;

  @override
  ConsumerState<VotingSubmissionConfirmationScreen> createState() =>
      _VotingSubmissionConfirmationScreenState();
}

class _VotingSubmissionConfirmationScreenState
    extends ConsumerState<VotingSubmissionConfirmationScreen> {
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
  void didUpdateWidget(covariant VotingSubmissionConfirmationScreen oldWidget) {
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
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: session.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) {
            final cachedState = _lastSubmissionState;
            if (cachedState != null) {
              return _buildSubmissionContent(
                state: cachedState,
                jobKey: jobKey,
                loadError: error,
              );
            }
            return _ConfirmationScaffold(
              confirmed: false,
              title: 'Submission not complete',
              pollTitle: 'Token holder voting',
              message: "Couldn't load submission details: $error",
              votingPower: 'Not available',
            );
          },
          data: (state) {
            return _buildSubmissionContent(state: state, jobKey: jobKey);
          },
        ),
      ),
    );
  }

  Widget _buildSubmissionContent({
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
      return _ConfirmationScaffold(
        confirmed: false,
        title: 'Submission not complete',
        pollTitle: pollTitle,
        message:
            'This account has not completed submission for this voting round.',
        votingPower: 'Not available',
        doneLabel: 'Done',
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
      return _ConfirmationScaffold(
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
        doneLabel: 'Done',
        retryLabel: canRetry ? 'Retry' : null,
        onRetry: canRetry
            ? () => _retryVotingPowerRefresh(state, jobKey)
            : null,
      );
    }
    return _ConfirmationScaffold(
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

class _ConfirmationScaffold extends StatelessWidget {
  const _ConfirmationScaffold({
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppPaneToolbar(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: colors.background.inverse,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.full,
                                ),
                              ),
                              child: Icon(
                                Icons.how_to_vote,
                                color: colors.text.inverse,
                                size: 24,
                              ),
                            ),
                            Transform.translate(
                              offset: const Offset(-6, 0),
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      colors.background.utilitySuccessSubtle,
                                      colors.background.utilitySuccessStrong,
                                    ],
                                  ),
                                  border: Border.all(
                                    color: colors.background.base,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.full,
                                  ),
                                ),
                                child: Icon(
                                  confirmed
                                      ? Icons.verified
                                      : Icons.error_outline,
                                  color: confirmed
                                      ? colors.text.success
                                      : colors.text.warning,
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          title,
                          style: AppTypography.headlineMedium.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          message,
                          style: AppTypography.bodyMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _ReceiptCard(
                          rows: [
                            _ReceiptRow(
                              label: 'Voting round',
                              value: pollTitle,
                            ),
                            _ReceiptRow(
                              label: 'Voting power',
                              value: votingPower,
                            ),
                          ],
                        ),
                        const Spacer(flex: 2),
                        SizedBox(
                          width: double.infinity,
                          child: AppButton(
                            onPressed: doneEnabled
                                ? onDone ?? () => context.go('/voting')
                                : null,
                            variant: AppButtonVariant.primary,
                            child: Text(doneLabel),
                          ),
                        ),
                        if (onRetry != null && retryLabel != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          SizedBox(
                            width: double.infinity,
                            child: AppButton(
                              onPressed: onRetry,
                              variant: AppButtonVariant.secondary,
                              child: Text(retryLabel!),
                            ),
                          ),
                        ],
                        if (returnErrorMessage != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            returnErrorMessage!,
                            style: AppTypography.bodyMedium.copyWith(
                              color: colors.text.warning,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (isReturningToPolls)
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: DecoratedBox(
                  decoration: const BoxDecoration(color: Color(0x4D000000)),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppIcon(
                          AppIcons.loader,
                          size: 20,
                          color: Color(0xFFFFFFFF),
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          'Updating voting rounds...',
                          style: AppTypography.bodyMediumStrong.copyWith(
                            color: const Color(0xFFFFFFFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.rows});

  final List<_ReceiptRow> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.background.raised.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: colors.border.subtle),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: colors.border.subtle),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.s,
              ),
              child: rows[i],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}
