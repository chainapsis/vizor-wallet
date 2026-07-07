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
