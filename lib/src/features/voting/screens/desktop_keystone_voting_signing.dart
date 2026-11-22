part of 'voting_status_screen.dart';

class _DesktopKeystoneVotingSigning extends StatefulWidget {
  const _DesktopKeystoneVotingSigning({
    required this.bundleIndex,
    required this.urParts,
    required this.batchMemos,
    required this.batchMessageCount,
    required this.batchTotalCount,
    required this.canSkipRemainingBundles,
    this.qrError,
    this.scanError,
    this.terminalNotice,
    this.onScan,
    this.onSkipRemainingBundles,
  });

  final int bundleIndex;
  final List<String> urParts;
  final List<VotingKeystoneBatchMemo> batchMemos;
  final int batchMessageCount;
  final int batchTotalCount;
  final bool canSkipRemainingBundles;
  final String? qrError;
  final String? scanError;
  final String? terminalNotice;
  final VoidCallback? onScan;
  final VoidCallback? onSkipRemainingBundles;

  @override
  State<_DesktopKeystoneVotingSigning> createState() =>
      _DesktopKeystoneVotingSigningState();
}

class _DesktopKeystoneVotingSigningState
    extends State<_DesktopKeystoneVotingSigning> {
  late final KeystoneQrPlaybackController _playback;
  final _expandFocus = FocusNode();
  final _closeFocus = FocusNode();
  final _modalFocus = FocusScopeNode(
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );
  bool _expanded = false;
  bool _helpVisible = false;
  int _memoIndex = 0;

  bool get _ready => widget.qrError == null && widget.urParts.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _playback = KeystoneQrPlaybackController(widget.urParts);
  }

  @override
  void didUpdateWidget(covariant _DesktopKeystoneVotingSigning oldWidget) {
    super.didUpdateWidget(oldWidget);
    _playback.updateParts(widget.urParts);
    if (oldWidget.bundleIndex != widget.bundleIndex) _memoIndex = 0;
    if (!_ready) _expanded = false;
    if (widget.terminalNotice != null &&
        oldWidget.terminalNotice != widget.terminalNotice) {
      _expanded = false;
    }
  }

  @override
  void dispose() {
    _playback.dispose();
    _expandFocus.dispose();
    _closeFocus.dispose();
    _modalFocus.dispose();
    super.dispose();
  }

  void _closeExpanded() {
    setState(() => _expanded = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _expandFocus.requestFocus();
    });
  }

  void _scan() {
    if (!_ready || widget.onScan == null) return;
    if (!_expanded) {
      widget.onScan!();
      return;
    }
    // Remove the overlay's Back handler before pushing the scanner route.
    setState(() => _expanded = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _ready) widget.onScan?.call();
    });
  }

  Widget _qr(double size, {required bool enlarged}) => KeystonePcztQrStage(
    key: ValueKey(enlarged ? 'voting_qr_enlarged' : 'voting_qr_normal'),
    phase: widget.qrError != null
        ? KeystonePcztQrStagePhase.failed
        : _ready
        ? KeystonePcztQrStagePhase.ready
        : KeystonePcztQrStagePhase.preparing,
    urParts: widget.urParts,
    error: widget.qrError,
    size: size,
    playback: _playback,
  );

  Widget _scanButton() => AppButton(
    key: const ValueKey('voting_scan_signature'),
    expand: true,
    constrainContent: true,
    growWithContent: true,
    onPressed: _ready && widget.onScan != null ? _scan : null,
    child: Text(context.l10n.votingKeystoneScanSignature),
  );

  Widget _bundleSummary() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.l10n.votingKeystoneSignLabel(
          math.max(0, widget.batchMessageCount),
        ),
        style: AppTypography.bodyMediumStrong.copyWith(
          color: context.colors.text.accent,
        ),
      ),
      if (widget.batchMessageCount > 0) ...[
        const SizedBox(height: AppSpacing.xxs),
        Text(
          widget.batchTotalCount > widget.batchMessageCount
              ? context.l10n.votingKeystoneQrPartial(
                  widget.batchMessageCount,
                  widget.batchTotalCount,
                )
              : context.l10n.votingKeystoneOneApproval,
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ],
    ],
  );

  Widget? _memo() {
    final memos = widget.batchMemos
        .where((memo) => memo.displayMemo.trim().isNotEmpty)
        .toList();
    if (memos.isEmpty) return null;
    final index = _memoIndex.clamp(0, memos.length - 1);
    final memo = memos[index];
    return _KeystoneSigningMemo(
      key: ValueKey('voting_memo_${memo.bundleIndex}'),
      label: context.l10n.votingKeystoneMemoLabel(
        memo.bundleIndex + 1,
        memo.bundleCount,
      ),
      displayMemo: memo.displayMemo,
      showNavigation: memos.length > 1,
      onPrevious: index > 0
          ? () => setState(() => _memoIndex = index - 1)
          : null,
      onNext: index + 1 < memos.length
          ? () => setState(() => _memoIndex = index + 1)
          : null,
    );
  }

  Widget _details() {
    final memo = _memo();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _bundleSummary(),
        if (memo != null) ...[const SizedBox(height: AppSpacing.sm), memo],
        if (widget.terminalNotice case final notice?) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            key: const ValueKey('voting_status_terminal_delegation'),
            notice,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.destructive,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.l10n.votingKeystoneAfterApproval,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        if (widget.scanError != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.scanError!,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.destructive,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        _scanButton(),
        if (widget.canSkipRemainingBundles) ...[
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            key: const ValueKey('voting_use_signed_bundles'),
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.medium,
            onPressed: widget.onSkipRemainingBundles,
            constrainContent: true,
            growWithContent: true,
            child: Text(context.l10n.votingUseSignedBundles),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          key: const ValueKey('voting_scan_help'),
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.medium,
          onPressed: () => setState(() => _helpVisible = !_helpVisible),
          constrainContent: true,
          growWithContent: true,
          child: Text(context.l10n.keystoneScanIssuesTitle),
        ),
        if (_helpVisible) ...[
          const SizedBox(height: AppSpacing.xs),
          const KeystoneScanHelpDetails(),
        ],
      ],
    );
  }

  Widget _footer() => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.xs,
    alignment: WrapAlignment.center,
    children: [
      for (final (index, label) in [
        context.l10n.votingStepSigningKeystone,
        context.l10n.votingStepProving,
        context.l10n.votingStepCasting,
        context.l10n.votingStepFinalizing,
      ].indexed)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              index == 0 ? AppIcons.loader : AppIcons.chevronForward,
              size: 14,
              color: context.colors.icon.regular,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Flexible(
              child: Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: index == 0
                      ? context.colors.text.accent
                      : context.colors.text.secondary,
                ),
              ),
            ),
          ],
        ),
    ],
  );

  Widget _normal(double height, double width) {
    final paddedWidth = math.max(0.0, width - AppSpacing.md * 2);
    final horizontal =
        paddedWidth >= 696 && MediaQuery.textScalerOf(context).scale(14) <= 21;
    final qrSize = math.min(
      400.0,
      math.min(
        horizontal ? paddedWidth - 296 : paddedWidth,
        math.max(200.0, height - 280),
      ),
    );
    final qr = SizedBox(
      width: qrSize,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _qr(qrSize, enlarged: false),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            key: const ValueKey('voting_enlarge_qr'),
            focusNode: _expandFocus,
            constrainContent: true,
            growWithContent: true,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.medium,
            onPressed: _ready
                ? () {
                    setState(() => _expanded = true);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _expanded) _closeFocus.requestFocus();
                    });
                  }
                : null,
            child: Text(context.l10n.votingEnlargeQr),
          ),
        ],
      ),
    );
    return VotingPaneScrollbar(
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.votingKeystoneApproveTitle,
                      style: AppTypography.displaySmall.copyWith(
                        color: context.colors.text.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.l10n.commonScanWithKeystone,
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: horizontal
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            qr,
                            const SizedBox(width: AppSpacing.md),
                            Expanded(child: _details()),
                          ],
                        )
                      : Column(
                          children: [
                            qr,
                            const SizedBox(height: AppSpacing.sm),
                            _details(),
                          ],
                        ),
                ),
                Column(
                  children: [
                    _footer(),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      context.l10n.votingKeepOpenShort,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _enlarged(double height, double width) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final memos = widget.batchMemos
        .where((memo) => memo.displayMemo.trim().isNotEmpty)
        .toList();
    final memo = memos.isEmpty
        ? null
        : memos[_memoIndex.clamp(0, memos.length - 1)];
    // Firmware display_memo ends with the per-bundle amount.
    final memoSummary = memo == null
        ? null
        : [
            context.l10n.votingBundleOf(memo.bundleIndex + 1, memo.bundleCount),
            memo.displayMemo.trim().split('\n').last,
          ].join(' · ');
    final qrSize = math.max(
      120.0,
      math.min(480.0, math.min(width - 112, height - 232 * scale)),
    );
    return AppPaneModalOverlay(
      key: const ValueKey('voting_qr_overlay'),
      onDismiss: _closeExpanded,
      child: BlockSemantics(
        child: FocusScope(
          node: _modalFocus,
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: context.l10n.votingEnlargeQr,
            child: AppModalCard(
              width: math.min(640.0, width - 32),
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.commonScanWithKeystone,
                          style: AppTypography.headlineSmall.copyWith(
                            color: context.colors.text.accent,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: AppButton(
                          key: const ValueKey('voting_close_enlarged_qr'),
                          focusNode: _closeFocus,
                          constrainContent: true,
                          growWithContent: true,
                          size: AppButtonSize.small,
                          variant: AppButtonVariant.ghost,
                          onPressed: _closeExpanded,
                          child: Text(context.l10n.commonClose),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _bundleSummary(),
                  const SizedBox(height: AppSpacing.sm),
                  _qr(qrSize, enlarged: true),
                  if (memoSummary != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      memoSummary,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall.copyWith(
                        color: context.colors.text.secondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    width: math.min(320.0, width - 80),
                    child: _scanButton(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final height = constraints.hasBoundedHeight
          ? constraints.maxHeight
          : 720.0;
      final width = constraints.maxWidth;
      return SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeFocus(
                excluding: _expanded,
                child: ExcludeSemantics(
                  excluding: _expanded,
                  child: _normal(height, width),
                ),
              ),
            ),
            if (_expanded) _enlarged(height, width),
          ],
        ),
      );
    },
  );
}
