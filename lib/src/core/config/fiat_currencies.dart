/// Fiat display currencies for ZEC prices and balances.
///
/// The set and per-currency display rules (symbol, decimals) mirror Keplr's
/// `FiatCurrencies` config so both Chainapsis wallets present fiat the same
/// way. `code` is the CoinGecko `vs_currency` id — all supported currencies
/// are fetched in the single `/simple/price` call, so switching currency
/// never needs a new network round trip.
class FiatCurrency {
  const FiatCurrency({
    required this.code,
    required this.symbol,
    required this.maxDecimals,
  });

  /// CoinGecko `vs_currency` id, lowercase (e.g. `usd`, `krw`).
  final String code;

  /// Display symbol prefixed to values (e.g. `$`, `₩`).
  final String symbol;

  /// Fraction digits shown for plain (non-compacted) values.
  final int maxDecimals;

  /// Uppercased code for labels ("USD", "KRW").
  String get displayCode => code.toUpperCase();

  /// Picker label — "USD ($)", "KRW (₩)".
  String get pickerLabel => '$displayCode ($symbol)';

  /// Codes are unique within [kSupportedFiatCurrencies], so identity is the
  /// code — lets selections compare with `==` regardless of which const
  /// instance they came from.
  @override
  bool operator ==(Object other) => other is FiatCurrency && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

const kUsdFiatCurrency = FiatCurrency(
  code: 'usd',
  symbol: r'$',
  maxDecimals: 2,
);

const kDefaultFiatCurrency = kUsdFiatCurrency;

const kSupportedFiatCurrencies = <FiatCurrency>[
  kUsdFiatCurrency,
  FiatCurrency(code: 'eur', symbol: '€', maxDecimals: 2),
  FiatCurrency(code: 'gbp', symbol: '£', maxDecimals: 2),
  FiatCurrency(code: 'cad', symbol: 'CA\$', maxDecimals: 2),
  FiatCurrency(code: 'aud', symbol: 'AU\$', maxDecimals: 2),
  FiatCurrency(code: 'krw', symbol: '₩', maxDecimals: 0),
  FiatCurrency(code: 'hkd', symbol: 'HK\$', maxDecimals: 1),
  FiatCurrency(code: 'cny', symbol: '¥', maxDecimals: 1),
  FiatCurrency(code: 'jpy', symbol: '¥', maxDecimals: 0),
  FiatCurrency(code: 'inr', symbol: '₹', maxDecimals: 1),
  FiatCurrency(code: 'chf', symbol: '₣', maxDecimals: 2),
];

/// Resolves a stored currency code back to a supported currency. Unknown or
/// null codes fall back to USD so a stale preference can never break display.
FiatCurrency fiatCurrencyForCode(String? code) {
  if (code == null) return kDefaultFiatCurrency;
  final normalized = code.trim().toLowerCase();
  for (final currency in kSupportedFiatCurrencies) {
    if (currency.code == normalized) return currency;
  }
  return kDefaultFiatCurrency;
}

/// "$1.23" / "$4.56K" / "$7.89M"-style compact fiat text in [currency].
/// Zero-decimal currencies render whole numbers ("₩1,234" stays unformatted
/// grouping-wise: "₩1234" is never reached because values >= 1000 compact to
/// "₩1.23K").
String formatCompactFiatValueFor(FiatCurrency currency, double value) {
  if (!value.isFinite || value <= 0) {
    return '${currency.symbol}${(0.0).toStringAsFixed(currency.maxDecimals)}';
  }
  if (value >= 1000000) {
    return '${currency.symbol}${trimTrailingFiatZeros(value / 1000000, fractionDigits: 3)}M';
  }
  if (value >= 1000) {
    return '${currency.symbol}${trimTrailingFiatZeros(value / 1000, fractionDigits: 2)}K';
  }
  return '${currency.symbol}${value.toStringAsFixed(currency.maxDecimals)}';
}

String trimTrailingFiatZeros(double value, {required int fractionDigits}) {
  var text = value.toStringAsFixed(fractionDigits);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

/// How to render fiat values that originate as USD amounts (swap quotes,
/// captured intent fiat bases): the selected display currency plus the
/// implied USD→currency rate derived from the batched CoinGecko response
/// (`ZEC/<currency> ÷ ZEC/USD`).
///
/// When the selected currency's rate is unavailable (market data not loaded
/// yet, or the response lacked that currency) the display falls back to USD
/// so swap surfaces never go blank or lie about the unit.
class FiatDisplay {
  const FiatDisplay({required this.currency, this.usdToCurrencyRate});

  final FiatCurrency currency;

  /// Multiplier from a USD value to [currency]; null or non-positive means
  /// "cannot convert" and USD is displayed instead.
  final double? usdToCurrencyRate;

  bool get _isUsd => currency.code == kUsdFiatCurrency.code;

  bool get _convertible {
    if (_isUsd) return true;
    final rate = usdToCurrencyRate;
    return rate != null && rate.isFinite && rate > 0;
  }

  /// The currency values are actually rendered in (falls back to USD).
  FiatCurrency get displayCurrency =>
      _convertible ? currency : kUsdFiatCurrency;

  /// Converts a USD amount into [displayCurrency].
  double convertUsd(double usdValue) =>
      displayCurrency.code == kUsdFiatCurrency.code
      ? usdValue
      : usdValue * usdToCurrencyRate!;

  /// Converts an amount typed in [displayCurrency] back to USD.
  double toUsd(double displayValue) =>
      displayCurrency.code == kUsdFiatCurrency.code
      ? displayValue
      : displayValue / usdToCurrencyRate!;

  String get placeholderText => '${displayCurrency.symbol}--';

  String get zeroText => '${displayCurrency.symbol}0';

  /// "$1.23K" / "₹42.5K"-style compact text for a USD-denominated value.
  String formatCompactUsdValue(double usdValue) =>
      formatCompactFiatValueFor(displayCurrency, convertUsd(usdValue));

  /// Value equality so providers rebuilding this from a fresh market-data
  /// snapshot do not notify watchers (whole swap screens) when nothing
  /// user-visible changed — restores the dedup the old `double?` price
  /// provider got for free.
  @override
  bool operator ==(Object other) =>
      other is FiatDisplay &&
      other.currency.code == currency.code &&
      other.usdToCurrencyRate == usdToCurrencyRate;

  @override
  int get hashCode => Object.hash(currency.code, usdToCurrencyRate);
}

const kUsdFiatDisplay = FiatDisplay(
  currency: kUsdFiatCurrency,
  usdToCurrencyRate: 1,
);
