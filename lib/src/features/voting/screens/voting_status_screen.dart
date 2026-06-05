import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../../../providers/voting/voting_submission_job_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../../../rust/third_party/zcash_voting/delegate.dart' as rust_delegate;
import '../../../services/voting/pir_snapshot_resolver.dart';
import '../../keystone/widgets/keystone_pczt_qr_stage.dart';
import '../voting_error_messages.dart';
import '../voting_flow_models.dart';
import '../voting_formatters.dart';
import '../voting_resume_plan.dart';
import '../voting_routes.dart';
import '../widgets/voting_pane_scroll_area.dart';

class VotingStatusScreen extends ConsumerStatefulWidget {
  const VotingStatusScreen({
    super.key,
    required this.roundId,
    this.accountUuid,
  });

  final String roundId;
  final String? accountUuid;

  @override
  ConsumerState<VotingStatusScreen> createState() => _VotingStatusScreenState();
}

class _VotingStatusScreenState extends ConsumerState<VotingStatusScreen> {
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
  void didUpdateWidget(covariant VotingStatusScreen oldWidget) {
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
    final signedPczt = await context.push<List<int>>('/voting/keystone/scan');
    if (!mounted || _selectedJobKey() != key) return;
    if (signedPczt == null || signedPczt.isEmpty) return;
    await ref
        .read(votingSubmissionJobsProvider.notifier)
        .handleKeystoneSignedPczt(key, signedPczt);
  }

  Future<void> _skipRemainingKeystoneBundles() async {
    final key = _selectedJobKey();
    if (key == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return const _SkipSignedBundlesDialog();
      },
    );
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
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: session.when(
          skipLoadingOnRefresh: false,
          loading: () {
            if (startError != null) {
              return _StatusContent(
                phase: VotingSessionPhase.error,
                errorMessage: startError,
                onRetry: _retry,
              );
            }
            if (job?.status == VotingSubmissionJobStatus.error &&
                job?.key?.roundId == widget.roundId) {
              return _StatusContent(
                phase: VotingSessionPhase.error,
                errorMessage: job?.errorMessage,
                onRetry: _retry,
                onClear: _clearError,
              );
            }
            return const Center(child: CircularProgressIndicator());
          },
          error: (error, _) => _StatusContent(
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
            return _StatusContent(
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
              keystoneSigningRequest: state.keystoneSigningRequest,
              canSkipRemainingKeystoneBundles:
                  state.canSkipRemainingKeystoneBundles,
              keystoneUrParts: job?.keystoneUrParts ?? const [],
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
        ),
      ),
    );
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

class _SkipSignedBundlesDialog extends StatelessWidget {
  const _SkipSignedBundlesDialog();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: colors.text.warning,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Use signed bundles only?',
                      style: AppTypography.bodyMediumStrong.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Vizor can submit now using only signatures already scanned from Keystone.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Unsigned bundles are skipped, which lowers voting power for this voting round.',
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.warning,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  AppButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    variant: AppButtonVariant.secondary,
                    child: const Text('Keep signing'),
                  ),
                  AppButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    variant: AppButtonVariant.primary,
                    child: const Text('Skip bundles'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({
    required this.phase,
    this.voteSubmissionDetail,
    this.voteSubmissionProgress,
    this.delegationProgress,
    this.completedSubmission = false,
    this.submissionJobComplete = false,
    this.submissionJobInFlight = false,
    this.softwareAccountRequired = false,
    this.isHardwareAccount = false,
    this.keystoneSigningRequest,
    this.canSkipRemainingKeystoneBundles = false,
    this.keystoneUrParts = const [],
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
  final rust_delegate.KeystoneSigningRequest? keystoneSigningRequest;
  final bool canSkipRemainingKeystoneBundles;
  final List<String> keystoneUrParts;
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

  @override
  Widget build(BuildContext context) {
    if (softwareAccountRequired) {
      return const _SoftwareAccountRequiredContent();
    }
    final voteStepComplete =
        completedSubmission || (voteSubmissionProgress ?? 0) >= 1;
    final finalizingSubmission =
        submissionJobInFlight &&
        voteStepComplete &&
        !submissionJobComplete &&
        phase != VotingSessionPhase.error;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 0.0;
        return VotingPaneCenteredScrollView(
          maxWidth: 560,
          minHeight: minHeight,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Submitting votes',
                textAlign: TextAlign.center,
                style: AppTypography.displaySmall.copyWith(
                  color: context.colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "Don't close the window. Generating zero-knowledge proofs can take a while; closing now may lose in-flight proof work.",
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (phase == VotingSessionPhase.waitingForWalletSync) ...[
                _WalletSyncProgressText(
                  scannedHeight: walletScannedHeight,
                  snapshotHeight: walletSnapshotHeight,
                  chainTipHeight: walletChainTipHeight,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (isHardwareAccount &&
                  phase == VotingSessionPhase.keystoneSigning &&
                  keystoneSigningRequest != null) ...[
                _KeystoneSigningPanel(
                  request: keystoneSigningRequest!,
                  urParts: keystoneUrParts,
                  qrError: keystoneQrError,
                  scanError: keystoneScanError,
                  canSkipRemainingBundles: canSkipRemainingKeystoneBundles,
                  onScan: onScanKeystone,
                  onSkipRemainingBundles: onSkipKeystoneBundles,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (isHardwareAccount)
                _StepRow(
                  label: 'Signing with Keystone',
                  active: phase == VotingSessionPhase.keystoneSigning,
                  complete: _after(VotingSessionPhase.keystoneSigning),
                ),
              _StepRow(
                label: 'Delegating voting authority',
                active: phase == VotingSessionPhase.delegating,
                complete: _after(VotingSessionPhase.delegating),
                progressValue: delegationProgress,
              ),
              _StepRow(
                label: 'Casting votes and submitting shares',
                active:
                    !voteStepComplete &&
                    (phase == VotingSessionPhase.syncingVoteTree ||
                        phase == VotingSessionPhase.castingVotes ||
                        phase == VotingSessionPhase.submittingShares),
                complete: voteStepComplete,
                detail: voteStepComplete ? null : voteSubmissionDetail,
                progressValue: voteStepComplete ? null : voteSubmissionProgress,
              ),
              _StepRow(
                label: 'Finalizing submission',
                active: finalizingSubmission,
                complete: submissionJobComplete,
              ),
              if (phase == VotingSessionPhase.error) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  errorMessage ?? 'Voting failed.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.destructive,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    if (onClear != null)
                      AppButton(
                        key: const ValueKey(
                          'voting_status_clear_submission_error',
                        ),
                        onPressed: onClear,
                        variant: AppButtonVariant.secondary,
                        child: const Text('Clear'),
                      ),
                    AppButton(
                      onPressed: onRetry,
                      variant: AppButtonVariant.primary,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  bool _after(VotingSessionPhase target) {
    return phase.index > target.index && phase != VotingSessionPhase.error;
  }
}

class _WalletSyncProgressText extends StatelessWidget {
  const _WalletSyncProgressText({
    required this.scannedHeight,
    required this.snapshotHeight,
    required this.chainTipHeight,
  });

  final int? scannedHeight;
  final int? snapshotHeight;
  final int? chainTipHeight;

  @override
  Widget build(BuildContext context) {
    final scanned = scannedHeight;
    final snapshot = snapshotHeight;
    final chainTip = chainTipHeight;
    final rawRemaining = scanned == null || snapshot == null
        ? null
        : snapshot - scanned;
    final remaining = rawRemaining == null
        ? null
        : rawRemaining > 0
        ? rawRemaining
        : 0;
    final detail = [
      if (scanned != null) 'Synced to block $scanned',
      if (snapshot != null) 'snapshot block $snapshot',
      if (chainTip != null) 'chain tip $chainTip',
    ].join(' / ');
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            Text(
              'Waiting for wallet sync',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Your wallet is catching up to this voting round snapshot. Voting will continue automatically once the wallet has synced through the snapshot block.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
            if (remaining != null && remaining > 0) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                '$remaining blocks remaining',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KeystoneSigningPanel extends StatefulWidget {
  const _KeystoneSigningPanel({
    required this.request,
    required this.urParts,
    this.qrError,
    this.scanError,
    this.canSkipRemainingBundles = false,
    this.onScan,
    this.onSkipRemainingBundles,
  });

  final rust_delegate.KeystoneSigningRequest request;
  final List<String> urParts;
  final String? qrError;
  final String? scanError;
  final bool canSkipRemainingBundles;
  final VoidCallback? onScan;
  final VoidCallback? onSkipRemainingBundles;

  @override
  State<_KeystoneSigningPanel> createState() => _KeystoneSigningPanelState();
}

class _KeystoneSigningPanelState extends State<_KeystoneSigningPanel> {
  static const _transitionCueDuration = Duration(milliseconds: 1300);

  bool _showTransitionCue = false;
  int _cueGeneration = 0;
  Timer? _cueTimer;

  @override
  void didUpdateWidget(covariant _KeystoneSigningPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.bundleIndex != widget.request.bundleIndex) {
      _triggerTransitionCue();
    }
  }

  void _triggerTransitionCue() {
    _cueTimer?.cancel();
    setState(() {
      _showTransitionCue = true;
    });

    final generation = ++_cueGeneration;
    _cueTimer = Timer(_transitionCueDuration, () {
      if (!mounted || generation != _cueGeneration) return;
      setState(() {
        _showTransitionCue = false;
      });
    });
  }

  @override
  void dispose() {
    _cueTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final request = widget.request;
    final urParts = widget.urParts;
    final qrError = widget.qrError;
    final scanError = widget.scanError;
    final canSkipRemainingBundles = widget.canSkipRemainingBundles;
    final onSkipRemainingBundles = widget.onSkipRemainingBundles;
    final onScan = widget.onScan;
    final qrPhase = qrError != null
        ? KeystonePcztQrStagePhase.failed
        : urParts.isEmpty
        ? KeystonePcztQrStagePhase.preparing
        : KeystonePcztQrStagePhase.ready;
    final currentBundle = request.bundleIndex + 1;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 64),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: _showTransitionCue
                          ? colors.background.neutralSubtleOpacity
                          : null,
                      borderRadius: BorderRadius.circular(AppRadii.small),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        final slide = Tween<Offset>(
                          begin: const Offset(0, 0.12),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(position: slide, child: child),
                        );
                      },
                      child: Column(
                        key: ValueKey<String>(
                          'bundle-${request.bundleIndex}-${request.bundleCount}',
                        ),
                        children: [
                          Text(
                            'Sign bundle $currentBundle of ${request.bundleCount}',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                          if (request.bundleCount > 1) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            _KeystoneBundleProgress(
                              currentBundle: currentBundle,
                              bundleCount: request.bundleCount,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: canSkipRemainingBundles
                        ? AppButton(
                            onPressed: onSkipRemainingBundles,
                            variant: AppButtonVariant.primary,
                            size: AppButtonSize.small,
                            child: const Text('Skip'),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Scan QR on this screen with Keystone. Then, scan the signed voting QR displayed on Keystone with this device\'s camera',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            if (_showTransitionCue && request.bundleCount > 1) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Now signing bundle $currentBundle of ${request.bundleCount}',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
            if (request.displayMemo.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _KeystoneSigningMemo(displayMemo: request.displayMemo),
            ],
            const SizedBox(height: AppSpacing.sm),
            KeystonePcztQrStage(
              phase: qrPhase,
              urParts: urParts,
              error: qrError,
            ),
            if (scanError != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                scanError,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.destructive,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              onPressed: urParts.isEmpty ? null : onScan,
              variant: AppButtonVariant.primary,
              minWidth: 220,
              child: const Text('Scan signature'),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeystoneBundleProgress extends StatelessWidget {
  const _KeystoneBundleProgress({
    required this.currentBundle,
    required this.bundleCount,
  });

  final int currentBundle;
  final int bundleCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (bundleCount <= 1) return const SizedBox.shrink();

    final segments = List<Widget>.generate(bundleCount, (index) {
      final isActive = index + 1 == currentBundle;
      final isComplete = index + 1 < currentBundle;
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          height: 6,
          decoration: BoxDecoration(
            color: isActive || isComplete
                ? colors.icon.regular
                : colors.border.subtle,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
        ),
      );
    });

    return Row(
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xxs),
          segments[i],
        ],
      ],
    );
  }
}

class _KeystoneSigningMemo extends StatelessWidget {
  const _KeystoneSigningMemo({required this.displayMemo});

  final String displayMemo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface.input,
          border: Border.all(color: colors.border.subtle),
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Memo',
                style: AppTypography.labelSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              SelectableText(
                displayMemo,
                textAlign: TextAlign.left,
                maxLines: null,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SoftwareAccountRequiredContent extends StatelessWidget {
  const _SoftwareAccountRequiredContent();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Software account required',
              textAlign: TextAlign.center,
              style: AppTypography.displaySmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Token holder voting requires a software account. Switch to a software account to vote in this round.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    this.active = false,
    this.complete = false,
    this.detail,
    this.progressValue,
  });

  final String label;
  final bool active;
  final bool complete;
  final String? detail;
  final double? progressValue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = progressValue?.clamp(0.0, 1.0).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: active
                ? _ProgressBubble(progress: progress)
                : Icon(
                    complete
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: complete
                        ? colors.text.success
                        : colors.text.secondary,
                  ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: active || complete
                        ? colors.text.accent
                        : colors.text.secondary,
                  ),
                ),
                if (detail != null && detail!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail!,
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBubble extends StatelessWidget {
  const _ProgressBubble({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = progress;
    final backgroundColor = colors.text.secondary.withValues(alpha: 0.35);
    const size = 20.0;
    if (value == null) {
      return Center(
        child: SizedBox.square(
          dimension: size,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            backgroundColor: backgroundColor,
          ),
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, animatedValue, child) {
        return Center(
          child: SizedBox.square(
            dimension: size,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: animatedValue,
              backgroundColor: backgroundColor,
            ),
          ),
        );
      },
    );
  }
}
