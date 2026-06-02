import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/rust/api/voting_config.dart' as rust_config_api;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart'
    as rust_config;
import 'package:zcash_wallet/src/services/voting/resolved_voting_config_extensions.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

import 'fake_voting_http.dart';

void main() {
  test('default static config source points at the prod pinned config', () {
    final source = parseStaticVotingConfigSource(
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
    expect(source.raw, kDefaultStaticVotingConfigSource);
  });

  test('parses static config source and strips sha256 checksum', () {
    const hex =
        '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a';
    final source = parseStaticVotingConfigSource(
      'https://example.com/static.json?foo=bar&checksum=sha256:$hex&baz=qux',
    );

    expect(
      source.uri.toString(),
      'https://example.com/static.json?foo=bar&baz=qux',
    );
    expect(source.sha256Hex, hex);
    expect(
      source.raw,
      'https://example.com/static.json?foo=bar&checksum=sha256:$hex&baz=qux',
    );
  });

  test('preserves repeated non-checksum query parameters', () {
    const hex =
        '1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a';
    final source = parseStaticVotingConfigSource(
      'https://example.com/static.json?foo=one&foo=two&checksum=sha256:$hex',
    );

    expect(
      source.uri.toString(),
      'https://example.com/static.json?foo=one&foo=two',
    );
    expect(source.sha256Hex, hex);
  });

  test('preserves percent-encoded query values when stripping checksum', () {
    const hex =
        '2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a';
    final source = parseStaticVotingConfigSource(
      'https://example.com/static.json?sig=a%2Fb&checksum=sha256:$hex',
    );

    expect(source.uri.toString(), 'https://example.com/static.json?sig=a%2Fb');
    expect(source.sha256Hex, hex);
  });

  test('rejects malformed static config sources', () {
    const validHex =
        '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a';
    const shortHex =
        '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a';
    const uppercaseHex =
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    for (final source in [
      'http://example.com/static.json?checksum=sha256:$validHex',
      'https:///static.json?checksum=sha256:$validHex',
      'not-a-url',
      'https://user:token@example.com/static.json?checksum=sha256:$validHex',
      'https://example.com/static.json#v2',
      'https://example.com/static.json?checksum=sha512:$validHex',
      'https://example.com/static.json?checksum=sha256:',
      'https://example.com/static.json?checksum=sha256:$shortHex',
      'https://example.com/static.json?checksum=sha256:$uppercaseHex',
      'https://example.com/static.json?checksum=sha256:$validHex&checksum=sha256:$validHex',
      'https://example.com/static.json?checksum=sha256:'
          'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz',
      'https://example.com/static.json?%63hecksum=sha256:$validHex',
    ]) {
      expect(
        () => parseStaticVotingConfigSource(source),
        throwsA(isA<StaticVotingConfigSourceMalformed>()),
      );
    }
  });

  test('load fetches static then dynamic config and resolves', () async {
    final staticSource = parseStaticVotingConfigSource(
      'https://voting.example/static-voting-config.json?checksum=sha256:'
      '0000000000000000000000000000000000000000000000000000000000000000',
    );
    const dynamicUrl = 'https://voting.example/dynamic-voting-config.json';
    final http = FakeVotingHttpClient(
      responses: {
        staticSource.uri.toString(): '{"static":true}',
        dynamicUrl: '{"dynamic":true}',
      },
    );
    var staticResolved = false;
    final loader = VotingConfigLoader(
      httpClient: http,
      sourceUrl: staticSource.raw,
      resolveStaticVotingConfig: ({
        required source,
        required staticBytes,
      }) async {
        expect(source, staticSource.raw);
        expect(staticBytes, utf8.encode('{"static":true}'));
        staticResolved = true;
        return dynamicUrl;
      },
      resolveVotingConfig: ({
        required source,
        required staticBytes,
        required dynamicBytes,
        previous,
      }) async {
        expect(staticResolved, isTrue);
        expect(source, staticSource.raw);
        expect(staticBytes, utf8.encode('{"static":true}'));
        expect(dynamicBytes, utf8.encode('{"dynamic":true}'));
        return rust_config_api.VotingConfigResolution(
          config: _resolvedConfig(),
          switchKind: rust_config.ConfigSwitchKind.initialLoad,
        );
      },
    );

    final resolution = await loader.load();
    expect(resolution.config.apiBaseUrl.toString(), 'https://voting.example');
    expect(resolution.config.pirEndpointUrls.single.toString(), 'https://pir.example');
    expect(http.requests.map((request) => request.uri.toString()), [
      'https://voting.example/static-voting-config.json',
      dynamicUrl,
    ]);
  });

  test('load forwards previous resolved config to resolver', () async {
    const dynamicUrl = 'https://voting.example/dynamic-voting-config.json';
    final staticUri =
        parseStaticVotingConfigSource(kDefaultStaticVotingConfigSource).uri;
    rust_config.ResolvedVotingConfig? capturedPrevious;
    final previous = _resolvedConfig();
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {staticUri.toString(): '{}', dynamicUrl: '{}'},
      ),
      resolveStaticVotingConfig: ({required source, required staticBytes}) async =>
          dynamicUrl,
      resolveVotingConfig: ({
        required source,
        required staticBytes,
        required dynamicBytes,
        previous,
      }) async {
        capturedPrevious = previous;
        return rust_config_api.VotingConfigResolution(
          config: _resolvedConfig(),
          switchKind: rust_config.ConfigSwitchKind.unchanged,
        );
      },
    );

    await loader.load(previous: previous);
    expect(capturedPrevious, same(previous));
  });

  test('static fetch failure surfaces typed transport exception', () async {
    final staticSource = parseStaticVotingConfigSource(
      'https://voting.example/static-voting-config.json',
    );
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {
          staticSource.uri.toString(): textResponse('unavailable', statusCode: 503),
        },
      ),
      sourceUrl: staticSource.raw,
      resolveStaticVotingConfig: ({required source, required staticBytes}) async =>
          fail('resolveStaticVotingConfig must not run when static fetch fails'),
      resolveVotingConfig: ({
        required source,
        required staticBytes,
        required dynamicBytes,
        previous,
      }) async =>
          fail('resolveVotingConfig must not run when static fetch fails'),
    );

    await expectLater(
      loader.load(),
      throwsA(
        isA<VotingHttpException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.uri.toString(),
              'uri',
              staticSource.uri.toString(),
            ),
      ),
    );
  });

  test('dynamic fetch failure surfaces typed transport exception', () async {
    final staticSource = parseStaticVotingConfigSource(
      'https://voting.example/static-voting-config.json',
    );
    const dynamicUrl = 'https://voting.example/dynamic-voting-config.json';
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {
          staticSource.uri.toString(): '{}',
          dynamicUrl: textResponse('boom', statusCode: 500),
        },
      ),
      sourceUrl: staticSource.raw,
      resolveStaticVotingConfig: ({required source, required staticBytes}) async =>
          dynamicUrl,
      resolveVotingConfig: ({
        required source,
        required staticBytes,
        required dynamicBytes,
        previous,
      }) async =>
          fail('resolveVotingConfig must not run when dynamic fetch fails'),
    );

    await expectLater(
      loader.load(),
      throwsA(
        isA<VotingHttpException>()
            .having((error) => error.statusCode, 'statusCode', 500)
            .having((error) => error.uri.toString(), 'uri', dynamicUrl),
      ),
    );
  });

  test('load succeeds and surfaces skipped round IDs', () async {
    const dynamicUrl = 'https://voting.example/dynamic-voting-config.json';
    final staticUri =
        parseStaticVotingConfigSource(kDefaultStaticVotingConfigSource).uri;
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {staticUri.toString(): '{}', dynamicUrl: '{}'},
      ),
      resolveStaticVotingConfig: ({required source, required staticBytes}) async =>
          dynamicUrl,
      resolveVotingConfig: ({
        required source,
        required staticBytes,
        required dynamicBytes,
        previous,
      }) async {
        return rust_config_api.VotingConfigResolution(
          config: _resolvedConfig(
            authenticatedRoundEaPks: const {},
            skippedRoundIds: const [
              '0000000000000000000000000000000000000000000000000000000000000009',
            ],
          ),
          switchKind: rust_config.ConfigSwitchKind.initialLoad,
        );
      },
    );

    final resolution = await loader.load();
    expect(resolution.config.skippedRoundIds, hasLength(1));
    expect(resolution.config.authenticatedRounds, isEmpty);
  });
}

rust_config.ResolvedVotingConfig _resolvedConfig({
  Map<String, Uint8List>? authenticatedRoundEaPks,
  List<String> skippedRoundIds = const [],
}) {
  final effectiveAuthenticatedRoundEaPks =
      authenticatedRoundEaPks ??
      {
        '0000000000000000000000000000000000000000000000000000000000000001':
            Uint8List.fromList(List.filled(32, 1)),
      };
  return rust_config.ResolvedVotingConfig(
    sourceFingerprint: 'source-fp',
    trustedKeyFingerprint: 'key-fp',
    dynamicConfigFingerprint: 'dynamic-fp',
    voteServers: const [
      rust_config.ServiceEndpoint(url: 'https://voting.example', label: 'vote'),
    ],
    pirEndpoints: const [
      rust_config.ServiceEndpoint(url: 'https://pir.example', label: 'pir'),
    ],
    supportedVersions: const rust_config.SupportedVersions(
      pir: ['v0'],
      voteProtocol: 'v0',
      tally: 'v0',
      voteServer: 'v1',
    ),
    authenticatedRounds: effectiveAuthenticatedRoundEaPks.entries
        .map(
          (entry) =>
              rust_config.AuthenticatedRound(roundId: entry.key, eaPk: entry.value),
        )
        .toList(growable: false),
    skippedRoundIds: skippedRoundIds,
    conditions: const [
      rust_config.ConfigCondition(
        kind: rust_config.ConfigConditionKind.dynamicSignaturesVerified,
        status: true,
        message: 'dynamic round signatures verified: authenticated=1, skipped=0',
      ),
    ],
  );
}
