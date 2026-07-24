import 'package:flutter/foundation.dart';

import '../../core/config/network_config.dart';
import '../../rust/api/voting_config.dart' as rust_config_api;
import '../../rust/third_party/zcash_voting/config.dart' as rust_config;
import 'voting_http.dart';
import 'voting_models.dart';

/// Production static trust anchor used to discover the mutable voting config.
///
/// The URL itself is expected to stay stable in the app, while the fetched JSON
/// points at the current dynamic service configuration.
const kProductionStaticVotingConfigSource =
    'https://raw.githubusercontent.com/valargroup/token-holder-voting-config/'
    '671f76403eea8aaf64a87cb484c4b0cdaea596db/prod/static-voting-config.json'
    '?checksum=sha256:c06f1dfa2f0a30b3614aefcf00ac7e31d61ebc3cf551b3031d1b194232d1056d';

/// Stage static trust anchor used by public testnet builds.
const kStageStaticVotingConfigSource =
    'https://raw.githubusercontent.com/valargroup/token-holder-voting-config/'
    '491e55306aa5c539a0314d30a8b2c51946b88b73/stage/static-voting-config.json'
    '?checksum=sha256:80890a6de9acc7293c3e2fabf870bb3e5755dbe0e69de4a59feb8f696134d4dc';

/// Bundled voting config for the selected launch network.
const kDefaultStaticVotingConfigSource = kZcashDefaultNetworkRaw == 'test'
    ? kStageStaticVotingConfigSource
    : kProductionStaticVotingConfigSource;

/// Authenticates static config bytes and returns the dynamic config URL to
/// fetch next. Injectable so tests can stub the Rust boundary.
typedef ResolveStaticVotingConfigFn =
    Future<String> Function({
      required String source,
      required List<int> staticBytes,
    });

/// Resolves the full voting config from the static and dynamic config bytes.
/// Injectable so tests can stub the Rust boundary.
typedef ResolveVotingConfigFn =
    Future<rust_config_api.VotingConfigResolution> Function({
      required String source,
      required List<int> staticBytes,
      required List<int> dynamicBytes,
      rust_config.ResolvedVotingConfig? previous,
    });

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
  String raw, {
  bool requireChecksum = false,
}) {
  final trimmed = raw.trim();
  final rawQuery = _extractRawQuery(trimmed);
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
    throw StaticVotingConfigSourceMalformed('not an HTTPS URL: $raw');
  }
  if (parsed.userInfo.isNotEmpty) {
    throw const StaticVotingConfigSourceMalformed(
      'URL must not include user info',
    );
  }
  if (parsed.hasFragment) {
    throw const StaticVotingConfigSourceMalformed(
      'URL must not include a fragment',
    );
  }
  if (_containsEncodedChecksumKey(rawQuery)) {
    throw StaticVotingConfigSourceMalformed(
      'checksum key must be literal "checksum": $raw',
    );
  }

  final queryParametersAll = parsed.queryParametersAll;
  final checksumValues = queryParametersAll['checksum'];
  if (checksumValues != null && checksumValues.length != 1) {
    throw StaticVotingConfigSourceMalformed('checksum must appear once: $raw');
  }
  final checksum = checksumValues?.single;
  if (requireChecksum && checksum == null) {
    throw StaticVotingConfigSourceMalformed(
      'checksum query parameter is required: $raw',
    );
  }
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

  final strippedQuery = _stripChecksumQuery(rawQuery);
  final normalizedBase = Uri(
    scheme: parsed.scheme,
    host: parsed.host,
    port: parsed.hasPort ? parsed.port : null,
    path: parsed.path,
  ).toString();
  final uri = Uri.parse(
    strippedQuery.isEmpty ? normalizedBase : '$normalizedBase?$strippedQuery',
  );
  return (raw: trimmed, uri: uri, sha256Hex: sha256Hex);
}

String _extractRawQuery(String rawUrl) {
  final questionMarkIndex = rawUrl.indexOf('?');
  if (questionMarkIndex == -1 || questionMarkIndex == rawUrl.length - 1) {
    return '';
  }
  final fragmentIndex = rawUrl.indexOf('#', questionMarkIndex + 1);
  final queryEnd = fragmentIndex == -1 ? rawUrl.length : fragmentIndex;
  return rawUrl.substring(questionMarkIndex + 1, queryEnd);
}

bool _containsEncodedChecksumKey(String rawQuery) {
  if (rawQuery.isEmpty) return false;
  for (final segment in rawQuery.split('&')) {
    if (segment.isEmpty) continue;
    final separator = segment.indexOf('=');
    final encodedKey = separator == -1
        ? segment
        : segment.substring(0, separator);
    if (encodedKey == 'checksum') continue;
    final decodedKey = Uri.decodeQueryComponent(encodedKey);
    if (decodedKey == 'checksum') return true;
  }
  return false;
}

String _stripChecksumQuery(String rawQuery) {
  if (rawQuery.isEmpty) return '';
  final kept = <String>[];
  for (final segment in rawQuery.split('&')) {
    if (segment.isEmpty) continue;
    final separator = segment.indexOf('=');
    final encodedKey = separator == -1
        ? segment
        : segment.substring(0, separator);
    final key = Uri.decodeQueryComponent(encodedKey);
    if (key == 'checksum') continue;
    kept.add(segment);
  }
  return kept.join('&');
}

/// Loads the two-stage voting configuration and fails closed on any mismatch.
///
/// The static config is the trust anchor: it may be hash-pinned by the source
/// URL and contains the dynamic config URL plus trusted signing keys. The
/// dynamic config then supplies service endpoints, supported protocol versions,
/// and signed round metadata for later config resolution to verify.
///
/// Transport stays in Dart: this loader fetches the static bytes, asks Rust for
/// the authenticated dynamic config URL, fetches those bytes too, and hands both
/// blobs back to Rust for full resolution. Transport failures surface directly
/// as [VotingHttpException]; Rust only sees config (authenticity) errors.
class VotingConfigLoader {
  VotingConfigLoader({
    required VotingHttpClient httpClient,
    String? sourceUrl,
    Duration timeout = const Duration(seconds: 10),
    ResolveStaticVotingConfigFn resolveStaticVotingConfig =
        rust_config_api.resolveStaticVotingConfig,
    ResolveVotingConfigFn resolveVotingConfig =
        rust_config_api.resolveVotingConfig,
  }) : _httpClient = httpClient,
       _source = parseStaticVotingConfigSource(
         sourceUrl ?? kDefaultStaticVotingConfigSource,
       ),
       _timeout = timeout,
       _resolveStaticVotingConfig = resolveStaticVotingConfig,
       _resolveVotingConfig = resolveVotingConfig;

  final VotingHttpClient _httpClient;
  final ({String raw, Uri uri, String? sha256Hex}) _source;
  final Duration _timeout;
  final ResolveStaticVotingConfigFn _resolveStaticVotingConfig;
  final ResolveVotingConfigFn _resolveVotingConfig;

  /// Resolves config via Rust while keeping transport in Dart.
  ///
  /// Throws [VotingHttpException] when either fetch fails and rethrows the flat
  /// Rust error string when authentication/validation fails.
  Future<rust_config_api.VotingConfigResolution> load({
    rust_config.ResolvedVotingConfig? previous,
  }) async {
    // The raw source carries the hash-pin checksum (verified by Rust over the
    // bytes), but the fetch must hit the checksum-stripped URL.
    final staticBytes = await _fetchBytes(_source.uri);

    final dynamicConfigUrl = await _resolveStaticVotingConfig(
      source: _source.raw,
      staticBytes: staticBytes,
    );

    final dynamicBytes = await _fetchBytes(
      _dynamicConfigTransportUri(dynamicConfigUrl),
    );

    final resolution = await _resolveVotingConfig(
      source: _source.raw,
      staticBytes: staticBytes,
      dynamicBytes: dynamicBytes,
      previous: previous,
    );

    if (resolution.config.skippedRoundIds.isNotEmpty) {
      debugPrint(
        '[zcash] Voting: skipped unauthenticated round ids: '
        '${resolution.config.skippedRoundIds.join(",")}',
      );
    }
    return resolution;
  }

  Future<List<int>> _fetchBytes(Uri uri) async {
    final response = await _httpClient.get(
      uri,
      headers: _configFetchHeaders,
      timeout: _timeout,
    );
    if (response.statusCode != 200) {
      throw VotingHttpException(
        uri: uri,
        statusCode: response.statusCode,
        body: response.bodyText,
      );
    }
    return response.bodyBytes;
  }
}

const _configFetchHeaders = {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'};

Uri _dynamicConfigTransportUri(String dynamicConfigUrl) {
  final uri = Uri.parse(dynamicConfigUrl);
  if (!_isGithubRawBranchUri(uri)) return uri;

  // GitHub raw branch URLs are CDN-cached for several minutes after a merge.
  // The dynamic config is still verified after fetch, so this only changes
  // transport freshness for test/stage configs served directly from GitHub.
  return uri.replace(
    queryParameters: {
      ...uri.queryParametersAll,
      'vizor_cache_bust': [DateTime.now().microsecondsSinceEpoch.toString()],
    },
  );
}

bool _isGithubRawBranchUri(Uri uri) {
  if (uri.scheme != 'https' || uri.host != 'raw.githubusercontent.com') {
    return false;
  }
  final segments = uri.pathSegments;
  if (segments.length < 4) return false;
  final ref = segments[2];
  if (ref == 'refs' &&
      segments.length >= 6 &&
      segments[3] == 'heads' &&
      segments[4].isNotEmpty) {
    return true;
  }
  return !RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(ref);
}
