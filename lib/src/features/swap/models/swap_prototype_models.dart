import '../domain/swap_contract.dart';
import '../domain/swap_address_plan.dart';

export '../domain/swap_address_plan.dart';
export '../domain/swap_contract.dart';

const defaultSwapSlippageBps = 100;
const swapSlippagePresetBps = <int>[50, 100, 200];
const swapQuoteDifferenceWarningThreshold = 0.05;

enum SwapPrototypeStepState { done, active, pending, warning }

class SwapPrototypeStep {
  const SwapPrototypeStep({
    required this.label,
    required this.state,
    required this.evidence,
  });

  final String label;
  final SwapPrototypeStepState state;
  final String evidence;
}

class SwapPrototypeField {
  const SwapPrototypeField({required this.label, required this.value});

  final String label;
  final String value;
}

enum SwapExternalRequestStatus { needsReview, accepted, rejected, unsupported }

extension SwapExternalRequestStatusLabel on SwapExternalRequestStatus {
  String get label => switch (this) {
    SwapExternalRequestStatus.needsReview => 'Needs review',
    SwapExternalRequestStatus.accepted => 'Accepted',
    SwapExternalRequestStatus.rejected => 'Rejected',
    SwapExternalRequestStatus.unsupported => 'Unsupported',
  };
}

class SwapExternalRequest {
  const SwapExternalRequest({
    required this.id,
    required this.source,
    required this.title,
    required this.requestedAction,
    required this.route,
    required this.receivedAt,
    required this.status,
    required this.riskLabel,
    required this.riskDetail,
    required this.disclosures,
    this.direction,
    this.externalAsset,
    this.amountText,
    this.destinationText,
    this.paymentAddress,
    this.paymentAmountText,
    this.paymentMemoText,
    this.paymentLabel,
    this.paymentMessage,
  });

  final String id;
  final String source;
  final String title;
  final String requestedAction;
  final String route;
  final String receivedAt;
  final SwapExternalRequestStatus status;
  final String riskLabel;
  final String riskDetail;
  final List<SwapPrototypeField> disclosures;
  final SwapDirection? direction;
  final SwapAsset? externalAsset;
  final String? amountText;
  final String? destinationText;
  final String? paymentAddress;
  final String? paymentAmountText;
  final String? paymentMemoText;
  final String? paymentLabel;
  final String? paymentMessage;

  bool get isOpen => status == SwapExternalRequestStatus.needsReview;

  bool get canStageSwap =>
      isOpen &&
      direction != null &&
      externalAsset != null &&
      amountText != null &&
      destinationText != null;

  bool get canOpenPayment =>
      isOpen && paymentAddress != null && paymentAddress!.isNotEmpty;

  SwapExternalRequest copyWith({SwapExternalRequestStatus? status}) {
    return SwapExternalRequest(
      id: id,
      source: source,
      title: title,
      requestedAction: requestedAction,
      route: route,
      receivedAt: receivedAt,
      status: status ?? this.status,
      riskLabel: riskLabel,
      riskDetail: riskDetail,
      disclosures: disclosures,
      direction: direction,
      externalAsset: externalAsset,
      amountText: amountText,
      destinationText: destinationText,
      paymentAddress: paymentAddress,
      paymentAmountText: paymentAmountText,
      paymentMemoText: paymentMemoText,
      paymentLabel: paymentLabel,
      paymentMessage: paymentMessage,
    );
  }
}

class SwapDraftSnapshot {
  const SwapDraftSnapshot({
    required this.direction,
    required this.externalAsset,
    this.slippageBps = defaultSwapSlippageBps,
  });

  final SwapDirection direction;
  final SwapAsset externalAsset;
  final int slippageBps;
}

class SwapPrototypeIntent {
  const SwapPrototypeIntent({
    required this.id,
    required this.title,
    required this.pair,
    required this.sellAmount,
    required this.receiveEstimate,
    required this.provider,
    required this.status,
    required this.nextAction,
    required this.steps,
    required this.exposure,
    required this.receipt,
    this.direction,
    this.externalAsset,
    this.depositAddress,
    this.depositMemo,
    this.depositTxHash,
    this.shieldTxHash,
    this.providerQuoteId,
    this.providerSignature,
    this.providerStatusRaw,
    this.nearIntentHash,
    this.nearTransactionHash,
    this.lastStatusCheckedAt,
    this.statusError,
    this.oneClickRecipient,
    this.oneClickRefundTo,
    this.depositDeadline,
    this.accountUuid,
  });

  final String id;
  final String title;
  final String pair;
  final String sellAmount;
  final String receiveEstimate;
  final String provider;
  final SwapIntentStatus status;
  final String nextAction;
  final List<SwapPrototypeStep> steps;
  final List<SwapPrototypeField> exposure;
  final List<SwapPrototypeField> receipt;
  final SwapDirection? direction;
  final SwapAsset? externalAsset;
  final String? depositAddress;
  final String? depositMemo;
  final String? depositTxHash;
  final String? shieldTxHash;
  final String? providerQuoteId;
  final String? providerSignature;
  final String? providerStatusRaw;
  final String? nearIntentHash;
  final String? nearTransactionHash;
  final DateTime? lastStatusCheckedAt;
  final String? statusError;
  final String? oneClickRecipient;
  final String? oneClickRefundTo;
  final DateTime? depositDeadline;
  final String? accountUuid;

  String get statusLabel => status.label;

  SwapPrototypeIntent copyWith({
    String? id,
    String? title,
    String? pair,
    String? sellAmount,
    String? receiveEstimate,
    String? provider,
    SwapIntentStatus? status,
    String? nextAction,
    List<SwapPrototypeStep>? steps,
    List<SwapPrototypeField>? exposure,
    List<SwapPrototypeField>? receipt,
    SwapDirection? direction,
    SwapAsset? externalAsset,
    String? depositAddress,
    String? depositMemo,
    String? depositTxHash,
    String? shieldTxHash,
    String? providerQuoteId,
    String? providerSignature,
    String? providerStatusRaw,
    String? nearIntentHash,
    String? nearTransactionHash,
    DateTime? lastStatusCheckedAt,
    String? statusError,
    String? oneClickRecipient,
    String? oneClickRefundTo,
    DateTime? depositDeadline,
    String? accountUuid,
    bool clearStatusError = false,
  }) {
    return SwapPrototypeIntent(
      id: id ?? this.id,
      title: title ?? this.title,
      pair: pair ?? this.pair,
      sellAmount: sellAmount ?? this.sellAmount,
      receiveEstimate: receiveEstimate ?? this.receiveEstimate,
      provider: provider ?? this.provider,
      status: status ?? this.status,
      nextAction: nextAction ?? this.nextAction,
      steps: steps ?? this.steps,
      exposure: exposure ?? this.exposure,
      receipt: receipt ?? this.receipt,
      direction: direction ?? this.direction,
      externalAsset: externalAsset ?? this.externalAsset,
      depositAddress: depositAddress ?? this.depositAddress,
      depositMemo: depositMemo ?? this.depositMemo,
      depositTxHash: depositTxHash ?? this.depositTxHash,
      shieldTxHash: shieldTxHash ?? this.shieldTxHash,
      providerQuoteId: providerQuoteId ?? this.providerQuoteId,
      providerSignature: providerSignature ?? this.providerSignature,
      providerStatusRaw: providerStatusRaw ?? this.providerStatusRaw,
      nearIntentHash: nearIntentHash ?? this.nearIntentHash,
      nearTransactionHash: nearTransactionHash ?? this.nearTransactionHash,
      lastStatusCheckedAt: lastStatusCheckedAt ?? this.lastStatusCheckedAt,
      statusError: clearStatusError ? null : statusError ?? this.statusError,
      oneClickRecipient: oneClickRecipient ?? this.oneClickRecipient,
      oneClickRefundTo: oneClickRefundTo ?? this.oneClickRefundTo,
      depositDeadline: depositDeadline ?? this.depositDeadline,
      accountUuid: accountUuid ?? this.accountUuid,
    );
  }
}

class SwapPrototypeState {
  const SwapPrototypeState({
    required this.direction,
    required this.amountText,
    required this.destinationText,
    required this.externalAsset,
    required this.reviewVisible,
    required this.intents,
    required this.externalRequests,
    required this.requestImportText,
    this.slippageBps = defaultSwapSlippageBps,
    this.supportedExternalAssets = swapExternalAssets,
    this.indicativeExternalPerZec = const {},
    this.reviewQuote,
    this.reviewAddressPlan,
    this.quoteLoading = false,
    this.quoteExpired = false,
    this.quoteError,
    this.statusRefreshing = false,
    this.statusError,
    this.startSubmitting = false,
    this.maxAmountLoading = false,
    this.maxAmountError,
    this.depositTxHashText = '',
    this.depositSubmitting = false,
    this.selectedIntentId,
    this.selectedRequestId,
    this.requestImportError,
  });

  final SwapDirection direction;
  final String amountText;
  final String destinationText;
  final SwapAsset externalAsset;
  final bool reviewVisible;
  final List<SwapPrototypeIntent> intents;
  final List<SwapExternalRequest> externalRequests;
  final String requestImportText;
  final int slippageBps;
  final List<SwapAsset> supportedExternalAssets;
  final Map<SwapAsset, double> indicativeExternalPerZec;
  final SwapQuote? reviewQuote;
  final SwapAddressPlan? reviewAddressPlan;
  final bool quoteLoading;
  final bool quoteExpired;
  final String? quoteError;
  final bool statusRefreshing;
  final String? statusError;
  final bool startSubmitting;
  final bool maxAmountLoading;
  final String? maxAmountError;
  final String depositTxHashText;
  final bool depositSubmitting;
  final String? selectedIntentId;
  final String? selectedRequestId;
  final String? requestImportError;

  SwapPrototypeIntent? get selectedIntentOrNull {
    final selectedId = selectedIntentId;
    if (selectedId != null) {
      for (final intent in intents) {
        if (intent.id == selectedId) return intent;
      }
    }
    return intents.isEmpty ? null : intents.first;
  }

  SwapPrototypeIntent get selectedIntent {
    final intent = selectedIntentOrNull;
    if (intent == null) {
      throw StateError('No selected swap intent');
    }
    return intent;
  }

  int get openIntentCount {
    return intents.where((intent) => !intent.status.isTerminal).length;
  }

  SwapExternalRequest? get selectedRequestOrNull {
    final selectedId = selectedRequestId;
    if (selectedId != null) {
      for (final request in externalRequests) {
        if (request.id == selectedId) return request;
      }
    }
    return externalRequests.isEmpty ? null : externalRequests.first;
  }

  SwapExternalRequest get selectedRequest {
    final request = selectedRequestOrNull;
    if (request == null) {
      throw StateError('No selected swap request');
    }
    return request;
  }

  int get openRequestCount {
    return externalRequests.where((request) => request.isOpen).length;
  }

  String get walletTransparentStagingAddress =>
      't1wallet-shield-prompt-staging';

  double? get sellAmount {
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) return null;
    return amount;
  }

  SwapAddressPlan? get addressPlan => reviewAddressPlan ?? draftAddressPlan;

  SwapAddressPlan? get draftAddressPlan {
    if (destinationText.trim().isEmpty) return null;
    return SwapAddressPlan.fromUserInput(
      direction: direction,
      externalAsset: externalAsset,
      userExternalAddress: destinationText,
      walletTransparentAddress: walletTransparentStagingAddress,
    );
  }

  String get destinationFieldLabel => direction.sendsZec
      ? 'Destination'
      : '${externalAsset.symbol} refund address';

  String get destinationFieldHint => direction.sendsZec
      ? 'External ${externalAsset.symbol} address or account'
      : 'Refund address on the ${externalAsset.symbol} source chain';

  bool get canReviewQuote =>
      sellAmount != null && draftAddressPlan != null && !quoteLoading;

  bool get canSubmitDepositTx =>
      depositTxHashText.trim().isNotEmpty && !depositSubmitting;

  SwapQuote? get quote => reviewQuote ?? draftQuote;

  SwapQuote? get draftQuote {
    final amount = sellAmount;
    if (amount == null) return null;
    return SwapQuote.estimate(
      direction: direction,
      externalAsset: externalAsset,
      sellAmount: amount,
      externalPerZec: indicativeExternalPerZec[externalAsset],
      slippageBps: slippageBps,
    );
  }

  String? get reviewAmountDifferenceWarning {
    final liveQuote = reviewQuote;
    final estimate = draftQuote;
    if (liveQuote == null || estimate == null) return null;
    if (liveQuote.direction != direction ||
        liveQuote.externalAsset != externalAsset ||
        liveQuote.sellAmount != estimate.sellAmount ||
        estimate.receiveAmount <= 0) {
      return null;
    }
    final delta =
        (liveQuote.receiveAmount - estimate.receiveAmount) /
        estimate.receiveAmount;
    final absoluteDelta = delta.abs();
    if (absoluteDelta < swapQuoteDifferenceWarningThreshold) return null;
    final percent = (absoluteDelta * 100).toStringAsFixed(
      absoluteDelta >= 0.1 ? 0 : 1,
    );
    final directionLabel = delta < 0 ? 'lower' : 'higher';
    return 'Live quote is $percent% $directionLabel than the latest estimate. Check the minimum receive before starting.';
  }

  List<SwapPrototypeField> get draftExposure {
    final hasQuote = quote != null;
    if (!direction.sendsZec) {
      return [
        SwapPrototypeField(
          label: 'Deposit address',
          value: hasQuote
              ? 'one-time ${externalAsset.symbol} address prepared at review'
              : 'prepared after quote review',
        ),
        const SwapPrototypeField(
          label: 'ZEC destination',
          value:
              'ZEC arrives at the wallet receive address; shield prompt follows',
        ),
        SwapPrototypeField(
          label: 'Refund path',
          value: addressPlan == null
              ? '${externalAsset.symbol} refund address required'
              : '${externalAsset.symbol} refunds return to entered address',
        ),
        SwapPrototypeField(
          label: 'Transparent window',
          value: hasQuote
              ? 'external deposit is public on source chain'
              : 'not open yet',
        ),
        SwapPrototypeField(
          label: 'Third-party data',
          value: 'solver sees ${externalAsset.symbol} deposit and ZEC route',
        ),
        const SwapPrototypeField(
          label: 'Network disclosure',
          value: 'direct connection; Tor not enabled',
        ),
      ];
    }
    return [
      SwapPrototypeField(
        label: 'Deposit address',
        value: hasQuote
            ? 'one-time transparent address prepared at review'
            : 'prepared after quote review',
      ),
      const SwapPrototypeField(
        label: 'Address reuse',
        value: '0 previous uses',
      ),
      SwapPrototypeField(
        label: 'Transparent window',
        value: hasQuote
            ? 'opens only after ZEC deposit is sent'
            : 'not open yet',
      ),
      const SwapPrototypeField(
        label: 'Third-party data',
        value: 'solver sees ZEC deposit tx and route after start',
      ),
      const SwapPrototypeField(
        label: 'Network disclosure',
        value: 'direct connection; Tor not enabled',
      ),
    ];
  }

  SwapPrototypeState copyWith({
    SwapDirection? direction,
    String? amountText,
    String? destinationText,
    SwapAsset? externalAsset,
    bool? reviewVisible,
    List<SwapPrototypeIntent>? intents,
    List<SwapExternalRequest>? externalRequests,
    String? requestImportText,
    int? slippageBps,
    List<SwapAsset>? supportedExternalAssets,
    Map<SwapAsset, double>? indicativeExternalPerZec,
    SwapQuote? reviewQuote,
    SwapAddressPlan? reviewAddressPlan,
    bool? quoteLoading,
    bool? quoteExpired,
    String? quoteError,
    bool? statusRefreshing,
    String? statusError,
    bool? startSubmitting,
    bool? maxAmountLoading,
    String? maxAmountError,
    String? depositTxHashText,
    bool? depositSubmitting,
    String? selectedIntentId,
    String? selectedRequestId,
    String? requestImportError,
    bool clearReview = false,
    bool clearQuoteError = false,
    bool clearStatusError = false,
    bool clearMaxAmountError = false,
    bool clearSelectedIntent = false,
    bool clearSelectedRequest = false,
    bool clearRequestImportError = false,
  }) {
    return SwapPrototypeState(
      direction: direction ?? this.direction,
      amountText: amountText ?? this.amountText,
      destinationText: destinationText ?? this.destinationText,
      externalAsset: externalAsset ?? this.externalAsset,
      reviewVisible: reviewVisible ?? this.reviewVisible,
      intents: intents ?? this.intents,
      externalRequests: externalRequests ?? this.externalRequests,
      requestImportText: requestImportText ?? this.requestImportText,
      slippageBps: slippageBps ?? this.slippageBps,
      supportedExternalAssets:
          supportedExternalAssets ?? this.supportedExternalAssets,
      indicativeExternalPerZec:
          indicativeExternalPerZec ?? this.indicativeExternalPerZec,
      reviewQuote: clearReview ? null : reviewQuote ?? this.reviewQuote,
      reviewAddressPlan: clearReview
          ? null
          : reviewAddressPlan ?? this.reviewAddressPlan,
      quoteLoading: quoteLoading ?? this.quoteLoading,
      quoteExpired: clearReview ? false : quoteExpired ?? this.quoteExpired,
      quoteError: clearQuoteError ? null : quoteError ?? this.quoteError,
      statusRefreshing: statusRefreshing ?? this.statusRefreshing,
      statusError: clearStatusError ? null : statusError ?? this.statusError,
      startSubmitting: startSubmitting ?? this.startSubmitting,
      maxAmountLoading: maxAmountLoading ?? this.maxAmountLoading,
      maxAmountError: clearMaxAmountError
          ? null
          : maxAmountError ?? this.maxAmountError,
      depositTxHashText: depositTxHashText ?? this.depositTxHashText,
      depositSubmitting: depositSubmitting ?? this.depositSubmitting,
      selectedIntentId: clearSelectedIntent
          ? null
          : selectedIntentId ?? this.selectedIntentId,
      selectedRequestId: clearSelectedRequest
          ? null
          : selectedRequestId ?? this.selectedRequestId,
      requestImportError: clearRequestImportError
          ? null
          : requestImportError ?? this.requestImportError,
    );
  }
}

const previewExternalRequests = <SwapExternalRequest>[
  SwapExternalRequest(
    id: 'request-one-click-usdc',
    source: 'Pasted request',
    title: 'Swap ZEC to USDC',
    requestedAction: 'Stage 0.2500 ZEC for USDC delivery',
    route: 'ZEC -> USDC',
    receivedAt: '10:58',
    status: SwapExternalRequestStatus.needsReview,
    riskLabel: 'Address reveal after approval',
    riskDetail: 'Destination is only used after you review the quote.',
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    amountText: '0.2500',
    destinationText: '0xrequest-usdc-recipient',
    disclosures: [
      SwapPrototypeField(label: 'Input', value: 'pasted swap request'),
      SwapPrototypeField(
        label: 'Destination',
        value: '0xrequest-usdc-recipient',
      ),
      SwapPrototypeField(
        label: 'Wallet action',
        value: 'requires quote review',
      ),
    ],
  ),
  SwapExternalRequest(
    id: 'request-receive-zec-usdc',
    source: 'Pasted request',
    title: 'Receive ZEC from USDC',
    requestedAction: 'Stage 140.35 USDC to receive ZEC',
    route: 'USDC -> ZEC',
    receivedAt: '10:55',
    status: SwapExternalRequestStatus.needsReview,
    riskLabel: 'Source-chain deposit required',
    riskDetail:
        'Approval prepares one-time USDC deposit instructions; ZEC lands on the wallet t-address before shielding.',
    direction: SwapDirection.externalToZec,
    externalAsset: SwapAsset.usdc,
    amountText: '140.35',
    destinationText: '0xrequest-usdc-refund',
    disclosures: [
      SwapPrototypeField(label: 'Input', value: 'pasted swap request'),
      SwapPrototypeField(label: 'Pay asset', value: 'USDC on Ethereum'),
      SwapPrototypeField(
        label: 'Receive address',
        value: 'current wallet address; shield prompt follows',
      ),
      SwapPrototypeField(label: 'Refund', value: '0xrequest-usdc-refund'),
    ],
  ),
  SwapExternalRequest(
    id: 'request-zip321',
    source: 'ZIP-321 URI',
    title: 'Zcash payment request',
    requestedAction: 'Review shielded ZEC payment request',
    route: 'ZEC payment',
    receivedAt: '10:51',
    status: SwapExternalRequestStatus.needsReview,
    riskLabel: 'Not a swap route',
    riskDetail: 'Keep payment requests out of swap execution.',
    disclosures: [
      SwapPrototypeField(label: 'Input', value: 'zcash: URI'),
      SwapPrototypeField(label: 'Wallet action', value: 'payment review'),
      SwapPrototypeField(label: 'Swap route', value: 'none'),
    ],
  ),
  SwapExternalRequest(
    id: 'request-walletconnect',
    source: 'WalletConnect (blocked)',
    title: 'Pairing request',
    requestedAction: 'No session opened; explicit requests only',
    route: 'external connector',
    receivedAt: '10:44',
    status: SwapExternalRequestStatus.unsupported,
    riskLabel: 'Connector disabled',
    riskDetail:
        'Swap does not open long-lived dapp sessions. Import explicit payment or swap requests instead.',
    disclosures: [
      SwapPrototypeField(label: 'Input', value: 'WalletConnect pairing'),
      SwapPrototypeField(label: 'Account reveal', value: 'blocked'),
      SwapPrototypeField(label: 'Background session', value: 'blocked'),
    ],
  ),
];

const previewSwapIntents = <SwapPrototypeIntent>[
  SwapPrototypeIntent(
    id: 'swap-8f29',
    title: 'ZEC to USDC',
    pair: 'ZEC -> USDC',
    sellAmount: '2.4000 ZEC',
    receiveEstimate: '~168.42 USDC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.shieldingPending,
    nextAction: 'Wait for shielding confirmation',
    steps: [
      SwapPrototypeStep(
        label: 'Quote locked',
        state: SwapPrototypeStepState.done,
        evidence: 'Quote saved locally',
      ),
      SwapPrototypeStep(
        label: 'One-time transparent address prepared',
        state: SwapPrototypeStepState.done,
        evidence: '0 previous uses',
      ),
      SwapPrototypeStep(
        label: 'Deposit observed',
        state: SwapPrototypeStepState.done,
        evidence: 'Height 2,860,411',
      ),
      SwapPrototypeStep(
        label: 'Destination transaction submitted',
        state: SwapPrototypeStepState.done,
        evidence: 'USDC tx pending finality',
      ),
      SwapPrototypeStep(
        label: 'Shielding pending',
        state: SwapPrototypeStepState.active,
        evidence: 'Transparent residue window is open',
      ),
      SwapPrototypeStep(
        label: 'Receipt sealed',
        state: SwapPrototypeStepState.pending,
        evidence: 'Waiting on shield tx',
      ),
    ],
    exposure: [
      SwapPrototypeField(
        label: 'Deposit address',
        value: 'one-time transparent address',
      ),
      SwapPrototypeField(label: 'Address reuse', value: '0 previous uses'),
      SwapPrototypeField(
        label: 'Transparent window',
        value: 'open until shielding completes',
      ),
      SwapPrototypeField(
        label: 'Third-party data',
        value: 'solver sees deposit tx and route',
      ),
      SwapPrototypeField(
        label: 'Network disclosure',
        value: 'direct connection; Tor not enabled',
      ),
    ],
    receipt: [
      SwapPrototypeField(label: 'Swap id', value: 'swap-8f29'),
      SwapPrototypeField(label: 'Pair', value: 'ZEC -> USDC'),
      SwapPrototypeField(label: 'Quote', value: 'locked at 10:42'),
      SwapPrototypeField(label: 'Shared fields', value: 'txid + status only'),
    ],
  ),
  SwapPrototypeIntent(
    id: 'swap-6c44',
    title: 'USDC to ZEC',
    pair: 'USDC -> ZEC',
    sellAmount: '210.52 USDC',
    receiveEstimate: '~3.0000 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.awaitingExternalDeposit,
    nextAction: 'Send USDC to the one-time deposit address',
    steps: [
      SwapPrototypeStep(
        label: 'Quote locked',
        state: SwapPrototypeStepState.done,
        evidence: 'Quote saved locally',
      ),
      SwapPrototypeStep(
        label: 'One-time USDC address prepared',
        state: SwapPrototypeStepState.active,
        evidence: 'Do not reuse this address',
      ),
      SwapPrototypeStep(
        label: 'External deposit observed',
        state: SwapPrototypeStepState.pending,
        evidence: 'Waiting for source-chain confirmation',
      ),
      SwapPrototypeStep(
        label: 'Shielded receive pending',
        state: SwapPrototypeStepState.pending,
        evidence: 'Destination is the active ZEC account',
      ),
    ],
    exposure: [
      SwapPrototypeField(
        label: 'Deposit address',
        value: 'one-time USDC address',
      ),
      SwapPrototypeField(
        label: 'ZEC destination',
        value: 'active shielded account',
      ),
      SwapPrototypeField(
        label: 'Third-party data',
        value: 'solver sees USDC deposit and ZEC route',
      ),
    ],
    receipt: [
      SwapPrototypeField(label: 'Swap id', value: 'swap-6c44'),
      SwapPrototypeField(label: 'Pair', value: 'USDC -> ZEC'),
      SwapPrototypeField(label: 'Quote', value: 'locked at 10:48'),
      SwapPrototypeField(label: 'Shared fields', value: 'txid + status only'),
    ],
  ),
  SwapPrototypeIntent(
    id: 'swap-underpaid',
    title: 'USDC to ZEC',
    pair: 'USDC -> ZEC',
    sellAmount: '100.00 USDC',
    receiveEstimate: '~1.4250 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.incompleteDeposit,
    nextAction: 'Top up the missing deposit or wait for refund',
    steps: [
      SwapPrototypeStep(
        label: 'Quote locked',
        state: SwapPrototypeStepState.done,
        evidence: 'Quote saved locally',
      ),
      SwapPrototypeStep(
        label: 'One-time USDC address prepared',
        state: SwapPrototypeStepState.done,
        evidence: '0 previous uses',
      ),
      SwapPrototypeStep(
        label: 'Incomplete deposit',
        state: SwapPrototypeStepState.warning,
        evidence: 'Deposit is below the quoted amount',
      ),
      SwapPrototypeStep(
        label: 'Resolution pending',
        state: SwapPrototypeStepState.active,
        evidence: 'Top up or wait for refund',
      ),
    ],
    exposure: [
      SwapPrototypeField(
        label: 'Deposit address',
        value: 'one-time USDC address',
      ),
      SwapPrototypeField(label: 'Visible issue', value: 'underpaid deposit'),
      SwapPrototypeField(
        label: 'Refund path',
        value: 'USDC refunds return to entered address',
      ),
    ],
    receipt: [
      SwapPrototypeField(label: 'Swap id', value: 'swap-underpaid'),
      SwapPrototypeField(label: 'Pair', value: 'USDC -> ZEC'),
      SwapPrototypeField(label: 'Deposit', value: '0xunderpaid-usdc-deposit'),
      SwapPrototypeField(label: 'Memo', value: 'memo-underpaid'),
      SwapPrototypeField(label: 'Status', value: 'incomplete deposit'),
      SwapPrototypeField(label: 'Resolution', value: 'top up or refund'),
    ],
    direction: SwapDirection.externalToZec,
    externalAsset: SwapAsset.usdc,
    depositAddress: '0xunderpaid-usdc-deposit',
    depositMemo: 'memo-underpaid',
    oneClickRefundTo: '0xusdc-refund-underpaid',
  ),
  SwapPrototypeIntent(
    id: 'swap-refund',
    title: 'ZEC to USDC',
    pair: 'ZEC -> USDC',
    sellAmount: '0.9000 ZEC',
    receiveEstimate: '~63.16 USDC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.refunded,
    nextAction: 'Refunded to source address',
    steps: [
      SwapPrototypeStep(
        label: 'Quote locked',
        state: SwapPrototypeStepState.done,
        evidence: 'Quote refund',
      ),
      SwapPrototypeStep(
        label: 'Deposit observed',
        state: SwapPrototypeStepState.done,
        evidence: 'Height 2,860,205',
      ),
      SwapPrototypeStep(
        label: 'Refund tx submitted',
        state: SwapPrototypeStepState.warning,
        evidence: 'Refunded to source address',
      ),
    ],
    exposure: [
      SwapPrototypeField(
        label: 'Transparent window',
        value: 'closed after refund',
      ),
      SwapPrototypeField(label: 'Third-party data', value: 'refund status'),
    ],
    receipt: [
      SwapPrototypeField(label: 'Swap id', value: 'swap-refund'),
      SwapPrototypeField(label: 'Pair', value: 'ZEC -> USDC'),
      SwapPrototypeField(label: 'Refund tx submitted', value: 'refund-zec-tx'),
      SwapPrototypeField(label: 'Outcome', value: 'Refunded to source address'),
    ],
    direction: SwapDirection.zecToExternal,
    externalAsset: SwapAsset.usdc,
    depositAddress: 't1refund-zec-deposit',
    oneClickRecipient: '0xusdc-recipient-refund',
    oneClickRefundTo: 't1refund-source',
  ),
  SwapPrototypeIntent(
    id: 'swap-failed',
    title: 'NEAR to ZEC',
    pair: 'NEAR -> ZEC',
    sellAmount: '14.00 NEAR',
    receiveEstimate: '~0.2778 ZEC',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.failed,
    nextAction: 'Swap route failed',
    steps: [
      SwapPrototypeStep(
        label: 'Quote locked',
        state: SwapPrototypeStepState.done,
        evidence: 'Quote failed',
      ),
      SwapPrototypeStep(
        label: 'Swap route failed',
        state: SwapPrototypeStepState.warning,
        evidence: 'No funds moved',
      ),
    ],
    exposure: [
      SwapPrototypeField(label: 'Transparent window', value: 'never opened'),
      SwapPrototypeField(label: 'Third-party data', value: 'failed quote id'),
    ],
    receipt: [
      SwapPrototypeField(label: 'Swap id', value: 'swap-failed'),
      SwapPrototypeField(label: 'Pair', value: 'NEAR -> ZEC'),
      SwapPrototypeField(label: 'Swap route failed', value: 'No funds moved'),
      SwapPrototypeField(label: 'Outcome', value: 'failed'),
    ],
    direction: SwapDirection.externalToZec,
    externalAsset: SwapAsset.near,
    depositAddress: 'near-failed-deposit.near',
    oneClickRefundTo: 'rowan.near',
  ),
  SwapPrototypeIntent(
    id: 'swap-2a11',
    title: 'ZEC to NEAR',
    pair: 'ZEC -> NEAR',
    sellAmount: '0.7500 ZEC',
    receiveEstimate: '~37.8 NEAR',
    provider: 'NEAR Intents',
    status: SwapIntentStatus.complete,
    nextAction: 'Copy redacted receipt',
    steps: [
      SwapPrototypeStep(
        label: 'Quote locked',
        state: SwapPrototypeStepState.done,
        evidence: 'Quote 2a11',
      ),
      SwapPrototypeStep(
        label: 'Deposit observed',
        state: SwapPrototypeStepState.done,
        evidence: 'Height 2,860,009',
      ),
      SwapPrototypeStep(
        label: 'Destination transaction submitted',
        state: SwapPrototypeStepState.done,
        evidence: 'NEAR tx final',
      ),
      SwapPrototypeStep(
        label: 'Shielding completed',
        state: SwapPrototypeStepState.done,
        evidence: 'No transparent residue',
      ),
    ],
    exposure: [
      SwapPrototypeField(
        label: 'Deposit address',
        value: 'one-time transparent address',
      ),
      SwapPrototypeField(label: 'Transparent window', value: 'closed'),
      SwapPrototypeField(label: 'Shareable receipt', value: 'redacted'),
    ],
    receipt: [
      SwapPrototypeField(label: 'Swap id', value: 'swap-2a11'),
      SwapPrototypeField(label: 'Pair', value: 'ZEC -> NEAR'),
      SwapPrototypeField(label: 'Status', value: 'complete'),
    ],
  ),
];
