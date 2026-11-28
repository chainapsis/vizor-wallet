import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../services/voting/voting_api_client.dart';
import '../../../services/voting/voting_http.dart';
import 'delegate_error_log.dart';
import 'proxy_registry_fetcher.dart';

/// The verifier API's network role (contracts section 12.4): delegate mode
/// posts zcash_voting's attest request to the round config's
/// `verifier_api_urls`, in order (see [post] for failover). Nothing a
/// request names is logged.
class DelegateVerifierClient {
  /// Creates the client over [http].
  DelegateVerifierClient(
    this.http, {
    this.timeout = const Duration(seconds: 30),
  });

  /// Route-aware HTTP.
  final VotingHttpClient http;

  /// Longest wait for one host: the verifier checks the post with the
  /// provider before it answers.
  final Duration timeout;

  /// Largest answer accepted; the transport stops reading past it.
  static const maxResponseBytes = 64 * 1024;

  /// Posts [body] to [path] under each of [urls] in turn and returns what
  /// [accept] makes of the first usable answer, or null when no host gave
  /// a JSON answer.
  ///
  /// [accept] reads one JSON answer. It returns the result, throws
  /// [DelegateVerifierAnswerUnusable] for an answer that is not the API's,
  /// which moves on to the next host, or throws anything else to end the
  /// call, as a valid refusal does. When every answer was unusable, the
  /// last one's cause is thrown.
  Future<T?> post<T>({
    required String network,
    required Iterable<String> urls,
    required String path,
    required Uint8List body,
    required Future<T> Function(VotingChainAnswer answer) accept,
  }) async {
    final decoded = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    Object? unusable;
    for (final url in urls) {
      final base = Uri.tryParse(url);
      if (base == null || !proxyRegistryHostAllowed(network, base)) continue;
      final VotingChainAnswer answer;
      try {
        final response = await http.postJson(
          _join(base, path),
          decoded,
          timeout: timeout,
          maxBodyBytes: maxResponseBytes,
        );
        final bytes = response.bodyBytes;
        if (bytes.length > maxResponseBytes) {
          throw _NotAnAnswer('${bytes.length} bytes');
        }
        if (!_isJsonObject(bytes)) {
          throw _NotAnAnswer('status ${response.statusCode} without JSON');
        }
        answer = VotingChainAnswer(response.statusCode, bytes);
      } catch (error) {
        _passOver(base, error is _NotAnAnswer ? error.reason : null, error);
        continue;
      }
      try {
        return await accept(answer);
      } on DelegateVerifierAnswerUnusable catch (error) {
        unusable = error.cause;
        _passOver(
          base,
          'status ${answer.statusCode} is not the API\'s', // l10n-ignore: log message
          null,
        );
      }
    }
    if (unusable != null) throw unusable;
    return null;
  }

  /// Logs that the host at [base] was passed over for [reason], or for
  /// [error] when no reason is given.
  static void _passOver(Uri base, String? reason, Object? error) {
    debugPrint(
      '[zcash] Delegate mode: verifier ${base.host} passed over: '
      '${reason ?? describeDelegateError(error!)}',
    );
  }

  /// [path] under [base], keeping the base URL's own path.
  static Uri _join(Uri base, String path) => base.replace(
    pathSegments: [
      ...base.pathSegments.where((segment) => segment.isNotEmpty),
      ...Uri.parse(path).pathSegments.where((segment) => segment.isNotEmpty),
    ],
  );

  /// Whether [bytes] are a JSON object.
  static bool _isJsonObject(Uint8List bytes) {
    try {
      return jsonDecode(utf8.decode(bytes)) is Map;
    } catch (_) {
      return false;
    }
  }
}

/// Thrown by a [DelegateVerifierClient.post] reader for a JSON answer that
/// is not the verifier API's, such as a 200 without the attestation's
/// fields or an error code without its paired status: the next host is
/// asked.
class DelegateVerifierAnswerUnusable implements Exception {
  /// Creates the exception for [cause].
  const DelegateVerifierAnswerUnusable(this.cause);

  /// What the reader made of the answer; thrown when no host answers
  /// usably.
  final Object cause;

  @override
  String toString() => 'DelegateVerifierAnswerUnusable($cause)';
}

/// A host answer that is not the verifier API's; carries no body.
class _NotAnAnswer implements Exception {
  const _NotAnAnswer(this.reason);

  /// The status or size that made the answer unusable.
  final String reason;
}
