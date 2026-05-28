import 'package:crypto/crypto.dart';

import 'voting_http.dart';
import 'voting_models.dart';

/// Hash-pinned static trust anchor used to discover the mutable voting config.
///
/// The URL itself is expected to stay stable in the app, while the fetched JSON
/// points at the current dynamic service configuration. The checksum query
/// parameter is stripped before fetching and verified against the raw body.
const kDefaultStaticVotingConfigSource =
    'https://raw.githubusercontent.com/valargroup/token-holder-voting-config/'
    '2785311d45758e85567d70a1f13709fa01b62c6b/prod/static-voting-config.json'
    '?checksum=sha256:bed0116f961226b256a574b52461ce81d9f5294a57e190987dc155f07eb1e431';

class VotingConfigChecksumMismatch implements Exception {
  final Uri uri;
  final String expected;
  final String actual;

  const VotingConfigChecksumMismatch({
    required this.uri,
    required this.expected,
    required this.actual,
  });

  @override
  String toString() =>
      'VotingConfigChecksumMismatch($uri): expected $expected, got $actual';
}

class StaticVotingConfigSourceMalformed implements Exception {
  final String message;

  const StaticVotingConfigSourceMalformed(this.message);

  @override
  String toString() => 'StaticVotingConfigSourceMalformed: $message';
}

class StaticVotingConfigSource {
  final Uri uri;
  final String? sha256Hex;

  const StaticVotingConfigSource({required this.uri, this.sha256Hex});

  /// Parses a source URL of the form `https://...?...checksum=sha256:<hex>`.
  ///
  /// The checksum is metadata for this client, not part of the resource URL, so
  /// callers fetch [uri] and verify the body against [sha256Hex] when present.
  static StaticVotingConfigSource parse(String raw) {
    final parsed = Uri.tryParse(raw);
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      throw StaticVotingConfigSourceMalformed('not an HTTPS URL: $raw');
    }

    final checksum = parsed.queryParameters['checksum'];
    String? sha256Hex;
    if (checksum != null) {
      const prefix = 'sha256:';
      if (!checksum.startsWith(prefix)) {
        throw const StaticVotingConfigSourceMalformed(
          'checksum must start with sha256:',
        );
      }
      sha256Hex = checksum.substring(prefix.length);
      if (sha256Hex.length != 64 ||
          !RegExp(r'^[0-9a-f]+$').hasMatch(sha256Hex)) {
        throw StaticVotingConfigSourceMalformed(
          'sha256 must be 64 lowercase hex chars; got ${sha256Hex.length}',
        );
      }
    }

    final strippedQuery = Map<String, String>.from(parsed.queryParameters)
      ..remove('checksum');
    return StaticVotingConfigSource(
      uri: Uri(
        scheme: parsed.scheme,
        userInfo: parsed.userInfo,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : null,
        path: parsed.path,
        queryParameters: strippedQuery.isEmpty ? null : strippedQuery,
        fragment: parsed.fragment.isEmpty ? null : parsed.fragment,
      ),
      sha256Hex: sha256Hex,
    );
  }
}

/// Loads the two-stage voting configuration and fails closed on any mismatch.
///
/// The static config is the trust anchor: it may be hash-pinned by the source
/// URL and contains the dynamic config URL plus trusted signing keys. The
/// dynamic config then supplies service endpoints, supported protocol versions,
/// and the authenticated round registry used by higher layers.
class VotingConfigLoader {
  VotingConfigLoader({
    required VotingHttpClient httpClient,
    StaticVotingConfigSource? staticConfigSource,
    Duration timeout = const Duration(seconds: 10),
  }) : _httpClient = httpClient,
       _staticConfigSource =
           staticConfigSource ??
           StaticVotingConfigSource.parse(kDefaultStaticVotingConfigSource),
       _timeout = timeout;

  final VotingHttpClient _httpClient;
  final StaticVotingConfigSource _staticConfigSource;
  final Duration _timeout;

  /// Fetches the static trust anchor first, then follows its dynamic config URL.
  Future<VotingConfig> load() async {
    final staticConfig = await loadStaticConfig();
    return loadDynamicConfig(staticConfig.dynamicConfigUrl);
  }

  /// Fetches and validates only the static trust anchor.
  ///
  /// This is exposed separately so providers can surface more precise failures
  /// and tests can verify checksum behavior without contacting the dynamic URL.
  Future<StaticVotingConfig> loadStaticConfig() async {
    final source = _staticConfigSource;
    final response = await _httpClient.get(source.uri, timeout: _timeout);
    if (response.statusCode != 200) {
      throw VotingHttpException(
        uri: source.uri,
        statusCode: response.statusCode,
        body: response.bodyText,
      );
    }
    _verifyChecksumIfPresent(source, response.bodyBytes);
    final staticConfig = StaticVotingConfig.fromJson(
      response.decodeJsonObject(),
    );
    staticConfig.validate();
    return staticConfig;
  }

  /// Fetches and validates a dynamic service configuration.
  ///
  /// There is intentionally no bundled fallback: stale endpoint or round data
  /// could make the wallet submit to the wrong service or authenticate the wrong
  /// round, so malformed or unavailable config remains an explicit error.
  Future<VotingConfig> loadDynamicConfig(Uri dynamicConfigUrl) async {
    final response = await _httpClient.get(dynamicConfigUrl, timeout: _timeout);
    if (response.statusCode != 200) {
      throw VotingHttpException(
        uri: dynamicConfigUrl,
        statusCode: response.statusCode,
        body: response.bodyText,
      );
    }
    final config = VotingConfig.fromJson(response.decodeJsonObject());
    config.validate();
    return config;
  }

  static void _verifyChecksumIfPresent(
    StaticVotingConfigSource source,
    List<int> bodyBytes,
  ) {
    final expected = source.sha256Hex;
    if (expected == null) return;

    final actual = sha256.convert(bodyBytes).toString();
    if (actual != expected) {
      throw VotingConfigChecksumMismatch(
        uri: source.uri,
        expected: expected,
        actual: actual,
      );
    }
  }
}
