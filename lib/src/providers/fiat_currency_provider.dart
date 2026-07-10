import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/fiat_currencies.dart';
import '../core/storage/app_secure_store.dart';

/// Holds the user's selected fiat display currency (Settings → Currency).
///
/// Defaults to USD. Unlike theme mode this is not hydrated through app
/// bootstrap: fiat text only renders once the first CoinGecko market-data
/// fetch resolves (seconds), so the async preference read (milliseconds)
/// always wins that race and the first painted fiat value is already in the
/// stored currency.
class FiatCurrencyNotifier extends Notifier<FiatCurrency> {
  static final _store = AppSecureStore.instance;

  /// True once the user picked a currency this session. A slow initial
  /// hydration read must never overwrite a newer selection: [set] has
  /// already persisted it, so losing the race would leave storage on the
  /// new currency while this session displays the stale one.
  bool _selectionMade = false;

  @override
  FiatCurrency build() {
    unawaited(_hydrate());
    return kDefaultFiatCurrency;
  }

  Future<void> _hydrate() async {
    try {
      final stored = await _store.readPlain(kFiatCurrencyKey);
      if (_selectionMade || stored == null) return;
      state = fiatCurrencyForCode(stored);
    } catch (_) {
      // Keep the USD default when the preference cannot be read; selection
      // still works for the session and the next set() rewrites the key.
    }
  }

  Future<void> set(FiatCurrency currency) async {
    _selectionMade = true;
    state = currency;
    try {
      await _store.writePlain(kFiatCurrencyKey, currency.code);
    } catch (_) {
      // The selection still applies for this session; the next successful
      // set() rewrites the key.
    }
  }
}

final fiatCurrencyProvider =
    NotifierProvider<FiatCurrencyNotifier, FiatCurrency>(
      FiatCurrencyNotifier.new,
    );
