part of '../swap_screen_test.dart';

class _FakeReceiveAddressService extends ReceiveAddressService {
  _FakeReceiveAddressService(this._ref) : super(_ref);

  final Ref _ref;

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async {
    return _ref.read(accountProvider).value?.activeAddress ??
        'u1actualshieldedrecipient';
  }

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async {
    return 'u1actualshieldedrecipient';
  }
}

class _FakeSwapSyncNotifier extends SyncNotifier {
  _FakeSwapSyncNotifier(
    this.spendableBalance, {
    this.recentTransactions = const [],
  });

  final BigInt spendableBalance;
  final List<rust_sync.TransactionInfo> recentTransactions;
  var restartCount = 0;

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    spendableBalance: spendableBalance,
    totalBalance: spendableBalance,
    recentTransactions: recentTransactions,
  );

  @override
  Future<void> restartSync() async {
    restartCount++;
  }
}

class _FakeSwapMaxAmountEstimator implements SwapMaxAmountEstimator {
  _FakeSwapMaxAmountEstimator({BigInt? maxZatoshi})
    : maxZatoshi = maxZatoshi ?? BigInt.zero;

  final BigInt maxZatoshi;
  final requests = <String>[];

  @override
  Future<BigInt> estimateMaxZecSellAmount({required String accountUuid}) async {
    requests.add(accountUuid);
    return maxZatoshi;
  }
}

class _CompletingSwapMaxAmountEstimator implements SwapMaxAmountEstimator {
  final requests = <String>[];
  final _completer = Completer<BigInt>();

  void complete(BigInt value) {
    _completer.complete(value);
  }

  @override
  Future<BigInt> estimateMaxZecSellAmount({required String accountUuid}) async {
    requests.add(accountUuid);
    return _completer.future;
  }
}

class _FakeSwapProvider implements SwapProvider {
  _FakeSwapProvider({
    List<SwapAsset>? supportedAssets,
    this.submitDepositError,
    this.quoteExpiresAt,
  }) : supportedAssets = supportedAssets ?? swapExternalAssets;

  final requests = <SwapQuoteRequest>[];
  final startedQuotes = <SwapQuote>[];
  final statusRequests = <_StatusRequest>[];
  final submittedDeposits = <_SubmittedDeposit>[];
  final List<SwapAsset> supportedAssets;
  final Object? submitDepositError;

  /// When set, every quote carries this expiry so tests can exercise the
  /// review-quote expiry guard in [SwapNotifier.startIntent].
  final DateTime? quoteExpiresAt;

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async {
    return supportedAssets;
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    requests.add(request);
    final estimate = SwapQuote.estimate(
      direction: request.direction,
      externalAsset: request.externalAsset,
      mode: request.mode,
      amount: request.amount,
      slippageBps: request.slippageBps ?? 50,
    );
    return SwapQuote(
      direction: estimate.direction,
      sellAsset: estimate.sellAsset,
      receiveAsset: estimate.receiveAsset,
      externalAsset: estimate.externalAsset,
      mode: estimate.mode,
      sellAmount: estimate.sellAmount,
      receiveAmount: estimate.receiveAmount,
      minimumReceiveAmount: estimate.minimumReceiveAmount,
      providerLabel: estimate.providerLabel,
      feeLabel: estimate.feeLabel,
      expiryLabel: estimate.expiryLabel,
      sellAmountBaseUnits: _fakeBaseUnits(
        estimate.sellAsset,
        estimate.sellAmount,
      ),
      providerQuoteId: 'quote-live',
      quoteExpiresAt: quoteExpiresAt,
      providerRefundInfo: request.mode == SwapQuoteMode.exactOutput
          ? const SwapProviderRefundInfo(
              minimumDepositText: '1.485 ZEC',
              refundFeeText: '0.0001 ZEC',
            )
          : null,
      fiatValueBasis: _fakeFiatValueBasis(estimate),
      depositInstruction: SwapDepositInstruction(
        asset: estimate.sellAsset,
        address: request.direction == SwapDirection.zecToExternal
            ? 't1live-deposit'
            : '0xlive-deposit',
        expiresInLabel: '07:12',
        reuseWarning: 'Do not reuse this address',
        memo: 'memo-live',
      ),
    );
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    startedQuotes.add(quote);
    return SwapIntentSnapshot.fromQuote(
      quote,
      id: quote.depositInstruction.address,
    );
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    statusRequests.add(
      _StatusRequest(depositAddress: intentId, depositMemo: depositMemo),
    );
    final statusQuote = await quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: 1.5,
        destination: '0xrecipient',
        refundAddress: 'u1actualshieldedrecipient',
      ),
    );
    final base = SwapIntentSnapshot.fromQuote(statusQuote, id: intentId);
    final depositInstruction = statusQuote.depositInstruction;
    return SwapIntentSnapshot(
      id: base.id,
      providerLabel: base.providerLabel,
      pairText: base.pairText,
      sellAmountText: base.sellAmountText,
      receiveEstimateText: base.receiveEstimateText,
      status: SwapIntentStatus.processing,
      nextAction: 'Swap is processing',
      depositInstruction: SwapDepositInstruction(
        asset: depositInstruction.asset,
        address: depositInstruction.address,
        expiresInLabel: depositInstruction.expiresInLabel,
        reuseWarning: depositInstruction.reuseWarning,
        memo: depositMemo ?? depositInstruction.memo,
      ),
      providerRefundInfo: const SwapProviderRefundInfo(
        depositedAmountText: '1.5 ZEC',
        refundedAmountText: '0.01 ZEC',
        refundReason: 'UNUSED_INPUT',
      ),
    );
  }

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) async {
    submittedDeposits.add(
      _SubmittedDeposit(
        depositAddress: depositAddress,
        txHash: txHash,
        depositMemo: depositMemo,
      ),
    );
    final error = submitDepositError;
    if (error != null) throw error;
    final statusQuote = await quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: 1.5,
        destination: '0xrecipient',
        refundAddress: 'u1actualshieldedrecipient',
      ),
    );
    final base = SwapIntentSnapshot.fromQuote(statusQuote, id: depositAddress);
    return SwapIntentSnapshot(
      id: base.id,
      providerLabel: base.providerLabel,
      pairText: base.pairText,
      sellAmountText: base.sellAmountText,
      receiveEstimateText: base.receiveEstimateText,
      status: SwapIntentStatus.depositObserved,
      nextAction: 'Deposit detected',
      depositInstruction: base.depositInstruction,
    );
  }
}

class _DeferredSupportedAssetsSwapProvider extends _FakeSwapProvider {
  final _supportedAssetsCompleter = Completer<List<SwapAsset>>();

  void completeSupportedAssets(List<SwapAsset> assets) {
    _supportedAssetsCompleter.complete(assets);
  }

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() {
    return _supportedAssetsCompleter.future;
  }
}

SwapFiatValueBasis _fakeFiatValueBasis(SwapQuote quote) {
  return SwapFiatValueBasis(
    capturedAt: DateTime.utc(2026, 5, 7, 10),
    sellUsdUnitPrice: _fakeUsdUnitPrice(quote.sellAsset),
    receiveUsdUnitPrice: _fakeUsdUnitPrice(quote.receiveAsset),
  );
}

double? _fakeUsdUnitPrice(SwapAsset asset) {
  if (asset.isNativeZec) return 70.1733333333;
  return switch (asset.symbol.toUpperCase()) {
    'USDC' || 'USDT' || 'DAI' => 1,
    _ => null,
  };
}

BigInt _fakeBaseUnits(SwapAsset asset, double amount) {
  final fixed = amount.toStringAsFixed(asset.decimals);
  final parts = fixed.split('.');
  final whole = BigInt.parse(parts.first);
  final fraction = parts.length == 1
      ? BigInt.zero
      : BigInt.parse(parts[1].padRight(asset.decimals, '0'));
  var scale = BigInt.one;
  for (var i = 0; i < asset.decimals; i++) {
    scale *= BigInt.from(10);
  }
  return whole * scale + fraction;
}

class _PendingExternalDepositSwapProvider extends _FakeSwapProvider {
  _PendingExternalDepositSwapProvider({Completer<void>? statusGate})
    : _statusGate = statusGate;

  final Completer<void>? _statusGate;

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    statusRequests.add(
      _StatusRequest(depositAddress: intentId, depositMemo: depositMemo),
    );
    final statusGate = _statusGate;
    if (statusGate != null) {
      await statusGate.future;
    }
    final statusQuote = await quote(
      const SwapQuoteRequest(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        sellAmount: 140.35,
        destination: '0xexternal-refund',
        refundAddress: '0xexternal-refund',
      ),
    );
    final base = SwapIntentSnapshot.fromQuote(statusQuote, id: intentId);
    return SwapIntentSnapshot(
      id: base.id,
      providerLabel: base.providerLabel,
      pairText: base.pairText,
      sellAmountText: base.sellAmountText,
      receiveEstimateText: base.receiveEstimateText,
      status: SwapIntentStatus.awaitingExternalDeposit,
      nextAction: 'Waiting for deposit confirmation',
      depositInstruction: base.depositInstruction,
    );
  }
}

class _DriftingExactOutputSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    final quote = await super.quote(request);
    if (request.mode != SwapQuoteMode.exactOutput) return quote;
    const sellAmount = 1.6;
    return SwapQuote(
      direction: quote.direction,
      sellAsset: quote.sellAsset,
      receiveAsset: quote.receiveAsset,
      externalAsset: quote.externalAsset,
      mode: quote.mode,
      sellAmount: sellAmount,
      receiveAmount: quote.receiveAmount,
      minimumReceiveAmount: quote.minimumReceiveAmount,
      providerLabel: quote.providerLabel,
      feeLabel: quote.feeLabel,
      expiryLabel: quote.expiryLabel,
      quoteExpiresAt: quote.quoteExpiresAt,
      depositInstruction: quote.depositInstruction,
      providerQuoteId: quote.providerQuoteId,
      sellAmountBaseUnits: _fakeBaseUnits(quote.sellAsset, sellAmount),
      sellAmountTextOverride: '${sellAmount.toStringAsFixed(4)} ZEC',
      receiveEstimateTextOverride: quote.receiveEstimateText,
      minimumReceiveTextOverride: quote.minimumReceiveText,
      rateTextOverride: quote.rateText,
      providerRefundInfo: quote.providerRefundInfo,
      fiatValueBasis: quote.fiatValueBasis,
    );
  }
}

class _DriftingExactInputSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    final quote = await super.quote(request);
    if (request.mode != SwapQuoteMode.exactInput ||
        request.direction != SwapDirection.zecToExternal) {
      return quote;
    }
    const receiveAmount = 123.45;
    return SwapQuote(
      direction: quote.direction,
      sellAsset: quote.sellAsset,
      receiveAsset: quote.receiveAsset,
      externalAsset: quote.externalAsset,
      mode: quote.mode,
      sellAmount: quote.sellAmount,
      receiveAmount: receiveAmount,
      minimumReceiveAmount: 122.83,
      providerLabel: quote.providerLabel,
      feeLabel: quote.feeLabel,
      expiryLabel: quote.expiryLabel,
      quoteExpiresAt: quote.quoteExpiresAt,
      depositInstruction: quote.depositInstruction,
      providerQuoteId: quote.providerQuoteId,
      sellAmountBaseUnits: quote.sellAmountBaseUnits,
      sellAmountTextOverride: quote.sellAmountText,
      receiveEstimateTextOverride: '123.45 USDC',
      minimumReceiveTextOverride: '122.83 USDC',
      rateTextOverride: '1 ZEC = 82.30 USDC',
      providerRefundInfo: quote.providerRefundInfo,
      fiatValueBasis: quote.fiatValueBasis,
    );
  }
}

class _AwaitingSubmitSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) async {
    submittedDeposits.add(
      _SubmittedDeposit(
        depositAddress: depositAddress,
        txHash: txHash,
        depositMemo: depositMemo,
      ),
    );
    final statusQuote = await quote(
      const SwapQuoteRequest(
        direction: SwapDirection.zecToExternal,
        externalAsset: SwapAsset.usdc,
        sellAmount: 1.5,
        destination: '0xrecipient',
        refundAddress: 'u1actualshieldedrecipient',
      ),
    );
    final base = SwapIntentSnapshot.fromQuote(statusQuote, id: depositAddress);
    return SwapIntentSnapshot(
      id: base.id,
      providerLabel: base.providerLabel,
      pairText: base.pairText,
      sellAmountText: base.sellAmountText,
      receiveEstimateText: base.receiveEstimateText,
      status: SwapIntentStatus.awaitingDeposit,
      nextAction: 'Waiting for deposit',
      depositInstruction: base.depositInstruction,
    );
  }
}

class _PricingSwapProvider extends _FakeSwapProvider
    implements SwapPricingProvider {
  _PricingSwapProvider(this._rates);

  final List<double> _rates;
  var pricingRequests = 0;
  var sawForcedRefresh = false;

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({
    bool forceRefresh = false,
  }) async {
    pricingRequests += 1;
    sawForcedRefresh = sawForcedRefresh || forceRefresh;
    final index = pricingRequests - 1;
    final rate = _rates[index < _rates.length ? index : _rates.length - 1];
    return SwapPricingSnapshot(
      usdPrices: {SwapAsset.zec: rate, SwapAsset.usdc: 1},
    );
  }
}

class _FailingQuoteSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    requests.add(request);
    throw StateError('provider unavailable');
  }
}

class _DeferredStatusSwapProvider extends _FakeSwapProvider {
  _DeferredStatusSwapProvider(this.snapshot);

  final SwapIntentSnapshot snapshot;
  final statusCompleter = Completer<SwapIntentSnapshot>();

  void completeStatus() {
    if (!statusCompleter.isCompleted) {
      statusCompleter.complete(snapshot);
    }
  }

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    statusRequests.add(
      _StatusRequest(depositAddress: intentId, depositMemo: depositMemo),
    );
    return statusCompleter.future;
  }
}

class _FixedStatusSwapProvider extends _FakeSwapProvider {
  _FixedStatusSwapProvider(this.snapshot);

  final SwapIntentSnapshot snapshot;

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    statusRequests.add(
      _StatusRequest(depositAddress: intentId, depositMemo: depositMemo),
    );
    return snapshot;
  }
}

class _DelayedQuoteSwapProvider extends _FakeSwapProvider {
  final _quoteGate = Completer<void>();

  void completeQuote() {
    if (!_quoteGate.isCompleted) {
      _quoteGate.complete();
    }
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    await _quoteGate.future;
    return super.quote(request);
  }
}

class _DelayedRefreshQuoteSwapProvider extends _FakeSwapProvider {
  final _refreshGate = Completer<void>();
  var _quoteCount = 0;

  void completeRefresh() {
    if (!_refreshGate.isCompleted) {
      _refreshGate.complete();
    }
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    _quoteCount += 1;
    if (_quoteCount > 1) {
      await _refreshGate.future;
    }
    return super.quote(request);
  }
}

class _FailingStartSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    startedQuotes.add(quote);
    throw StateError('provider rejected start');
  }
}

class _DelayedStartSwapProvider extends _FakeSwapProvider {
  final _startGate = Completer<void>();

  void completeStart() {
    if (!_startGate.isCompleted) {
      _startGate.complete();
    }
  }

  @override
  Future<SwapIntentSnapshot> startSwap(SwapQuote quote) async {
    startedQuotes.add(quote);
    await _startGate.future;
    return SwapIntentSnapshot.fromQuote(
      quote,
      id: quote.depositInstruction.address,
    );
  }
}

class _LongQuoteSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    final estimate = await super.quote(request);
    return SwapQuote(
      direction: estimate.direction,
      sellAsset: estimate.sellAsset,
      receiveAsset: estimate.receiveAsset,
      externalAsset: estimate.externalAsset,
      mode: estimate.mode,
      sellAmount: estimate.sellAmount,
      receiveAmount: estimate.receiveAmount,
      minimumReceiveAmount: estimate.minimumReceiveAmount,
      providerLabel: estimate.providerLabel,
      feeLabel: 'Included in shown rate',
      expiryLabel: estimate.expiryLabel,
      providerQuoteId: 'quote-long-provider-reference',
      sellAmountBaseUnits: estimate.sellAmountBaseUnits,
      sellAmountTextOverride: '12345.678901 ${estimate.sellAsset.symbol}',
      receiveEstimateTextOverride: '175.942100 ${estimate.receiveAsset.symbol}',
      minimumReceiveTextOverride: '174.812300 ${estimate.receiveAsset.symbol}',
      fiatValueBasis: estimate.fiatValueBasis,
      depositInstruction: SwapDepositInstruction(
        asset: estimate.sellAsset,
        address:
            '0xprovider-deposit-address-with-very-long-tail-abcdef1234567890',
        expiresInLabel: estimate.expiryLabel,
        reuseWarning: 'Do not reuse this address',
        memo: 'memo-with-very-long-routing-tag-abcdef1234567890',
      ),
    );
  }
}

class _LongExternalStatusSwapProvider extends _LongQuoteSwapProvider {
  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    statusRequests.add(
      _StatusRequest(depositAddress: intentId, depositMemo: depositMemo),
    );
    final statusQuote = await quote(
      const SwapQuoteRequest(
        direction: SwapDirection.externalToZec,
        externalAsset: SwapAsset.usdc,
        sellAmount: 12345.678901,
        destination: 'u1wallet-transparent-staging-shield-prompt-target',
        refundAddress:
            '0xrefund-address-with-a-very-long-source-chain-suffix-abcdef1234567890',
      ),
    );
    return SwapIntentSnapshot(
      id: intentId,
      providerLabel: statusQuote.providerLabel,
      pairText: statusQuote.pairText,
      sellAmountText: statusQuote.sellAmountText,
      receiveEstimateText: statusQuote.receiveEstimateText,
      status: SwapIntentStatus.awaitingExternalDeposit,
      nextAction:
          'Send the external deposit, then submit the source-chain transaction hash after confirmation.',
      depositInstruction: SwapDepositInstruction(
        asset: statusQuote.sellAsset,
        address: intentId,
        expiresInLabel: statusQuote.expiryLabel,
        reuseWarning: 'Do not reuse this address',
        memo:
            depositMemo ??
            'memo-with-a-long-routing-tag-and-provider-reference-9876543210',
      ),
    );
  }
}

class _CompletingExternalStatusSwapProvider
    extends _LongExternalStatusSwapProvider {
  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    final base = await super.getStatus(intentId, depositMemo: depositMemo);
    return SwapIntentSnapshot(
      id: base.id,
      providerLabel: base.providerLabel,
      pairText: base.pairText,
      sellAmountText: base.sellAmountText,
      receiveEstimateText: base.receiveEstimateText,
      status: SwapIntentStatus.complete,
      nextAction: 'Provider reports destination settlement complete',
      depositInstruction: base.depositInstruction,
    );
  }
}

class _StatusRequest {
  const _StatusRequest({required this.depositAddress, this.depositMemo});

  final String depositAddress;
  final String? depositMemo;
}

class _SubmittedDeposit {
  const _SubmittedDeposit({
    required this.depositAddress,
    required this.txHash,
    this.depositMemo,
  });

  final String depositAddress;
  final String txHash;
  final String? depositMemo;
}

class _FakeSwapDepositSender implements SwapDepositSender {
  _FakeSwapDepositSender({
    this.preflightError,
    this.broadcastStatus = SwapDepositBroadcastStatus.broadcasted,
    this.broadcastMessage,
  });

  final Object? preflightError;
  final String broadcastStatus;
  final String? broadcastMessage;
  final preflightRequests = <_DepositSendRequest>[];
  final requests = <_DepositSendRequest>[];

  @override
  Future<BigInt> estimateZecDepositFee({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    preflightRequests.add(
      _DepositSendRequest(
        accountUuid: accountUuid,
        depositAddress: quote.depositInstruction.address,
        sellAmountText: quote.sellAmountText,
        sellAmountBaseUnits: quote.sellAmountBaseUnits,
      ),
    );
    final error = preflightError;
    if (error != null) throw error;
    return BigInt.from(10000);
  }

  @override
  Future<SwapDepositBroadcastResult> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    requests.add(
      _DepositSendRequest(
        accountUuid: accountUuid,
        depositAddress: quote.depositInstruction.address,
        sellAmountText: quote.sellAmountText,
        sellAmountBaseUnits: quote.sellAmountBaseUnits,
      ),
    );
    return SwapDepositBroadcastResult(
      txHash: 'zec-auto-txid',
      status: broadcastStatus,
      message: broadcastMessage,
    );
  }
}

class _DelayedSwapDepositSender extends _FakeSwapDepositSender {
  final _sendGate = Completer<SwapDepositBroadcastResult>();

  void completeSend([String txid = 'zec-auto-txid']) {
    if (!_sendGate.isCompleted) {
      _sendGate.complete(
        SwapDepositBroadcastResult(
          txHash: txid,
          status: SwapDepositBroadcastStatus.broadcasted,
        ),
      );
    }
  }

  @override
  Future<SwapDepositBroadcastResult> sendZecDeposit({
    required String accountUuid,
    required SwapQuote quote,
  }) async {
    requests.add(
      _DepositSendRequest(
        accountUuid: accountUuid,
        depositAddress: quote.depositInstruction.address,
        sellAmountText: quote.sellAmountText,
        sellAmountBaseUnits: quote.sellAmountBaseUnits,
      ),
    );
    return _sendGate.future;
  }
}

class _FakeSwapHardwareSigningService implements SwapHardwareSigningService {
  _FakeSwapHardwareSigningService({
    this.broadcastStatus = 'broadcasted',
    this.broadcastMessage,
    this.proofCompleter,
  });

  final String broadcastStatus;
  final String? broadcastMessage;
  final Completer<List<int>>? proofCompleter;
  final depositDrafts = <String>[];
  final proofDrafts = <List<int>>[];
  final broadcasts = <_HardwareBroadcastRequest>[];

  @override
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapIntent intent,
  }) async {
    depositDrafts.add(intent.id);
    return SwapHardwarePcztDraft(
      pcztBytes: const [1, 2, 3],
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(10000),
    );
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required SwapHardwarePcztDraft draft,
  }) async {
    return const ['ur:zcash-pczt/test'];
  }

  @override
  Future<List<int>> addProofsForSigning({
    required SwapHardwarePcztDraft draft,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    proofDrafts.add(draft.pcztBytes);
    final pending = proofCompleter;
    if (pending != null) return pending.future;
    return const [7, 8, 9];
  }

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcasts.add(
      _HardwareBroadcastRequest(
        proofs: pcztWithProofsBytes,
        signatures: pcztWithSignaturesBytes,
      ),
    );
    return rust_sync.ExtractAndBroadcastPcztResult(
      txid: 'hardware-broadcast-txid',
      status: broadcastStatus,
      message: broadcastMessage,
    );
  }
}

class _HardwareBroadcastRequest {
  const _HardwareBroadcastRequest({
    required this.proofs,
    required this.signatures,
  });

  final List<int> proofs;
  final List<int> signatures;
}

class _FakeKeystoneScanScreen extends StatelessWidget {
  const _FakeKeystoneScanScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const ValueKey('fake_keystone_signature_done'),
          onPressed: () => Navigator.of(context).pop(<int>[10, 11, 12]),
          child: const Text('Return signature'),
        ),
      ),
    );
  }
}

class _FakeSwapAccountNotifier extends AccountNotifier {
  _FakeSwapAccountNotifier(this.initialState);

  final AccountState initialState;

  @override
  FutureOr<AccountState> build() => initialState;

  @override
  Future<void> switchAccount(String uuid) async {
    final prev = state.value ?? initialState;
    state = AsyncData(prev.copyWith(activeAccountUuid: uuid));
  }
}

class _FakeSwapPersistenceStore
    implements
        SwapActivityStore,
        SwapComposerPreferencesStore,
        PaySelectedAssetStore {
  _FakeSwapPersistenceStore({
    List<SwapIntent> initialIntents = const [],
    SwapComposerPreferences? initialPreferences,
    Map<String, SwapComposerPreferences> initialPreferencesByAccount = const {},
    SwapAsset? initialPayAsset,
  }) : savedIntents = [...initialIntents],
       savedPreferences = initialPreferences {
    if (initialPreferences != null) {
      _preferencesByAccount['account-1'] = initialPreferences;
    }
    if (initialPayAsset != null) {
      _payAssetByAccount['account-1'] = initialPayAsset;
    }
    _preferencesByAccount.addAll(initialPreferencesByAccount);
    for (final intent in initialIntents) {
      final accountUuid = intent.accountUuid;
      if (accountUuid == null || accountUuid.trim().isEmpty) {
        _legacyIntents.add(intent);
      } else {
        _intentsByAccount
            .putIfAbsent(accountUuid, () => <SwapIntent>[])
            .add(intent);
      }
    }
  }

  var loadCount = 0;
  var loadPreferencesCount = 0;
  var savePreferencesCount = 0;
  var savePayAssetCount = 0;
  final saveSnapshots = <List<SwapIntent>>[];
  final loadedAccounts = <String>[];
  final savedAccounts = <String>[];
  List<SwapIntent> savedIntents;
  SwapComposerPreferences? savedPreferences;
  SwapAsset? savedPayAsset;
  final _legacyIntents = <SwapIntent>[];
  final _intentsByAccount = <String, List<SwapIntent>>{};
  final _preferencesByAccount = <String, SwapComposerPreferences>{};
  final _payAssetByAccount = <String, SwapAsset>{};

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    loadCount++;
    loadedAccounts.add(accountUuid);
    final accountIntents = _intentsByAccount[accountUuid] ?? const [];
    return [
      for (final intent in [..._legacyIntents, ...accountIntents])
        SwapIntentRecord.fromIntent(intent.copyWith(accountUuid: accountUuid)),
    ];
  }

  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) async {
    savedAccounts.add(accountUuid);
    final recordIds = records.map((record) => record.id).toSet();
    _legacyIntents.removeWhere((intent) => recordIds.contains(intent.id));
    savedIntents = swapIntentsFromRecords(
      records.map((record) => record.copyWith(accountUuid: accountUuid)),
    );
    _intentsByAccount[accountUuid] = [...savedIntents];
    saveSnapshots.add(savedIntents);
  }

  @override
  Future<void> deleteForAccount({required String accountUuid}) async {
    _intentsByAccount.remove(accountUuid);
    savedIntents = const [];
  }

  @override
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  }) async {
    loadPreferencesCount++;
    return _preferencesByAccount[accountUuid];
  }

  @override
  Future<void> savePreferences({
    required String accountUuid,
    required SwapComposerPreferences preferences,
  }) async {
    savePreferencesCount++;
    savedPreferences = preferences;
    _preferencesByAccount[accountUuid] = preferences;
  }

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async {
    return _payAssetByAccount[accountUuid];
  }

  @override
  Future<void> saveSelectedAsset({
    required String accountUuid,
    required SwapAsset asset,
  }) async {
    savePayAssetCount++;
    savedPayAsset = asset;
    _payAssetByAccount[accountUuid] = asset;
  }
}

class _DelayedLoadSwapPersistenceStore extends _FakeSwapPersistenceStore {
  _DelayedLoadSwapPersistenceStore({
    required this.delayedAccounts,
    super.initialIntents,
  });

  final Set<String> delayedAccounts;
  final _loadGates = <String, Completer<void>>{};

  void completeLoad(String accountUuid) {
    final gate = _loadGates[accountUuid];
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  @override
  Future<List<SwapIntentRecord>> loadRecords({
    required String accountUuid,
  }) async {
    final records = await super.loadRecords(accountUuid: accountUuid);
    if (!delayedAccounts.contains(accountUuid)) return records;

    final gate = _loadGates.putIfAbsent(accountUuid, Completer<void>.new);
    await gate.future;
    return records;
  }
}

class _DelayedPayAssetLoadSwapPersistenceStore
    extends _FakeSwapPersistenceStore {
  _DelayedPayAssetLoadSwapPersistenceStore({
    required super.initialIntents,
    required super.initialPayAsset,
  });

  final _loadGate = Completer<void>();

  void completePayAssetLoad() {
    _loadGate.complete();
  }

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async {
    final loaded = await super.loadSelectedAsset(accountUuid: accountUuid);
    await _loadGate.future;
    return loaded;
  }
}

AddressBookContact _addressBookContact({
  required String id,
  required String label,
  required AddressBookNetwork network,
  required String address,
}) {
  return AddressBookContact(
    id: id,
    label: label,
    network: network,
    address: address,
    profilePictureId: 'pfp-01',
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

class _FakeAddressBookRepository implements AddressBookRepository {
  _FakeAddressBookRepository([List<AddressBookContact> contacts = const []])
    : contacts = [...contacts];

  final List<AddressBookContact> contacts;

  @override
  Future<List<AddressBookContact>> loadContacts() async => [...contacts];

  @override
  Future<void> saveContacts(List<AddressBookContact> contacts) async {
    this.contacts
      ..clear()
      ..addAll(contacts);
  }
}
