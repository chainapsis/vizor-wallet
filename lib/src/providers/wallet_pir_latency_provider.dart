import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/network_http_client.dart';
import '../rust/api/pir_config.dart' as rust;
import '../services/wallet_pir/wallet_pir_latency.dart';

/// Uses the app's current network route, including Tor. No wallet identifiers
/// or private queries are sent, and redirects are refused.
final walletPirServerProbeProvider = Provider<WalletPirServerProbe>((ref) {
  final client = NetworkHttpClient();
  return (baseUrl, cancelled) => measureWalletPirPing(() async {
    final uri = Uri.parse(rust.walletPirServerPingUrl(baseUrl: baseUrl));
    final response = await client.request(
      'GET',
      uri,
      headers: const {'Cache-Control': 'no-cache'},
      timeout: const Duration(seconds: 5),
      maxRedirects: 0,
      cancelSignal: cancelled,
    );
    return response.statusCode;
  });
});
