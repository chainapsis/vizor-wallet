import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/voting/voting_session_provider.dart';
import '../../../providers/voting/voting_state.dart';
import '../../../rust/api/keystone.dart' as rust_keystone;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../../rust/api/voting.dart' as rust_voting;
import '../../keystone/widgets/keystone_pczt_qr_stage.dart';
import '../voting_flow_models.dart';
import '../voting_routes.dart';
import '../voting_share_timing.dart';

class VotingStatusScreen extends ConsumerStatefulWidget {
  const VotingStatusScreen({super.key, required this.roundId});

  final String roundId;

  @override
  ConsumerState<VotingStatusScreen> createState() => _VotingStatusScreenState();
}

class _VotingStatusScreenState extends ConsumerState<VotingStatusScreen> {
  bool _started = false;
  bool _completedInThisRun = false;
  bool _softwareAccountRequired = false;
  String? _runErrorMessage;
  List<String> _keystoneUrParts = const [];
  String? _keystoneQrError;
  List<rust_voting.ApiDraftVote>? _pendingDraftVotes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_started) return;
    try {
      _started = true;
      if (mounted) {
        setState(() {
          _runErrorMessage = null;
          _softwareAccountRequired = false;
        });
      }

      final roundId = widget.roundId;
      final sessionNotifier = ref.read(votingSessionProvider(roundId).notifier);
      final session = await ref.read(votingSessionProvider(roundId).future);
      if (!mounted) return;
      final round = session.round;
      if (round == null) {
        _setRunError(
          'Voting round details are not available yet. Retry in a moment.',
        );
        return;
      }
      final proposals = proposalsFromRound(round);
      final accountUuid = session.accountUuid;
      if (accountUuid == null) {
        _setRunError('No active account for voting session.');
        return;
      }
      final draftVotes = ref
          .read(
            votingDraftProvider(
              VotingSessionKey(roundId: roundId, accountUuid: accountUuid),
            ),
          )
          .toDraftVotes(proposals);
      if (draftVotes.isEmpty) {
        _setRunError('Choose at least one vote before submitting.');
        return;
      }
      await sessionNotifier.ensureWalletReadyForVoting();
      if (!mounted) return;
      final afterWalletSync = ref.read(votingSessionProvider(roundId)).value;
      if (afterWalletSync?.phase == VotingSessionPhase.error ||
          afterWalletSync?.phase == VotingSessionPhase.waitingForWalletSync) {
        return;
      }

      if (session.isHardwareAccount) {
        _pendingDraftVotes = draftVotes;
        await _prepareKeystoneSigning(sessionNotifier);
        return;
      }

      final mnemonic = await ref
          .read(accountProvider.notifier)
          .getMnemonicForAccount(accountUuid);
      if (!mounted) return;
      if (mnemonic == null || mnemonic.isEmpty) {
        setState(() {
          _softwareAccountRequired = true;
        });
        return;
      }
      final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);
      try {
        if (!mounted) return;
        await sessionNotifier.delegatePendingBundles(seedBytes: seedBytes);
      } finally {
        seedBytes.fillRange(0, seedBytes.length, 0);
      }
      if (!mounted) return;
      final afterDelegation = ref.read(votingSessionProvider(roundId)).value;
      if (afterDelegation?.phase == VotingSessionPhase.error) return;
      await sessionNotifier.castVotes(draftVotes: draftVotes);
      if (!mounted) return;
      final afterVotes = ref.read(votingSessionProvider(roundId)).value;
      if (afterVotes?.phase == VotingSessionPhase.error) return;
      await sessionNotifier.submitPendingShares();
      if (!mounted) return;
      final done = ref.read(votingSessionProvider(roundId)).value;
      if (done?.phase != VotingSessionPhase.done) return;
      setState(() {
        _completedInThisRun = true;
      });
      context.go(votingSubmissionConfirmedRoute(roundId));
    } catch (error) {
      _setRunError(_messageFromError(error));
    }
  }

  Future<void> _prepareKeystoneSigning(
    VotingSessionNotifier sessionNotifier,
  ) async {
    await sessionNotifier.prepareKeystoneSigning();
    if (!mounted) return;
    final state = ref.read(votingSessionProvider(widget.roundId)).value;
    if (state == null || state.phase == VotingSessionPhase.error) return;
    final request = state.keystoneSigningRequest;
    if (request != null) {
      await _updateKeystoneQr(request);
      return;
    }
    await _submitAfterKeystoneSignatures(sessionNotifier);
  }

  Future<void> _updateKeystoneQr(
    rust_voting.ApiKeystoneDelegationRequest request,
  ) async {
    if (!mounted) return;
    setState(() {
      _keystoneUrParts = const [];
      _keystoneQrError = null;
    });
    try {
      final urParts = await rust_keystone.encodePcztUrParts(
        pcztBytes: request.redactedPcztBytes,
        maxFragmentLen: BigInt.from(200),
      );
      if (!mounted) return;
      setState(() {
        _keystoneUrParts = urParts;
        _keystoneQrError = null;
      });
    } catch (error) {
      _setRunError(
        'Failed to prepare Keystone voting QR: ${_messageFromError(error)}',
      );
    }
  }

  Future<void> _scanKeystoneSignature() async {
    final signedPczt = await context.push<List<int>>('/voting/keystone/scan');
    if (!mounted) return;
    if (signedPczt == null || signedPczt.isEmpty) return;

    try {
      final sessionNotifier = ref.read(
        votingSessionProvider(widget.roundId).notifier,
      );
      await sessionNotifier.handleKeystoneSignedPczt(signedPczt);
      if (!mounted) return;
      final state = ref.read(votingSessionProvider(widget.roundId)).value;
      if (state == null || state.phase == VotingSessionPhase.error) return;
      final request = state.keystoneSigningRequest;
      if (request != null) {
        await _updateKeystoneQr(request);
        return;
      }
      await _submitAfterKeystoneSignatures(sessionNotifier);
    } catch (error) {
      _setRunError(_messageFromError(error));
    }
  }

  Future<void> _submitAfterKeystoneSignatures(
    VotingSessionNotifier sessionNotifier,
  ) async {
    if (!mounted) return;
    final draftVotes = _pendingDraftVotes;
    if (draftVotes == null || draftVotes.isEmpty) {
      _setRunError('Choose at least one vote before submitting.');
      return;
    }
    setState(() {
      _keystoneUrParts = const [];
      _keystoneQrError = null;
    });
    await sessionNotifier.delegatePendingBundlesWithKeystoneSignatures();
    if (!mounted) return;
    final afterDelegation = ref
        .read(votingSessionProvider(widget.roundId))
        .value;
    if (afterDelegation?.phase == VotingSessionPhase.error) return;
    await sessionNotifier.castVotes(draftVotes: draftVotes);
    if (!mounted) return;
    final afterVotes = ref.read(votingSessionProvider(widget.roundId)).value;
    if (afterVotes?.phase == VotingSessionPhase.error) return;
    await sessionNotifier.submitPendingShares();
    if (!mounted) return;
    final done = ref.read(votingSessionProvider(widget.roundId)).value;
    if (done?.phase != VotingSessionPhase.done) return;
    setState(() {
      _completedInThisRun = true;
    });
    context.go(votingSubmissionConfirmedRoute(widget.roundId));
  }

  void _setRunError(String message) {
    if (!mounted) return;
    setState(() {
      _runErrorMessage = message;
      _softwareAccountRequired = false;
      _keystoneUrParts = const [];
      _keystoneQrError = null;
    });
  }

  String _messageFromError(Object error) {
    final text = error.toString().trim();
    for (final prefix in const ['Exception: ', 'StateError: ', 'Bad state: ']) {
      if (text.startsWith(prefix)) {
        return text.substring(prefix.length);
      }
    }
    return text.isEmpty ? 'Voting session action failed.' : text;
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(votingSessionProvider(widget.roundId));
    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: SensitivePrivacyOverlay(
          sensitiveContentVisible: true,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: session.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _StatusContent(
                phase: VotingSessionPhase.error,
                errorMessage: _runErrorMessage ?? _messageFromError(error),
                onRetry: _retry,
              ),
              data: (state) {
                final localError = _runErrorMessage;
                final phase = localError == null
                    ? _displayPhase(state.phase)
                    : VotingSessionPhase.error;
                return _StatusContent(
                  phase: phase,
                  shareSummary: _shareSummary(state),
                  voteSubmissionDetail: _voteSubmissionDetail(state),
                  voteSubmissionProgress: _voteSubmissionProgress(state),
                  delegationProgress: _delegationProgress(state),
                  softwareAccountRequired: _softwareAccountRequired,
                  isHardwareAccount: state.isHardwareAccount,
                  keystoneSigningRequest: state.keystoneSigningRequest,
                  keystoneUrParts: _keystoneUrParts,
                  keystoneQrError: _keystoneQrError,
                  keystoneScanError: state.keystoneScanError,
                  walletScannedHeight: state.walletScannedHeight,
                  walletSnapshotHeight: state.walletSnapshotHeight,
                  walletChainTipHeight: state.walletChainTipHeight,
                  errorMessage: localError ?? state.error?.message,
                  onRetry: _retry,
                  onScanKeystone: _scanKeystoneSignature,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  VotingSessionPhase _displayPhase(VotingSessionPhase phase) {
    if (phase == VotingSessionPhase.done && !_completedInThisRun) {
      return VotingSessionPhase.loadingWitnesses;
    }
    return phase;
  }

  VotingShareTrackingSummary? _shareSummary(VotingSessionState state) {
    final plan = state.resumePlan;
    final round = state.round;
    if (plan == null || round == null || plan.shareDelegations.isEmpty) {
      return null;
    }
    return VotingShareTrackingSummary.fromShares(plan.shareDelegations, round);
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
      final bundleDetail = _voteSubmissionBundleDetail(state);
      final questionDetail = 'Question $current/$total';
      return bundleDetail == null
          ? questionDetail
          : '$questionDetail · $bundleDetail';
    }
    return _shareSubmissionDetail(state);
  }

  String? _voteSubmissionBundleDetail(VotingSessionState state) {
    final bundleIndex = state.currentVoteKey?.bundleIndex;
    final bundleCount = state.resumePlan?.bundleCount ?? 0;
    if (bundleIndex == null || bundleCount <= 1) return null;
    return 'Bundle ${bundleIndex + 1}/$bundleCount';
  }

  double? _voteSubmissionProgress(VotingSessionState state) {
    if (state.phase == VotingSessionPhase.done) return 1;
    final progress = state.voteSubmissionProgress;
    if (progress == null) return null;
    return progress.clamp(0.0, 1.0).toDouble();
  }

  double? _delegationProgress(VotingSessionState state) {
    if (state.phase != VotingSessionPhase.delegating) return null;
    final bundleIndex = state.currentBundleIndex;
    if (bundleIndex == null) return null;
    return state.delegationProgress[bundleIndex]?.proofProgress
        ?.clamp(0.0, 1.0)
        .toDouble();
  }

  void _retry() {
    _started = false;
    _completedInThisRun = false;
    _softwareAccountRequired = false;
    _runErrorMessage = null;
    _keystoneUrParts = const [];
    _keystoneQrError = null;
    _pendingDraftVotes = null;
    unawaited(_run());
  }
}

class _StatusContent extends StatelessWidget {
  const _StatusContent({
    required this.phase,
    this.shareSummary,
    this.voteSubmissionDetail,
    this.voteSubmissionProgress,
    this.delegationProgress,
    this.softwareAccountRequired = false,
    this.isHardwareAccount = false,
    this.keystoneSigningRequest,
    this.keystoneUrParts = const [],
    this.keystoneQrError,
    this.keystoneScanError,
    this.walletScannedHeight,
    this.walletSnapshotHeight,
    this.walletChainTipHeight,
    this.errorMessage,
    this.onRetry,
    this.onScanKeystone,
  });

  final VotingSessionPhase phase;
  final VotingShareTrackingSummary? shareSummary;
  final String? voteSubmissionDetail;
  final double? voteSubmissionProgress;
  final double? delegationProgress;
  final bool softwareAccountRequired;
  final bool isHardwareAccount;
  final rust_voting.ApiKeystoneDelegationRequest? keystoneSigningRequest;
  final List<String> keystoneUrParts;
  final String? keystoneQrError;
  final String? keystoneScanError;
  final int? walletScannedHeight;
  final int? walletSnapshotHeight;
  final int? walletChainTipHeight;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onScanKeystone;

  @override
  Widget build(BuildContext context) {
    if (softwareAccountRequired) {
      return const _SoftwareAccountRequiredContent();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 0.0;
        return Scrollbar(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          phase == VotingSessionPhase.done
                              ? 'Votes Submitted'
                              : 'Submitting Votes',
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
                        if (phase ==
                            VotingSessionPhase.waitingForWalletSync) ...[
                          _WalletSyncProgressText(
                            scannedHeight: walletScannedHeight,
                            snapshotHeight: walletSnapshotHeight,
                            chainTipHeight: walletChainTipHeight,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        _StepRow(
                          label: 'Syncing wallet to snapshot',
                          active:
                              phase == VotingSessionPhase.waitingForWalletSync,
                          complete: _after(
                            VotingSessionPhase.waitingForWalletSync,
                          ),
                        ),
                        _StepRow(
                          label: 'Selecting notes',
                          complete: _after(VotingSessionPhase.loadingWitnesses),
                        ),
                        if (isHardwareAccount) ...[
                          _StepRow(
                            label: 'Signing with Keystone',
                            active: phase == VotingSessionPhase.keystoneSigning,
                            complete: _after(
                              VotingSessionPhase.keystoneSigning,
                            ),
                          ),
                          if (phase == VotingSessionPhase.keystoneSigning &&
                              keystoneSigningRequest != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            _KeystoneSigningPanel(
                              request: keystoneSigningRequest!,
                              urParts: keystoneUrParts,
                              qrError: keystoneQrError,
                              scanError: keystoneScanError,
                              onScan: onScanKeystone,
                            ),
                            const SizedBox(height: AppSpacing.md),
                          ],
                        ],
                        _StepRow(
                          label: 'Delegating voting authority',
                          active: phase == VotingSessionPhase.delegating,
                          complete: _after(VotingSessionPhase.delegating),
                          progressValue: delegationProgress,
                        ),
                        _StepRow(
                          label: 'Casting votes and submitting shares',
                          active:
                              phase == VotingSessionPhase.syncingVoteTree ||
                              phase == VotingSessionPhase.castingVotes ||
                              phase == VotingSessionPhase.submittingShares,
                          complete: phase == VotingSessionPhase.done,
                          detail: voteSubmissionDetail,
                          progressValue: voteSubmissionProgress,
                        ),
                        if (shareSummary case final summary?
                            when summary.hasShares) ...[
                          const SizedBox(height: AppSpacing.xs),
                          _ShareTrackingRows(summary: summary),
                        ],
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
                          AppButton(
                            onPressed: onRetry,
                            variant: AppButtonVariant.primary,
                            child: const Text('Retry'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
    return Column(
      children: [
        Text(
          'Waiting for wallet sync',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMediumStrong.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ],
        if (remaining != null && remaining > 0) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '$remaining blocks remaining',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ],
      ],
    );
  }
}

class _KeystoneSigningPanel extends StatelessWidget {
  const _KeystoneSigningPanel({
    required this.request,
    required this.urParts,
    this.qrError,
    this.scanError,
    this.onScan,
  });

  final rust_voting.ApiKeystoneDelegationRequest request;
  final List<String> urParts;
  final String? qrError;
  final String? scanError;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final qrPhase = qrError != null
        ? KeystonePcztQrStagePhase.failed
        : urParts.isEmpty
        ? KeystonePcztQrStagePhase.preparing
        : KeystonePcztQrStagePhase.ready;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            Text(
              'Sign Bundle ${request.bundleIndex + 1} of ${request.bundleCount}',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Scan this QR with Keystone, then scan the signed voting QR here.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
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
                scanError!,
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
              child: const Text('Scan Signature'),
            ),
          ],
        ),
      ),
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

class _ShareTrackingRows extends StatelessWidget {
  const _ShareTrackingRows({required this.summary});

  final VotingShareTrackingSummary summary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            _ShareStatusLine(
              label: 'Accepted, waiting for reveal',
              count: summary.waiting,
            ),
            _ShareStatusLine(
              label: 'Ready for helper confirmation',
              count: summary.ready,
            ),
            _ShareStatusLine(
              label: 'Overdue, retrying helpers',
              count: summary.overdue,
            ),
            _ShareStatusLine(
              label: 'Confirmed by helper',
              count: summary.confirmed,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareStatusLine extends StatelessWidget {
  const _ShareStatusLine({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Text(
            count.toString(),
            style: AppTypography.bodySmall.copyWith(color: colors.text.accent),
          ),
        ],
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
              'Software Account Required',
              textAlign: TextAlign.center,
              style: AppTypography.displaySmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Coinholder voting requires a software account. Switch to a software account to vote in this round.',
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
                ? CircularProgressIndicator(strokeWidth: 2, value: progress)
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
