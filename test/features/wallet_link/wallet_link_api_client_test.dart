import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/network/network_http_client.dart';
import 'package:zcash_wallet/src/features/wallet_link/services/wallet_link_api_client.dart';

void main() {
  const packageId = '550e8400-e29b-41d4-a716-446655440000';

  test('revoke package uses POST over Tor', () async {
    final bridge = _RecordingTorBridge([
      NetworkHttpResponse(statusCode: 204, bodyBytes: Uint8List(0)),
    ]);
    final networkClient = NetworkHttpClient(
      torDesired: () => true,
      torBridge: bridge,
    );
    final client = WalletLinkApiClient(
      networkClient: networkClient,
      baseUri: Uri.parse('https://functions.example.test'),
    );
    addTearDown(() => client.close(force: true));

    await client.revokePackage(packageId);

    expect(bridge.posts, hasLength(1));
    expect(
      bridge.posts.single.uri.toString(),
      'https://functions.example.test/api/wallet-link/v1/packages/'
      '$packageId/revoke',
    );
    expect(bridge.posts.single.bodyBytes, isEmpty);
  });

  test(
    'revoke package accepts an already missing or expired package',
    () async {
      final bridge = _RecordingTorBridge([
        NetworkHttpResponse(statusCode: 404, bodyBytes: Uint8List(0)),
        NetworkHttpResponse(statusCode: 410, bodyBytes: Uint8List(0)),
      ]);
      final networkClient = NetworkHttpClient(
        torDesired: () => true,
        torBridge: bridge,
      );
      final client = WalletLinkApiClient(
        networkClient: networkClient,
        baseUri: Uri.parse('https://functions.example.test'),
      );
      addTearDown(() => client.close(force: true));

      await client.revokePackage(packageId);
      await client.revokePackage(packageId);

      expect(bridge.posts, hasLength(2));
    },
  );

  test('revoke package reports a backend failure', () async {
    final bridge = _RecordingTorBridge([
      NetworkHttpResponse(statusCode: 500, bodyBytes: Uint8List(0)),
    ]);
    final networkClient = NetworkHttpClient(
      torDesired: () => true,
      torBridge: bridge,
    );
    final client = WalletLinkApiClient(
      networkClient: networkClient,
      baseUri: Uri.parse('https://functions.example.test'),
    );
    addTearDown(() => client.close(force: true));

    await expectLater(
      client.revokePackage(packageId),
      throwsA(
        isA<WalletLinkApiException>()
            .having((error) => error.statusCode, 'statusCode', 500)
            .having(
              (error) => error.message,
              'message',
              'Failed to revoke wallet link package.',
            ),
      ),
    );
  });
}

class _RecordingTorBridge implements TorHttpBridge {
  _RecordingTorBridge(this.responses);

  final List<NetworkHttpResponse> responses;
  final posts = <_RecordedPost>[];

  @override
  Future<NetworkHttpResponse> download(
    Uri uri, {
    required Map<String, String> headers,
    required String destinationPath,
  }) => throw UnsupportedError('Unexpected download');

  @override
  Future<NetworkHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
  }) => throw UnsupportedError('Unexpected GET');

  @override
  Future<NetworkHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required List<int> bodyBytes,
  }) async {
    posts.add(_RecordedPost(uri: uri, bodyBytes: List.of(bodyBytes)));
    return responses[posts.length - 1];
  }
}

class _RecordedPost {
  const _RecordedPost({required this.uri, required this.bodyBytes});

  final Uri uri;
  final List<int> bodyBytes;
}
