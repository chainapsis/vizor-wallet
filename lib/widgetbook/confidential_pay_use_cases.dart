part of 'pay_use_cases.dart';

// Deterministic, local-only prototype. No provider, storage, timer or wallet calls.
enum _ConfidentialPayStage { amount, recipient, review, status }

Widget buildConfidentialPayAmountUseCase(BuildContext context) =>
    const _ConfidentialPayPreview();

Widget buildConfidentialPayAmountOnUseCase(BuildContext context) =>
    const _ConfidentialPayPreview(confidential: true);

Widget buildConfidentialPayLiquidityUseCase(BuildContext context) =>
    const _ConfidentialPayPreview(
      stage: _ConfidentialPayStage.recipient,
      failure: SwapQuoteFeedbackKind.liquidityUnavailable,
    );

Widget buildConfidentialPayReviewUseCase(BuildContext context) =>
    const _ConfidentialPayPreview(
      confidential: true,
      stage: _ConfidentialPayStage.review,
    );

Widget buildConfidentialPayInProgressUseCase(BuildContext context) =>
    const _ConfidentialPayPreview(
      confidential: true,
      stage: _ConfidentialPayStage.status,
    );

Widget buildConfidentialPayCompletedUseCase(BuildContext context) =>
    const _ConfidentialPayPreview(
      confidential: true,
      stage: _ConfidentialPayStage.status,
      completed: true,
    );

class _ConfidentialPayPreview extends StatefulWidget {
  const _ConfidentialPayPreview({
    this.confidential = false,
    this.failure,
    this.stage = _ConfidentialPayStage.amount,
    this.completed = false,
  });

  final bool confidential;
  final SwapQuoteFeedbackKind? failure;
  final _ConfidentialPayStage stage;
  final bool completed;

  @override
  State<_ConfidentialPayPreview> createState() =>
      _ConfidentialPayPreviewState();
}

class _ConfidentialPayPreviewState extends State<_ConfidentialPayPreview> {
  late bool _confidential = widget.confidential;
  bool _settingsOpen = false;
  final _confidentialReveal = SwapConfidentialRevealCounter();
  int _slippageBps = 200;
  late SwapQuoteFeedbackKind? _failure = widget.failure;
  late _ConfidentialPayStage _stage = widget.stage;
  SwapStatusTab _statusTab = SwapStatusTab.progress;
  final _amountController = TextEditingController(text: '990');
  final _recipientController = TextEditingController(
    text: _newRecipientAddress,
  );
  final _amountFocus = FocusNode(
    debugLabel: 'Confidential pay amount',
    canRequestFocus: false,
  );

  @override
  void dispose() {
    _amountController.dispose();
    _recipientController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  bool get _mobile => kAppFormFactor == AppFormFactor.mobile;

  // Confidential quotes carried an extra 0.2% fee in the 1Click probes.
  String get _estimatedZec => _confidential ? '2.256' : '2.251';

  SwapState get _amountState => SwapState(
    direction: SwapDirection.zecToExternal,
    quoteMode: SwapQuoteMode.exactOutput,
    amountText: _estimatedZec,
    receiveAmountText: '990',
    receiveFiatText: '990.00',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: const [],
    payMode: true,
    slippageBps: _slippageBps,
    confidential: _confidential,
  );

  SwapQuote get _quote => SwapQuote(
    direction: SwapDirection.zecToExternal,
    sellAsset: SwapAsset.zec,
    receiveAsset: SwapAsset.usdc,
    externalAsset: SwapAsset.usdc,
    mode: SwapQuoteMode.exactOutput,
    sellAmount: double.parse(_estimatedZec),
    receiveAmount: 990,
    minimumReceiveAmount: 990,
    providerLabel: 'NEAR Intents',
    feeLabel: 'Included in shown rate',
    expiryLabel: '1:30',
    sellAmountTextOverride: '$_estimatedZec ZEC',
    receiveEstimateTextOverride: '990 USDC',
    minimumReceiveTextOverride: '990 USDC',
    depositInstruction: const SwapDepositInstruction(
      asset: SwapAsset.zec,
      address: 'widgetbook-zec-deposit',
      expiresInLabel: '1:30',
      reuseWarning: 'Do not reuse this address',
    ),
  );

  Widget? _route({required bool review}) => _confidential
      ? SwapConfidentialRouteConnector.pay(
          review: review,
          flowing: !review && !widget.completed,
        )
      : null;

  /// Requesting the quote happens on the recipient step, so its failure and
  /// recovery live there too.
  void _selectRecipient() {
    final failure = _failure;
    setState(() {
      if (failure != null && failure.offersConfidential(_confidential)) {
        _confidential = true;
      }
      _failure = null;
      _stage = _ConfidentialPayStage.review;
    });
  }

  void _openSettings() => setState(() => _settingsOpen = true);

  void _closeSettings() => setState(() {
    _settingsOpen = false;
    _confidentialReveal.settingsClosed(confidential: _confidential);
  });

  /// Confidential applies as it is switched, as in the app.
  void _setConfidential(bool value) => setState(() {
    if (value && !_confidential) {
      _confidentialReveal.turnedOn(settingsOpen: _settingsOpen);
    }
    _confidential = value;
  });

  void _saveSlippage(int bps) {
    setState(() => _slippageBps = bps);
    _closeSettings();
  }

  /// Pay's heading settings button; the mark shows while confidential is on.
  Widget _settingsButton() => GestureDetector(
    key: const ValueKey('pay_slippage_button'),
    behavior: HitTestBehavior.opaque,
    onTap: _openSettings,
    child: SizedBox(
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_confidential) ...[
            SwapConfidentialIcon(reveal: _confidentialReveal.value),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Text(
            formatSwapSlippage(_slippageBps),
            style: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w400,
              color: context.colors.text.secondary,
            ),
          ),
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(AppIcons.cog, size: 16, color: context.colors.icon.muted),
        ],
      ),
    ),
  );

  String? get _quoteStatus => _failure?.status(_confidential);

  String? get _selectLabel => _failure?.recoveryLabel(_confidential);

  @override
  Widget build(BuildContext context) {
    final content = _mobile ? _mobileContent(context) : _desktopContent();
    final page = Stack(
      children: [
        Positioned.fill(
          child: ExcludeFocus(
            excluding: _settingsOpen,
            child: ExcludeSemantics(
              excluding: _settingsOpen,
              child: IgnorePointer(ignoring: _settingsOpen, child: content),
            ),
          ),
        ),
        if (_settingsOpen)
          AppPaneModalOverlay(
            borderRadius: null,
            onDismiss: _closeSettings,
            alignment: _mobile ? Alignment.bottomCenter : Alignment.center,
            child: _mobile
                ? MobileModalCard(
                    child: MobileSwapSlippageStepperModal(
                      slippageBps: _slippageBps,
                      confidential: _confidential,
                      paymentMode: true,
                      onConfidentialChanged: _setConfidential,
                      onSubmitted: _saveSlippage,
                      onCancel: _closeSettings,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: SwapSlippageModal(
                      slippageBps: _slippageBps,
                      confidential: _confidential,
                      paymentMode: true,
                      onConfidentialChanged: _setConfidential,
                      onSubmitted: _saveSlippage,
                      onCancel: _closeSettings,
                    ),
                  ),
          ),
      ],
    );
    return _mobile
        ? ColoredBox(color: context.colors.background.window, child: page)
        : _PayDesktopFrame(child: page);
  }

  Widget _desktopContent() => switch (_stage) {
    _ConfidentialPayStage.amount => PayWizardPage(
      title: 'Pay in USDC',
      currentIndex: 0,
      backLabel: 'Home',
      onBack: () {},
      headingTrailing: _settingsButton(),
      actions: PayAmountAction(
        state: _amountState,
        onContinue: () =>
            setState(() => _stage = _ConfidentialPayStage.recipient),
      ),
      child: PayAmountStep(
        state: _amountState,
        controller: _amountController,
        focusNode: _amountFocus,
        onAmountChanged: (_) {},
        onFiatAmountChanged: (_) {},
        onToggleFiatInputMode: () {},
        onOpenAssetSelector: () {},
      ),
    ),
    _ConfidentialPayStage.recipient => PayWizardPage(
      title: 'Select Recipient',
      currentIndex: 1,
      backLabel: 'Amount',
      onBack: () => setState(() => _stage = _ConfidentialPayStage.amount),
      onStepSelected: (_) {},
      actions: PayRecipientActions(
        typedAddress: _newRecipientAddress,
        addressError: null,
        contacts: _previewContacts,
        busy: false,
        quoteError: _quoteStatus,
        selectLabel: _selectLabel,
        onSelectRecipient: _selectRecipient,
        onAddToContacts: () {},
      ),
      child: PayRecipientStep(
        controller: _recipientController,
        typedAddress: _newRecipientAddress,
        addressError: null,
        contacts: _previewContacts,
        recents: _previewRecents,
        busy: false,
        onAddressChanged: (_) {},
        onOpenScanner: () {},
        onChooseRecipient: (_) {},
      ),
    ),
    _ConfidentialPayStage.review => PayWizardPage(
      title: 'Review Payment',
      currentIndex: 2,
      backLabel: 'Recipient',
      onBack: () => setState(() => _stage = _ConfidentialPayStage.recipient),
      onStepSelected: (_) {},
      actions: PayReviewAction(
        expired: false,
        starting: false,
        startBlockedReason: null,
        onConfirm: () => setState(() => _stage = _ConfidentialPayStage.status),
        onReviewAgain: () {},
      ),
      child: PayReviewStep(
        quote: _quote,
        recipientAddress: _newRecipientAddress,
        recipientContact: null,
        payingFiatText: r'$990.10',
        convertedFiatText: r'$990.10',
        expiresInText: '1:30',
        expired: false,
        starting: false,
        startBlockedReason: null,
        startError: null,
        onShowFullAddress: () {},
        onConfirm: () {},
        onReviewAgain: () {},
        flowConnector: _route(review: true),
      ),
    ),
    _ConfidentialPayStage.status => AppPaneScrollScaffold(
      toolbar: AppPaneToolbar(
        leading: AppBackLink(label: 'Activity', minWidth: 60, onTap: () {}),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: PayActivityStatusContent(
          status: PayActivityStatusPresentation(
            phase: widget.completed
                ? PayActivityStatusPhase.completed
                : PayActivityStatusPhase.inProgress,
            timestampText: '25 May, 13:30',
            txIdText: '0123123124512512',
            txIdCopyText: '0123123124512512',
            convertedFromText: '$_estimatedZec ZEC',
            transactionFeeText: '0.012 ZEC',
          ),
          amountAsset: SwapAsset.usdc,
          amountText: '990 USDC',
          amountFiatText: r'$990.12',
          recipientAddress: _newRecipientAddress,
          onShowFullAddress: () {},
          flowConnector: _route(review: false),
        ),
      ),
    ),
  };

  Widget _mobileContent(BuildContext context) => Scaffold(
    backgroundColor: context.colors.background.window,
    body: SafeArea(
      child: switch (_stage) {
        _ConfidentialPayStage.amount => Column(
          children: [
            const SizedBox(height: AppSpacing.s),
            MobileTopNav.back(title: 'Pay in USDC', onBack: () {}),
            Expanded(
              child: MobilePayAmountStep(
                state: _amountState,
                controller: _amountController,
                focusNode: _amountFocus,
                zecAvailableZatoshi: BigInt.from(12800000000),
                onAmountChanged: (_) {},
                onFiatAmountChanged: (_) {},
                onToggleFiatInputMode: () {},
                onOpenAssetSelector: () {},
                slippageLabel: formatSwapSlippage(_slippageBps),
                confidentialReveal: _confidentialReveal.value,
                onOpenSlippage: _openSettings,
                onContinue: () =>
                    setState(() => _stage = _ConfidentialPayStage.recipient),
              ),
            ),
          ],
        ),
        _ConfidentialPayStage.recipient => Column(
          children: [
            MobileTopNav.back(
              title: 'Select Recipient',
              onBack: () =>
                  setState(() => _stage = _ConfidentialPayStage.amount),
            ),
            Expanded(
              child: MobilePayRecipientStep(
                controller: _recipientController,
                typedAddress: _newRecipientAddress,
                addressError: null,
                quoteError: _quoteStatus,
                selectLabel: _selectLabel,
                contacts: _previewContacts,
                recents: const [],
                busy: false,
                externalAsset: SwapAsset.usdc,
                onAddressChanged: (_) {},
                onOpenScanner: () {},
                onChooseRecipient: (_) {},
                onSelectRecipient: _selectRecipient,
                onAddToContacts: () {},
              ),
            ),
          ],
        ),
        _ConfidentialPayStage.review => Column(
          children: [
            MobileTopNav.back(
              title: 'Review Payment',
              onBack: () =>
                  setState(() => _stage = _ConfidentialPayStage.recipient),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.s,
                  AppSpacing.sm,
                  AppSpacing.s,
                ),
                child: MobilePayReviewContent(
                  quote: _quote,
                  recipientAddress: _newRecipientAddress,
                  recipientContact: null,
                  payingFiatText: r'$990.10',
                  convertedFiatText: r'$990.10',
                  expiresInText: '1:30',
                  expired: false,
                  flowConnector: _route(review: true),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.s,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: MobilePayReviewActions(
                expired: false,
                starting: false,
                startBlockedReason: null,
                onConfirm: () =>
                    setState(() => _stage = _ConfidentialPayStage.status),
                onRefreshQuote: () {},
                onCancel: () {},
              ),
            ),
          ],
        ),
        _ConfidentialPayStage.status => _mobileStatus(),
      },
    ),
  );

  Widget _mobileStatus() {
    final presentation = _confidentialPayPresentation(
      completed: widget.completed,
      sellAmount: '$_estimatedZec ZEC',
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: MobileSwapStatusContent(
        presentation: presentation,
        paymentHeader: MobilePayStatusHeader(
          asset: SwapAsset.usdc,
          amountText: '990 USDC',
          fiatText: r'$990.12',
          label: widget.completed ? 'You paid' : "You're paying",
          recipientAddress: _newRecipientAddress,
          flowConnector: _route(review: false),
        ),
        payHeaderRow: MobileSwapReviewHeaderRow(
          label: presentation.payLabel,
          amountText: presentation.payAmountText,
          asset: presentation.payAsset,
        ),
        receiveHeaderRow: MobileSwapReviewHeaderRow(
          label: presentation.receiveLabel,
          amountText: presentation.receiveAmountText,
          asset: presentation.receiveAsset,
        ),
        activeTab: _statusTab,
        detailsExpanded: true,
        onTabChanged: (tab) => setState(() => _statusTab = tab),
        onToggleDetails: () {},
      ),
    );
  }
}

SwapActivityStatusPresentation _confidentialPayPresentation({
  required bool completed,
  required String sellAmount,
}) {
  final rawIntent = SwapIntent(
    id: 'widgetbook-confidential-pay',
    pair: 'ZEC -> USDC',
    sellAmount: sellAmount,
    receiveEstimate: '990 USDC',
    provider: 'NEAR Intents',
    status: completed ? SwapIntentStatus.complete : SwapIntentStatus.processing,
    nextAction: completed ? 'Payment complete' : 'Payment in progress',
    providerStatusRaw: completed ? 'SUCCESS' : 'PROCESSING',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: '0123123124512512',
    oneClickRecipient: _newRecipientAddress,
    fiatValueBasis: SwapFiatValueBasis(
      sellUsdUnitPrice: 990.12 / 2.256,
      receiveUsdUnitPrice: 990.12 / 990,
      capturedAt: DateTime.utc(2026, 5, 25, 13, 30),
    ),
    payMode: true,
    confidential: true,
    createdAt: DateTime.utc(2026, 5, 25, 13, 30),
    completedAt: completed ? DateTime.utc(2026, 5, 25, 13, 32) : null,
  );
  final intent = swapIntentsFromRecords([
    SwapIntentRecord.fromIntent(rawIntent),
  ]).single;
  final state = SwapState(
    direction: SwapDirection.zecToExternal,
    quoteMode: SwapQuoteMode.exactOutput,
    amountText: '',
    receiveAmountText: '',
    receiveFiatText: '',
    destinationText: '',
    externalAsset: SwapAsset.usdc,
    reviewVisible: false,
    intents: [intent],
    payMode: true,
  );
  return swapActivityStatusPresentationForIntent(state, intent);
}
