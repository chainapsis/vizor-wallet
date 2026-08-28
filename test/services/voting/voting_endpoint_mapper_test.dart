import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/voting/voting_endpoint_mapper.dart';
import 'package:zcash_wallet/src/services/voting/voting_http.dart';

void main() {
  group('VotingEndpointMapper', () {
    test('is identity outside regtest', () {
      final mapper = VotingEndpointMapper(
        isRegtest: false,
        gatewayUrl: 'http://127.0.0.1:18080',
      );
      final logical = Uri.parse(
        'https://vote.vizor-vote.invalid/shielded-vote/v1/rounds',
      );

      expect(mapper.isEnabled, isFalse);
      expect(mapper.map(logical), logical);
    });

    test('maps only reserved HTTPS identities through loopback', () {
      final mapper = VotingEndpointMapper(
        isRegtest: true,
        gatewayUrl: 'http://127.0.0.1:18080/gateway',
      );

      expect(
        mapper.map(Uri.parse('https://pir.vizor-vote.invalid/root?height=42')),
        Uri.parse(
          'http://127.0.0.1:18080/gateway/'
          'pir.vizor-vote.invalid/root?height=42',
        ),
      );
      expect(
        mapper.map(Uri.parse('https://example.com/root')),
        Uri.parse('https://example.com/root'),
      );
      expect(
        mapper.map(Uri.parse('http://pir.vizor-vote.invalid/root')),
        Uri.parse('http://pir.vizor-vote.invalid/root'),
      );
    });

    test('rejects non-loopback or HTTPS gateways', () {
      expect(
        () => VotingEndpointMapper(
          isRegtest: true,
          gatewayUrl: 'http://example.com:18080',
        ),
        throwsStateError,
      );
      expect(
        () => VotingEndpointMapper(
          isRegtest: true,
          gatewayUrl: 'https://127.0.0.1:18080',
        ),
        throwsStateError,
      );
    });
  });

  test('MappedVotingHttpClient rewrites GET and POST destinations', () async {
    final inner = _RecordingVotingHttpClient();
    final client = MappedVotingHttpClient(
      inner,
      VotingEndpointMapper(
        isRegtest: true,
        gatewayUrl: 'http://localhost:18080',
      ),
    );

    await client.get(Uri.parse('https://config.vizor-vote.invalid/static'));
    await client.postJson(
      Uri.parse('https://vote.vizor-vote.invalid/api'),
      const {'vote': 1},
    );

    expect(
      inner.getUris.single,
      Uri.parse('http://localhost:18080/config.vizor-vote.invalid/static'),
    );
    expect(
      inner.postUris.single,
      Uri.parse('http://localhost:18080/vote.vizor-vote.invalid/api'),
    );
  });
}

class _RecordingVotingHttpClient implements VotingHttpClient {
  final List<Uri> getUris = [];
  final List<Uri> postUris = [];

  @override
  Future<VotingHttpResponse> get(
    Uri uri, {
    Map<String, String>? headers,
    Duration? timeout,
    Future<void>? cancelSignal,
  }) async {
    getUris.add(uri);
    return VotingHttpResponse(statusCode: 200, bodyBytes: Uint8List(0));
  }

  @override
  Future<VotingHttpResponse> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    postUris.add(uri);
    return VotingHttpResponse(statusCode: 200, bodyBytes: Uint8List(0));
  }
}
