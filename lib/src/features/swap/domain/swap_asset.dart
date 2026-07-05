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

  /// USDC on Base (second EVM chain — see [ethBase]).
  static const usdcBase = SwapAsset._(
    name: 'usdc_base',
    symbol: 'USDC',
    displayName: 'USD Coin',
    chainTicker: 'base',
    chainLabel: 'Base',
    railLabel: 'Base USDC',
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

  /// ETH on Base. Same token, different EVM chain — the swap backend and the
  /// wallet select the chain from [chainTicker] (`base`), so this is how the
  /// in-app chain selector offers the second EVM chain.
  static const ethBase = SwapAsset._(
    name: 'eth_base',
    symbol: 'ETH',
    displayName: 'Ether',
    chainTicker: 'base',
    chainLabel: 'Base',
    railLabel: 'Base ETH',
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
    usdcBase,
    eth,
    ethBase,
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
    final baseDigits = _displayFractionDigits;
    final digits = _displayFractionDigitsFor(amount, baseDigits);
    final displayAmount = switch (rounding) {
      _SwapAmountRounding.nearest => amount,
      _SwapAmountRounding.down => _roundDisplayAmountDown(amount, digits),
      _SwapAmountRounding.up => _roundDisplayAmountUp(amount, digits),
    };
    final text = displayAmount.toStringAsFixed(digits);
    // Only the precision-boosted (sub-0.001 fine-grained) path can leave
    // trailing zeros; trim them back to the base width so a clean amount
    // stays clean while a small one keeps its significant figures.
    return digits > baseDigits ? _trimTrailingZeros(text, baseDigits) : text;
  }

  /// Fine-grained assets (ETH/SOL/NEAR) are natively high-decimal but display
  /// at [_displayFractionDigits] (4) for readability. That is far too coarse
  /// for sub-0.001 amounts: 0.00014835 ETH would render as "0.0001", which no
  /// longer matches the attested rate the review shows nor the amount actually
  /// delivered on-chain. For amounts below 0.001 widen to ~4 significant
  /// figures (capped at 8 decimals) so the composer, review, and settled
  /// amounts read consistently; larger amounts keep the clean 4-decimal form.
  int _displayFractionDigitsFor(double amount, int baseDigits) {
    final normalized = symbol.toUpperCase();
    final fineGrained =
        normalized == 'ETH' || normalized == 'SOL' || normalized == 'NEAR';
    if (!fineGrained) return baseDigits;
    final abs = amount.abs();
    if (!abs.isFinite || abs == 0 || abs >= 0.001) return baseDigits;
    var leadingZeros = 0;
    var threshold = 0.1;
    while (abs < threshold && leadingZeros < 8) {
      leadingZeros++;
      threshold /= 10;
    }
    return (leadingZeros + 4).clamp(baseDigits, 8).toInt();
  }

  static String _trimTrailingZeros(String text, int minFractionDigits) {
    if (!text.contains('.')) return text;
    final parts = text.split('.');
    var frac = parts[1];
    while (frac.length > minFractionDigits && frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    return frac.isEmpty ? parts[0] : '${parts[0]}.$frac';
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
  SwapAsset.usdcBase,
  SwapAsset.eth,
  SwapAsset.ethBase,
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

String formatSwapProtectionPercent(double percent) {
  if (!percent.isFinite || percent <= 0) return '0.0%';
  // Round to 2 decimals first: a sub-1 value (e.g. 0.999) can round up to
  // 1.00, which must read like the >= 1 case ("1.0%") rather than collapse
  // to "1." once the trailing zeros are trimmed below.
  final rounded = (percent * 100).round() / 100;
  if (rounded >= 1) return '${rounded.toStringAsFixed(1)}%';
  var text = rounded.toStringAsFixed(2);
  while (text.endsWith('0') && text.contains('.')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return '$text%';
}

String formatSwapProtectionAmount(SwapAsset asset, double amount) {
  if (!amount.isFinite || amount <= 0) return asset.formatAmount(0);
  final displayFractionDigits = asset._displayFractionDigits;
  final maxFractionDigits = _swapProtectionMaxFractionDigits(asset);
  var fractionDigits = displayFractionDigits;
  while (fractionDigits < maxFractionDigits &&
      amount < _minimumVisibleDisplayAmount(fractionDigits)) {
    fractionDigits++;
  }
  final minimumVisibleAmount = _minimumVisibleDisplayAmount(fractionDigits);
  if (amount < minimumVisibleAmount) {
    return '<${minimumVisibleAmount.toStringAsFixed(fractionDigits)}';
  }
  return _trimSwapFixedAmount(amount, fractionDigits);
}

int _swapProtectionMaxFractionDigits(SwapAsset asset) {
  const maxReadableFractionDigits = 8;
  final tokenFractionDigits = asset.decimals < maxReadableFractionDigits
      ? asset.decimals
      : maxReadableFractionDigits;
  return tokenFractionDigits > asset._displayFractionDigits
      ? tokenFractionDigits
      : asset._displayFractionDigits;
}

String _trimSwapFixedAmount(double amount, int fractionDigits) {
  var text = amount.toStringAsFixed(fractionDigits);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

double _minimumVisibleDisplayAmount(int fractionDigits) {
  var value = 1.0;
  for (var i = 0; i < fractionDigits; i++) {
    value /= 10;
  }
  return value;
}
