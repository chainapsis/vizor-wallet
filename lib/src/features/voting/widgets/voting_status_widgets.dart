import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/voting/voting_state.dart';
import '../../../providers/voting/voting_submission_job_provider.dart'
    show VotingKeystoneBatchMemo;
import '../../keystone/widgets/keystone_pczt_qr_stage.dart';
import '../../keystone/widgets/keystone_scan_help_overlay.dart';
import '../voting_status_flow.dart';

/// The step checklist, Keystone signing panel, wallet-sync card, and error
/// section of the submission status screen — everything between the header
/// copy and the shell. Shared by the desktop and mobile status screens; the
/// shells provide their own scroll container and header copy.
class VotingStatusStepsBody extends StatelessWidget {
  const VotingStatusStepsBody({
    super.key,
    required this.view,
    required this.title,
    required this.subtitle,
  });

  final VotingStatusViewModel view;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final phase = view.phase;
    final voteStepComplete =
        view.completedSubmission || (view.voteSubmissionProgress ?? 0) >= 1;
    final finalizingSubmission =
        view.submissionJobInFlight &&
        voteStepComplete &&
        !view.submissionJobComplete &&
        phase != VotingSessionPhase.error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.displaySmall.copyWith(
            color: context.colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (phase == VotingSessionPhase.waitingForWalletSync) ...[
          VotingWalletSyncProgressText(
            scannedHeight: view.walletScannedHeight,
            snapshotHeight: view.walletSnapshotHeight,
            chainTipHeight: view.walletChainTipHeight,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (view.isHardwareAccount &&
            phase == VotingSessionPhase.keystoneSigning &&
            view.keystoneSigningBundleIndex != null) ...[
          VotingKeystoneSigningPanel(
            bundleIndex: view.keystoneSigningBundleIndex!,
            urParts: view.keystoneUrParts,
            batchMemos: view.keystoneBatchMemos,
            batchMessageCount: view.keystoneBatchMessageCount,
            batchTotalCount: view.keystoneBatchTotalCount,
            qrError: view.keystoneQrError,
            scanError: view.keystoneScanError,
            canSkipRemainingBundles: view.canSkipRemainingKeystoneBundles,
            onScan: view.onScanKeystone,
            onSkipRemainingBundles: view.onSkipKeystoneBundles,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (view.isHardwareAccount)
          _StepRow(
            label: 'Signing with Keystone',
            active: phase == VotingSessionPhase.keystoneSigning,
            complete: _after(phase, VotingSessionPhase.keystoneSigning),
          ),
        _StepRow(
          label: 'Delegating voting authority',
          active: phase == VotingSessionPhase.delegating,
          complete: _after(phase, VotingSessionPhase.delegating),
          progressValue: view.delegationProgress,
        ),
        _StepRow(
          label: 'Casting votes and submitting shares',
          active:
              !voteStepComplete &&
              (phase == VotingSessionPhase.syncingVoteTree ||
                  phase == VotingSessionPhase.castingVotes ||
                  phase == VotingSessionPhase.submittingShares),
          complete: voteStepComplete,
          detail: voteStepComplete ? null : view.voteSubmissionDetail,
          progressValue: voteStepComplete ? null : view.voteSubmissionProgress,
        ),
        _StepRow(
          label: 'Finalizing submission',
          active: finalizingSubmission,
          complete: view.submissionJobComplete,
        ),
        if (phase == VotingSessionPhase.error) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            view.errorMessage ?? 'Voting failed.',
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
              if (view.onClear != null)
                AppButton(
                  key: const ValueKey('voting_status_clear_submission_error'),
                  onPressed: view.onClear,
                  variant: AppButtonVariant.secondary,
                  child: const Text('Clear'),
                ),
              AppButton(
                onPressed: view.onRetry,
                variant: AppButtonVariant.primary,
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static bool _after(VotingSessionPhase phase, VotingSessionPhase target) {
    return phase.index > target.index && phase != VotingSessionPhase.error;
  }
}

/// Shown when the submission job refused to run because the round needs a
/// software account (e.g. the signing mnemonic is unavailable).
class VotingSoftwareAccountRequiredContent extends StatelessWidget {
  const VotingSoftwareAccountRequiredContent({super.key});

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

class VotingWalletSyncProgressText extends StatelessWidget {
  const VotingWalletSyncProgressText({
    super.key,
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

class VotingKeystoneSigningPanel extends StatefulWidget {
  const VotingKeystoneSigningPanel({
    super.key,
    required this.bundleIndex,
    required this.urParts,
    required this.batchMemos,
    required this.batchMessageCount,
    required this.batchTotalCount,
    this.qrError,
    this.scanError,
    this.canSkipRemainingBundles = false,
    this.onScan,
    this.onSkipRemainingBundles,
  });

  final int bundleIndex;
  final List<String> urParts;
  final List<VotingKeystoneBatchMemo> batchMemos;
  final int batchMessageCount;
  final int batchTotalCount;
  final String? qrError;
  final String? scanError;
  final bool canSkipRemainingBundles;
  final VoidCallback? onScan;
  final VoidCallback? onSkipRemainingBundles;

  @override
  State<VotingKeystoneSigningPanel> createState() =>
      _VotingKeystoneSigningPanelState();
}

class _VotingKeystoneSigningPanelState
    extends State<VotingKeystoneSigningPanel> {
  static const _transitionCueDuration = Duration(milliseconds: 1300);

  bool _showTransitionCue = false;
  int _memoIndex = 0;
  int _cueGeneration = 0;
  Timer? _cueTimer;

  @override
  void didUpdateWidget(covariant VotingKeystoneSigningPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bundleIndex != widget.bundleIndex) {
      _memoIndex = 0;
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
    final urParts = widget.urParts;
    final batchMemos = [
      for (final memo in widget.batchMemos)
        if (memo.displayMemo.trim().isNotEmpty) memo,
    ];
    final qrError = widget.qrError;
    final scanError = widget.scanError;
    final canSkipRemainingBundles = widget.canSkipRemainingBundles;
    final onSkipRemainingBundles = widget.onSkipRemainingBundles;
    final onScan = widget.onScan;
    final memoIndex = _memoIndex < batchMemos.length ? _memoIndex : 0;
    final selectedMemo = batchMemos.isEmpty ? null : batchMemos[memoIndex];
    final qrPhase = qrError != null
        ? KeystonePcztQrStagePhase.failed
        : urParts.isEmpty
        ? KeystonePcztQrStagePhase.preparing
        : KeystonePcztQrStagePhase.ready;
    final batchMessageCount = widget.batchMessageCount;
    final signingLabel = batchMessageCount <= 0
        ? 'Preparing voting signatures'
        : batchMessageCount == 1
        ? 'Sign 1 voting bundle'
        : 'Sign $batchMessageCount voting bundles';

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
                          'batch-${widget.bundleIndex}-$batchMessageCount',
                        ),
                        children: [
                          Text(
                            signingLabel,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMediumStrong.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                          if (batchMessageCount > 0) ...[
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              widget.batchTotalCount > batchMessageCount
                                  ? 'This QR signs $batchMessageCount of ${widget.batchTotalCount} remaining bundles'
                                  : 'One Keystone approval',
                              textAlign: TextAlign.center,
                              style: AppTypography.bodySmall.copyWith(
                                color: colors.text.secondary,
                              ),
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
            if (_showTransitionCue) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'The next signing batch is ready',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
            if (selectedMemo != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _KeystoneSigningMemo(
                key: ValueKey<int>(selectedMemo.bundleIndex),
                label:
                    'Bundle ${selectedMemo.bundleIndex + 1} of ${selectedMemo.bundleCount} memo',
                displayMemo: selectedMemo.displayMemo,
                showNavigation: batchMemos.length > 1,
                onPrevious: memoIndex > 0
                    ? () => setState(() {
                        _memoIndex = memoIndex - 1;
                      })
                    : null,
                onNext: memoIndex + 1 < batchMemos.length
                    ? () => setState(() {
                        _memoIndex = memoIndex + 1;
                      })
                    : null,
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            KeystoneScanHelpOverlay(
              visible:
                  qrPhase == KeystonePcztQrStagePhase.ready &&
                  urParts.isNotEmpty,
              child: KeystonePcztQrStage(
                phase: qrPhase,
                urParts: urParts,
                error: qrError,
              ),
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

class _KeystoneSigningMemo extends StatelessWidget {
  const _KeystoneSigningMemo({
    required this.label,
    required this.displayMemo,
    required this.showNavigation,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final String label;
  final String displayMemo;
  final bool showNavigation;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface.input.primary,
          border: Border.all(color: colors.border.subtle),
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.labelSmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                  if (showNavigation) ...[
                    _KeystoneMemoNavigationButton(
                      key: const ValueKey('keystone_memo_previous'),
                      tooltip: 'Previous bundle memo',
                      iconName: AppIcons.chevronBackward,
                      onPressed: onPrevious,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    _KeystoneMemoNavigationButton(
                      key: const ValueKey('keystone_memo_next'),
                      tooltip: 'Next bundle memo',
                      iconName: AppIcons.chevronForward,
                      onPressed: onNext,
                    ),
                  ],
                ],
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

class _KeystoneMemoNavigationButton extends StatelessWidget {
  const _KeystoneMemoNavigationButton({
    required this.tooltip,
    required this.iconName,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final String iconName;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      color: colors.button.ghost.label,
      disabledColor: colors.icon.disabled,
      icon: AppIcon(iconName, size: 16),
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
