import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

import 'fake_voting_http.dart';

void main() {
  test('default static config source points at the prod pinned config', () {
    final source = StaticVotingConfigSource.parse(
      kDefaultStaticVotingConfigSource,
    );

    expect(
      source.uri.toString(),
      'https://raw.githubusercontent.com/valargroup/token-holder-voting-config/'
      '2785311d45758e85567d70a1f13709fa01b62c6b/prod/static-voting-config.json',
    );
    expect(
      source.sha256Hex,
      'bed0116f961226b256a574b52461ce81d9f5294a57e190987dc155f07eb1e431',
    );
  });

  test('parses static config source and strips sha256 checksum', () {
    const hex =
        '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a';
    final source = StaticVotingConfigSource.parse(
      'https://example.com/static.json?foo=bar&checksum=sha256:$hex&baz=qux',
    );

    expect(
      source.uri.toString(),
      'https://example.com/static.json?foo=bar&baz=qux',
    );
    expect(source.sha256Hex, hex);
  });

  test('rejects malformed static config sources', () {
    const validHex =
        '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a';
    for (final source in [
      'http://example.com/static.json?checksum=sha256:$validHex',
      'https://example.com/static.json?checksum=sha512:$validHex',
      'https://example.com/static.json?checksum=sha256:${validHex.toUpperCase()}',
      'https://example.com/static.json?checksum=sha256:0a',
    ]) {
      expect(
        () => StaticVotingConfigSource.parse(source),
        throwsA(isA<StaticVotingConfigSourceMalformed>()),
      );
    }
  });

  test('fetches static trust anchor then dynamic config', () async {
    final staticSource = StaticVotingConfigSource.parse(
      'https://voting.example/static-voting-config.json',
    );
    final http = FakeVotingHttpClient(
      responses: {
        staticSource.uri.toString(): staticConfigJson(),
        'https://voting.example/dynamic-voting-config.json':
            dynamicConfigJson(),
      },
    );
    final loader = VotingConfigLoader(
      httpClient: http,
      staticConfigSource: staticSource,
    );

    final config = await loader.load();

    expect(config.apiBaseUrl.toString(), 'https://voting.example');
    expect(config.pirEndpointUrls.single.toString(), 'https://pir.example');
    expect(http.requests.map((request) => request.uri.toString()), [
      'https://voting.example/static-voting-config.json',
      'https://voting.example/dynamic-voting-config.json',
    ]);
  });

  test('dynamic config normalizes service endpoint base URLs', () async {
    final staticSource = StaticVotingConfigSource.parse(
      'https://voting.example/static-voting-config.json',
    );
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {
          staticSource.uri.toString(): staticConfigJson(),
          'https://voting.example/dynamic-voting-config.json':
              dynamicConfigJson(
                voteServers: [
                  {'url': ' HTTPS://VOTING.EXAMPLE/base/../api/ '},
                ],
                pirEndpoints: [
                  {'url': 'https://pir.example/snapshot/'},
                ],
              ),
        },
      ),
      staticConfigSource: staticSource,
    );

    final config = await loader.load();

    expect(config.apiBaseUrl.toString(), 'https://voting.example/api');
    expect(
      config.pirEndpointUrls.single.toString(),
      'https://pir.example/snapshot',
    );
  });

  test('dynamic config rejects unsafe service endpoint URLs', () async {
    final staticSource = StaticVotingConfigSource.parse(
      'https://voting.example/static-voting-config.json',
    );
    for (final endpoint in [
      'ftp://voting.example',
      'http://voting.example',
      'https://user@voting.example',
      'https://voting.example?x=1',
      'https://voting.example/#frag',
      '/relative',
    ]) {
      final loader = VotingConfigLoader(
        httpClient: FakeVotingHttpClient(
          responses: {
            staticSource.uri.toString(): staticConfigJson(),
            'https://voting.example/dynamic-voting-config.json':
                dynamicConfigJson(
                  voteServers: [
                    {'url': endpoint},
                  ],
                ),
          },
        ),
        staticConfigSource: staticSource,
      );

      expect(
        loader.load(),
        throwsA(isA<VotingConfigDecodeException>()),
        reason: endpoint,
      );
    }
  });

  test('dynamic config allows plain HTTP only for localhost and regtest', () {
    for (final endpoint in [
      'http://localhost:8080',
      'http://127.0.0.1:8080',
      'http://regtest:8080',
      'http://vote.regtest:8080',
    ]) {
      final config = VotingConfig.fromJson(
        dynamicConfigJson(
          voteServers: [
            {'url': endpoint},
          ],
        ),
      );

      expect(config.apiBaseUrl.scheme, 'http');
    }
  });

  test('accepts matching checksum on raw response body', () async {
    final body = jsonEncode(staticConfigJson());
    final checksum = sha256.convert(utf8.encode(body)).toString();
    final staticSource = StaticVotingConfigSource.parse(
      'https://voting.example/static-voting-config.json?checksum=sha256:$checksum',
    );
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {staticSource.uri.toString(): body},
      ),
      staticConfigSource: staticSource,
    );

    final config = await loader.loadStaticConfig();

    expect(
      config.dynamicConfigUrl.toString(),
      'https://voting.example/dynamic-voting-config.json',
    );
  });

  test('checksum mismatch is typed and does not fall back', () async {
    final staticSource = StaticVotingConfigSource.parse(
      'https://voting.example/static-voting-config.json?checksum=sha256:'
      '0000000000000000000000000000000000000000000000000000000000000000',
    );
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {staticSource.uri.toString(): staticConfigJson()},
      ),
      staticConfigSource: staticSource,
    );

    expect(loader.load(), throwsA(isA<VotingConfigChecksumMismatch>()));
  });

  test(
    'malformed dynamic config and unsupported versions fail closed',
    () async {
      final staticSource = StaticVotingConfigSource.parse(
        'https://voting.example/static-voting-config.json',
      );
      final malformedLoader = VotingConfigLoader(
        httpClient: FakeVotingHttpClient(
          responses: {
            staticSource.uri.toString(): staticConfigJson(),
            'https://voting.example/dynamic-voting-config.json': '{',
          },
        ),
        staticConfigSource: staticSource,
      );
      expect(malformedLoader.load(), throwsA(isA<FormatException>()));

      final unsupportedLoader = VotingConfigLoader(
        httpClient: FakeVotingHttpClient(
          responses: {
            staticSource.uri.toString(): staticConfigJson(),
            'https://voting.example/dynamic-voting-config.json':
                dynamicConfigJson(voteServerVersion: 'v99'),
          },
        ),
        staticConfigSource: staticSource,
      );
      expect(
        unsupportedLoader.load(),
        throwsA(isA<VotingConfigUnsupportedVersion>()),
      );
    },
  );

  test('dynamic config rejects missing required rounds registry', () async {
    final staticSource = StaticVotingConfigSource.parse(
      'https://voting.example/static-voting-config.json',
    );
    final dynamicJson = Map<String, dynamic>.of(dynamicConfigJson())
      ..remove('rounds');
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {
          staticSource.uri.toString(): staticConfigJson(),
          'https://voting.example/dynamic-voting-config.json': dynamicJson,
        },
      ),
      staticConfigSource: staticSource,
    );

    expect(loader.load(), throwsA(isA<VotingConfigDecodeException>()));
  });
}

Map<String, dynamic> staticConfigJson() => {
  'static_config_version': 1,
  'dynamic_config_url': 'https://voting.example/dynamic-voting-config.json',
  'trusted_keys': [
    {
      'key_id': 'demo',
      'alg': 'ed25519',
      'pubkey':
          '0101010101010101010101010101010101010101010101010101010101010101',
    },
  ],
};

Map<String, dynamic> dynamicConfigJson({
  String voteServerVersion = 'v1',
  List<Map<String, String>> voteServers = const [
    {'url': 'https://voting.example', 'label': 'primary'},
  ],
  List<Map<String, String>> pirEndpoints = const [
    {'url': 'https://pir.example', 'label': 'pir'},
  ],
}) => {
  'config_version': 1,
  'vote_servers': voteServers,
  'pir_endpoints': pirEndpoints,
  'supported_versions': {
    'pir': ['v0'],
    'vote_protocol': 'v0',
    'tally': 'v0',
    'vote_server': voteServerVersion,
  },
  'rounds': {
    '0000000000000000000000000000000000000000000000000000000000000001': {
      'auth_version': 1,
      'ea_pk':
          '0202020202020202020202020202020202020202020202020202020202020202',
      'signatures': [
        {
          'key_id': 'demo',
          'alg': 'ed25519',
          'sig':
              '0303030303030303030303030303030303030303030303030303030303030303',
        },
      ],
    },
  },
};
