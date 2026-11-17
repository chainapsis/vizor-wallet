part of 'swap_use_cases.dart';

// Deterministic, local-only prototype. No provider, storage, timer or wallet calls.
enum _ConfidentialPreviewStage { composer, review, pending, complete }

Widget buildConfidentialSwapSettingsUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(settingsOpen: true);

Widget buildConfidentialSwapSettingsOnUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(settingsOpen: true, confidential: true);

/// Isolated settings content for narrow-width and text-scaling checks.
Widget buildConfidentialSwapSettingsContentUseCase(BuildContext context) =>
    Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Center(
        child: _ConfidentialSettingsPreview(
          slippageBps: 50,
          confidential: false,
          onSave: (_, _) {},
          onCancel: () {},
        ),
      ),
    );

Widget buildConfidentialSwapLiquidityUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(
      failure: SwapQuoteFeedbackKind.liquidityUnavailable,
    );

Widget buildConfidentialSwapNoLiquidityUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(
      confidential: true,
      failure: SwapQuoteFeedbackKind.liquidityUnavailable,
    );

Widget buildConfidentialSwapMinimumUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(failure: SwapQuoteFeedbackKind.amountTooLow);

Widget buildConfidentialSwapNetworkUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(
      failure: SwapQuoteFeedbackKind.networkUnavailable,
    );

Widget buildConfidentialSwapUnknownUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(
      failure: SwapQuoteFeedbackKind.quoteUnavailable,
    );

Widget buildConfidentialSwapDeniedUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(
      confidential: true,
      failure: SwapQuoteFeedbackKind.confidentialUnavailable,
    );

Widget buildConfidentialSwapStandardUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview();

Widget buildConfidentialSwapReadyUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(confidential: true);

Widget buildConfidentialSwapLoadingUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(confidential: true, loading: true);

Widget buildConfidentialSwapReviewUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(
      confidential: true,
      stage: _ConfidentialPreviewStage.review,
    );

Widget buildConfidentialSwapStandardReviewUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(stage: _ConfidentialPreviewStage.review);

Widget buildConfidentialSwapStatusUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(
      confidential: true,
      stage: _ConfidentialPreviewStage.pending,
    );

Widget buildConfidentialSwapCompletedUseCase(BuildContext context) =>
    const _ConfidentialSwapPreview(
      confidential: true,
      stage: _ConfidentialPreviewStage.complete,
    );

class _ConfidentialSwapPreview extends StatefulWidget {
  const _ConfidentialSwapPreview({
    this.settingsOpen = false,
    this.confidential = false,
    this.failure,
    this.loading = false,
    this.stage = _ConfidentialPreviewStage.composer,
  });

  final bool settingsOpen;
  final bool confidential;
  final SwapQuoteFeedbackKind? failure;
  final bool loading;
  final _ConfidentialPreviewStage stage;

  @override
  State<_ConfidentialSwapPreview> createState() =>
      _ConfidentialSwapPreviewState();
}

class _ConfidentialSwapPreviewState extends State<_ConfidentialSwapPreview> {
  late bool _settingsOpen = widget.settingsOpen;
  late bool _confidential = widget.confidential;
  final _confidentialReveal = SwapConfidentialRevealCounter();
  late bool _recordedMode = widget.confidential;
  late SwapQuoteFeedbackKind? _failure = widget.failure;
  late _ConfidentialPreviewStage _stage = widget.stage;
  int _slippageBps = 50;
  SwapStatusTab _statusTab = SwapStatusTab.progress;
  late SwapState _composer = _figmaNode5State.copyWith(
    externalAsset: SwapAsset.usdc,
    supportedExternalAssets: const [SwapAsset.usdc],
    indicativeExternalPerZec: {
      SwapAsset.usdc: widget.confidential ? 1120 : 1125,
    },
    amountText: '0.1',
    receiveAmountText: widget.failure != null || widget.loading
        ? ''
        : widget.confidential
        ? '112.00'
        : '112.50',
    destinationText: '0xrecipient',
    clearQuoteError: true,
    quoteLoading: widget.loading,
    confidential: widget.confidential,
  );
  final _settingsFocus = FocusNode(debugLabel: 'Confidential preview settings');
  final _amountFocus = FocusNode(debugLabel: 'Confidential preview amount');
  final _modalFocus = FocusScopeNode(
    debugLabel: 'Confidential preview modal',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );

  @override
  void dispose() {
    _settingsFocus.dispose();
    _amountFocus.dispose();
    _modalFocus.dispose();
    super.dispose();
  }

  void _closeSettings() {
    setState(() {
      _settingsOpen = false;
      _confidentialReveal.settingsClosed(confidential: _confidential);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _settingsFocus.requestFocus();
    });
  }

  double get _rate => _confidential ? 1120 : 1125;

  void _setMode(bool value) => setState(() {
    if (value && !_confidential) {
      _confidentialReveal.turnedOn(settingsOpen: _settingsOpen);
    }
    _confidential = value;
    _failure = null;
    _composer = _composer.copyWith(
      confidential: value,
      indicativeExternalPerZec: {SwapAsset.usdc: _rate},
      receiveAmountText: ((double.tryParse(_composer.amountText) ?? 0) * _rate)
          .toStringAsFixed(2),
    );
  });

  void _recover() {
    if (_failure!.offersConfidential(_confidential)) {
      _setMode(true);
    } else {
      final editAmount = _failure == SwapQuoteFeedbackKind.amountTooLow;
      _setMode(_confidential);
      if (editAmount) _amountFocus.requestFocus();
    }
  }

  void _review() => setState(() {
    _recordedMode = _confidential;
    _stage = _ConfidentialPreviewStage.review;
  });

  SwapQuote get _quote => SwapQuote.estimate(
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    sellAmount: double.tryParse(_composer.amountText) ?? 0.1,
    externalPerZec: _recordedMode ? 1120 : 1125,
    slippageBps: _slippageBps,
  );

  SwapAddressPlan get _addressPlan => _figmaZecToExternalAddressPlan;

  Widget _button(String label, VoidCallback? onPressed, {Key? key}) =>
      Semantics(
        button: true,
        child: AppButton(
          key: key,
          onPressed: onPressed,
          variant: AppButtonVariant.primary,
          expand: true,
          constrainContent: true,
          growWithContent: true,
          height: 44,
          child: Text(label, textAlign: TextAlign.center),
        ),
      );

  Widget _composerContent(BuildContext context) {
    final mobile = kAppFormFactor == AppFormFactor.mobile;
    final failure = _failure;
    final status = failure == null
        ? null
        : SwapQuoteUnavailableStatus(message: failure.status(_confidential));
    final placeholder = failure != null || widget.loading ? '—' : null;
    final meta = failure != null
        ? ''
        : widget.loading
        ? '—'
        : null;
    void amount(String value) => setState(() {
      _composer = _composer.copyWith(
        amountText: value,
        receiveAmountText: ((double.tryParse(value) ?? 0) * _rate)
            .toStringAsFixed(2),
      );
      _failure = null;
    });
    void receive(String value) => setState(() {
      _composer = _composer.copyWith(
        receiveAmountText: value,
        amountText: ((double.tryParse(value) ?? 0) / _rate).toStringAsFixed(8),
      );
      _failure = null;
    });
    final label = widget.loading
        ? 'Getting quote'
        : failure?.recoveryLabel(_confidential) ??
              (mobile ? 'Continue to review' : 'Review swap');
    final action = Semantics(
      button: true,
      child: AppButton(
        key: ValueKey(
          failure == null
              ? 'confidential_preview_review'
              : 'swap_quote_recovery',
        ),
        expand: true,
        constrainContent: true,
        // Mobile matches _MobileSwapReviewButton: one line, scaled down
        // beside the slippage button on the narrowest phones.
        contentPadding: mobile
            ? const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              )
            : null,
        onPressed: widget.loading
            ? null
            : failure == null
            ? _review
            : _recover,
        child: mobile
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, maxLines: 1, textAlign: TextAlign.center),
              )
            : Text(label, textAlign: TextAlign.center),
      ),
    );
    if (mobile) {
      // Mirrors MobileSwapScreen: real top nav, ticket, shared action row,
      // and 96px clearance above the floating tab bar.
      return AppMobileShell(
        tabBar: AppMobileTabBar(
          items: const [
            AppMobileTabItem(iconName: AppIcons.home, label: 'Home'),
            AppMobileTabItem(iconName: AppIcons.swapArrows, label: 'Swap'),
            AppMobileTabItem(iconName: AppIcons.history, label: 'Activity'),
            AppMobileTabItem(iconName: AppIcons.cog, label: 'Settings'),
          ],
          currentIndex: 1,
          onSelect: (_) {},
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              MobileTopNav.back(
                title: 'Swap',
                onBack: () {},
                trailing: const SwapNearIntentsAttribution(alignEnd: true),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('confidential_composer_scroll'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    0,
                    AppSpacing.sm,
                    96,
                  ),
                  child: Column(
                    children: [
                      MobileSwapComposerTicket(
                        confidentialReveal: _confidentialReveal.value,
                        state: _composer,
                        amountFocusNode: _amountFocus,
                        receiveAmountPlaceholder: placeholder,
                        receiveAmountMetaText: meta,
                        onAmountChanged: amount,
                        onAmountFiatChanged: amount,
                        onReceiveAmountChanged: receive,
                        onReceiveAmountFiatChanged: receive,
                        onToggleFiatInputMode: (_) {},
                        onToggleDirection: () {},
                        onOpenExternalAssetPicker: () {},
                        onOpenDestinationAddress: () {},
                        onUseMaxZecAmount: () => amount('1'),
                        zecAvailableText: '1 ZEC',
                      ),
                      if (status == null)
                        const SizedBox(height: AppSpacing.md)
                      else ...[
                        const SizedBox(height: AppSpacing.s),
                        status,
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      Row(
                        children: [
                          _settingsButton(mobile: true),
                          const SizedBox(width: AppSpacing.s),
                          Expanded(child: action),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final panel = SwapComposerPanel(
      confidentialReveal: _confidentialReveal.value,
      state: _composer,
      amountFocusNode: _amountFocus,
      // No rate without a quote; '--' is the app's unknown-value idiom.
      rateText: failure == null ? null : '1 ZEC = -- USDC',
      receiveAmountPlaceholder: placeholder,
      receiveAmountMetaText: meta,
      onAmountChanged: amount,
      onAmountFiatChanged: amount,
      onReceiveAmountChanged: receive,
      onReceiveAmountFiatChanged: receive,
      onToggleFiatInputMode: (_) {},
      onToggleDirection: () {},
      onOpenExternalAssetPicker: () {},
      onOpenDestinationAddress: () {},
      onOpenSlippageSettings: () => setState(() => _settingsOpen = true),
      onUseMaxZecAmount: () => amount('1'),
      assetSelectorOpen: false,
      slippageSettingsOpen: _settingsOpen,
      zecAvailableText: '1 ZEC',
      zecAvailableZatoshi: BigInt.from(100000000),
      settingsControl: _settingsButton(),
    );
    // Match SwapScreen's toolbar, 420px content, 624px pinning threshold,
    // centered heading, attribution before the 232px review action.
    return AppPaneScrollScaffold(
      toolbar: const AppPaneToolbar(
        backLinkMinWidth: 60,
        leading: SizedBox.shrink(),
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pinned = constraints.minHeight >= 624;
          final column = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SwapPreviewPageTitle(),
              const SizedBox(height: AppSpacing.md),
              if (pinned) Expanded(child: Center(child: panel)) else panel,
              // SwapScreen's 24 + attribution + 24 band. A failure keeps the
              // band's height and lifts the attribution so the status sits
              // directly above the CTA; neither the ticket nor the CTA moves.
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.md * 2 + 32,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const SizedBox(
                      height: 32,
                      child: Center(
                        child: SwapNearIntentsAttribution(centered: true),
                      ),
                    ),
                    if (status == null)
                      const SizedBox(height: AppSpacing.md)
                    else ...[
                      const SizedBox(height: AppSpacing.s),
                      status,
                      const SizedBox(height: AppSpacing.xs),
                    ],
                  ],
                ),
              ),
              Center(child: SizedBox(width: 232, child: action)),
            ],
          );
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
                child: pinned
                    ? SizedBox(height: constraints.minHeight, child: column)
                    : column,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _settingsButton({bool mobile = false}) {
    final colors = context.colors;
    final alpha = widget.loading ? 0.45 : 1.0;
    final mark = _confidential
        ? SwapConfidentialIcon(alpha: alpha, reveal: _confidentialReveal.value)
        : null;
    return Semantics(
      label:
          'Slippage settings, ${formatSwapSlippage(_slippageBps)}'
          '${_confidential ? ', confidential' : ''}',
      button: true,
      enabled: !widget.loading,
      onTap: widget.loading ? null : () => setState(() => _settingsOpen = true),
      excludeSemantics: true,
      child: AppButton(
        key: const ValueKey('confidential_preview_settings'),
        focusNode: _settingsFocus,
        onPressed: widget.loading
            ? null
            : () => setState(() => _settingsOpen = true),
        variant: mobile ? AppButtonVariant.secondary : AppButtonVariant.ghost,
        // Desktop matches SwapComposerPanel's _SlippageControl metrics.
        size: mobile ? AppButtonSize.large : AppButtonSize.small,
        height: mobile ? null : 24,
        contentPadding: mobile ? null : const EdgeInsets.fromLTRB(8, 0, 4, 0),
        enabledBackgroundColor: !mobile && _settingsOpen
            ? colors.state.selectedOpacity
            : null,
        leading: mobile ? mark : null,
        trailing: mobile ? const AppIcon(AppIcons.cog) : null,
        child: mobile
            ? Text(formatSwapSlippage(_slippageBps))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mark != null) ...[
                    mark,
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                  Text(
                    formatSwapSlippage(_slippageBps),
                    style: AppTypography.labelLarge.copyWith(
                      fontWeight: FontWeight.w400,
                      color: colors.text.secondary.withValues(alpha: alpha),
                    ),
                  ),
                  const SizedBox(width: 2),
                  AppIcon(
                    AppIcons.cog,
                    size: 16,
                    color: colors.icon.muted.withValues(alpha: alpha),
                  ),
                ],
              ),
      ),
    );
  }

  // The recorded mode marks the flow itself instead of adding a detail row.
  Widget? get _route => _recordedMode
      ? SwapConfidentialRouteConnector.swap(
          flowing: _stage == _ConfidentialPreviewStage.pending,
        )
      : null;

  Widget _reviewContent(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (kAppFormFactor == AppFormFactor.mobile)
        MobileSwapReviewContent(
          quote: _quote,
          addressPlan: _addressPlan,
          accountLabel: 'Main wallet',
          accountProfilePictureId: '1',
          expired: false,
          amountWarning: null,
          startError: null,
          flowConnector: _route,
        )
      else
        SwapReviewPageContent(
          quote: _quote,
          addressPlan: _addressPlan,
          expired: false,
          amountWarning: null,
          startError: null,
          flowConnector: _route,
        ),
      const SizedBox(height: AppSpacing.md),
      _button(
        'Confirm & swap',
        () => setState(() {
          _stage = _ConfidentialPreviewStage.pending;
        }),
        key: const ValueKey('confidential_preview_confirm'),
      ),
      const SizedBox(height: AppSpacing.xs),
      Semantics(
        button: true,
        child: AppButton(
          onPressed: () =>
              setState(() => _stage = _ConfidentialPreviewStage.composer),
          variant: AppButtonVariant.ghost,
          growWithContent: true,
          child: const Text('Back to swap'),
        ),
      ),
    ],
  );

  Widget _statusContent(BuildContext context) {
    final complete = _stage == _ConfidentialPreviewStage.complete;
    final quote = _quote;
    const steps = [
      SwapStatusStepData(
        title: 'Awaiting deposit',
        state: SwapStatusStepState.active,
      ),
      SwapStatusStepData(
        title: 'Deposit confirmation',
        state: SwapStatusStepState.pending,
      ),
      SwapStatusStepData(title: 'Swap', state: SwapStatusStepState.pending),
      SwapStatusStepData(
        title: 'Deliver USDC',
        state: SwapStatusStepState.pending,
      ),
    ];
    final title = complete ? 'Swap completed' : 'Awaiting deposit';
    final statusLabel = complete ? 'Completed' : 'Awaiting deposit';
    const details = [
      SwapStatusDetailRowData(
        label: 'Total fees',
        value: 'Included in shown rate',
      ),
    ];
    final flowConnector = _route;
    if (kAppFormFactor == AppFormFactor.mobile) {
      final presentation = SwapActivityStatusPresentation(
        title: title,
        payAsset: SwapAsset.zec,
        receiveAsset: SwapAsset.usdc,
        payFiatText: '',
        receiveFiatText: '',
        payAmountText: quote.sellAmountText,
        receiveAmountText: quote.receiveEstimateText,
        statusLabel: statusLabel,
        badgeKind: complete
            ? SwapStatusBadgeKind.completed
            : SwapStatusBadgeKind.liveQuote,
        progressIndex: 0,
        steps: steps,
        details: details,
        showTabs: !complete,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            presentation.title,
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          MobileSwapStatusContent(
            presentation: presentation,
            payHeaderRow: MobileSwapReviewHeaderRow(
              label: "You're paying",
              amountText: quote.sellAmountText,
              asset: SwapAsset.zec,
            ),
            receiveHeaderRow: MobileSwapReviewHeaderRow(
              label: "You're receiving",
              amountText: quote.receiveEstimateText,
              asset: SwapAsset.usdc,
            ),
            activeTab: _statusTab,
            detailsExpanded: true,
            onTabChanged: (tab) => setState(() => _statusTab = tab),
            onToggleDetails: () {},
            flowConnector: flowConnector,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwapStatusPageContent(
          title: title,
          payAsset: SwapAsset.zec,
          receiveAsset: SwapAsset.usdc,
          payAmountText: quote.sellAmountText,
          receiveAmountText: quote.receiveEstimateText,
          payDetailText: '',
          receiveDetailText: 'To: 0xrecipient on Ethereum',
          statusLabel: statusLabel,
          badgeKind: complete
              ? SwapStatusBadgeKind.completed
              : SwapStatusBadgeKind.liveQuote,
          progressIndex: 0,
          showTabs: !complete,
          activeTab: _statusTab,
          onTabChanged: (tab) => setState(() => _statusTab = tab),
          steps: steps,
          details: details,
          flowConnector: flowConnector,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final content = _stage == _ConfidentialPreviewStage.composer
          ? _composerContent(context)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 396),
                  child: _stage == _ConfidentialPreviewStage.review
                      ? _reviewContent(context)
                      : _statusContent(context),
                ),
              ),
            );
      final blocked = _settingsOpen;
      final page = ColoredBox(
        color: context.colors.background.base,
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeFocus(
                excluding: blocked,
                child: ExcludeSemantics(
                  excluding: blocked,
                  child: IgnorePointer(ignoring: blocked, child: content),
                ),
              ),
            ),
            if (_settingsOpen)
              AppPaneModalOverlay(
                borderRadius: null,
                onDismiss: _closeSettings,
                alignment: kAppFormFactor == AppFormFactor.mobile
                    ? Alignment.bottomCenter
                    : Alignment.center,
                child: Padding(
                  // The mobile sheet card brings its own margins.
                  padding: kAppFormFactor == AppFormFactor.mobile
                      ? EdgeInsets.zero
                      : const EdgeInsets.all(AppSpacing.sm),
                  child: FocusScope(
                    node: _modalFocus,
                    child: _ConfidentialSettingsPreview(
                      slippageBps: _slippageBps,
                      confidential: _confidential,
                      onCancel: _closeSettings,
                      // Update applies slippage and confidential together, as
                      // in the app.
                      onSave: (bps, confidential) {
                        _setMode(confidential);
                        setState(() {
                          _slippageBps = bps;
                          _composer = _composer.copyWith(slippageBps: bps);
                        });
                        _closeSettings();
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
      if (kAppFormFactor == AppFormFactor.desktop &&
          constraints.maxWidth >= 800) {
        return AppDesktopShell(
          sidebar: const _PreviewSwapSidebar(),
          pane: AppDesktopPane(padding: EdgeInsets.zero, child: page),
        );
      }
      return page;
    },
  );
}

class _ConfidentialSettingsPreview extends StatelessWidget {
  const _ConfidentialSettingsPreview({
    required this.slippageBps,
    required this.confidential,
    required this.onSave,
    required this.onCancel,
  });
  final int slippageBps;
  final bool confidential;
  final void Function(int slippageBps, bool confidential) onSave;
  final VoidCallback onCancel;

  /// The app's own settings surface per form factor: the desktop modal, or
  /// the mobile stepper sheet.
  @override
  Widget build(BuildContext context) => kAppFormFactor == AppFormFactor.mobile
      ? MobileModalCard(
          child: MobileSwapSlippageStepperModal(
            slippageBps: slippageBps,
            confidential: confidential,
            onSubmitted: onSave,
            onCancel: onCancel,
          ),
        )
      : SwapSlippageModal(
          slippageBps: slippageBps,
          confidential: confidential,
          onSubmitted: onSave,
          onCancel: onCancel,
        );
}
