import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../rust/api/voting_config.dart' as rust_config_api;
import '../../rust/third_party/zcash_voting/config.dart' as rust_config;
import 'voting_http.dart';
import 'voting_models.dart';

/// Hash-pinned static trust anchor used to discover the mutable voting config.
///
/// The URL itself is expected to stay stable in the app, while the fetched JSON
/// points at the current dynamic service configuration.
const kDefaultStaticVotingConfigSource =
    'https://raw.githubusercontent.com/valargroup/token-holder-voting-config/'
    '2785311d45758e85567d70a1f13709fa01b62c6b/prod/static-voting-config.json'
    '?checksum=sha256:bed0116f961226b256a574b52461ce81d9f5294a57e190987dc155f07eb1e431';

typedef ResolveVotingConfigFn = Future<rust_config_api.VotingConfigResolution>
    Function({
      required String source,
      rust_config.ResolvedVotingConfig? previous,
      required FutureOr<rust_config_api.VotingConfigFetch> Function(
        String,
      )
      fetchBytes,
    });

class _CapturedFetchError {
  const _CapturedFetchError(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

class StaticVotingConfigSourceMalformed implements Exception {
  final String message;

  const StaticVotingConfigSourceMalformed(this.message);

  @override
  String toString() => 'StaticVotingConfigSourceMalformed: $message';
}

/// Parses and validates a wallet-provided static config source URL.
///
/// Returns normalized source metadata used for UI identity and source transport.
({String raw, Uri uri, String? sha256Hex}) parseStaticVotingConfigSource(
  String raw,
) {
  final trimmed = raw.trim();
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
    throw StaticVotingConfigSourceMalformed('not an HTTPS URL: $raw');
  }

  final checksum = parsed.queryParameters['checksum'];
  String? sha256Hex;
  if (checksum != null) {
    const prefix = 'sha256:';
    if (!checksum.startsWith(prefix)) {
      throw StaticVotingConfigSourceMalformed(
        'checksum must use sha256: prefix: $raw',
      );
    }
    final checksumHex = checksum.substring(prefix.length);
    final isLowerHex = RegExp(r'^[0-9a-f]+$').hasMatch(checksumHex);
    if (checksumHex.length != 64 || !isLowerHex) {
      throw StaticVotingConfigSourceMalformed(
        'checksum must be 64 lowercase hex chars: $raw',
      );
    }
    sha256Hex = checksumHex;
  }

  final strippedQuery = Map<String, String>.from(parsed.queryParameters)
    ..remove('checksum');
  final uri = Uri(
    scheme: parsed.scheme,
    userInfo: parsed.userInfo,
    host: parsed.host,
    port: parsed.hasPort ? parsed.port : null,
    path: parsed.path,
    queryParameters: strippedQuery.isEmpty ? null : strippedQuery,
    fragment: parsed.fragment.isEmpty ? null : parsed.fragment,
  );
  return (raw: trimmed, uri: uri, sha256Hex: sha256Hex);
}

/// Loads the two-stage voting configuration and fails closed on any mismatch.
///
/// The static config is the trust anchor: it may be hash-pinned by the source
/// URL and contains the dynamic config URL plus trusted signing keys. The
/// dynamic config then supplies service endpoints, supported protocol versions,
/// and signed round metadata for later config resolution to verify.
class VotingConfigLoader {
  VotingConfigLoader({
    required VotingHttpClient httpClient,
    String? sourceUrl,
    Duration timeout = const Duration(seconds: 10),
    ResolveVotingConfigFn resolveVotingConfig = rust_config_api.resolveVotingConfig,
  }) : _httpClient = httpClient,
       _sourceUrl =
           parseStaticVotingConfigSource(
             sourceUrl ?? kDefaultStaticVotingConfigSource,
           ).raw,
       _timeout = timeout,
       _resolveVotingConfig = resolveVotingConfig;

  final VotingHttpClient _httpClient;
  final String _sourceUrl;
  final Duration _timeout;
  final ResolveVotingConfigFn _resolveVotingConfig;
  static const _transportErrorTokenPrefix = '__voting_config_transport_error__:';

  /// Resolves voting config via Rust while keeping transport in Dart.
  Future<rust_config_api.VotingConfigResolution> load({
    rust_config.ResolvedVotingConfig? previous,
  }) async {
    var transportErrorIndex = 0;
    final capturedTransportErrors = <String, _CapturedFetchError>{};
    try {
      final resolution = await _resolveVotingConfig(
        source: _sourceUrl,
        previous: previous,
        fetchBytes: (url) async {
          try {
            final requestUrl = Uri.parse(url);
            final response = await _httpClient.get(requestUrl, timeout: _timeout);
            if (response.statusCode != 200) {
              throw VotingHttpException(
                uri: requestUrl,
                statusCode: response.statusCode,
                body: response.bodyText,
              );
            }
            return rust_config_api.VotingConfigFetch(bytes: response.bodyBytes);
          } catch (error, stackTrace) {
            final token = '$_transportErrorTokenPrefix${transportErrorIndex++}';
            capturedTransportErrors[token] = _CapturedFetchError(
              error,
              stackTrace,
            );
            return rust_config_api.VotingConfigFetch(error: token);
          }
        },
      );
      if (resolution.config.skippedRoundIds.isNotEmpty) {
        debugPrint(
          '[zcash] Voting: skipped unauthenticated round ids: '
          '${resolution.config.skippedRoundIds.join(",")}',
        );
      }
      return resolution;
    } catch (error, stackTrace) {
      final token = _extractTransportErrorToken(error);
      final capturedError = capturedTransportErrors[token];
      if (capturedError != null) {
        Error.throwWithStackTrace(capturedError.error, capturedError.stackTrace);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  String _extractTransportErrorToken(Object error) {
    if (error is String) return error;
    final text = error.toString();
    final markerIndex = text.indexOf(_transportErrorTokenPrefix);
    if (markerIndex == -1) return text;
    final tokenTail = text.substring(markerIndex);
    final tokenMatch = RegExp(
      '^${RegExp.escape(_transportErrorTokenPrefix)}\\d+',
    ).firstMatch(tokenTail);
    return tokenMatch?.group(0) ?? text;
  }
}
