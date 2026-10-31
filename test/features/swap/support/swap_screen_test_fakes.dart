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

  @override
  Future<String> reserveOrchardAddress({required String accountUuid}) async {
    return 'u1actualshieldedrecipient';
  }
}

class _FakeSwapSyncNotifier extends SyncNotifier {
  _FakeSwapSyncNotifier(
    this.spendableBalance, {
    BigInt? displaySpendableBalance,
    this.displaySpendableFreshness = SpendableBalanceFreshness.authoritative,
    this.recentTransactions = const [],
  }) : displaySpendableBalance = displaySpendableBalance ?? spendableBalance;

  final BigInt spendableBalance;
  final BigInt displaySpendableBalance;
  final SpendableBalanceFreshness displaySpendableFreshness;
  final List<rust_sync.TransactionInfo> recentTransactions;
  var restartCount = 0;
  var refreshAfterSendCount = 0;
  var swapRecoveryRounds = 0;
  var swapRecoveryContinues = 0;
  var swapRecoveryRequests = 0;

  /// What each waited round reports: its failure, or null when it succeeded.
  Object? swapRecoveryFailure;

  /// Counts recovery rounds a swap flow starts without waiting.
  @override
  void continueSwapRecovery() => swapRecoveryContinues++;

  /// Counts rounds NEAR statuses owe, without native work.
  @override
  void requestSwapRecovery() => swapRecoveryRequests++;

  /// Counts the receiver rounds a swap flow waits for, without native work,
  /// each ending with [swapRecoveryFailure].
  @override
  Future<Object?> awaitSwapRecovery() async {
    swapRecoveryRounds++;
    return swapRecoveryFailure;
  }

  @override
  Future<SyncState> build() async => SyncState(
    accountUuid: 'account-1',
    hasAccountScopedData: true,
    spendableBalance: spendableBalance,
    displaySpendableBalance: displaySpendableBalance,
    displaySpendableFreshness: displaySpendableFreshness,
    totalBalance: spendableBalance,
    recentTransactions: recentTransactions,
  );

  @override
  Future<void> restartSync() async {
    restartCount++;
  }

  @override
  Future<void> refreshAfterSend() async {
    refreshAfterSendCount++;
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
    this.zecDepositMemo = 'memo-live',
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

  /// The memo on ZEC deposit instructions. NEAR gives none, and a swap refund key
  /// requires none.
  final String? zecDepositMemo;

  /// The address on ZEC deposit instructions, read after the request is recorded.
  String get zecDepositAddress => 't1live-deposit';

  /// The address on external deposit instructions, read once per quote.
  String get externalDepositAddress => '0xlive-deposit';

  @override
  String get providerLabel => 'NEAR Intents';

  @override
  Future<List<SwapAsset>> listSupportedExternalAssets() async {
    return supportedAssets;
  }

  /// Sends `request` as the NEAR adapter does: its send hook runs, then the
  /// request counts as received.
  Future<void> send(SwapQuoteRequest request) async {
    await request.beforeSend?.call(
      DateTime.now().add(const Duration(hours: 1)),
    );
    requests.add(request);
  }

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    await send(request);
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
            ? zecDepositAddress
            : externalDepositAddress,
        expiresInLabel: '07:12',
        reuseWarning: 'Do not reuse this address',
        memo: request.direction == SwapDirection.zecToExternal
            ? zecDepositMemo
            : 'memo-live',
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

/// Reports every deposit submission and status refresh as refunded, a terminal
/// status.
class _TerminalDepositSwapProvider extends _FakeSwapProvider {
  _TerminalDepositSwapProvider() : super(zecDepositMemo: null);

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async => (await super.getStatus(
    intentId,
    depositMemo: depositMemo,
  )).withStatus(SwapIntentStatus.refunded);

  @override
  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  }) async => (await super.submitDepositTransaction(
    depositAddress: depositAddress,
    txHash: txHash,
    depositMemo: depositMemo,
    nearSenderAccount: nearSenderAccount,
  )).withStatus(SwapIntentStatus.refunded);
}

/// Fails the status request for each deposit address in [failing].
class _FailingStatusSwapProvider extends _FakeSwapProvider {
  _FailingStatusSwapProvider(this.failing) : super(zecDepositMemo: null);

  final Set<String> failing;

  @override
  Future<SwapIntentSnapshot> getStatus(
    String intentId, {
    String? depositMemo,
  }) async {
    final status = await super.getStatus(intentId, depositMemo: depositMemo);
    if (failing.contains(intentId)) throw Exception('status unavailable');
    return status;
  }
}

/// The wallet's four incoming slots, held by deposit address. A recorded status
/// frees its slot, as a conclusive one does for an expired quote, and a status
/// for a freed address reports that the wallet no longer tracks it.
class _ReceiveSlots {
  _ReceiveSlots(this.held);

  final Set<String> held;

  /// The reservation hook for the swap harness, refusing at the limit.
  Future<SwapZecStagingAddress?> reserve({
    required String accountUuid,
    required SwapDirection direction,
  }) async {
    if (held.length >= 4) {
      throw const ReceiveError(
        message: 'Every swap address is in use.',
        kind: ReceiveErrorKind.limit,
      );
    }
    held.add('incoming');
    return SwapZecStagingAddress(
      address: 'u1incoming',
      reservationIndex: BigInt.from(held.length),
    );
  }

  /// The wallet status hook for the swap harness.
  Future<bool?> observe(
    SwapIntent intent,
    SwapIntentSnapshot snapshot,
    DateTime checkedAt,
  ) async => held.remove(intent.depositAddress ?? intent.id);
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
  SwapIntentStatus nextStatus = SwapIntentStatus.awaitingExternalDeposit;

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
      status: nextStatus,
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

class _DeferredCatalogPricingSwapProvider extends _FakeSwapProvider
    implements SwapPricingProvider {
  _DeferredCatalogPricingSwapProvider({
    required super.supportedAssets,
    required this.usdPrices,
  });

  final Map<SwapAsset, double> usdPrices;
  final _pricingCompleter = Completer<SwapPricingSnapshot>();

  void completePricing() {
    _pricingCompleter.complete(SwapPricingSnapshot(usdPrices: usdPrices));
  }

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({bool forceRefresh = false}) {
    return _pricingCompleter.future;
  }
}

class _TorBlockedPricingSwapProvider extends _FakeSwapProvider
    implements SwapPricingProvider {
  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({bool forceRefresh = false}) {
    throw const OneClickApiException(
      'NEAR Intents token list failed (403): Request blocked',
      operation: 'token list',
      statusCode: 403,
      responseBody:
          '<html><h1>Request blocked</h1><p>Generated by cloudfront</p></html>',
    );
  }
}

class _PricingThenTorBlockedSwapProvider extends _FakeSwapProvider
    implements SwapPricingProvider {
  var pricingRequests = 0;

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({bool forceRefresh = false}) {
    pricingRequests += 1;
    if (pricingRequests == 1) {
      return Future.value(
        SwapPricingSnapshot(
          usdPrices: {SwapAsset.zec: 100.0, SwapAsset.usdc: 1.0},
        ),
      );
    }
    throw const OneClickApiException(
      'NEAR Intents token list failed (403): Request blocked',
      operation: 'token list',
      statusCode: 403,
      responseBody:
          '<html><h1>Request blocked</h1><p>Generated by cloudfront</p></html>',
    );
  }
}

class _InitialPricingFailureSwapProvider extends _FakeSwapProvider
    implements SwapPricingProvider {
  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({bool forceRefresh = false}) {
    throw StateError('temporary token list failure');
  }
}

class _TorThenPricingSwapProvider extends _FakeSwapProvider
    implements SwapPricingProvider {
  var pricingRequests = 0;

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({bool forceRefresh = false}) {
    pricingRequests += 1;
    if (pricingRequests == 1) {
      throw const OneClickApiException(
        'NEAR Intents token list failed (403): Request blocked',
        operation: 'token list',
        statusCode: 403,
        responseBody:
            '<html><h1>Request blocked</h1><p>Generated by cloudfront</p></html>',
      );
    }
    return Future.value(
      SwapPricingSnapshot(
        usdPrices: {SwapAsset.zec: 100.0, SwapAsset.usdc: 1.0},
      ),
    );
  }
}

class _PricingThenFailureSwapProvider extends _FakeSwapProvider
    implements SwapPricingProvider {
  var pricingRequests = 0;

  @override
  Future<SwapPricingSnapshot> loadPricingSnapshot({bool forceRefresh = false}) {
    pricingRequests += 1;
    if (pricingRequests > 1) {
      throw StateError('temporary price refresh failure');
    }
    return Future.value(
      SwapPricingSnapshot(
        usdPrices: {SwapAsset.zec: 100.0, SwapAsset.usdc: 1.0},
      ),
    );
  }
}

class _FakeNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  _FakeNetworkPrivacyNotifier(this.initialState);

  final NetworkPrivacyState initialState;

  @override
  NetworkPrivacyState build() => initialState;

  void setStateForTest(NetworkPrivacyState next) {
    state = next;
  }
}

/// Swap address records that accept every quote without a wallet database.
class _FakeReceiveReservationStore extends Fake
    implements ReceiveReservationStore {
  @override
  Future<String> begin(BigInt reservation, DateTime deadline) async =>
      'request-$reservation';

  @override
  Future<void> finish(String request, SwapQuote? accepted) async {}

  @override
  Future<void> recordRefund(BigInt refundIndex, SwapQuote quote) async {}
}

/// Swap address records that bind each refund key to one deposit, as the wallet
/// does.
class _BindingReceiveReservationStore extends Fake
    implements ReceiveReservationStore {
  final bindings = <BigInt, String>{};

  @override
  Future<void> recordRefund(BigInt refundIndex, SwapQuote quote) async {
    final deposit = quote.depositInstruction.address;
    if ((bindings[refundIndex] ??= deposit) != deposit) {
      throw StateError('refund key is bound to another deposit');
    }
  }
}

/// Incoming reservation records that refuse the first reservation with `kind`:
/// stale, as the wallet does once its latest quote expired, or waiting on a history
/// check, as it does once a hint queued the address again.
class _StaleFirstReservationStore extends Fake
    implements ReceiveReservationStore {
  _StaleFirstReservationStore([this.kind = ReceiveErrorKind.stale]);

  final ReceiveErrorKind kind;
  final begun = <BigInt>[];

  @override
  Future<String> begin(BigInt reservation, DateTime deadline) async {
    begun.add(reservation);
    if (reservation == BigInt.one) {
      throw ReceiveError(message: 'This swap address is waiting.', kind: kind);
    }
    return 'request-$reservation';
  }

  @override
  Future<void> finish(String request, SwapQuote? accepted) async {}
}

/// Incoming reservation records that accept every quote but refuse to start one,
/// as the wallet does once a hint queued the address for another history check.
class _HistoryPendingStartStore extends Fake
    implements ReceiveReservationStore {
  @override
  Future<String> begin(BigInt reservation, DateTime deadline) async =>
      'request-$reservation';

  @override
  Future<void> finish(String request, SwapQuote? accepted) async {}

  @override
  Future<ReceiveDeposit> start(String request) async =>
      throw const ReceiveError(
        message: 'Preparing a private swap address. Try again in a moment.',
        kind: ReceiveErrorKind.receiveHistory,
      );
}

/// Incoming reservation records whose start waits until [release], returning
/// the deposit instructions the quote was saved with, or throwing [refusal]
/// when set, as the wallet does for a stale reservation.
class _HeldStartReservationStore extends Fake
    implements ReceiveReservationStore {
  _HeldStartReservationStore({this.refusal});

  final ReceiveError? refusal;
  final _held = Completer<void>();
  final _accepted = <String, SwapQuote>{};

  /// How many starts were asked for.
  var starts = 0;

  /// Lets the held start finish.
  void release() => _held.complete();

  @override
  Future<String> begin(BigInt reservation, DateTime deadline) async =>
      'request-$reservation';

  @override
  Future<void> finish(String request, SwapQuote? accepted) async {
    if (accepted != null) _accepted[request] = accepted;
  }

  @override
  Future<ReceiveDeposit> start(String request) async {
    starts++;
    await _held.future;
    if (refusal case final refusal?) throw refusal;
    final deposit = _accepted[request]!.depositInstruction;
    return ReceiveDeposit(
      address: deposit.address,
      memo: deposit.memo,
      deadlineSeconds: PlatformInt64Util.from(0),
    );
  }
}

/// Reserves `<prefix><n>` on the n-th call, as the wallet does: a refund key
/// for a direction that sends ZEC, otherwise an incoming reservation.
class _CountingReservations {
  _CountingReservations(this.prefix);

  final String prefix;
  var count = 0;

  /// The reservation hook for the swap harness.
  Future<SwapZecStagingAddress?> reserve({
    required String accountUuid,
    required SwapDirection direction,
  }) async {
    count++;
    final index = BigInt.from(count);
    return SwapZecStagingAddress(
      address: '$prefix$count',
      refundIndex: direction.sendsZec ? index : null,
      reservationIndex: direction.sendsZec ? null : index,
    );
  }
}

/// Reserves nothing the first time, refusing with `kind` as the wallet does while
/// it waits on work it can finish itself, then reserves incoming addresses.
class _WaitingFirstReservation {
  _WaitingFirstReservation(this.kind);

  final ReceiveErrorKind kind;
  var calls = 0;

  /// The reservation hook for the swap harness.
  Future<SwapZecStagingAddress?> reserve({
    required String accountUuid,
    required SwapDirection direction,
  }) async {
    calls++;
    if (calls == 1) {
      throw ReceiveError(message: 'Waiting on the wallet', kind: kind);
    }
    return SwapZecStagingAddress(
      address: 'u1incoming$calls',
      reservationIndex: BigInt.from(calls),
    );
  }
}

/// Swap activity storage whose saves fail once [failSaves] is set, as when
/// secure storage becomes unavailable.
class _FailingSaveSwapPersistenceStore extends _FakeSwapPersistenceStore {
  _FailingSaveSwapPersistenceStore({super.initialIntents});

  var failSaves = false;

  /// How many next saves fail, apart from [failSaves].
  var failNextSaves = 0;

  /// Throws while [failSaves] is set or [failNextSaves] counts down, else saves.
  @override
  Future<void> saveRecords({
    required String accountUuid,
    required List<SwapIntentRecord> records,
  }) {
    if (failNextSaves > 0) {
      failNextSaves--;
      throw StateError('Secure storage is unavailable.');
    }
    if (failSaves) throw StateError('Secure storage is unavailable.');
    return super.saveRecords(accountUuid: accountUuid, records: records);
  }
}

/// Quotes with a new address-only ZEC deposit address each time, as NEAR does.
class _NewDepositPerQuoteSwapProvider extends _FakeSwapProvider {
  _NewDepositPerQuoteSwapProvider() : super(zecDepositMemo: null);

  @override
  String get zecDepositAddress => 't1deposit${requests.length}';
}

/// Holds the first quote's response until [releaseFirst], so a later quote
/// can be sent and answered while it is in flight.
class _HeldFirstQuoteSwapProvider extends _NewDepositPerQuoteSwapProvider {
  final _first = Completer<void>();

  /// Lets the first quote's response arrive.
  void releaseFirst() => _first.complete();

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    final first = requests.isEmpty;
    final quote = await super.quote(request);
    if (first) await _first.future;
    return quote;
  }
}

/// NEAR swap privacy, off at first, that a test sets without the settings
/// store or native calls.
class _FakeNearSwapPrivacyNotifier extends NearSwapPrivacyNotifier {
  @override
  bool build() => false;

  @override
  Future<void> set(bool enabled) async => state = enabled;
}

class _FailingQuoteSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    await send(request);
    throw StateError('provider unavailable');
  }
}

/// NEAR receives each quote request, but its response is lost.
class _LostResponseSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    await send(request);
    throw TimeoutException('quote response lost');
  }
}

/// Fails each quote request in local checks, before it is sent.
class _UnsentQuoteSwapProvider extends _FakeSwapProvider {
  final unsent = <SwapQuoteRequest>[];

  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    unsent.add(request);
    throw StateError('unsupported asset');
  }
}

class _LowAmountQuoteSwapProvider extends _FakeSwapProvider {
  @override
  Future<SwapQuote> quote(SwapQuoteRequest request) async {
    await send(request);
    throw const OneClickApiException(
      'NEAR Intents quote failed (400): amount is too low',
      statusCode: 400,
      providerMessage: 'Amount is too low for bridge',
    );
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

  /// When set, the fee check waits for it.
  Completer<void>? holdPreflight;
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
    await holdPreflight?.future;
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
  final discardedDrafts = <BigInt>[];
  final broadcasts = <_HardwareBroadcastRequest>[];

  @override
  Future<SwapHardwarePcztDraft> createZecDepositPczt({
    required String accountUuid,
    required SwapIntent intent,
  }) async {
    depositDrafts.add(intent.id);
    return SwapHardwarePcztDraft(
      accountUuid: accountUuid,
      pcztBytes: const [1, 2, 3],
      needsSaplingParams: false,
      feeZatoshi: BigInt.from(10000),
      proposalId: BigInt.one,
      sendFlowId: 'test-swap-hardware',
    );
  }

  @override
  Future<List<String>> encodeSigningUrParts({
    required SwapHardwarePcztDraft draft,
  }) async {
    return const ['ur:zcash-sign-batch/test'];
  }

  @override
  Future<List<int>> decodeSigningResponse({
    required SwapHardwarePcztDraft draft,
    required List<int> responseCbor,
  }) async {
    return responseCbor;
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
  Future<void> discardPcztDraft({required SwapHardwarePcztDraft draft}) async {
    discardedDrafts.add(draft.proposalId);
  }

  @override
  Future<void> settlePcztDraftAfterLedgerBroadcast({
    required SwapHardwarePcztDraft draft,
    required String? status,
  }) async {
    discardedDrafts.add(draft.proposalId);
  }

  @override
  Future<rust_sync.ExtractAndBroadcastPcztResult> broadcastSignedPczt({
    required SwapHardwarePcztDraft draft,
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

class _LedgerOperationCheckpoint {
  const _LedgerOperationCheckpoint({
    required this.operationId,
    required this.proofs,
    required this.signatures,
  });

  final String operationId;
  final List<int> proofs;
  final List<int> signatures;
}

class _FakeLedgerSignedOperationService
    implements LedgerSignedOperationService {
  final checkpoints = <_LedgerOperationCheckpoint>[];
  final broadcasts = <String>[];
  final acknowledged = <String>[];

  @override
  Future<void> checkpoint({
    required String operationId,
    required String accountUuid,
    required LedgerSignedOperationKind kind,
    required List<int> pcztWithProofsBytes,
    required List<int> pcztWithSignaturesBytes,
    String? externalRef,
  }) async {
    checkpoints.add(
      _LedgerOperationCheckpoint(
        operationId: operationId,
        proofs: [...pcztWithProofsBytes],
        signatures: [...pcztWithSignaturesBytes],
      ),
    );
  }

  @override
  Future<List<LedgerSignedOperationMetadata>> list() async => const [];

  @override
  Future<LedgerSignedOperationBroadcastResult> broadcast({
    required String operationId,
    String? spendParamsPath,
    String? outputParamsPath,
  }) async {
    broadcasts.add(operationId);
    return LedgerSignedOperationBroadcastResult(
      operationId: operationId,
      txid: 'hardware-broadcast-txid',
      status: SwapDepositBroadcastStatus.broadcasted,
      requiresAck: true,
    );
  }

  @override
  Future<void> acknowledge(String operationId) async {
    acknowledged.add(operationId);
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

class _DelayedComposerPreferencesStore extends _FakeSwapPersistenceStore {
  _DelayedComposerPreferencesStore({
    super.initialPreferences,
    super.initialPayAsset,
  });

  final _preferencesGate = Completer<void>();

  void completePreferencesLoad() => _preferencesGate.complete();

  @override
  Future<SwapComposerPreferences?> loadPreferences({
    required String accountUuid,
  }) async {
    final preferences = await super.loadPreferences(accountUuid: accountUuid);
    await _preferencesGate.future;
    return preferences;
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

class _FlakyPayAssetLoadSwapPersistenceStore extends _FakeSwapPersistenceStore {
  var payAssetLoadCount = 0;

  @override
  Future<SwapAsset?> loadSelectedAsset({required String accountUuid}) async {
    payAssetLoadCount += 1;
    if (payAssetLoadCount == 1) {
      throw StateError('transient secure store failure');
    }
    return SwapAsset.sol;
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
