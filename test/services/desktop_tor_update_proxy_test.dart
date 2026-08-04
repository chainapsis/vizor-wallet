import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/services/desktop_tor_update_proxy.dart';

void main() {
  test(
    'preserves signed Sparkle feed and proxies requested update resources',
    () async {
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
        bodies: {
          'https://updates.example/appcast.xml': utf8.encode(signedFeed),
          'https://cdn.example/Vizor.zip': [1, 2, 3, 4],
        },
      );
      final proxy = DesktopTorUpdateProxy(
        clientFactory: () =>
            NetworkHttpClient(torDesired: () => true, torBridge: bridge),
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
      expect(bridge.downloads, ['https://cdn.example/Vizor.zip']);
    },
  );

  test('maps Velopack release assets to the configured Tor base', () async {
    final bridge = _UpdateTorBridge(
      bodies: {
        'https://updates.example/releases/releases.win.json': utf8.encode(
          '{"assets":[]}',
        ),
      },
    );
    final proxy = DesktopTorUpdateProxy(
      clientFactory: () =>
          NetworkHttpClient(torDesired: () => true, torBridge: bridge),
    );
    addTearDown(proxy.stop);

    final baseUrl = await proxy.configureWindows(
      Uri.parse('https://updates.example/releases'),
    );
    final response = await _get(baseUrl.resolve('releases.win.json'));

    expect(response.statusCode, HttpStatus.ok);
    expect(utf8.decode(response.bodyBytes), '{"assets":[]}');
    expect(bridge.downloads, [
      'https://updates.example/releases/releases.win.json',
    ]);
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
  }) => throw UnimplementedError();
}
