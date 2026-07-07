import 'package:zcash_wallet/src/core/config/fiat_currencies.dart';
import 'package:zcash_wallet/src/providers/fiat_currency_provider.dart';

/// Skips the secure-storage read/write so currency selection works without a
/// platform channel in widget tests (unmocked channel futures never
/// complete). Override with
/// `fiatCurrencyProvider.overrideWith(InMemoryFiatCurrencyNotifier.new)`.
class InMemoryFiatCurrencyNotifier extends FiatCurrencyNotifier {
  @override
  FiatCurrency build() => kDefaultFiatCurrency;

  @override
  Future<void> set(FiatCurrency currency) async {
    state = currency;
  }
}
