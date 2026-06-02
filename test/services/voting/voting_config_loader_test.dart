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
      'https://user@example.com/static.json?checksum=sha256:$validHex',
      'https://example.com/static.json?checksum=sha256:$validHex#fragment',
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
      'http://0.0.0.0:8080',
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

  test('static config rejects unsafe dynamic config URLs', () {
    for (final dynamicConfigUrl in [
      'ftp://voting.example/dynamic-voting-config.json',
      'http://voting.example/dynamic-voting-config.json',
      'http://0.0.0.0:8080/dynamic-voting-config.json',
      'https://user@voting.example/dynamic-voting-config.json',
      'https://voting.example/dynamic-voting-config.json#fragment',
      '/dynamic-voting-config.json',
    ]) {
      final json = Map<String, dynamic>.of(staticConfigJson())
        ..['dynamic_config_url'] = dynamicConfigUrl;
      final config = StaticVotingConfig.fromJson(json);

      expect(
        config.validate,
        throwsA(isA<VotingConfigDecodeException>()),
        reason: dynamicConfigUrl,
      );
    }
  });

  test('loadDynamicConfig validates direct dynamic config URLs', () async {
    final loader = VotingConfigLoader(httpClient: FakeVotingHttpClient());

    await expectLater(
      loader.loadDynamicConfig(
        Uri.parse('http://voting.example/dynamic-voting-config.json'),
      ),
      throwsA(isA<VotingConfigDecodeException>()),
    );
  });

  test('static config allows localhost dynamic config during regtest', () {
    final json = Map<String, dynamic>.of(staticConfigJson())
      ..['dynamic_config_url'] =
          'http://localhost:8080/dynamic-voting-config.json';
    final config = StaticVotingConfig.fromJson(json);

    expect(config.validate, returnsNormally);
  });

  test('static config rejects duplicate trusted key ids', () {
    final key = Map<String, dynamic>.of(
      (staticConfigJson()['trusted_keys'] as List).single
          as Map<String, dynamic>,
    );
    final json = Map<String, dynamic>.of(staticConfigJson())
      ..['trusted_keys'] = [key, Map<String, dynamic>.of(key)];
    final config = StaticVotingConfig.fromJson(json);

    expect(config.validate, throwsA(isA<VotingConfigDecodeException>()));
  });

  test('config parsing rejects obsolete camelCase field aliases', () {
    final allCamelStaticJson = {
      'staticConfigVersion': 1,
      'dynamicConfigUrl': 'https://voting.example/dynamic-voting-config.json',
      'trustedKeys': [
        {'keyId': 'demo', 'alg': 'ed25519', 'pubkey': _b64(1, 32)},
      ],
    };
    expect(
      () => StaticVotingConfig.fromJson(allCamelStaticJson),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required int: static_config_version',
        ),
      ),
    );

    final dynamicUrlAlias = Map<String, dynamic>.of(staticConfigJson())
      ..remove('dynamic_config_url')
      ..['dynamicConfigUrl'] =
          'https://voting.example/dynamic-voting-config.json';
    expect(
      () => StaticVotingConfig.fromJson(dynamicUrlAlias),
      throwsA(
        isA<VotingConfigDecodeException>().having(
          (error) => error.message,
          'message',
          'Missing required URI: dynamic_config_url',
        ),
      ),
    );

    final dynamicUrlUpperAlias = Map<String, dynamic>.of(staticConfigJson())
      ..remove('dynamic_config_url')
      ..['dynamicConfigURL'] =
          'https://voting.example/dynamic-voting-config.json';
    expect(
      () => StaticVotingConfig.fromJson(dynamicUrlUpperAlias),
      throwsA(
        isA<VotingConfigDecodeException>().having(
          (error) => error.message,
          'message',
          'Missing required URI: dynamic_config_url',
        ),
      ),
    );

    final trustedKeysAlias = Map<String, dynamic>.of(staticConfigJson())
      ..remove('trusted_keys')
      ..['trustedKeys'] = [
        {'key_id': 'demo', 'alg': 'ed25519', 'pubkey': _b64(1, 32)},
      ];
    expect(
      () => StaticVotingConfig.fromJson(trustedKeysAlias),
      throwsA(
        isA<VotingConfigDecodeException>().having(
          (error) => error.message,
          'message',
          'Missing required field: trusted_keys',
        ),
      ),
    );

    final trustedKeyIdAlias = Map<String, dynamic>.of(staticConfigJson())
      ..['trusted_keys'] = [
        {'keyId': 'demo', 'alg': 'ed25519', 'pubkey': _b64(1, 32)},
      ];
    expect(
      () => StaticVotingConfig.fromJson(trustedKeyIdAlias),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required string: key_id',
        ),
      ),
    );

    final allCamelDynamicJson = {
      'configVersion': 1,
      'voteServers': [
        {'url': 'https://voting.example'},
      ],
      'pirEndpoints': [
        {'url': 'https://pir.example'},
      ],
      'supportedVersions': {
        'pir': ['v0'],
        'voteProtocol': 'v0',
        'tally': 'v0',
        'voteServer': 'v1',
      },
      'rounds': {_roundId: roundConfigJson()},
    };
    expect(
      () => VotingConfig.fromJson(allCamelDynamicJson),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required int: config_version',
        ),
      ),
    );

    final voteServersAlias = Map<String, dynamic>.of(dynamicConfigJson())
      ..remove('vote_servers')
      ..['voteServers'] = [
        {'url': 'https://voting.example'},
      ];
    expect(
      () => VotingConfig.fromJson(voteServersAlias),
      throwsA(
        isA<VotingConfigDecodeException>().having(
          (error) => error.message,
          'message',
          'Missing required field: vote_servers',
        ),
      ),
    );

    final pirEndpointsAlias = Map<String, dynamic>.of(dynamicConfigJson())
      ..remove('pir_endpoints')
      ..['pirEndpoints'] = [
        {'url': 'https://pir.example'},
      ];
    expect(
      () => VotingConfig.fromJson(pirEndpointsAlias),
      throwsA(
        isA<VotingConfigDecodeException>().having(
          (error) => error.message,
          'message',
          'Missing required field: pir_endpoints',
        ),
      ),
    );

    final supportedVersionsAlias = Map<String, dynamic>.of(dynamicConfigJson())
      ..remove('supported_versions')
      ..['supportedVersions'] = {
        'pir': ['v0'],
        'vote_protocol': 'v0',
        'tally': 'v0',
        'vote_server': 'v1',
      };
    expect(
      () => VotingConfig.fromJson(supportedVersionsAlias),
      throwsA(
        isA<VotingConfigDecodeException>().having(
          (error) => error.message,
          'message',
          'Missing required field: supported_versions',
        ),
      ),
    );

    final versionFieldAliases = Map<String, dynamic>.of(dynamicConfigJson())
      ..['supported_versions'] = {
        'pir': ['v0'],
        'voteProtocol': 'v0',
        'tally': 'v0',
        'voteServer': 'v1',
      };
    expect(
      () => VotingConfig.fromJson(versionFieldAliases),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required string: vote_protocol',
        ),
      ),
    );

    final voteServerAlias = Map<String, dynamic>.of(dynamicConfigJson())
      ..['supported_versions'] = {
        'pir': ['v0'],
        'vote_protocol': 'v0',
        'tally': 'v0',
        'voteServer': 'v1',
      };
    expect(
      () => VotingConfig.fromJson(voteServerAlias),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required string: vote_server',
        ),
      ),
    );

    final roundFieldAliases = Map<String, dynamic>.of(dynamicConfigJson())
      ..['rounds'] = {
        _roundId: {
          'authVersion': 1,
          'eaPk': _b64(2, 32),
          'signatures': [
            {'keyId': 'demo', 'alg': 'ed25519', 'sig': _b64(3, 64)},
          ],
        },
      };
    expect(
      () => VotingConfig.fromJson(roundFieldAliases),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required int: auth_version',
        ),
      ),
    );

    final roundEaPkAlias = Map<String, dynamic>.of(dynamicConfigJson())
      ..['rounds'] = {
        _roundId: {
          'auth_version': 1,
          'eaPk': _b64(2, 32),
          'signatures': [
            {'key_id': 'demo', 'alg': 'ed25519', 'sig': _b64(3, 64)},
          ],
        },
      };
    expect(
      () => VotingConfig.fromJson(roundEaPkAlias),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required string: ea_pk',
        ),
      ),
    );

    final signatureKeyIdAlias = Map<String, dynamic>.of(dynamicConfigJson())
      ..['rounds'] = {
        _roundId: {
          'auth_version': 1,
          'ea_pk': _b64(2, 32),
          'signatures': [
            {'keyId': 'demo', 'alg': 'ed25519', 'sig': _b64(3, 64)},
          ],
        },
      };
    expect(
      () => VotingConfig.fromJson(signatureKeyIdAlias),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Missing required string: key_id',
        ),
      ),
    );
  });

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

  test('dynamic config validates signed round metadata', () {
    void expectInvalidRound(Map<String, dynamic> roundJson, Matcher matcher) {
      final dynamicJson = Map<String, dynamic>.of(dynamicConfigJson())
        ..['rounds'] = {_roundId: roundJson};

      expect(() => VotingConfig.fromJson(dynamicJson).validate(), matcher);
    }

    expectInvalidRound(
      roundConfigJson(authVersion: 2),
      throwsA(isA<VotingConfigDecodeException>()),
    );
    expectInvalidRound(
      roundConfigJson(eaPk: _b64(2, 31)),
      throwsA(isA<VotingConfigDecodeException>()),
    );
    expectInvalidRound(
      roundConfigJson(signatures: const []),
      throwsA(isA<VotingConfigDecodeException>()),
    );
    expectInvalidRound(
      roundConfigJson(
        signatures: [
          {'key_id': 'demo', 'alg': 'ed25519', 'sig': _b64(3, 63)},
        ],
      ),
      throwsA(isA<VotingConfigDecodeException>()),
    );
    expectInvalidRound(
      roundConfigJson(
        signatures: [
          {'key_id': 'demo', 'alg': 'unknown', 'sig': _b64(3, 64)},
        ],
      ),
      throwsA(isA<VotingConfigDecodeException>()),
    );
  });

  test('config parsing rejects fractional integer fields', () {
    final staticJson = Map<String, dynamic>.of(staticConfigJson())
      ..['static_config_version'] = 1.9;
    expect(
      () => StaticVotingConfig.fromJson(staticJson),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'static_config_version must be an integer',
        ),
      ),
    );

    final dynamicJson = Map<String, dynamic>.of(dynamicConfigJson())
      ..['config_version'] = 1.9;
    expect(
      () => VotingConfig.fromJson(dynamicJson),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'config_version must be an integer',
        ),
      ),
    );
  });
}

const _roundId =
    '0000000000000000000000000000000000000000000000000000000000000001';

Map<String, dynamic> staticConfigJson() => {
  'static_config_version': 1,
  'dynamic_config_url': 'https://voting.example/dynamic-voting-config.json',
  'trusted_keys': [
    {'key_id': 'demo', 'alg': 'ed25519', 'pubkey': _b64(1, 32)},
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
  'rounds': {_roundId: roundConfigJson()},
};

Map<String, dynamic> roundConfigJson({
  int authVersion = 1,
  String? eaPk,
  List<Map<String, String>>? signatures,
}) => {
  'auth_version': authVersion,
  'ea_pk': eaPk ?? _b64(2, 32),
  'signatures':
      signatures ??
      [
        {'key_id': 'demo', 'alg': 'ed25519', 'sig': _b64(3, 64)},
      ],
};

String _b64(int byte, int length) =>
    base64Encode(List<int>.filled(length, byte));
