enum SwapDirection { zecToExternal, externalToZec }

enum SwapQuoteMode {
  exactInput,
  exactOutput;

  String get oneClickSwapType => switch (this) {
    SwapQuoteMode.exactInput => 'EXACT_INPUT',
    SwapQuoteMode.exactOutput => 'EXACT_OUTPUT',
  };
}

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
    required double fallbackExternalPerZec,
    this.assetId,
    String? railLabel,
  }) : _fallbackExternalPerZec = fallbackExternalPerZec,
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
      fallbackExternalPerZec: _fallbackRateFor(displaySymbol),
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
    fallbackExternalPerZec: 1,
  );
  static const usdc = SwapAsset._(
    name: 'usdc',
    symbol: 'USDC',
    displayName: 'USD Coin',
    chainTicker: 'eth',
    chainLabel: 'Ethereum',
    railLabel: 'Ethereum USDC',
    decimals: 6,
    fallbackExternalPerZec: 70.1733333333,
  );
  static const eth = SwapAsset._(
    name: 'eth',
    symbol: 'ETH',
    displayName: 'Ether',
    chainTicker: 'eth',
    chainLabel: 'Ethereum',
    railLabel: 'Ethereum ETH',
    decimals: 18,
    fallbackExternalPerZec: 0.0254,
  );
  static const btc = SwapAsset._(
    name: 'btc',
    symbol: 'BTC',
    displayName: 'Bitcoin',
    chainTicker: 'btc',
    chainLabel: 'Bitcoin',
    railLabel: 'Bitcoin BTC',
    decimals: 8,
    fallbackExternalPerZec: 0.00064,
  );
  static const sol = SwapAsset._(
    name: 'sol',
    symbol: 'SOL',
    displayName: 'Solana',
    chainTicker: 'sol',
    chainLabel: 'Solana',
    railLabel: 'Solana SOL',
    decimals: 9,
    fallbackExternalPerZec: 0.42,
  );
  static const usdt = SwapAsset._(
    name: 'usdt',
    symbol: 'USDT',
    displayName: 'Tether USD',
    chainTicker: 'eth',
    chainLabel: 'Ethereum',
    railLabel: 'Ethereum USDT',
    decimals: 6,
    fallbackExternalPerZec: 70.11,
  );
  static const dai = SwapAsset._(
    name: 'dai',
    symbol: 'DAI',
    displayName: 'Dai Stablecoin',
    chainTicker: 'eth',
    chainLabel: 'Ethereum',
    railLabel: 'Ethereum DAI',
    decimals: 18,
    fallbackExternalPerZec: 70.08,
  );
  static const wbtc = SwapAsset._(
    name: 'wbtc',
    symbol: 'WBTC',
    displayName: 'Wrapped Bitcoin',
    chainTicker: 'eth',
    chainLabel: 'Ethereum',
    railLabel: 'Ethereum WBTC',
    decimals: 8,
    fallbackExternalPerZec: 0.00064,
  );
  static const near = SwapAsset._(
    name: 'near',
    symbol: 'NEAR',
    displayName: 'NEAR',
    chainTicker: 'near',
    chainLabel: 'NEAR',
    railLabel: 'NEAR account',
    decimals: 24,
    fallbackExternalPerZec: 50.4,
  );
  static const doge = SwapAsset._(
    name: 'doge',
    symbol: 'DOGE',
    displayName: 'Dogecoin',
    chainTicker: 'doge',
    chainLabel: 'Dogecoin',
    railLabel: 'Dogecoin DOGE',
    decimals: 8,
    fallbackExternalPerZec: 435,
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
  final double _fallbackExternalPerZec;

  String get railLabel => _railLabel ?? '$chainLabel $symbol';

  String get preferredBlockchain => chainTicker;

  double get fallbackExternalPerZec => _fallbackExternalPerZec;

  String get identityKey => assetId ?? name;

  String get tokenIconAsset => _tokenIconAssetPath(tokenIconKey);

  String get chainIconAsset => _chainIconAssetPath(chainIconKey);

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
      fallbackExternalPerZec: _fallbackExternalPerZec,
    );
  }

  String formatAmount(double amount) {
    return _formatAmountForDisplay(
      amount,
      rounding: _SwapAmountRounding.nearest,
    );
  }

  String formatAmountDown(double amount) {
    return _formatAmountForDisplay(amount, rounding: _SwapAmountRounding.down);
  }

  String formatAmountUp(double amount) {
    return _formatAmountForDisplay(amount, rounding: _SwapAmountRounding.up);
  }

  String _formatAmountForDisplay(
    double amount, {
    required _SwapAmountRounding rounding,
  }) {
    final digits = _displayFractionDigits;
    final displayAmount = switch (rounding) {
      _SwapAmountRounding.nearest => amount,
      _SwapAmountRounding.down => _roundDisplayAmountDown(amount, digits),
      _SwapAmountRounding.up => _roundDisplayAmountUp(amount, digits),
    };
    return displayAmount.toStringAsFixed(digits);
  }

  int get _displayFractionDigits {
    final normalized = symbol.toUpperCase();
    if (normalized == 'ZEC') {
      return 4;
    }
    if (normalized == 'BTC' || normalized == 'WBTC' || decimals == 8) {
      return 8;
    }
    if (normalized == 'ETH' || normalized == 'SOL' || normalized == 'NEAR') {
      return 4;
    }
    return 2;
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
      fallbackExternalPerZec: _fallbackRateFor(symbol),
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

enum _SwapAmountRounding { nearest, down, up }

double _roundDisplayAmountDown(double amount, int fractionDigits) {
  return _roundDisplayAmount(amount, fractionDigits, roundUp: false);
}

double _roundDisplayAmountUp(double amount, int fractionDigits) {
  return _roundDisplayAmount(amount, fractionDigits, roundUp: true);
}

double _roundDisplayAmount(
  double amount,
  int fractionDigits, {
  required bool roundUp,
}) {
  if (!amount.isFinite || amount <= 0) return 0;
  var factor = 1.0;
  for (var i = 0; i < fractionDigits; i++) {
    factor *= 10;
  }
  final scaled = amount * factor;
  final epsilon = scaled.abs() * 1e-12 + 1e-9;
  final rounded = roundUp
      ? (scaled - epsilon).ceilToDouble()
      : (scaled + epsilon).floorToDouble();
  return rounded / factor;
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

List<SwapAsset> sortSwapAssetsForSelection(Iterable<SwapAsset> assets) {
  final indexed = <_IndexedSwapAsset>[];
  final seen = <String>{};
  var order = 0;
  for (final asset in assets) {
    if (seen.add(asset.identityKey)) {
      indexed.add(_IndexedSwapAsset(asset, order));
    }
    order++;
  }
  indexed.sort(_compareIndexedSwapAssetForSelection);
  return [for (final item in indexed) item.asset];
}

class _IndexedSwapAsset {
  const _IndexedSwapAsset(this.asset, this.order);

  final SwapAsset asset;
  final int order;
}

int _compareIndexedSwapAssetForSelection(
  _IndexedSwapAsset left,
  _IndexedSwapAsset right,
) {
  final leftAsset = left.asset;
  final rightAsset = right.asset;
  final routeRank = _compareInt(
    _swapAssetRoutePriority(leftAsset),
    _swapAssetRoutePriority(rightAsset),
  );
  if (routeRank != 0) return routeRank;

  final symbolRank = _compareInt(
    _swapAssetSymbolPriority(leftAsset.symbol),
    _swapAssetSymbolPriority(rightAsset.symbol),
  );
  if (symbolRank != 0) return symbolRank;

  final symbol = _swapAssetSortKey(
    leftAsset.symbol,
  ).compareTo(_swapAssetSortKey(rightAsset.symbol));
  if (symbol != 0) return symbol;

  final chainRank = _compareInt(
    _swapAssetChainPriority(leftAsset.chainTicker),
    _swapAssetChainPriority(rightAsset.chainTicker),
  );
  if (chainRank != 0) return chainRank;

  final chain = leftAsset.chainLabel.compareTo(rightAsset.chainLabel);
  if (chain != 0) return chain;

  final assetId = (leftAsset.assetId ?? leftAsset.name).compareTo(
    rightAsset.assetId ?? rightAsset.name,
  );
  if (assetId != 0) return assetId;

  return _compareInt(left.order, right.order);
}

int _swapAssetRoutePriority(SwapAsset asset) {
  final key =
      '${_swapAssetSortKey(asset.symbol)}:${_swapAssetSortKey(asset.chainTicker)}';
  const priority = <String>[
    'usdc:eth',
    'btc:btc',
    'eth:eth',
    'sol:sol',
    'usdt:eth',
    'near:near',
    'usdc:base',
    'usdc:arb',
    'usdc:sol',
    'usdt:sol',
    'usdt:bsc',
    'usdt:tron',
    'usdc:sui',
    'dai:eth',
    'wbtc:eth',
    'cbbtc:base',
    'weth:eth',
    'doge:doge',
  ];
  final index = priority.indexOf(key);
  return index == -1 ? 1000 : index;
}

int _swapAssetSymbolPriority(String symbol) {
  final key = _swapAssetSortKey(symbol);
  const priority = <String>[
    'usdc',
    'usdt',
    'btc',
    'eth',
    'sol',
    'near',
    'weth',
    'wbtc',
    'cbbtc',
    'xbtc',
    'bnb',
    'doge',
    'xrp',
    'dai',
    'usdt0',
    'susdc',
    'xdai',
  ];
  final index = priority.indexOf(key);
  return index == -1 ? 1000 : index;
}

int _swapAssetChainPriority(String chainTicker) {
  final key = _swapAssetSortKey(chainTicker);
  const priority = <String>[
    'eth',
    'base',
    'arb',
    'sol',
    'near',
    'btc',
    'bsc',
    'tron',
    'sui',
    'aptos',
    'op',
    'avax',
    'gnosis',
    'pol',
    'ton',
    'stellar',
    'xlayer',
    'plasma',
    'zec',
  ];
  final index = priority.indexOf(key);
  return index == -1 ? 1000 : index;
}

String _swapAssetSortKey(String value) {
  return _normalizeIconKey(value).replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

int _compareInt(int left, int right) => left.compareTo(right);

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

String _tokenIconAssetPath(String iconKey) {
  final assetKey = switch (iconKey) {
    'btc(omni)' => 'btc',
    'gtusdcp' || 'mwusdc' || 'sparkusdc' || 'steakusdc' => 'usdc',
    'hemibtc' => 'btc',
    'kv-gtsolb' => 'sol',
    'nrusdt' || 'usdt0' => 'usdt',
    'stnear' => 'near',
    _ => iconKey,
  };
  return 'assets/swap/tokens/$assetKey.png';
}

String _chainIconAssetPath(String iconKey) {
  return switch (iconKey) {
    'abs' => 'assets/swap/chains/eth.png',
    'bsc' => 'assets/swap/tokens/bnb.png',
    'cardano' => 'assets/swap/tokens/ada.png',
    'xlayer' => 'assets/swap/tokens/okb.png',
    _ => 'assets/swap/chains/$iconKey.png',
  };
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
    'abs' => 'Abstract',
    'adi' => 'Adi',
    'aleo' => 'Aleo',
    'aptos' => 'Aptos',
    'arb' => 'Arbitrum',
    'avax' => 'Avalanche',
    'base' => 'Base',
    'bera' => 'Bera',
    'bch' => 'Bitcoin Cash',
    'bsc' => 'Binance Smart Chain',
    'btc' => 'Bitcoin',
    'cardano' => 'Cardano',
    'dash' => 'Dash',
    'doge' => 'Dogecoin',
    'eth' => 'Ethereum',
    'gnosis' => 'Gnosis',
    'ltc' => 'Litecoin',
    'monad' => 'Monad',
    'near' => 'NEAR',
    'op' => 'Optimism',
    'plasma' => 'Plasma',
    'pol' => 'Polygon',
    'scroll' => 'Scroll',
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

double _fallbackRateFor(String symbol) {
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
    double? amount,
    double? sellAmount,
    required this.destination,
    this.mode = SwapQuoteMode.exactInput,
    String? amountText,
    String? sellAmountText,
    this.refundAddress,
    this.dryRun = false,
    this.slippageBps,
    this.deadline,
  }) : assert(
         amount != null || sellAmount != null,
         'SwapQuoteRequest amount is required',
       ),
       amount = amount ?? sellAmount ?? 0,
       amountText = amountText ?? sellAmountText;

  final SwapDirection direction;
  final SwapAsset externalAsset;
  final SwapQuoteMode mode;
  final double amount;
  final String? amountText;
  final String destination;
  final String? refundAddress;
  final bool dryRun;
  final int? slippageBps;
  final Duration? deadline;

  SwapAsset get sellAsset => direction.fromAsset(externalAsset);
  SwapAsset get receiveAsset => direction.toAsset(externalAsset);
  SwapAsset get amountAsset =>
      mode == SwapQuoteMode.exactInput ? sellAsset : receiveAsset;

  double get sellAmount {
    if (mode != SwapQuoteMode.exactInput) {
      throw StateError('Exact-output quote requests do not carry sellAmount');
    }
    return amount;
  }

  String? get sellAmountText =>
      mode == SwapQuoteMode.exactInput ? amountText : null;
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

class SwapProviderRefundInfo {
  const SwapProviderRefundInfo({
    this.minimumDepositText,
    this.refundFeeText,
    this.depositedAmountText,
    this.refundedAmountText,
    this.refundReason,
  });

  final String? minimumDepositText;
  final String? refundFeeText;
  final String? depositedAmountText;
  final String? refundedAmountText;
  final String? refundReason;

  bool get hasAny =>
      minimumDepositText != null ||
      refundFeeText != null ||
      depositedAmountText != null ||
      refundedAmountText != null ||
      refundReason != null;

  SwapProviderRefundInfo merge(SwapProviderRefundInfo? other) {
    if (other == null) return this;
    return SwapProviderRefundInfo(
      minimumDepositText: other.minimumDepositText ?? minimumDepositText,
      refundFeeText: other.refundFeeText ?? refundFeeText,
      depositedAmountText: other.depositedAmountText ?? depositedAmountText,
      refundedAmountText: other.refundedAmountText ?? refundedAmountText,
      refundReason: other.refundReason ?? refundReason,
    );
  }
}

class SwapQuote {
  const SwapQuote({
    required this.direction,
    required this.sellAsset,
    required this.receiveAsset,
    required this.externalAsset,
    this.mode = SwapQuoteMode.exactInput,
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
    this.providerRefundInfo,
  });

  factory SwapQuote.estimate({
    required SwapDirection direction,
    required SwapAsset externalAsset,
    double? amount,
    double? sellAmount,
    SwapQuoteMode mode = SwapQuoteMode.exactInput,
    String providerLabel = 'NEAR Intents',
    String expiryLabel = '07:12',
    DateTime? quoteExpiresAt,
    DateTime? depositDeadline,
    double? externalPerZec,
    int slippageBps = 50,
  }) {
    assert(externalAsset.name != 'zec');
    final quoteAmount = amount ?? sellAmount;
    if (quoteAmount == null) {
      throw ArgumentError('SwapQuote.estimate amount is required');
    }
    final sellAsset = direction.fromAsset(externalAsset);
    final receiveAsset = direction.toAsset(externalAsset);
    final rate = externalPerZec ?? externalAsset.fallbackExternalPerZec;
    final estimatedSellAmount = switch (mode) {
      SwapQuoteMode.exactInput => quoteAmount,
      SwapQuoteMode.exactOutput =>
        direction.sendsZec ? quoteAmount / rate : quoteAmount * rate,
    };
    final receiveAmount = switch (mode) {
      SwapQuoteMode.exactInput =>
        direction.sendsZec ? quoteAmount * rate : quoteAmount / rate,
      SwapQuoteMode.exactOutput => quoteAmount,
    };
    final rateText = direction.sendsZec
        ? '1 ZEC = ${rate.toStringAsFixed(2)} ${externalAsset.symbol}'
        : '1 ${externalAsset.symbol} = ${(1 / rate).toStringAsFixed(4)} ZEC';
    return SwapQuote(
      direction: direction,
      sellAsset: sellAsset,
      receiveAsset: receiveAsset,
      externalAsset: externalAsset,
      mode: mode,
      sellAmount: estimatedSellAmount,
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
  final SwapQuoteMode mode;
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
  final SwapProviderRefundInfo? providerRefundInfo;

  String get pairText => '${sellAsset.symbol} -> ${receiveAsset.symbol}';
  String get sellAmountText =>
      sellAmountTextOverride ??
      '${mode == SwapQuoteMode.exactOutput ? sellAsset.formatAmountUp(sellAmount) : sellAsset.formatAmount(sellAmount)} ${sellAsset.symbol}';
  String get receiveEstimateText =>
      receiveEstimateTextOverride ??
      '${mode == SwapQuoteMode.exactInput ? receiveAsset.formatAmountDown(receiveAmount) : receiveAsset.formatAmount(receiveAmount)} ${receiveAsset.symbol}';
  String get minimumReceiveText =>
      minimumReceiveTextOverride ??
      '${receiveAsset.formatAmountDown(minimumReceiveAmount)} ${receiveAsset.symbol}';

  String get rateText {
    final override = rateTextOverride;
    if (override != null) {
      return override;
    }
    final rate = externalAsset.fallbackExternalPerZec;
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
    this.nearIntentHash,
    this.nearTransactionHash,
    this.originChainTxHash,
    this.destinationChainTxHash,
    this.providerRefundInfo,
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
      providerRefundInfo: quote.providerRefundInfo,
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
  final String? nearIntentHash;
  final String? nearTransactionHash;
  final String? originChainTxHash;
  final String? destinationChainTxHash;
  final SwapProviderRefundInfo? providerRefundInfo;
}

class SwapPricingSnapshot {
  const SwapPricingSnapshot({required this.usdPrices});

  final Map<SwapAsset, double> usdPrices;

  List<SwapAsset> get supportedExternalAssets {
    final zecPrice = usdPrices[SwapAsset.zec];
    if (zecPrice == null || zecPrice <= 0) return const [];
    return sortSwapAssetsForSelection([
      for (final entry in usdPrices.entries)
        if (entry.key != SwapAsset.zec && entry.value > 0) entry.key,
    ]);
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
