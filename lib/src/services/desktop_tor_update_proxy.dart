import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/network/network_http_client.dart';

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
/// Sparkle and Velopack require HTTP URLs but cannot use the embedded Arti
/// client directly. This server exposes only the configured update feed and
/// assets on a random, process-local path; every upstream request still goes
/// through [NetworkHttpClient], and therefore through Tor while Tor is desired.
class DesktopTorUpdateProxy {
  DesktopTorUpdateProxy({NetworkHttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? NetworkHttpClient.new;

  final NetworkHttpClient Function() _clientFactory;

  HttpServer? _server;
  NetworkHttpClient? _client;
  String? _token;
  Uri? _macOSFeed;
  Uri? _windowsReleaseBase;

  Future<MacOSTorUpdateProxyConfiguration> configureMacOS(
    Uri upstreamFeed,
  ) async {
    _requireHttps(upstreamFeed);
    await _ensureStarted();
    _macOSFeed = upstreamFeed;
    return MacOSTorUpdateProxyConfiguration(
      feedUrl: _localUri('macos/appcast.xml'),
      resourceUrl: _localUri('macos/resource'),
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
      if (segments.length == 3 &&
          segments[1] == 'macos' &&
          segments[2] == 'resource') {
        final rawUpstream = request.uri.queryParameters['url'];
        if (rawUpstream == null) {
          request.response.statusCode = HttpStatus.notFound;
          return;
        }
        final upstream = Uri.parse(rawUpstream);
        _requireHttps(upstream);
        await _serveUpstreamFile(upstream, request.response);
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

  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
