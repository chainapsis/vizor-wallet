import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/network/network_http_client.dart';
import '../rust/api/network_privacy.dart' as rust_network_privacy;

typedef TorUpdateRelayStarter = Future<Uri> Function();
typedef TorUpdateRelayStopper = Future<void> Function();

class MacOSTorUpdateProxyConfiguration {
  const MacOSTorUpdateProxyConfiguration({
    required this.feedUrl,
    required this.resourceUrl,
  });

  final Uri feedUrl;
  final Uri resourceUrl;
}

/// Loopback-only HTTP bridge for native desktop updaters.
///
/// The signed Sparkle feed and Velopack resources use [NetworkHttpClient].
/// Sparkle package bytes use a Rust loopback relay so the embedded Arti client
/// can stream directly to the native updater without buffering the full
/// archive on disk or copying chunks through Flutter Rust Bridge.
class DesktopTorUpdateProxy {
  DesktopTorUpdateProxy({
    NetworkHttpClient Function()? clientFactory,
    TorUpdateRelayStarter? torRelayStarter,
    TorUpdateRelayStopper? torRelayStopper,
  }) : _clientFactory = clientFactory ?? NetworkHttpClient.new,
       _torRelayStarter = torRelayStarter ?? _startTorUpdateRelay,
       _torRelayStopper =
           torRelayStopper ?? rust_network_privacy.stopTorUpdateRelay;

  final NetworkHttpClient Function() _clientFactory;
  final TorUpdateRelayStarter _torRelayStarter;
  final TorUpdateRelayStopper _torRelayStopper;

  HttpServer? _server;
  NetworkHttpClient? _client;
  String? _token;
  Uri? _macOSFeed;
  Uri? _windowsReleaseBase;
  var _torRelayRunning = false;

  Future<MacOSTorUpdateProxyConfiguration> configureMacOS(
    Uri upstreamFeed,
  ) async {
    _requireHttps(upstreamFeed);
    await _ensureStarted();
    _macOSFeed = upstreamFeed;
    final resourceUrl = await _torRelayStarter();
    _torRelayRunning = true;
    try {
      _requireLoopbackHttp(resourceUrl);
    } catch (_) {
      _torRelayRunning = false;
      await _torRelayStopper();
      rethrow;
    }
    return MacOSTorUpdateProxyConfiguration(
      feedUrl: _localUri('macos/appcast.xml'),
      resourceUrl: resourceUrl,
    );
  }

  Future<Uri> configureWindows(Uri upstreamReleaseBase) async {
    _requireHttps(upstreamReleaseBase);
    await _ensureStarted();
    _windowsReleaseBase = upstreamReleaseBase.path.endsWith('/')
        ? upstreamReleaseBase
        : upstreamReleaseBase.replace(path: '${upstreamReleaseBase.path}/');
    return _localUri('windows/');
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = null;
    _macOSFeed = null;
    _windowsReleaseBase = null;
    _client?.close(force: true);
    _client = null;
    await server?.close(force: true);
    if (_torRelayRunning) {
      _torRelayRunning = false;
      await _torRelayStopper();
    }
  }

  Future<void> _ensureStarted() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _client = _clientFactory();
    _token = _randomToken();
    unawaited(_serve(server));
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.length < 2 || segments.first != _token) {
        request.response.statusCode = HttpStatus.notFound;
        return;
      }

      if (segments.length == 3 &&
          segments[1] == 'macos' &&
          segments[2] == 'appcast.xml') {
        await _serveMacOSFeed(request.response);
        return;
      }
      if (segments.length == 3 && segments[1] == 'windows') {
        final base = _windowsReleaseBase;
        if (base == null || segments[2].isEmpty) {
          request.response.statusCode = HttpStatus.notFound;
          return;
        }
        await _serveUpstreamFile(
          base.resolveUri(Uri(pathSegments: [segments[2]])),
          request.response,
        );
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
    } finally {
      await request.response.close();
    }
  }

  Future<void> _serveMacOSFeed(HttpResponse response) async {
    final upstream = _macOSFeed;
    final client = _client;
    if (upstream == null || client == null) {
      response.statusCode = HttpStatus.serviceUnavailable;
      return;
    }
    final result = await client.request(
      'GET',
      upstream,
      headers: const {HttpHeaders.acceptHeader: 'application/xml'},
    );
    if (result.statusCode < 200 || result.statusCode >= 300) {
      response.statusCode = result.statusCode;
      return;
    }

    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType(
      'application',
      'xml',
      charset: 'utf-8',
    );
    response.contentLength = result.bodyBytes.length;
    response.add(result.bodyBytes);
  }

  Future<void> _serveUpstreamFile(Uri upstream, HttpResponse response) async {
    final client = _client;
    if (client == null) {
      response.statusCode = HttpStatus.serviceUnavailable;
      return;
    }

    final directory = await Directory.systemTemp.createTemp(
      'vizor-tor-update-',
    );
    final file = File('${directory.path}/download');
    try {
      final result = await client.downloadToFile(upstream, file);
      if (result.statusCode < 200 || result.statusCode >= 300) {
        response.statusCode = result.statusCode;
        return;
      }
      response.statusCode = HttpStatus.ok;
      final contentType = result.header(HttpHeaders.contentTypeHeader);
      if (contentType != null) {
        response.headers.set(HttpHeaders.contentTypeHeader, contentType);
      }
      response.contentLength = await file.length();
      await response.addStream(file.openRead());
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Uri _localUri(String relativePath) {
    final server = _server;
    final token = _token;
    if (server == null || token == null) {
      throw StateError('Tor update proxy is not running.');
    }
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      path: '/$token/$relativePath',
    );
  }

  static void _requireHttps(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'Expected an HTTPS update URL.');
    }
  }

  static void _requireLoopbackHttp(Uri uri) {
    if (uri.scheme != 'http' ||
        uri.host != InternetAddress.loopbackIPv4.address ||
        uri.port == 0) {
      throw ArgumentError.value(
        uri,
        'uri',
        'Expected a loopback HTTP relay URL.',
      );
    }
  }

  static Future<Uri> _startTorUpdateRelay() async =>
      Uri.parse(await rust_network_privacy.startTorUpdateRelay());

  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
