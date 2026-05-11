import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

import 'fake_voting_http.dart';

void main() {
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

Map<String, dynamic> dynamicConfigJson({String voteServerVersion = 'v1'}) => {
  'config_version': 1,
  'vote_servers': [
    {'url': 'https://voting.example', 'label': 'primary'},
  ],
  'pir_endpoints': [
    {'url': 'https://pir.example', 'label': 'pir'},
  ],
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
