import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/config/network_config.dart';
import '../../rust/api/voting.dart' as rust_config_api;
import '../../rust/third_party/zcash_voting/config.dart' as rust_config;
import 'voting_http.dart';
import 'voting_models.dart';

/// Production static trust anchor used to discover the mutable voting config.
///
/// This is mirror 0 — the canonical gateway copy, and the string that identifies
/// the bundled default everywhere else in the app (settings display, saved
/// source dedupe, config-switch bookkeeping). The full ordered mirror list the
/// loader actually walks is [kProductionStaticVotingConfigMirrors].
const kProductionStaticVotingConfigSource =
    'https://voting.valargroup.dev/pins/prod/'
    '28fc9b631091ae8bc2f8635d8930489238ce144174cbd15a03efb0530b301ebe/'
    'v2-static-voting-config.json'
    '?checksum=sha256:28fc9b631091ae8bc2f8635d8930489238ce144174cbd15a03efb0530b301ebe';

/// Independent origin serving the byte-identical production trust anchor.
const kProductionStaticVotingConfigMirror =
    'https://raw.githubusercontent.com/valargroup/token-holder-voting-config/main/'
    'pins/prod/28fc9b631091ae8bc2f8635d8930489238ce144174cbd15a03efb0530b301ebe/'
    'v2-static-voting-config.json'
    '?checksum=sha256:28fc9b631091ae8bc2f8635d8930489238ce144174cbd15a03efb0530b301ebe';

/// Stage static trust anchor used by public testnet builds. See
/// [kProductionStaticVotingConfigSource] for what mirror 0 means.
const kStageStaticVotingConfigSource =
    'https://voting.valargroup.dev/pins/stage/'
    '17484ebabab92225205a02a962add09f1659c9798c2e2e325bd8eac56ab3bf8f/'
    'v2-static-voting-config.json'
    '?checksum=sha256:17484ebabab92225205a02a962add09f1659c9798c2e2e325bd8eac56ab3bf8f';

/// Independent origin serving the byte-identical stage trust anchor.
const kStageStaticVotingConfigMirror =
    'https://raw.githubusercontent.com/valargroup/token-holder-voting-config/main/'
    'pins/stage/17484ebabab92225205a02a962add09f1659c9798c2e2e325bd8eac56ab3bf8f/'
    'v2-static-voting-config.json'
    '?checksum=sha256:17484ebabab92225205a02a962add09f1659c9798c2e2e325bd8eac56ab3bf8f';

/// Ordered production trust-anchor mirrors, canonical origin first.
///
/// Every entry carries the same `?checksum=sha256:` pin, so whichever origin
/// answers, Rust authenticates the same bytes. A second origin widens
/// availability only: it cannot introduce bytes the pin does not already cover.
const kProductionStaticVotingConfigMirrors = <String>[
  kProductionStaticVotingConfigSource,
  kProductionStaticVotingConfigMirror,
];

/// Ordered stage trust-anchor mirrors, canonical origin first.
const kStageStaticVotingConfigMirrors = <String>[
  kStageStaticVotingConfigSource,
  kStageStaticVotingConfigMirror,
];

/// Bundled voting config for the selected launch network.
const kDefaultStaticVotingConfigSource = kZcashDefaultNetworkRaw == 'test'
    ? kStageStaticVotingConfigSource
    : kProductionStaticVotingConfigSource;

/// Mirrors for the selected launch network's bundled trust anchor.
const kDefaultStaticVotingConfigMirrors = kZcashDefaultNetworkRaw == 'test'
    ? kStageStaticVotingConfigMirrors
    : kProductionStaticVotingConfigMirrors;

/// Authenticates static config bytes and returns the ordered dynamic config
/// mirrors to walk next. Injectable so tests can stub the Rust boundary.
typedef ResolveStaticVotingConfigFn =
    Future<List<String>> Function({
      required String source,
      required List<int> staticBytes,
    });

/// Resolves the full voting config from the static bytes plus the accumulated
/// per-mirror dynamic fetch outcomes. Injectable so tests can stub the Rust
/// boundary.
typedef ResolveVotingConfigFromAttemptsFn =
    Future<rust_config_api.VotingConfigResolution> Function({
      required String source,
      required List<int> staticBytes,
      required List<rust_config_api.ApiDynamicConfigAttempt> attempts,
      rust_config.ResolvedVotingConfig? previous,
    });

class StaticVotingConfigSourceMalformed implements Exception {
  final String message;

  const StaticVotingConfigSourceMalformed(this.message);

  @override
  String toString() => 'StaticVotingConfigSourceMalformed: $message';
}

/// Which of the two mirrored fetch stages a mirror failure came from.
enum VotingConfigMirrorStage { staticAnchor, dynamicConfig }

/// Why a mirror was passed over.
///
/// The distinction is the point: [transport] means the origin never answered
/// usable bytes, while [integrity] means it *did* answer and Rust rejected what
/// it served — a hash-pin mismatch, a bad signature, an unsupported version.
/// An [integrity] failure is the strongest tamper signal the wallet has, and it
/// must stay visible even when a later mirror rescues the load.
enum VotingConfigMirrorFailureKind { transport, integrity }

/// One mirror the loader passed over, and why.
///
/// Reported through [VotingConfigLoader.onMirrorFailure] as a side channel:
/// mirroring means a failure here is routinely survivable, so it must not be
/// conflated with the load's own success or failure.
class VotingConfigMirrorFailure {
  const VotingConfigMirrorFailure({
    required this.stage,
    required this.url,
    required this.kind,
    required this.error,
  });

  final VotingConfigMirrorStage stage;

  /// The mirror's transport URL, with any hash pin already stripped.
  final String url;

  final VotingConfigMirrorFailureKind kind;
  final Object error;

  bool get isIntegrityFailure =>
      kind == VotingConfigMirrorFailureKind.integrity;

  @override
  String toString() =>
      'VotingConfigMirrorFailure(${stage.name}, ${kind.name}, $url: $error)';
}

/// Classifies a per-mirror failure as transport or integrity.
///
/// Transport is the closed set of "the origin never gave us usable bytes"
/// outcomes that [isRetryableVotingError] already reasons about. Everything
/// else reached Rust with bytes in hand and was rejected there, so it is
/// treated as an integrity failure — erring toward over-reporting a tamper
/// signal rather than silently classifying a novel error as a network blip.
VotingConfigMirrorFailureKind classifyVotingConfigMirrorFailure(Object error) {
  if (error is VotingHttpException ||
      error is TimeoutException ||
      error is SocketException ||
      error is HttpException) {
    return VotingConfigMirrorFailureKind.transport;
  }
  return VotingConfigMirrorFailureKind.integrity;
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

typedef _StaticSource = ({String raw, Uri uri, String? sha256Hex});

/// Loads the two-stage voting configuration and fails closed on any mismatch.
///
/// The static config is the trust anchor: it may be hash-pinned by the source
/// URL and contains the dynamic config mirrors plus trusted signing keys. The
/// dynamic config then supplies service endpoints, supported protocol versions,
/// and signed round metadata for later config resolution to verify.
///
/// Both stages are mirrored. The bundled trust anchor ships as an ordered list
/// of hash-pinned URLs on independent origins, and the authenticated static
/// config names its own ordered list of dynamic config mirrors. Each list is
/// walked lazily and stops at the first mirror that answers, so a healthy
/// primary costs exactly one request per stage.
///
/// Every mirror the walk passes over is reported through [onMirrorFailure],
/// classified as transport or integrity. That channel exists because mirroring
/// decouples "a mirror was rejected" from "the load failed": once a fallback
/// rescues the load, the return value carries no trace that the canonical
/// origin served bytes failing its hash pin.
/// Mirroring widens availability only: the static hash pin still covers the
/// trust anchor and every round is still authenticated against the static
/// trusted keys, so a mirror can serve a stale round set but cannot forge one.
///
/// Transport stays in Dart: this loader fetches the static bytes, asks Rust for
/// the authenticated dynamic config mirrors, fetches those in turn, and hands
/// the accumulated outcomes back to Rust for full resolution. Transport failures
/// surface directly as [VotingHttpException]; Rust only sees config
/// (authenticity) errors.
class VotingConfigLoader {
  VotingConfigLoader({
    required VotingHttpClient httpClient,
    String? sourceUrl,
    Duration timeout = const Duration(seconds: 10),
    ResolveStaticVotingConfigFn resolveStaticVotingConfig =
        rust_config_api.resolveStaticVotingConfig,
    ResolveVotingConfigFromAttemptsFn resolveVotingConfigFromAttempts =
        rust_config_api.resolveVotingConfigFromAttempts,
    this.onMirrorFailure,
  }) : _sources = _resolveSources(sourceUrl),
       _httpClient = httpClient,
       _timeout = timeout,
       _resolveStaticVotingConfig = resolveStaticVotingConfig,
       _resolveVotingConfigFromAttempts = resolveVotingConfigFromAttempts;

  /// Side channel for every mirror the loader passes over.
  ///
  /// Called for both stages and both failure kinds, including on loads that
  /// ultimately succeed. Mirroring makes a rejected mirror survivable, so the
  /// thrown error can no longer be the only record of one: a hash-pin mismatch
  /// on the canonical origin is invisible in the return value precisely because
  /// the fallback worked. Callers that care about tamper signals watch this.
  final void Function(VotingConfigMirrorFailure failure)? onMirrorFailure;

  /// Ordered static trust-anchor mirrors to walk, canonical origin first.
  ///
  /// A user-selected custom source is a single entry: only the bundled default
  /// ships a reviewed mirror list, so an arbitrary URL never gains a fallback
  /// origin the user did not ask for.
  static List<_StaticSource> _resolveSources(String? sourceUrl) {
    final trimmed = sourceUrl?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return _parseAll(kDefaultStaticVotingConfigMirrors);
    }
    final parsed = parseStaticVotingConfigSource(trimmed);
    for (final mirrors in const [
      kProductionStaticVotingConfigMirrors,
      kStageStaticVotingConfigMirrors,
    ]) {
      final canonical = parseStaticVotingConfigSource(mirrors.first);
      if (canonical.uri == parsed.uri &&
          canonical.sha256Hex == parsed.sha256Hex) {
        return _parseAll(mirrors);
      }
    }
    return [parsed];
  }

  static List<_StaticSource> _parseAll(List<String> raw) {
    return [for (final url in raw) parseStaticVotingConfigSource(url)];
  }

  final VotingHttpClient _httpClient;
  final List<_StaticSource> _sources;
  final Duration _timeout;
  final ResolveStaticVotingConfigFn _resolveStaticVotingConfig;
  final ResolveVotingConfigFromAttemptsFn _resolveVotingConfigFromAttempts;

  /// Resolves config via Rust while keeping transport in Dart.
  ///
  /// Throws [VotingHttpException] when every mirror of a stage fails to fetch,
  /// and rethrows the flat Rust error string when authentication/validation
  /// fails on every mirror. Preserving the transport exception type matters:
  /// `isRetryableVotingError` keys the retry and last-good-config paths off it.
  Future<rust_config_api.VotingConfigResolution> load({
    rust_config.ResolvedVotingConfig? previous,
  }) async {
    final (source, staticBytes, dynamicUrls) = await _resolveStaticAnchor();
    final resolution = await _walkDynamicMirrors(
      source: source,
      staticBytes: staticBytes,
      dynamicUrls: dynamicUrls,
      previous: previous,
    );

    for (final mirror in resolution.skippedMirrors) {
      debugPrint(
        '[zcash] Voting: skipped dynamic config mirror '
        '${mirror.url}: ${mirror.reason}',
      );
    }
    if (resolution.config.skippedRoundIds.isNotEmpty) {
      debugPrint(
        '[zcash] Voting: skipped unauthenticated round ids: '
        '${resolution.config.skippedRoundIds.join(",")}',
      );
    }
    return resolution;
  }

  /// Walks the static mirrors and returns the first that fetches and
  /// authenticates, with the dynamic mirrors it names.
  ///
  /// A mirror is passed over both when its fetch fails and when Rust rejects
  /// its bytes: an origin serving stale or truncated content must not be fatal
  /// while another origin may still hold the pinned bytes. When every mirror
  /// fails, the first failure is rethrown, so a transport outage still surfaces
  /// as [VotingHttpException] rather than as a config error.
  Future<(String, Uint8List, List<String>)> _resolveStaticAnchor() async {
    Object? firstError;
    StackTrace? firstStackTrace;

    for (final source in _sources) {
      try {
        // The raw source carries the hash-pin checksum (verified by Rust over
        // the bytes), but the fetch must hit the checksum-stripped URL.
        final staticBytes = await _fetchBytes(source.uri);
        final dynamicUrls = await _resolveStaticVotingConfig(
          source: source.raw,
          staticBytes: staticBytes,
        );
        return (source.raw, staticBytes, dynamicUrls);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
        _reportMirrorFailure(
          stage: VotingConfigMirrorStage.staticAnchor,
          url: source.uri.toString(),
          error: error,
        );
      }
    }

    Error.throwWithStackTrace(
      firstError ?? StateError('no static voting config mirrors configured'),
      firstStackTrace ?? StackTrace.current,
    );
  }

  /// Walks the dynamic mirrors, re-resolving after each fetch.
  ///
  /// Rust owns the preference rules, so every mirror gathered so far is handed
  /// back on each pass rather than being judged here. Any resolution ends the
  /// walk, including one that authenticates zero rounds.
  ///
  /// Round count is deliberately *not* a freshness proxy. An earlier revision
  /// kept walking while the round set was empty so a stale mirror could not
  /// shadow a healthy one, but that guard only ever covered the empty-to-first
  /// -round transition: a mirror serving one stale round already ended the walk
  /// ahead of a mirror serving five fresh ones. Meanwhile prod authenticates
  /// zero rounds as its normal steady state, so the guard charged every prod
  /// refresh a second fetch — an uncacheable `raw.githubusercontent.com`
  /// request — to protect a single moment in the config's life. The dynamic
  /// config carries no serial or timestamp, so no cheap rule does better;
  /// stopping at the first answer restores "a healthy primary costs exactly one
  /// request per stage" and shrinks the window in which a fallback mirror's
  /// unsigned `vote_servers` / `pir_endpoints` are adopted at all.
  ///
  /// The cost is that a primary which resolves but has not yet picked up a
  /// newly published round hides it until the primary catches up. That is
  /// bounded: the canonical gateway is not edge-cached, and config loads are
  /// event-driven, so the following refresh sees the round.
  Future<rust_config_api.VotingConfigResolution> _walkDynamicMirrors({
    required String source,
    required Uint8List staticBytes,
    required List<String> dynamicUrls,
    required rust_config.ResolvedVotingConfig? previous,
  }) async {
    final attempts = <rust_config_api.ApiDynamicConfigAttempt>[];
    rust_config_api.VotingConfigResolution? best;
    Object? transportError;
    StackTrace? transportStackTrace;
    Object? resolveError;
    StackTrace? resolveStackTrace;

    for (final url in dynamicUrls) {
      try {
        final bytes = await _fetchBytes(_dynamicConfigTransportUri(url));
        attempts.add(
          rust_config_api.ApiDynamicConfigAttempt(url: url, bytes: bytes),
        );
      } catch (error, stackTrace) {
        transportError ??= error;
        transportStackTrace ??= stackTrace;
        _reportMirrorFailure(
          stage: VotingConfigMirrorStage.dynamicConfig,
          url: url,
          error: error,
        );
        attempts.add(
          rust_config_api.ApiDynamicConfigAttempt(
            url: url,
            error: error.toString(),
          ),
        );
      }

      // This mirror produced no new bytes, so re-running Rust could only repeat
      // an earlier mirror's rejection and incorrectly attribute that integrity
      // failure to this transport-only mirror.
      if (attempts.last.bytes == null) continue;

      try {
        best = await _resolveVotingConfigFromAttempts(
          source: source,
          staticBytes: staticBytes,
          attempts: attempts,
          previous: previous,
        );
        break;
      } catch (error, stackTrace) {
        // First-wins, matching the static walk. Reporting the last mirror's
        // rejection instead would make two outages with the same root cause
        // read differently depending on mirror order, which is exactly the
        // ambiguity that makes triage from user reports unreliable.
        resolveError ??= error;
        resolveStackTrace ??= stackTrace;
        _reportMirrorFailure(
          stage: VotingConfigMirrorStage.dynamicConfig,
          url: url,
          error: error,
        );
      }
    }

    if (best != null) return best;

    // Every mirror failed. Prefer the transport failure so the caller's retry
    // and last-good-config handling still recognizes an outage as retryable —
    // a bad mirror must not cost the user their last-good config while the
    // network is merely down. The integrity failure is not lost by that choice:
    // it already went out through [onMirrorFailure], which is why that channel
    // exists rather than being inferred from the thrown error.
    if (transportError != null) {
      Error.throwWithStackTrace(transportError, transportStackTrace!);
    }
    Error.throwWithStackTrace(
      resolveError ??
          StateError('static voting config named no dynamic config mirrors'),
      resolveStackTrace ?? StackTrace.current,
    );
  }

  /// Logs a passed-over mirror and forwards it to [onMirrorFailure].
  ///
  /// Never throws: a broken observer must not turn a survivable mirror failure
  /// into a failed config load.
  void _reportMirrorFailure({
    required VotingConfigMirrorStage stage,
    required String url,
    required Object error,
  }) {
    final kind = classifyVotingConfigMirrorFailure(error);
    debugPrint(
      '[zcash] Voting: ${stage.name} mirror $url passed over '
      '(${kind.name}): $error',
    );
    final observer = onMirrorFailure;
    if (observer == null) return;
    try {
      observer(
        VotingConfigMirrorFailure(
          stage: stage,
          url: url,
          kind: kind,
          error: error,
        ),
      );
    } catch (observerError) {
      debugPrint(
        '[zcash] Voting: mirror failure observer threw: $observerError',
      );
    }
  }

  Future<Uint8List> _fetchBytes(Uri uri) async {
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
