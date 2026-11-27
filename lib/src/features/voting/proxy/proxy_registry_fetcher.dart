import 'package:flutter/foundation.dart';

import '../../../services/voting/voting_http.dart';
import 'proxy_delegation_models.dart';

/// Whether [host] may serve proxy registry documents or proofs on
/// [network]: HTTPS, or HTTP to a loopback host on regtest for the local
/// harness. The URL lists are unsigned, so nothing else is fetched.
bool proxyRegistryHostAllowed(String network, Uri host) {
  if (host.host.isEmpty || host.userInfo.isNotEmpty) return false;
  if (host.scheme == 'https') return true;
  return network == 'regtest' &&
      host.scheme == 'http' &&
      const {'127.0.0.1', 'localhost', '::1'}.contains(host.host);
}

/// GETs proxy registry documents from mirrors in order: Vizor's wallet list
/// from the URLs the build names (contracts-v1 section 12.3).
///
/// An answer counts only when the caller's zcash_voting check accepts it, so
/// a mirror serving a bad document is passed over like one that is down.
class ProxyRegistryFetcher {
  /// Creates the fetcher over [http].
  ProxyRegistryFetcher(this.http, {this.timeout = const Duration(seconds: 10)});

  /// Route-aware HTTP.
  final VotingHttpClient http;

  /// Longest wait for one mirror.
  final Duration timeout;

  /// Largest document accepted: the wallet list's 4 MiB cap (contracts-v1
  /// section 15.1). The transport stops reading past it, so an oversized
  /// answer is passed over without being held.
  static const maxResponseBytes = 4 * 1024 * 1024;

  /// Headers for documents that change while a round runs.
  static const noCache = {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'};

  /// The first answer among [urls] that [accept] returns a value for,
  /// trying each in order, or null when no mirror gives one. [accept]
  /// throws to refuse an answer, or returns null for one that is valid but
  /// brings nothing new, such as an unchanged list: either way the next
  /// mirror is tried. [role] names the document in logs. Never throws.
  Future<T?> first<T>({
    required String network,
    required Iterable<String> urls,
    required String role,
    required Future<T> Function(Uint8List body) accept,
    Map<String, String>? headers,
  }) async {
    for (final url in urls) {
      final uri = Uri.tryParse(url);
      if (uri == null || !proxyRegistryHostAllowed(network, uri)) continue;
      try {
        final response = await http.get(
          uri,
          headers: headers,
          timeout: timeout,
          maxBodyBytes: maxResponseBytes,
        );
        if (response.statusCode != 200) {
          throw _UnusableAnswer('status ${response.statusCode}');
        }
        if (response.bodyBytes.length > maxResponseBytes) {
          throw _UnusableAnswer('${response.bodyBytes.length} bytes');
        }
        final value = await accept(response.bodyBytes);
        if (value != null) return value;
      } catch (error) {
        final reason = error is _UnusableAnswer
            ? error.reason
            : describeProxyRegistryError(error);
        debugPrint(
          '[zcash] Proxy registry: $role mirror ${uri.host} passed over: '
          '$reason',
        );
      }
    }
    return null;
  }
}

/// A mirror answer that is not a document; carries no body.
class _UnusableAnswer implements Exception {
  const _UnusableAnswer(this.reason);

  /// The status or size that made the answer unusable.
  final String reason;
}
