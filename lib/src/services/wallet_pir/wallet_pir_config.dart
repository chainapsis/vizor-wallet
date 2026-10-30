import 'dart:async';
import 'dart:typed_data';

import '../../core/config/network_config.dart';
import '../../core/network/network_http_client.dart';
import '../../rust/api/pir_config.dart' as rust;

/// Which wallet PIR server Private queries use, and where that list comes
/// from.
///
/// A config source is an HTTPS URL pinned to the SHA-256 of a static
/// document. That document names mirrors of a dynamic server list. Dart only
/// fetches bytes over the app's routed transport and stores what Rust hands
/// back; every check (pin, schema, network, attestation, selection rules)
/// runs in the shared `zakura-pir-config` profile behind
/// [WalletPirConfigResolver].

/// Production static source (mainnet). Immutable, hash-pinned copy served
/// from GitHub Pages; the server list is delivered separately.
const kProductionWalletPirConfigSource =
    'https://valargroup.github.io/wallet-pir-config/pins/prod/'
    'f0b0d989892cbccc72c17e7de7530f754d5e0b0292f682109a1f3d88025a77f9/'
    'static-wallet-pir-config.json'
    '?checksum=sha256:f0b0d989892cbccc72c17e7de7530f754d5e0b0292f682109a1f3d88025a77f9';

/// The app's fixed source, or `null` on networks without a published config.
/// Users choose a server from this source's list, never the source itself.
String? defaultWalletPirConfigSource() {
  return switch (kZcashDefaultNetworkRaw) {
    'main' => kProductionWalletPirConfigSource,
    _ => null,
  };
}

/// The config network name for this build's wallet network.
String walletPirConfigNetworkName([String raw = kZcashDefaultNetworkRaw]) =>
    switch (raw) {
      'main' => 'mainnet',
      'test' => 'testnet',
      _ => 'regtest',
    };

/// What the accepted config means for the user's server.
enum WalletPirSelectionState {
  /// The saved server is still offered.
  kept,

  /// First load in this scope; the first offered server was chosen.
  defaulted,

  /// The list is empty. Private queries have no server.
  noServers,

  /// The saved server is no longer offered. Private queries have no server
  /// until the user picks one.
  selectionRequired,
}

class WalletPirServerOption {
  const WalletPirServerOption({required this.label, required this.baseUrl});

  /// Display text only.
  final String label;

  /// The server's identity: the canonical base for all four products.
  final String baseUrl;

  @override
  bool operator ==(Object other) =>
      other is WalletPirServerOption &&
      other.label == label &&
      other.baseUrl == baseUrl;

  @override
  int get hashCode => Object.hash(label, baseUrl);
}

/// An accepted config, as Rust reported it.
class WalletPirConfigView {
  const WalletPirConfigView({
    required this.scope,
    required this.snapshotJson,
    required this.servers,
    required this.selectionState,
    this.selectedBaseUrl,
    this.selectionJson,
    this.removedBaseUrl,
    this.passedOver = const [],
  });

  /// Source, pin, network and policy identity; caches and choices are kept
  /// per scope.
  final String scope;

  /// Raw accepted documents. Re-validated by Rust on every reload.
  final String snapshotJson;
  final List<WalletPirServerOption> servers;
  final WalletPirSelectionState selectionState;
  final String? selectedBaseUrl;

  /// Opaque selection to persist when [selectionState] is kept/defaulted.
  final String? selectionJson;
  final String? removedBaseUrl;
  final List<String> passedOver;
}

class WalletPirConfigException implements Exception {
  const WalletPirConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The Rust profile boundary. Injectable so provider tests need no Rust.
abstract interface class WalletPirConfigResolver {
  /// Validates and normalizes an explicit custom server using the shared
  /// server-base rules. This does not add it to the published configuration.
  String normalizeCustomServer(String baseUrl);

  /// Returns the dynamic mirrors to fetch, in order.
  List<String> resolveStatic({
    required String source,
    required String network,
    required Uint8List staticBytes,
  });

  /// Accepts the first passing attempt. Attempts are (url, bytes | error).
  WalletPirConfigView resolve({
    required String source,
    required String network,
    required Uint8List staticBytes,
    required List<WalletPirMirrorAttempt> attempts,
    String? savedSelectionJson,
  });

  /// Re-validates a persisted snapshot under the current source.
  WalletPirConfigView revalidate({
    required String source,
    required String network,
    required String snapshotJson,
    String? savedSelectionJson,
  });

  /// Returns the selection to persist for an explicit choice.
  String select({
    required String source,
    required String network,
    required String snapshotJson,
    required String baseUrl,
  });
}

class WalletPirMirrorAttempt {
  const WalletPirMirrorAttempt.fetched(this.url, Uint8List this.bytes)
    : error = null;

  const WalletPirMirrorAttempt.failed(this.url, String this.error)
    : bytes = null;

  final String url;
  final Uint8List? bytes;
  final String? error;
}

class RustWalletPirConfigResolver implements WalletPirConfigResolver {
  const RustWalletPirConfigResolver();

  @override
  String normalizeCustomServer(String baseUrl) {
    try {
      return rust.normalizeWalletPirServerBase(baseUrl: baseUrl);
    } on String catch (message) {
      throw WalletPirConfigException(message);
    }
  }

  @override
  List<String> resolveStatic({
    required String source,
    required String network,
    required Uint8List staticBytes,
  }) {
    try {
      return rust
          .resolveWalletPirStaticConfig(
            source: source,
            networkName: network,
            staticBytes: staticBytes,
          )
          .dynamicConfigUrls;
    } on String catch (message) {
      throw WalletPirConfigException(message);
    }
  }

  @override
  WalletPirConfigView resolve({
    required String source,
    required String network,
    required Uint8List staticBytes,
    required List<WalletPirMirrorAttempt> attempts,
    String? savedSelectionJson,
  }) {
    try {
      return _view(
        rust.resolveWalletPirConfig(
          source: source,
          networkName: network,
          staticBytes: staticBytes,
          attempts: [
            for (final attempt in attempts)
              rust.ApiWalletPirConfigAttempt(
                url: attempt.url,
                bytes: attempt.bytes,
                error: attempt.error,
              ),
          ],
          savedSelectionJson: savedSelectionJson,
        ),
      );
    } on String catch (message) {
      throw WalletPirConfigException(message);
    }
  }

  @override
  WalletPirConfigView revalidate({
    required String source,
    required String network,
    required String snapshotJson,
    String? savedSelectionJson,
  }) {
    try {
      return _view(
        rust.resolveWalletPirConfigSnapshot(
          source: source,
          networkName: network,
          snapshotJson: snapshotJson,
          savedSelectionJson: savedSelectionJson,
        ),
      );
    } on String catch (message) {
      throw WalletPirConfigException(message);
    }
  }

  @override
  String select({
    required String source,
    required String network,
    required String snapshotJson,
    required String baseUrl,
  }) {
    try {
      return rust.selectWalletPirServer(
        source: source,
        networkName: network,
        snapshotJson: snapshotJson,
        baseUrl: baseUrl,
      );
    } on String catch (message) {
      throw WalletPirConfigException(message);
    }
  }

  static WalletPirConfigView _view(rust.ApiWalletPirConfig config) {
    return WalletPirConfigView(
      scope: config.scope,
      snapshotJson: config.snapshotJson,
      servers: [
        for (final server in config.servers)
          WalletPirServerOption(label: server.label, baseUrl: server.baseUrl),
      ],
      selectionState: switch (config.selectionState) {
        rust.ApiWalletPirSelectionState.kept => WalletPirSelectionState.kept,
        rust.ApiWalletPirSelectionState.defaulted =>
          WalletPirSelectionState.defaulted,
        rust.ApiWalletPirSelectionState.noServers =>
          WalletPirSelectionState.noServers,
        rust.ApiWalletPirSelectionState.selectionRequired =>
          WalletPirSelectionState.selectionRequired,
      },
      selectedBaseUrl: config.selectedBaseUrl,
      selectionJson: config.selectionJson,
      removedBaseUrl: config.removedBaseUrl,
      passedOver: config.passedOver,
    );
  }
}

/// Fetches config bytes. Injectable so demos and tests supply explicit
/// fixture transports.
abstract interface class WalletPirConfigFetcher {
  Future<Uint8List> fetch(Uri uri);
}

/// Fetches over the app's routed HTTP client (Tor when enabled), HTTPS only,
/// without following redirects, under a deadline and a body limit.
class RoutedWalletPirConfigFetcher implements WalletPirConfigFetcher {
  RoutedWalletPirConfigFetcher({NetworkHttpClient? client})
    : _client = client ?? NetworkHttpClient();

  static const timeout = Duration(seconds: 20);
  static const maxBodyBytes = 256 * 1024;

  final NetworkHttpClient _client;

  @override
  Future<Uint8List> fetch(Uri uri) async {
    if (uri.scheme != 'https') {
      throw const WalletPirConfigException('Config URLs must use HTTPS.');
    }
    final response = await _client.request(
      'GET',
      uri,
      headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      timeout: timeout,
      maxRedirects: 0,
      maxBodyBytes: maxBodyBytes,
    );
    if (response.statusCode != 200) {
      throw WalletPirConfigException(
        'HTTP ${response.statusCode} from ${uri.host}',
      );
    }
    if (response.bodyBytes.length > maxBodyBytes) {
      throw WalletPirConfigException('Config from ${uri.host} is too large');
    }
    return response.bodyBytes;
  }
}

/// One complete fetch of a source: static bytes, then mirrors in order until
/// one passes. Throws [WalletPirConfigException] when nothing passes.
Future<WalletPirConfigView> fetchWalletPirConfig({
  required WalletPirConfigFetcher fetcher,
  required WalletPirConfigResolver resolver,
  required String source,
  required String network,
  String? savedSelectionJson,
}) async {
  final Uint8List staticBytes;
  try {
    staticBytes = await fetcher.fetch(walletPirConfigTransportUri(source));
  } catch (error) {
    throw WalletPirConfigException('Could not reach the config source: $error');
  }
  final mirrors = resolver.resolveStatic(
    source: source,
    network: network,
    staticBytes: staticBytes,
  );
  final attempts = <WalletPirMirrorAttempt>[];
  WalletPirConfigException? last;
  for (final mirror in mirrors) {
    try {
      attempts.add(
        WalletPirMirrorAttempt.fetched(
          mirror,
          await fetcher.fetch(Uri.parse(mirror)),
        ),
      );
    } catch (error) {
      attempts.add(WalletPirMirrorAttempt.failed(mirror, '$error'));
    }
    try {
      return resolver.resolve(
        source: source,
        network: network,
        staticBytes: staticBytes,
        attempts: attempts,
        savedSelectionJson: savedSelectionJson,
      );
    } on WalletPirConfigException catch (error) {
      last = error;
    }
  }
  throw last ?? const WalletPirConfigException('No config mirror answered.');
}

/// The URL to fetch: the source without its `checksum` pin item.
Uri walletPirConfigTransportUri(String source) {
  final trimmed = source.trim();
  final separator = trimmed.indexOf('?');
  if (separator < 0) return Uri.parse(trimmed);
  final kept = trimmed
      .substring(separator + 1)
      .split('&')
      .where((item) => item.isNotEmpty && !item.startsWith('checksum='))
      .join('&');
  final base = trimmed.substring(0, separator);
  return Uri.parse(kept.isEmpty ? base : '$base?$kept');
}
