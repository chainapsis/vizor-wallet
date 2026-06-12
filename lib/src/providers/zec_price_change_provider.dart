import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../core/config/swap_feature_config.dart';

/// 24h ZEC price change source. The production implementation queries the
/// Chainapsis satellite service (the same backend the Keplr extension uses
/// for its 24h change badges); tests substitute a fake.
abstract interface class ZecPriceChange24hSource {
  /// Returns the 24h change in percentage points (e.g. `-0.26` for -0.26%),
  /// or null when the value is unavailable.
  Future<double?> fetchChangePct();
}

class SatelliteZecPriceChange24hSource implements ZecPriceChange24hSource {
  SatelliteZecPriceChange24hSource({
    HttpClient? client,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? HttpClient();

  static final _endpoint = Uri.parse(
    'https://satellite.keplr.app/price/changes/24h?ids=zcash',
  );

  final HttpClient _client;
  final Duration timeout;

  @override
  Future<double?> fetchChangePct() async {
    try {
      final request = await _client.getUrl(_endpoint).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        log('zecPriceChange24h: satellite returned ${response.statusCode}');
        return null;
      }
      return parseZecPriceChange24hPct(body);
    } catch (e) {
      log('zecPriceChange24h: fetch failed: $e');
      return null;
    }
  }
}

/// Parses a satellite `/price/changes/24h` response body into the zcash
/// percentage. Returns null when the id is absent — satellite omits ids its
/// subscriber has not tracked yet (the first request registers the id and a
/// ~3-minute backend loop fills it in), so an empty `{}` is a normal warm-up
/// state rather than an error.
double? parseZecPriceChange24hPct(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return null;
    final value = decoded['zcash'];
    if (value is! num) return null;
    final pct = value.toDouble();
    return pct.isFinite ? pct : null;
  } catch (_) {
    return null;
  }
}

/// Matches satellite's own refresh cadence; polling faster cannot observe
/// new values, and the poll doubles as the retry for the warm-up case above.
const zecPriceChange24hRefreshInterval = Duration(minutes: 3);

final zecPriceChange24hSourceProvider = Provider<ZecPriceChange24hSource>((
  ref,
) {
  return SatelliteZecPriceChange24hSource();
});

/// Latest known 24h ZEC price change in percentage points, or null until the
/// first successful fetch. Stays on the last known value across transient
/// fetch failures. Null while the swap feature is disabled (testnet/regtest),
/// mirroring [zecUsdUnitPriceProvider]'s gating so the badge and the fiat
/// sub-label it rides on appear together.
final zecPriceChange24hPctProvider =
    NotifierProvider.autoDispose<ZecPriceChange24hNotifier, double?>(
      ZecPriceChange24hNotifier.new,
    );

class ZecPriceChange24hNotifier extends Notifier<double?> {
  Timer? _timer;
  int _epoch = 0;

  @override
  double? build() {
    _timer?.cancel();
    final epoch = ++_epoch;
    if (!ref.watch(swapFeatureEnabledProvider)) return null;
    final source = ref.watch(zecPriceChange24hSourceProvider);

    ref.onDispose(() {
      _epoch++;
      _timer?.cancel();
    });

    Future<void> tick() async {
      final pct = await source.fetchChangePct();
      if (epoch != _epoch) return;
      if (pct != null) state = pct;
      _timer = Timer(zecPriceChange24hRefreshInterval, () => unawaited(tick()));
    }

    scheduleMicrotask(() {
      if (epoch == _epoch) unawaited(tick());
    });
    return null;
  }
}

/// Rounds to the displayed 2-decimal precision so text and color agree —
/// e.g. -0.004 renders as a neutral "0.00%", not a red zero.
double roundZecPriceChange24hPct(double pct) {
  return double.parse(pct.toStringAsFixed(2));
}

/// "+ 1.25% (24h)" / "- 0.26% (24h)" / "0.00% (24h)" badge text for a 24h
/// change percentage. The space between the sign and the number follows the
/// Figma Home Card spec ("+ 13.12% (24h)").
String formatZecPriceChange24hPct(double pct) {
  final rounded = roundZecPriceChange24hPct(pct);
  if (rounded == 0) return '0.00% (24h)';
  return rounded > 0
      ? '+ ${rounded.toStringAsFixed(2)}% (24h)'
      : '- ${rounded.abs().toStringAsFixed(2)}% (24h)';
}
