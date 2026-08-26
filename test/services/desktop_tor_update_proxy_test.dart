import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/services/desktop_tor_update_proxy.dart';

void main() {
  test('preserves signed Sparkle feed and delegates update resources to the '
      'streaming relay', () async {
    const signedFeed = '''
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="https://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <enclosure url="https://cdn.example/Vizor.zip" />
      <sparkle:releaseNotesLink>https://cdn.example/notes.html</sparkle:releaseNotesLink>
    </item>
  </channel>
</rss><!-- sparkle-signatures:
edSignature: signed-feed-value
length: 321
-->
''';
    final bridge = _UpdateTorBridge(
      bodies: {'https://updates.example/appcast.xml': utf8.encode(signedFeed)},
    );
    final relayedUrls = <String>[];
    final relay = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    relay.listen((request) async {
      relayedUrls.add(request.uri.queryParameters['url']!);
      request.response.add([1, 2]);
      await request.response.flush();
      request.response.add([3, 4]);
      await request.response.close();
    });
    addTearDown(() => relay.close(force: true));
    var relayStopped = false;
    final proxy = DesktopTorUpdateProxy(
      clientFactory: () =>
          NetworkHttpClient(torDesired: () => true, torBridge: bridge),
      torRelayStarter: () async => Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: relay.port,
        path: '/resource',
      ),
      torRelayStopper: () async => relayStopped = true,
    );
    addTearDown(proxy.stop);

    final configuration = await proxy.configureMacOS(
      Uri.parse('https://updates.example/appcast.xml'),
    );
    final feedResponse = await _get(configuration.feedUrl);
    expect(feedResponse.statusCode, HttpStatus.ok);
    expect(feedResponse.bodyBytes, utf8.encode(signedFeed));

    final packageUrl = configuration.resourceUrl.replace(
      queryParameters: const {'url': 'https://cdn.example/Vizor.zip'},
    );
    expect(packageUrl.host, InternetAddress.loopbackIPv4.address);

    final packageResponse = await _get(packageUrl);
    expect(packageResponse.bodyBytes, [1, 2, 3, 4]);
    expect(relayedUrls, ['https://cdn.example/Vizor.zip']);
    expect(bridge.downloads, isEmpty);

    await proxy.stop();
    expect(relayStopped, isTrue);
  });

  test('maps Velopack release assets to the configured Tor base', () async {
    final packageBytes = List<int>.generate(1024, (index) => index % 251);
    final bridge = _UpdateTorBridge(
      bodies: {
        'https://updates.example/releases/releases.win.json': utf8.encode(
          '{"Assets":[{"FileName":"Vizor-1.2.3-full.nupkg","Size":1024}]}',
        ),
      },
    );
    final relayedUrls = <String>[];
    final relayedLengths = <String>[];
    final relay = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    relay.listen((request) async {
      relayedUrls.add(request.uri.queryParameters['url']!);
      relayedLengths.add(request.uri.queryParameters['length']!);
      request.response.add(packageBytes.sublist(0, 512));
      await request.response.flush();
      request.response.add(packageBytes.sublist(512));
      await request.response.close();
    });
    addTearDown(() => relay.close(force: true));
    var relayStopped = false;
    final proxy = DesktopTorUpdateProxy(
      clientFactory: () =>
          NetworkHttpClient(torDesired: () => true, torBridge: bridge),
      torRelayStarter: () async => Uri(
        scheme: 'http',
        host: InternetAddress.loopbackIPv4.address,
        port: relay.port,
        path: '/resource',
      ),
      torRelayStopper: () async => relayStopped = true,
    );
    addTearDown(proxy.stop);

    final baseUrl = await proxy.configureWindows(
      Uri.parse('https://updates.example/releases'),
    );
    final feedResponse = await _get(baseUrl.resolve('releases.win.json'));
    final packageResponse = await _get(
      baseUrl.resolve('Vizor-1.2.3-full.nupkg'),
    );

    expect(feedResponse.statusCode, HttpStatus.ok);
    expect(
      utf8.decode(feedResponse.bodyBytes),
      '{"Assets":[{"FileName":"Vizor-1.2.3-full.nupkg","Size":1024}]}',
    );
    expect(packageResponse.statusCode, HttpStatus.ok);
    expect(packageResponse.bodyBytes, packageBytes);
    expect(relayedUrls, [
      'https://updates.example/releases/Vizor-1.2.3-full.nupkg',
    ]);
    expect(relayedLengths, ['1024']);
    expect(bridge.downloads, [
      'https://updates.example/releases/releases.win.json',
    ]);

    await proxy.stop();
    expect(relayStopped, isTrue);
  });
}

Future<NetworkHttpResponse> _get(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    final body = await response.fold<List<int>>(
      <int>[],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    return NetworkHttpResponse(
      statusCode: response.statusCode,
      bodyBytes: Uint8List.fromList(body),
    );
  } finally {
    client.close(force: true);
  }
}

class _UpdateTorBridge implements TorHttpBridge {
  _UpdateTorBridge({required this.bodies});

  final Map<String, List<int>> bodies;
  final downloads = <String>[];

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) async {
    final body = bodies[uri.toString()];
    if (body == null) throw StateError('Unexpected download: $uri');
    downloads.add(uri.toString());
    await File(destinationPath).writeAsBytes(body);
    return NetworkHttpResponse(
      statusCode: HttpStatus.ok,
      bodyBytes: Uint8List(0),
      headers: const {
        HttpHeaders.contentTypeHeader: ['application/octet-stream'],
      },
    );
  }

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration? timeout,
  }) async {
    final body = bodies[uri.toString()];
    if (body == null) throw StateError('Unexpected GET: $uri');
    return NetworkHttpResponse(
      statusCode: HttpStatus.ok,
      bodyBytes: Uint8List.fromList(body),
    );
  }

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
    required Duration? timeout,
  }) => throw UnimplementedError();
}
