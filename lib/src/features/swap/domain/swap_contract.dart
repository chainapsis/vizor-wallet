enum SwapDirection { zecToExternal, externalToZec }

extension SwapDirectionLabels on SwapDirection {
  bool get sendsZec => this == SwapDirection.zecToExternal;

  SwapDirection get toggled =>
      sendsZec ? SwapDirection.externalToZec : SwapDirection.zecToExternal;

  String get segmentLabel => sendsZec ? 'Send ZEC' : 'Receive ZEC';

  SwapAsset fromAsset(SwapAsset externalAsset) {
    return sendsZec ? SwapAsset.zec : externalAsset;
  }

  SwapAsset toAsset(SwapAsset externalAsset) {
    return sendsZec ? externalAsset : SwapAsset.zec;
  }

  String fromSymbol(SwapAsset externalAsset) => fromAsset(externalAsset).symbol;

  String toSymbol(SwapAsset externalAsset) => toAsset(externalAsset).symbol;

  String get destinationLabel => sendsZec ? 'Destination' : 'ZEC destination';

  String get destinationHint =>
      sendsZec ? 'External address or account' : 'Account or unified address';
}

class SwapAsset {
  const SwapAsset._({
    required this.name,
    required this.symbol,
    required this.displayName,
    required this.chainTicker,
    required this.chainLabel,
    required this.decimals,
    required double mockExternalPerZec,
    this.assetId,
    String? railLabel,
  }) : _mockExternalPerZec = mockExternalPerZec,
       _railLabel = railLabel;

  factory SwapAsset.live({
    required String assetId,
    required String symbol,
    required String blockchain,
    required int decimals,
  }) {
    final chainTicker = _normalizeKey(blockchain);
    final displaySymbol = _displaySymbol(symbol, chainTicker);
    final staticAsset = _staticAssetFor(displaySymbol, chainTicker, decimals);
    if (staticAsset != null) {
      return staticAsset._withAssetId(assetId);
    }
    return SwapAsset._(
      name: _assetName(displaySymbol, chainTicker, decimals),
      symbol: displaySymbol,
      displayName: _tokenDisplayName(displaySymbol),
      chainTicker: chainTicker,
      chainLabel: _chainDisplayName(chainTicker),
      decimals: decimals,
      assetId: assetId,
      mockExternalPerZec: _mockRateFor(displaySymbol),
    );
  }

  static const zec = SwapAsset._(
    name: 'zec',
    symbol: 'ZEC',
    displayName: 'Zcash',
    chainTicker: 'zec',
    chainLabel: 'Zcash',
    railLabel: 'Zcash wallet',
    decimals: 8,
    mockExternalPerZec: 1,
  );
  static const usdc = SwapAsset._(
    name: 'usdc',
    symbol: 'USDC',
    displayName: 'USD Coin',
    chainTicker: 'eth',
    chainLabel: 'Ethereum',
    railLabel: 'Ethereum USDC',
    decimals: 6,
    mockExternalPerZec: 70.1733333333,
  );
  static const eth = SwapAsset._(
    name: 'eth',
    symbol: 'ETH',
    displayName: 'Ether',
    chainTicker: 'eth',
    chainLabel: 'Ethereum',
    railLabel: 'Ethereum ETH',
    decimals: 18,
    mockExternalPerZec: 0.0254,
  );
  static const btc = SwapAsset._(
    name: 'btc',
    symbol: 'BTC',
    displayName: 'Bitcoin',
    chainTicker: 'btc',
    chainLabel: 'Bitcoin',
    railLabel: 'Bitcoin BTC',
    decimals: 8,
    mockExternalPerZec: 0.00064,
  );
  static const sol = SwapAsset._(
    name: 'sol',
    symbol: 'SOL',
    displayName: 'Solana',
    chainTicker: 'sol',
    chainLabel: 'Solana',
    railLabel: 'Solana SOL',
    decimals: 9,
    mockExternalPerZec: 0.42,
  );
  static const usdt = SwapAsset._(
    name: 'usdt',
    symbol: 'USDT',
    displayName: 'Tether USD',
    chainTicker: 'eth',
    chainLabel: 'Ethereum',
    railLabel: 'Ethereum USDT',
    decimals: 6,
    mockExternalPerZec: 70.11,
  );
  static const dai = SwapAsset._(
    name: 'dai',
    symbol: 'DAI',
    displayName: 'Dai Stablecoin',
    chainTicker: 'eth',
    chainLabel: 'Ethereum',
    railLabel: 'Ethereum DAI',
    decimals: 18,
    mockExternalPerZec: 70.08,
  );
  static const wbtc = SwapAsset._(
    name: 'wbtc',
    symbol: 'WBTC',
    displayName: 'Wrapped Bitcoin',
    chainTicker: 'eth',
    chainLabel: 'Ethereum',
    railLabel: 'Ethereum WBTC',
    decimals: 8,
    mockExternalPerZec: 0.00064,
  );
  static const near = SwapAsset._(
    name: 'near',
    symbol: 'NEAR',
    displayName: 'NEAR',
    chainTicker: 'near',
    chainLabel: 'NEAR',
    railLabel: 'NEAR account',
    decimals: 24,
    mockExternalPerZec: 50.4,
  );
  static const doge = SwapAsset._(
    name: 'doge',
    symbol: 'DOGE',
    displayName: 'Dogecoin',
    chainTicker: 'doge',
    chainLabel: 'Dogecoin',
    railLabel: 'Dogecoin DOGE',
    decimals: 8,
    mockExternalPerZec: 435,
  );

  static const values = <SwapAsset>[
    zec,
    usdc,
    eth,
    btc,
    sol,
    usdt,
    dai,
    wbtc,
    near,
    doge,
  ];

  final String name;
  final String symbol;
  final String displayName;
  final String chainTicker;
  final String chainLabel;
  final int decimals;
  final String? assetId;
  final String? _railLabel;
  final double _mockExternalPerZec;

  String get railLabel => _railLabel ?? '$chainLabel $symbol';

  String get preferredBlockchain => chainTicker;

  double get mockExternalPerZec => _mockExternalPerZec;

  String get identityKey => assetId ?? name;

  String get tokenIconAsset => 'assets/swap/tokens/$tokenIconKey.png';

  String get chainIconAsset => 'assets/swap/chains/$chainIconKey.png';

  String get tokenIconKey => _normalizeIconKey(symbol);

  String get chainIconKey => _normalizeIconKey(chainTicker);

  bool get isNativeZec => this == zec;

  bool hasSameMarketAs(SwapAsset other) {
    return _marketKey == other._marketKey;
  }

  SwapAsset _withAssetId(String assetId) {
    return SwapAsset._(
      name: name,
      symbol: symbol,
      displayName: displayName,
      chainTicker: chainTicker,
      chainLabel: chainLabel,
      decimals: decimals,
      assetId: assetId,
      railLabel: _railLabel,
      mockExternalPerZec: _mockExternalPerZec,
    );
  }

  String formatAmount(double amount) {
    final normalized = symbol.toUpperCase();
    if (normalized == 'ZEC') {
      return amount.toStringAsFixed(4);
    }
    if (normalized == 'BTC' || normalized == 'WBTC' || decimals == 8) {
      return amount.toStringAsFixed(8);
    }
    if (normalized == 'ETH' || normalized == 'SOL' || normalized == 'NEAR') {
      return amount.toStringAsFixed(4);
    }
    return amount.toStringAsFixed(2);
  }

  Map<String, Object?> toPersistedJson() {
    return {
      'name': name,
      'symbol': symbol,
      'displayName': displayName,
      'chainTicker': chainTicker,
      'chainLabel': chainLabel,
      'decimals': decimals,
      'assetId': assetId,
      'railLabel': _railLabel,
    };
  }

  static SwapAsset? fromPersistedJson(Object? value) {
    if (value is String) {
      return byName(value);
    }
    if (value is! Map<String, dynamic>) {
      return null;
    }
    final name = value['name'];
    final symbol = value['symbol'];
    final chainTicker = value['chainTicker'];
    final decimals = value['decimals'];
    if (name is String) {
      final staticAsset = byName(name);
      if (staticAsset != null &&
          (value['assetId'] == null || value['assetId'] is String)) {
        final assetId = value['assetId'] as String?;
        return assetId == null
            ? staticAsset
            : staticAsset._withAssetId(assetId);
      }
    }
    if (symbol is! String || chainTicker is! String || decimals is! int) {
      return null;
    }
    return SwapAsset._(
      name: name is String ? name : _assetName(symbol, chainTicker, decimals),
      symbol: symbol,
      displayName: value['displayName'] is String
          ? value['displayName'] as String
          : _tokenDisplayName(symbol),
      chainTicker: _normalizeKey(chainTicker),
      chainLabel: value['chainLabel'] is String
          ? value['chainLabel'] as String
          : _chainDisplayName(chainTicker),
      decimals: decimals,
      assetId: value['assetId'] is String ? value['assetId'] as String : null,
      railLabel: value['railLabel'] is String
          ? value['railLabel'] as String
          : null,
      mockExternalPerZec: _mockRateFor(symbol),
    );
  }

  static SwapAsset? byName(String name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    return other is SwapAsset && identityKey == other.identityKey;
  }

  @override
  int get hashCode => identityKey.hashCode;

  @override
  String toString() => 'SwapAsset($symbol on $chainTicker)';

  String get _marketKey =>
      '${symbol.toLowerCase()}:${chainTicker.toLowerCase()}:$decimals';
}

const swapExternalAssets = <SwapAsset>[
  SwapAsset.usdc,
  SwapAsset.eth,
  SwapAsset.btc,
  SwapAsset.sol,
  SwapAsset.usdt,
  SwapAsset.dai,
  SwapAsset.wbtc,
  SwapAsset.near,
  SwapAsset.doge,
];

SwapAsset? _staticAssetFor(String symbol, String chainTicker, int decimals) {
  for (final asset in SwapAsset.values) {
    if (asset.symbol.toLowerCase() == symbol.toLowerCase() &&
        asset.chainTicker.toLowerCase() == chainTicker.toLowerCase() &&
        asset.decimals == decimals) {
      return asset;
    }
  }
  return null;
}

String _assetName(String symbol, String chainTicker, int decimals) {
  return '${_normalizeIconKey(symbol)}_${_normalizeKey(chainTicker)}_$decimals';
}

String _displaySymbol(String symbol, String chainTicker) {
  final normalized = symbol.trim();
  if (chainTicker == 'near' && normalized.toLowerCase() == 'wnear') {
    return 'NEAR';
  }
  return normalized.toUpperCase();
}

String _normalizeKey(String value) => value.trim().toLowerCase();

String _normalizeIconKey(String value) {
  return value.trim().replaceFirst(RegExp(r'^\$'), '').toLowerCase();
}

String _tokenDisplayName(String symbol) {
  return switch (symbol.toLowerCase()) {
    'btc' || 'wbtc' || 'xbtc' || 'cbbtc' => 'Bitcoin',
    'eth' || 'weth' => 'Ethereum',
    'usdc' || 'susdc' => 'USD Coin',
    'usdt' => 'Tether USD',
    'dai' => 'Dai Stablecoin',
    'near' || 'wnear' => 'NEAR',
    'sol' => 'Solana',
    'zec' => 'Zcash',
    'doge' => 'Dogecoin',
    _ => symbol,
  };
}

String _chainDisplayName(String ticker) {
  return switch (ticker.toLowerCase()) {
    'adi' => 'Adi',
    'aptos' => 'Aptos',
    'arb' => 'Arbitrum',
    'avax' => 'Avalanche',
    'base' => 'Base',
    'bera' => 'Bera',
    'bch' => 'Bitcoin Cash',
    'bsc' => 'Binance Smart Chain',
    'btc' => 'Bitcoin',
    'cardano' => 'Cardano',
    'doge' => 'Dogecoin',
    'eth' => 'Ethereum',
    'gnosis' => 'Gnosis',
    'ltc' => 'Litecoin',
    'near' => 'NEAR',
    'op' => 'Optimism',
    'plasma' => 'Plasma',
    'pol' => 'Polygon',
    'sol' => 'Solana',
    'starknet' => 'Starknet',
    'stellar' => 'Stellar',
    'sui' => 'Sui',
    'ton' => 'TON',
    'tron' => 'Tron',
    'xrp' => 'XRP',
    'xlayer' => 'X Layer',
    'zec' => 'Zcash',
    _ =>
      ticker.isEmpty
          ? ticker
          : '${ticker[0].toUpperCase()}${ticker.substring(1)}',
  };
}

double _mockRateFor(String symbol) {
  return switch (symbol.toLowerCase()) {
    'usdc' || 'usdt' || 'dai' => 70,
    'eth' || 'weth' => 0.0254,
    'btc' || 'wbtc' || 'xbtc' || 'cbbtc' => 0.00064,
    'sol' => 0.42,
    'near' || 'wnear' => 50.4,
    'doge' => 435,
    _ => 1,
  };
}

enum SwapIntentStatus {
  awaitingDeposit,
  awaitingExternalDeposit,
  depositObserved,
  processing,
  providerStatusUnknown,
  incompleteDeposit,
  shieldingPending,
  shieldingConfirming,
  shieldingFailed,
  complete,
  refunded,
  expired,
  failed,
}

extension SwapIntentStatusLabels on SwapIntentStatus {
  bool get isTerminal => switch (this) {
    SwapIntentStatus.complete ||
    SwapIntentStatus.refunded ||
    SwapIntentStatus.expired ||
    SwapIntentStatus.failed => true,
    _ => false,
  };

  String get label => switch (this) {
    SwapIntentStatus.awaitingDeposit => 'Awaiting deposit',
    SwapIntentStatus.awaitingExternalDeposit => 'Awaiting external deposit',
    SwapIntentStatus.depositObserved => 'Deposit observed',
    SwapIntentStatus.processing => 'Processing',
    SwapIntentStatus.providerStatusUnknown => 'Checking status',
    SwapIntentStatus.incompleteDeposit => 'Incomplete deposit',
    SwapIntentStatus.shieldingPending => 'Shielding pending',
    SwapIntentStatus.shieldingConfirming => 'Shielding confirming',
    SwapIntentStatus.shieldingFailed => 'Shielding failed',
    SwapIntentStatus.complete => 'Complete',
    SwapIntentStatus.refunded => 'Refunded',
    SwapIntentStatus.expired => 'Expired',
    SwapIntentStatus.failed => 'Failed',
  };
}

class SwapQuoteRequest {
  const SwapQuoteRequest({
    required this.direction,
    required this.externalAsset,
    required this.sellAmount,
    required this.destination,
    this.refundAddress,
    this.dryRun = false,
    this.slippageBps,
    this.deadline,
  });

  final SwapDirection direction;
  final SwapAsset externalAsset;
  final double sellAmount;
  final String destination;
  final String? refundAddress;
  final bool dryRun;
  final int? slippageBps;
  final Duration? deadline;

  SwapAsset get sellAsset => direction.fromAsset(externalAsset);
  SwapAsset get receiveAsset => direction.toAsset(externalAsset);
}

class SwapDepositInstruction {
  const SwapDepositInstruction({
    required this.asset,
    required this.address,
    required this.expiresInLabel,
    required this.reuseWarning,
    this.memo,
    this.deadline,
  });

  final SwapAsset asset;
  final String address;
  final String expiresInLabel;
  final String reuseWarning;
  final String? memo;
  final DateTime? deadline;
}

class SwapQuote {
  const SwapQuote({
    required this.direction,
    required this.sellAsset,
    required this.receiveAsset,
    required this.externalAsset,
    required this.sellAmount,
    required this.receiveAmount,
    required this.minimumReceiveAmount,
    required this.providerLabel,
    required this.feeLabel,
    required this.expiryLabel,
    required this.depositInstruction,
    this.quoteExpiresAt,
    this.providerQuoteId,
    this.providerSignature,
    this.sellAmountTextOverride,
    this.receiveEstimateTextOverride,
    this.minimumReceiveTextOverride,
    this.rateTextOverride,
  });

  factory SwapQuote.estimate({
    required SwapDirection direction,
    required SwapAsset externalAsset,
    required double sellAmount,
    String providerLabel = 'NEAR Intents',
    String expiryLabel = '07:12',
    DateTime? quoteExpiresAt,
    DateTime? depositDeadline,
    double? externalPerZec,
    int slippageBps = 50,
  }) {
    assert(externalAsset.name != 'zec');
    final sellAsset = direction.fromAsset(externalAsset);
    final receiveAsset = direction.toAsset(externalAsset);
    final rate = externalPerZec ?? externalAsset.mockExternalPerZec;
    final receiveAmount = direction.sendsZec
        ? sellAmount * rate
        : sellAmount / rate;
    final rateText = direction.sendsZec
        ? '1 ZEC = ${rate.toStringAsFixed(2)} ${externalAsset.symbol}'
        : '1 ${externalAsset.symbol} = ${(1 / rate).toStringAsFixed(4)} ZEC';
    return SwapQuote(
      direction: direction,
      sellAsset: sellAsset,
      receiveAsset: receiveAsset,
      externalAsset: externalAsset,
      sellAmount: sellAmount,
      receiveAmount: receiveAmount,
      minimumReceiveAmount: receiveAmount * (1 - slippageBps / 10000),
      providerLabel: providerLabel,
      feeLabel: 'Included in shown rate',
      expiryLabel: expiryLabel,
      quoteExpiresAt: quoteExpiresAt,
      depositInstruction: SwapDepositInstruction(
        asset: sellAsset,
        address: 'one-time-${sellAsset.symbol.toLowerCase()}-deposit-preview',
        expiresInLabel: expiryLabel,
        reuseWarning: 'Do not reuse this address',
        deadline: depositDeadline,
      ),
      rateTextOverride: rateText,
    );
  }

  final SwapDirection direction;
  final SwapAsset sellAsset;
  final SwapAsset receiveAsset;
  final SwapAsset externalAsset;
  final double sellAmount;
  final double receiveAmount;
  final double minimumReceiveAmount;
  final String providerLabel;
  final String feeLabel;
  final String expiryLabel;
  final DateTime? quoteExpiresAt;
  final SwapDepositInstruction depositInstruction;
  final String? providerQuoteId;
  final String? providerSignature;
  final String? sellAmountTextOverride;
  final String? receiveEstimateTextOverride;
  final String? minimumReceiveTextOverride;
  final String? rateTextOverride;

  String get pairText => '${sellAsset.symbol} -> ${receiveAsset.symbol}';
  String get sellAmountText =>
      sellAmountTextOverride ??
      '${sellAsset.formatAmount(sellAmount)} ${sellAsset.symbol}';
  String get receiveEstimateText =>
      receiveEstimateTextOverride ??
      '~${receiveAsset.formatAmount(receiveAmount)} ${receiveAsset.symbol}';
  String get minimumReceiveText =>
      minimumReceiveTextOverride ??
      '${receiveAsset.formatAmount(minimumReceiveAmount)} ${receiveAsset.symbol}';

  String get rateText {
    final override = rateTextOverride;
    if (override != null) {
      return override;
    }
    final rate = externalAsset.mockExternalPerZec;
    if (direction.sendsZec) {
      return '1 ZEC = ${rate.toStringAsFixed(2)} ${externalAsset.symbol}';
    }
    return '1 ${externalAsset.symbol} = ${(1 / rate).toStringAsFixed(4)} ZEC';
  }
}

class SwapIntentSnapshot {
  const SwapIntentSnapshot({
    required this.id,
    required this.providerLabel,
    required this.pairText,
    required this.sellAmountText,
    required this.receiveEstimateText,
    required this.status,
    required this.nextAction,
    required this.depositInstruction,
    this.providerStatusRaw,
  });

  factory SwapIntentSnapshot.fromQuote(
    SwapQuote quote, {
    String id = 'swap-new',
  }) {
    final status = quote.direction.sendsZec
        ? SwapIntentStatus.awaitingDeposit
        : SwapIntentStatus.awaitingExternalDeposit;
    return SwapIntentSnapshot(
      id: id,
      providerLabel: quote.providerLabel,
      pairText: quote.pairText,
      sellAmountText: quote.sellAmountText,
      receiveEstimateText: quote.receiveEstimateText,
      status: status,
      nextAction:
          'Send ${quote.sellAsset.symbol} to the one-time deposit address',
      depositInstruction: quote.depositInstruction,
    );
  }

  final String id;
  final String providerLabel;
  final String pairText;
  final String sellAmountText;
  final String receiveEstimateText;
  final SwapIntentStatus status;
  final String nextAction;
  final SwapDepositInstruction depositInstruction;
  final String? providerStatusRaw;
}

class SwapPricingSnapshot {
  const SwapPricingSnapshot({required this.usdPrices});

  final Map<SwapAsset, double> usdPrices;

  List<SwapAsset> get supportedExternalAssets {
    final zecPrice = usdPrices[SwapAsset.zec];
    if (zecPrice == null || zecPrice <= 0) return const [];
    return [
      for (final entry in usdPrices.entries)
        if (entry.key != SwapAsset.zec && entry.value > 0) entry.key,
    ];
  }

  Map<SwapAsset, double> get externalPerZec {
    final zecPrice = usdPrices[SwapAsset.zec];
    if (zecPrice == null || zecPrice <= 0) return const {};
    return {
      for (final entry in usdPrices.entries)
        if (entry.key != SwapAsset.zec && entry.value > 0)
          entry.key: zecPrice / entry.value,
    };
  }
}

abstract interface class SwapProvider {
  String get providerLabel;

  Future<List<SwapAsset>> listSupportedExternalAssets();

  Future<SwapQuote> quote(SwapQuoteRequest request);

  Future<SwapIntentSnapshot> startSwap(SwapQuote quote);

  Future<SwapIntentSnapshot> getStatus(String intentId, {String? depositMemo});

  Future<SwapIntentSnapshot> submitDepositTransaction({
    required String depositAddress,
    required String txHash,
    String? depositMemo,
    String? nearSenderAccount,
  });
}

abstract interface class SwapPricingProvider {
  Future<SwapPricingSnapshot> loadPricingSnapshot({bool forceRefresh = false});
}
