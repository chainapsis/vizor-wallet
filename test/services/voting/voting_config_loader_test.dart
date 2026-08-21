import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/network_config.dart';
import 'package:zcash_wallet/src/rust/api/voting.dart' as rust_config_api;
import 'package:zcash_wallet/src/rust/third_party/zcash_voting/config.dart'
    as rust_config;
import 'package:zcash_wallet/src/services/voting/resolved_voting_config_extensions.dart';
import 'package:zcash_wallet/src/services/voting/voting_config_loader.dart';
import 'package:zcash_wallet/src/services/voting/voting_models.dart';

import 'fake_voting_http.dart';

void main() {
  test('production static config source uses immutable gateway pin', () {
    final source = parseStaticVotingConfigSource(
      kProductionStaticVotingConfigSource,
    );

    expect(
      source.uri.toString(),
      'https://voting.valargroup.dev/pins/prod/'
      '28fc9b631091ae8bc2f8635d8930489238ce144174cbd15a03efb0530b301ebe/'
      'v2-static-voting-config.json',
    );
    expect(
      source.sha256Hex,
      '28fc9b631091ae8bc2f8635d8930489238ce144174cbd15a03efb0530b301ebe',
    );
    expect(source.raw, kProductionStaticVotingConfigSource);
  });

  test('stage static config source uses immutable gateway pin', () {
    final source = parseStaticVotingConfigSource(
      kStageStaticVotingConfigSource,
    );

    expect(
      source.uri.toString(),
      'https://voting.valargroup.dev/pins/stage/'
      '17484ebabab92225205a02a962add09f1659c9798c2e2e325bd8eac56ab3bf8f/'
      'v2-static-voting-config.json',
    );
    expect(
      source.sha256Hex,
      '17484ebabab92225205a02a962add09f1659c9798c2e2e325bd8eac56ab3bf8f',
    );
    expect(source.raw, kStageStaticVotingConfigSource);
  });

  test('default static config follows the launch network', () {
    expect(
      kDefaultStaticVotingConfigSource,
      kZcashDefaultNetworkRaw == 'test'
          ? kStageStaticVotingConfigSource
          : kProductionStaticVotingConfigSource,
    );
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

  test('allows static config sources without checksum', () {
    final source = parseStaticVotingConfigSource(
      'https://example.com/static.json',
    );
    expect(source.uri.toString(), 'https://example.com/static.json');
    expect(source.sha256Hex, isNull);
    expect(source.raw, 'https://example.com/static.json');
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
      resolveStaticVotingConfig:
          ({required source, required staticBytes}) async {
            expect(source, staticSource.raw);
            expect(staticBytes, utf8.encode('{"static":true}'));
            staticResolved = true;
            return [dynamicUrl];
          },
      resolveVotingConfigFromAttempts:
          ({
            required source,
            required staticBytes,
            required attempts,
            previous,
          }) async {
            expect(staticResolved, isTrue);
            expect(source, staticSource.raw);
            expect(staticBytes, utf8.encode('{"static":true}'));
            expect(attempts.single.bytes, utf8.encode('{"dynamic":true}'));
            return rust_config_api.VotingConfigResolution(
              config: _resolvedConfig(),
              switchKind: rust_config.ConfigSwitchKind.initialLoad,
              skippedMirrors: const [],
            );
          },
    );

    final resolution = await loader.load();
    expect(resolution.config.apiBaseUrl.toString(), 'https://voting.example');
    expect(
      resolution.config.pirEndpointUrls.single.toString(),
      'https://pir.example',
    );
    expect(http.requests.map((request) => request.uri.toString()), [
      'https://voting.example/static-voting-config.json',
      dynamicUrl,
    ]);
    expect(http.requests.map((request) => request.headers), [
      {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
    ]);
  });

  test('load cache-busts GitHub raw branch dynamic config', () async {
    final staticSource = parseStaticVotingConfigSource(
      'https://voting.example/static-voting-config.json?checksum=sha256:'
      '0000000000000000000000000000000000000000000000000000000000000000',
    );
    const dynamicUrl =
        'https://raw.githubusercontent.com/valargroup/'
        'token-holder-voting-config/main/stage/dynamic-voting-config.json';
    final http = FakeVotingHttpClient(
      responses: {
        staticSource.uri.toString(): '{"static":true}',
        '/valargroup/token-holder-voting-config/main/stage/dynamic-voting-config.json':
            '{"dynamic":true}',
      },
    );
    final loader = VotingConfigLoader(
      httpClient: http,
      sourceUrl: staticSource.raw,
      resolveStaticVotingConfig:
          ({required source, required staticBytes}) async => [dynamicUrl],
      resolveVotingConfigFromAttempts:
          ({
            required source,
            required staticBytes,
            required attempts,
            previous,
          }) async {
            expect(attempts.single.bytes, utf8.encode('{"dynamic":true}'));
            return rust_config_api.VotingConfigResolution(
              config: _resolvedConfig(),
              switchKind: rust_config.ConfigSwitchKind.initialLoad,
              skippedMirrors: const [],
            );
          },
    );

    await loader.load();

    final dynamicRequest = http.requests.singleWhere(
      (request) =>
          request.uri.path ==
          '/valargroup/token-holder-voting-config/main/stage/dynamic-voting-config.json',
    );
    expect(dynamicRequest.uri.scheme, 'https');
    expect(dynamicRequest.uri.host, 'raw.githubusercontent.com');
    expect(dynamicRequest.uri.queryParameters['vizor_cache_bust'], isNotEmpty);
    expect(dynamicRequest.headers, {
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
    });
  });

  test('load does not cache-bust GitHub raw pinned dynamic config', () async {
    final staticSource = parseStaticVotingConfigSource(
      'https://voting.example/static-voting-config.json?checksum=sha256:'
      '0000000000000000000000000000000000000000000000000000000000000000',
    );
    const dynamicUrl =
        'https://raw.githubusercontent.com/valargroup/'
        'token-holder-voting-config/671f76403eea8aaf64a87cb484c4b0cdaea596db/'
        'prod/dynamic-voting-config.json';
    final http = FakeVotingHttpClient(
      responses: {
        staticSource.uri.toString(): '{"static":true}',
        dynamicUrl: '{"dynamic":true}',
      },
    );
    final loader = VotingConfigLoader(
      httpClient: http,
      sourceUrl: staticSource.raw,
      resolveStaticVotingConfig:
          ({required source, required staticBytes}) async => [dynamicUrl],
      resolveVotingConfigFromAttempts:
          ({
            required source,
            required staticBytes,
            required attempts,
            previous,
          }) async {
            return rust_config_api.VotingConfigResolution(
              config: _resolvedConfig(),
              switchKind: rust_config.ConfigSwitchKind.initialLoad,
              skippedMirrors: const [],
            );
          },
    );

    await loader.load();

    expect(http.requests.map((request) => request.uri.toString()), [
      'https://voting.example/static-voting-config.json',
      dynamicUrl,
    ]);
  });

  test('load forwards previous resolved config to resolver', () async {
    const dynamicUrl = 'https://voting.example/dynamic-voting-config.json';
    final staticUri = parseStaticVotingConfigSource(
      kDefaultStaticVotingConfigSource,
    ).uri;
    rust_config.ResolvedVotingConfig? capturedPrevious;
    final previous = _resolvedConfig();
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {staticUri.toString(): '{}', dynamicUrl: '{}'},
      ),
      resolveStaticVotingConfig:
          ({required source, required staticBytes}) async => [dynamicUrl],
      resolveVotingConfigFromAttempts:
          ({
            required source,
            required staticBytes,
            required attempts,
            previous,
          }) async {
            capturedPrevious = previous;
            return rust_config_api.VotingConfigResolution(
              config: _resolvedConfig(),
              switchKind: rust_config.ConfigSwitchKind.unchanged,
              skippedMirrors: const [],
            );
          },
    );

    await loader.load(previous: previous);
    expect(capturedPrevious, same(previous));
  });

  test('static fetch failure surfaces typed transport exception', () async {
    final staticSource = parseStaticVotingConfigSource(
      'https://voting.example/static-voting-config.json?checksum=sha256:'
      '1111111111111111111111111111111111111111111111111111111111111111',
    );
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {
          staticSource.uri.toString(): textResponse(
            'unavailable',
            statusCode: 503,
          ),
        },
      ),
      sourceUrl: staticSource.raw,
      resolveStaticVotingConfig:
          ({required source, required staticBytes}) async => fail(
            'resolveStaticVotingConfig must not run when static fetch fails',
          ),
      resolveVotingConfigFromAttempts:
          ({
            required source,
            required staticBytes,
            required attempts,
            previous,
          }) async =>
              fail('resolver must not run when every static mirror fails'),
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
      'https://voting.example/static-voting-config.json?checksum=sha256:'
      '2222222222222222222222222222222222222222222222222222222222222222',
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
      resolveStaticVotingConfig:
          ({required source, required staticBytes}) async => [dynamicUrl],
      resolveVotingConfigFromAttempts:
          ({
            required source,
            required staticBytes,
            required attempts,
            previous,
          }) async =>
              fail('resolver must not run when every dynamic mirror fails'),
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
    final staticUri = parseStaticVotingConfigSource(
      kDefaultStaticVotingConfigSource,
    ).uri;
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {staticUri.toString(): '{}', dynamicUrl: '{}'},
      ),
      resolveStaticVotingConfig:
          ({required source, required staticBytes}) async => [dynamicUrl],
      resolveVotingConfigFromAttempts:
          ({
            required source,
            required staticBytes,
            required attempts,
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
              skippedMirrors: const [],
            );
          },
    );

    final resolution = await loader.load();
    expect(resolution.config.skippedRoundIds, hasLength(1));
    expect(resolution.config.authenticatedRounds, isEmpty);
  });

  test('bundled mirrors pin identical bytes on independent origins', () {
    for (final mirrors in [
      kProductionStaticVotingConfigMirrors,
      kStageStaticVotingConfigMirrors,
    ]) {
      expect(mirrors, hasLength(2));
      final parsed = mirrors.map(parseStaticVotingConfigSource).toList();
      // Same pinned bytes, so whichever answers is equally authentic.
      expect(parsed[0].sha256Hex, parsed[1].sha256Hex);
      expect(parsed[0].sha256Hex, isNotNull);
      // Different origins, or the fallback buys no availability at all.
      expect(parsed[0].uri.host, isNot(parsed[1].uri.host));
      // The pin path embeds the hash it is pinned to.
      for (final source in parsed) {
        expect(source.uri.path, contains(source.sha256Hex!));
      }
    }
    expect(
      kDefaultStaticVotingConfigMirrors.first,
      kDefaultStaticVotingConfigSource,
    );
  });

  test(
    'static mirror fallback recovers from a primary transport failure',
    () async {
      final mirrors = kProductionStaticVotingConfigMirrors
          .map(parseStaticVotingConfigSource)
          .toList();
      const dynamicUrl = 'https://voting.example/dynamic-voting-config.json';
      final http = FakeVotingHttpClient(
        responses: {
          mirrors[0].uri.toString(): textResponse('down', statusCode: 503),
          mirrors[1].uri.toString(): '{"static":true}',
          dynamicUrl: '{"dynamic":true}',
        },
      );
      final loader = VotingConfigLoader(
        httpClient: http,
        sourceUrl: kProductionStaticVotingConfigSource,
        resolveStaticVotingConfig:
            ({required source, required staticBytes}) async {
              // Rust is told which origin actually answered, and every mirror
              // carries the same checksum, so the pin check is unchanged.
              expect(source, mirrors[1].raw);
              return [dynamicUrl];
            },
        resolveVotingConfigFromAttempts:
            ({
              required source,
              required staticBytes,
              required attempts,
              previous,
            }) async {
              return rust_config_api.VotingConfigResolution(
                config: _resolvedConfig(),
                switchKind: rust_config.ConfigSwitchKind.initialLoad,
                skippedMirrors: const [],
              );
            },
      );

      await loader.load();

      expect(http.requests.map((request) => request.uri.toString()), [
        mirrors[0].uri.toString(),
        mirrors[1].uri.toString(),
        dynamicUrl,
      ]);
    },
  );

  test(
    'static mirror fallback recovers when a mirror serves bad bytes',
    () async {
      final mirrors = kProductionStaticVotingConfigMirrors
          .map(parseStaticVotingConfigSource)
          .toList();
      const dynamicUrl = 'https://voting.example/dynamic-voting-config.json';
      final http = FakeVotingHttpClient(
        responses: {
          mirrors[0].uri.toString(): 'stale bytes',
          mirrors[1].uri.toString(): '{"static":true}',
          dynamicUrl: '{"dynamic":true}',
        },
      );
      final loader = VotingConfigLoader(
        httpClient: http,
        sourceUrl: kProductionStaticVotingConfigSource,
        resolveStaticVotingConfig:
            ({required source, required staticBytes}) async {
              if (source == mirrors[0].raw) {
                throw 'static config hash-pin mismatch';
              }
              return [dynamicUrl];
            },
        resolveVotingConfigFromAttempts:
            ({
              required source,
              required staticBytes,
              required attempts,
              previous,
            }) async {
              expect(source, mirrors[1].raw);
              return rust_config_api.VotingConfigResolution(
                config: _resolvedConfig(),
                switchKind: rust_config.ConfigSwitchKind.initialLoad,
                skippedMirrors: const [],
              );
            },
      );

      await loader.load();

      expect(http.requests.map((request) => request.uri.toString()), [
        mirrors[0].uri.toString(),
        mirrors[1].uri.toString(),
        dynamicUrl,
      ]);
    },
  );

  test(
    'every static mirror failing surfaces the first transport exception',
    () async {
      final mirrors = kProductionStaticVotingConfigMirrors
          .map(parseStaticVotingConfigSource)
          .toList();
      final loader = VotingConfigLoader(
        httpClient: FakeVotingHttpClient(
          responses: {
            mirrors[0].uri.toString(): textResponse('down', statusCode: 503),
            mirrors[1].uri.toString(): textResponse('down', statusCode: 502),
          },
        ),
        sourceUrl: kProductionStaticVotingConfigSource,
        resolveStaticVotingConfig:
            ({required source, required staticBytes}) async =>
                fail('resolver must not run when every static mirror fails'),
        resolveVotingConfigFromAttempts:
            ({
              required source,
              required staticBytes,
              required attempts,
              previous,
            }) async =>
                fail('resolver must not run when every static mirror fails'),
      );

      // Typed, because isRetryableVotingError keys retry and last-good-config
      // reuse off VotingHttpException.
      await expectLater(
        loader.load(),
        throwsA(
          isA<VotingHttpException>()
              .having((error) => error.statusCode, 'statusCode', 503)
              .having(
                (error) => error.uri.toString(),
                'uri',
                mirrors[0].uri.toString(),
              ),
        ),
      );
    },
  );

  test('a custom source gets no mirrors it did not ask for', () async {
    final custom = parseStaticVotingConfigSource(
      'https://custom.example/static-voting-config.json',
    );
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {
          custom.uri.toString(): textResponse('down', statusCode: 503),
        },
      ),
      sourceUrl: custom.raw,
      resolveStaticVotingConfig:
          ({required source, required staticBytes}) async =>
              fail('unreachable'),
      resolveVotingConfigFromAttempts:
          ({
            required source,
            required staticBytes,
            required attempts,
            previous,
          }) async => fail('unreachable'),
    );

    await expectLater(loader.load(), throwsA(isA<VotingHttpException>()));
  });

  test(
    'dynamic mirror fallback recovers from an unreachable primary',
    () async {
      final staticUri = parseStaticVotingConfigSource(
        kDefaultStaticVotingConfigSource,
      ).uri;
      const mirrorA = 'https://voting.example/dynamic-voting-config.json';
      const mirrorB = 'https://mirror.example/dynamic-voting-config.json';
      final loader = VotingConfigLoader(
        httpClient: FakeVotingHttpClient(
          responses: {
            staticUri.toString(): '{}',
            mirrorA: textResponse('down', statusCode: 503),
            mirrorB: '{"dynamic":true}',
          },
        ),
        resolveStaticVotingConfig:
            ({required source, required staticBytes}) async => [
              mirrorA,
              mirrorB,
            ],
        resolveVotingConfigFromAttempts:
            ({
              required source,
              required staticBytes,
              required attempts,
              previous,
            }) async {
              // The whole accumulated list is handed back each pass; Rust, not
              // Dart, decides which mirror wins.
              expect(attempts.map((attempt) => attempt.url), [
                mirrorA,
                mirrorB,
              ]);
              expect(attempts[0].bytes, isNull);
              expect(attempts[0].error, isNotNull);
              expect(attempts[1].bytes, utf8.encode('{"dynamic":true}'));
              return rust_config_api.VotingConfigResolution(
                config: _resolvedConfig(),
                switchKind: rust_config.ConfigSwitchKind.initialLoad,
                skippedMirrors: const [
                  rust_config_api.ApiDynamicConfigMirrorFailure(
                    url: mirrorA,
                    reason: 'fetch failed',
                  ),
                ],
              );
            },
      );

      final resolution = await loader.load();
      expect(resolution.skippedMirrors.single.url, mirrorA);
    },
  );

  test(
    'a rescued hash-pin mismatch is still reported as an integrity failure',
    () async {
      final mirrors = kProductionStaticVotingConfigMirrors
          .map(parseStaticVotingConfigSource)
          .toList();
      const dynamicUrl = 'https://voting.example/dynamic-voting-config.json';
      final failures = <VotingConfigMirrorFailure>[];
      final loader = VotingConfigLoader(
        httpClient: FakeVotingHttpClient(
          responses: {
            mirrors[0].uri.toString(): 'tampered bytes',
            mirrors[1].uri.toString(): '{"static":true}',
            dynamicUrl: '{"dynamic":true}',
          },
        ),
        sourceUrl: kProductionStaticVotingConfigSource,
        onMirrorFailure: failures.add,
        resolveStaticVotingConfig:
            ({required source, required staticBytes}) async {
              if (source == mirrors[0].raw) {
                throw Exception('static config hash-pin mismatch');
              }
              return [dynamicUrl];
            },
        resolveVotingConfigFromAttempts:
            ({
              required source,
              required staticBytes,
              required attempts,
              previous,
            }) async => rust_config_api.VotingConfigResolution(
              config: _resolvedConfig(),
              switchKind: rust_config.ConfigSwitchKind.initialLoad,
              skippedMirrors: const [],
            ),
      );

      // The load succeeds off the fallback origin, so its return value carries
      // no trace of the pin mismatch. The side channel is the only record.
      await loader.load();

      expect(failures, hasLength(1));
      expect(failures.single.stage, VotingConfigMirrorStage.staticAnchor);
      expect(failures.single.kind, VotingConfigMirrorFailureKind.integrity);
      expect(failures.single.isIntegrityFailure, isTrue);
      expect(failures.single.url, mirrors[0].uri.toString());
    },
  );

  test(
    'a transport-preferred throw still reports the integrity failure it hides',
    () async {
      final staticUri = parseStaticVotingConfigSource(
        kDefaultStaticVotingConfigSource,
      ).uri;
      const mirrorA = 'https://voting.example/dynamic-voting-config.json';
      const mirrorB = 'https://mirror.example/dynamic-voting-config.json';
      final failures = <VotingConfigMirrorFailure>[];
      final loader = VotingConfigLoader(
        httpClient: FakeVotingHttpClient(
          responses: {
            staticUri.toString(): '{}',
            // Answers, but with bytes Rust rejects.
            mirrorA: '{"a":true}',
            mirrorB: textResponse('down', statusCode: 503),
          },
        ),
        onMirrorFailure: failures.add,
        resolveStaticVotingConfig:
            ({required source, required staticBytes}) async => [
              mirrorA,
              mirrorB,
            ],
        resolveVotingConfigFromAttempts:
            ({
              required source,
              required staticBytes,
              required attempts,
              previous,
            }) async => throw Exception('dynamic config signature invalid'),
      );

      // The throw stays a transport exception so the caller keeps its
      // last-good config rather than hard-failing on a flaky network...
      await expectLater(loader.load(), throwsA(isA<VotingHttpException>()));

      // ...but the integrity failure it hides is not lost with it.
      expect(
        failures
            .where((failure) => failure.isIntegrityFailure)
            .map((failure) => failure.url),
        contains(mirrorA),
      );
      expect(
        failures.where(
          (failure) => failure.kind == VotingConfigMirrorFailureKind.transport,
        ),
        isNotEmpty,
      );
    },
  );

  test('an observer that throws cannot fail an otherwise good load', () async {
    final mirrors = kProductionStaticVotingConfigMirrors
        .map(parseStaticVotingConfigSource)
        .toList();
    const dynamicUrl = 'https://voting.example/dynamic-voting-config.json';
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {
          mirrors[0].uri.toString(): textResponse('down', statusCode: 503),
          mirrors[1].uri.toString(): '{"static":true}',
          dynamicUrl: '{"dynamic":true}',
        },
      ),
      sourceUrl: kProductionStaticVotingConfigSource,
      onMirrorFailure: (_) => throw StateError('observer exploded'),
      resolveStaticVotingConfig:
          ({required source, required staticBytes}) async => [dynamicUrl],
      resolveVotingConfigFromAttempts:
          ({
            required source,
            required staticBytes,
            required attempts,
            previous,
          }) async => rust_config_api.VotingConfigResolution(
            config: _resolvedConfig(),
            switchKind: rust_config.ConfigSwitchKind.initialLoad,
            skippedMirrors: const [],
          ),
    );

    final resolution = await loader.load();
    expect(resolution.config.authenticatedRounds, isNotEmpty);
  });

  test(
    'a round-less primary ends the walk instead of costing a second fetch',
    () async {
      final staticUri = parseStaticVotingConfigSource(
        kDefaultStaticVotingConfigSource,
      ).uri;
      const mirrorA = 'https://voting.example/dynamic-voting-config.json';
      const mirrorB = 'https://mirror.example/dynamic-voting-config.json';
      var passes = 0;
      final http = FakeVotingHttpClient(
        responses: {
          staticUri.toString(): '{}',
          mirrorA: '{"a":true}',
          mirrorB: '{"b":true}',
        },
      );
      final loader = VotingConfigLoader(
        httpClient: http,
        resolveStaticVotingConfig:
            ({required source, required staticBytes}) async => [
              mirrorA,
              mirrorB,
            ],
        resolveVotingConfigFromAttempts:
            ({
              required source,
              required staticBytes,
              required attempts,
              previous,
            }) async {
              passes += 1;
              return rust_config_api.VotingConfigResolution(
                config: _resolvedConfig(
                  // The primary resolves, but authenticates nothing — prod's
                  // normal steady state, not evidence that it is stale.
                  authenticatedRoundEaPks: passes == 1 ? const {} : null,
                ),
                switchKind: rust_config.ConfigSwitchKind.initialLoad,
                skippedMirrors: const [],
              );
            },
      );

      final resolution = await loader.load();
      // Round count is not a freshness signal, so the empty round set is the
      // answer and mirror B is never fetched.
      expect(passes, 1);
      expect(resolution.config.authenticatedRounds, isEmpty);
      expect(
        http.requests.map((request) => request.uri.toString()),
        isNot(contains(mirrorB)),
      );
    },
  );

  test('a round-less resolution is accepted as a normal outcome', () async {
    final staticUri = parseStaticVotingConfigSource(
      kDefaultStaticVotingConfigSource,
    ).uri;
    const mirrorA = 'https://voting.example/dynamic-voting-config.json';
    const mirrorB = 'https://mirror.example/dynamic-voting-config.json';
    final loader = VotingConfigLoader(
      httpClient: FakeVotingHttpClient(
        responses: {
          staticUri.toString(): '{}',
          mirrorA: '{"a":true}',
          mirrorB: '{"b":true}',
        },
      ),
      resolveStaticVotingConfig:
          ({required source, required staticBytes}) async => [mirrorA, mirrorB],
      resolveVotingConfigFromAttempts:
          ({
            required source,
            required staticBytes,
            required attempts,
            previous,
          }) async {
            return rust_config_api.VotingConfigResolution(
              config: _resolvedConfig(authenticatedRoundEaPks: const {}),
              switchKind: rust_config.ConfigSwitchKind.initialLoad,
              skippedMirrors: const [],
            );
          },
    );

    // Prod resolves with zero rounds today; that is a valid outcome, not an
    // error and not a reason to keep walking.
    final resolution = await loader.load();
    expect(resolution.config.authenticatedRounds, isEmpty);
  });

  test(
    'every dynamic mirror failing surfaces the first transport exception',
    () async {
      final staticUri = parseStaticVotingConfigSource(
        kDefaultStaticVotingConfigSource,
      ).uri;
      const mirrorA = 'https://voting.example/dynamic-voting-config.json';
      const mirrorB = 'https://mirror.example/dynamic-voting-config.json';
      final loader = VotingConfigLoader(
        httpClient: FakeVotingHttpClient(
          responses: {
            staticUri.toString(): '{}',
            mirrorA: textResponse('down', statusCode: 503),
            mirrorB: textResponse('down', statusCode: 502),
          },
        ),
        resolveStaticVotingConfig:
            ({required source, required staticBytes}) async => [
              mirrorA,
              mirrorB,
            ],
        resolveVotingConfigFromAttempts:
            ({
              required source,
              required staticBytes,
              required attempts,
              previous,
            }) async =>
                fail('resolver must not run when every dynamic mirror fails'),
      );

      await expectLater(
        loader.load(),
        throwsA(
          isA<VotingHttpException>()
              .having((error) => error.statusCode, 'statusCode', 503)
              .having((error) => error.uri.toString(), 'uri', mirrorA),
        ),
      );
    },
  );
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
    pirLayout: const rust_config.PirLayout(
      pirDepth: 19,
      tier0Layers: 12,
      tier1Layers: 7,
      polyLen: 4096,
    ),
    supportedVersions: const rust_config.SupportedVersions(
      pir: ['v0'],
      voteProtocol: 'v0',
      tally: 'v0',
      voteServer: 'v1',
    ),
    authenticatedRounds: effectiveAuthenticatedRoundEaPks.entries
        .map(
          (entry) => rust_config.AuthenticatedRound(
            roundId: entry.key,
            eaPk: entry.value,
          ),
        )
        .toList(growable: false),
    skippedRoundIds: skippedRoundIds,
    conditions: const [
      rust_config.ConfigCondition(
        kind: rust_config.ConfigConditionKind.dynamicSignaturesVerified,
        status: true,
        message:
            'dynamic round signatures verified: authenticated=1, skipped=0',
      ),
    ],
  );
}
