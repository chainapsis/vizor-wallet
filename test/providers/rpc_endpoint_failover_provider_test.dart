import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';

void main() {
  test('classifies transient endpoint failures only', () {
    expect(
      shouldFallbackFromLightwalletdError(
        'network: get_latest_block: status: DeadlineExceeded',
      ),
      isTrue,
    );
    expect(
      shouldFallbackFromLightwalletdError(
        'gRPC connect failed: connection refused',
      ),
      isTrue,
    );
    expect(
      shouldFallbackFromLightwalletdError(
        'Endpoint is for test, but this wallet uses main.',
      ),
      isFalse,
    );
    expect(
      shouldFallbackFromLightwalletdError(
        'Proposal not found (expired or already executed)',
      ),
      isFalse,
    );
  });

  test('checkRpcEndpointHealth rejects wrong-network endpoints', () async {
    await expectLater(
      checkRpcEndpointHealth(
        endpoint: defaultRpcEndpointConfig('main'),
        getChainName: (_) async => 'test',
        getLatestBlockHeight: (_) async => BigInt.from(10),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('runWithEndpointFallback switches to a healthy fallback', () async {
    final primary = defaultRpcEndpointConfig('main');
    final container = _container(
      primary: primary,
      chainNameByUrl: {'https://eu.zec.stardust.rest:443': 'main'},
      heightByUrl: {'https://eu.zec.stardust.rest:443': BigInt.from(10)},
    );
    addTearDown(container.dispose);

    final result = await container
        .read(rpcEndpointFailoverProvider.notifier)
        .runWithEndpointFallback(
          operation: 'test read',
          action: (endpoint) async {
            if (endpoint.normalizedLightwalletdUrl ==
                primary.normalizedLightwalletdUrl) {
              throw Exception('gRPC connect failed: connection refused');
            }
            return endpoint.hostPort;
          },
        );

    final state = container.read(rpcEndpointFailoverProvider);
    expect(result, 'eu.zec.stardust.rest:443');
    expect(state.isUsingFallback, isTrue);
    expect(
      state.current.normalizedLightwalletdUrl,
      'https://eu.zec.stardust.rest:443',
    );
    expect(
      state.lastEvent?.kind,
      RpcEndpointFailoverEventKind.switchedToFallback,
    );
  });

  test('does not fallback from custom endpoints', () async {
    final primary = _customRegtestPrimary();
    final container = _container(
      primary: primary,
      chainNameByUrl: {'http://127.0.0.1:9067': 'regtest'},
      heightByUrl: {'http://127.0.0.1:9067': BigInt.from(10)},
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(rpcEndpointFailoverProvider.notifier)
          .runWithEndpointFallback(
            operation: 'test read',
            action: (_) async =>
                throw Exception('gRPC connect failed: connection refused'),
          ),
      throwsA(isA<Exception>()),
    );

    final state = container.read(rpcEndpointFailoverProvider);
    expect(state.fallbackCandidates, isEmpty);
    expect(state.isUsingFallback, isFalse);
    expect(state.lastEvent, isNull);
  });

  test('tries fallback candidates in configured order', () async {
    final primary = defaultRpcEndpointConfig('main');
    final container = _container(
      primary: primary,
      chainNameByUrl: {'https://eu2.zec.stardust.rest:443': 'main'},
      heightByUrl: {'https://eu2.zec.stardust.rest:443': BigInt.from(12)},
    );
    addTearDown(container.dispose);

    final result = await container
        .read(rpcEndpointFailoverProvider.notifier)
        .runWithEndpointFallback(
          operation: 'test read',
          action: (endpoint) async {
            if (endpoint.normalizedLightwalletdUrl ==
                primary.normalizedLightwalletdUrl) {
              throw Exception('gRPC connect failed: connection refused');
            }
            return endpoint.hostPort;
          },
        );

    final state = container.read(rpcEndpointFailoverProvider);
    expect(result, 'eu2.zec.stardust.rest:443');
    expect(state.current.presetId, 'eu2-zec-stardust');
  });

  test('rotates from a failed fallback to the next healthy preset', () async {
    final primary = defaultRpcEndpointConfig('main');
    final container = _container(
      primary: primary,
      chainNameByUrl: {
        'https://eu.zec.stardust.rest:443': 'main',
        'https://eu2.zec.stardust.rest:443': 'main',
      },
      heightByUrl: {
        'https://eu.zec.stardust.rest:443': BigInt.from(10),
        'https://eu2.zec.stardust.rest:443': BigInt.from(11),
      },
    );
    addTearDown(container.dispose);

    await container
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(
          Exception('DeadlineExceeded'),
          operation: 'primary sync',
        );
    var state = container.read(rpcEndpointFailoverProvider);
    expect(state.current.presetId, 'eu-zec-stardust');

    final switched = await container
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(
          Exception('connection reset'),
          endpoint: state.current,
          operation: 'fallback sync',
        );

    state = container.read(rpcEndpointFailoverProvider);
    expect(switched, isTrue);
    expect(state.current.presetId, 'eu2-zec-stardust');
    expect(
      state.lastEvent?.kind,
      RpcEndpointFailoverEventKind.switchedToFallback,
    );
  });

  test(
    'runWithEndpointFallback retries after current fallback fails',
    () async {
      final primary = defaultRpcEndpointConfig('main');
      final container = _container(
        primary: primary,
        chainNameByUrl: {
          'https://eu.zec.stardust.rest:443': 'main',
          'https://eu2.zec.stardust.rest:443': 'main',
        },
        heightByUrl: {
          'https://eu.zec.stardust.rest:443': BigInt.from(10),
          'https://eu2.zec.stardust.rest:443': BigInt.from(11),
        },
      );
      addTearDown(container.dispose);

      final notifier = container.read(rpcEndpointFailoverProvider.notifier);
      await notifier.switchToFallbackFor(
        Exception('DeadlineExceeded'),
        operation: 'primary sync',
      );
      expect(
        container.read(rpcEndpointFailoverProvider).current.presetId,
        'eu-zec-stardust',
      );

      final result = await notifier.runWithEndpointFallback(
        operation: 'fallback poll',
        action: (endpoint) async {
          if (endpoint.presetId == 'eu-zec-stardust') {
            throw Exception('connection reset');
          }
          return endpoint.presetId;
        },
      );

      expect(result, 'eu2-zec-stardust');
      expect(
        container.read(rpcEndpointFailoverProvider).current.presetId,
        'eu2-zec-stardust',
      );
    },
  );

  test('does not rotate from fallback back to primary outside probe', () async {
    final primary = defaultRpcEndpointConfig('main');
    final primaryUrl = primary.normalizedLightwalletdUrl;
    final chainNameByUrl = <String, String>{
      'https://eu.zec.stardust.rest:443': 'main',
    };
    final heightByUrl = <String, BigInt>{
      'https://eu.zec.stardust.rest:443': BigInt.from(10),
    };
    final container = _container(
      primary: primary,
      chainNameByUrl: chainNameByUrl,
      heightByUrl: heightByUrl,
    );
    addTearDown(container.dispose);

    await container
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(
          Exception('DeadlineExceeded'),
          operation: 'primary sync',
        );
    var state = container.read(rpcEndpointFailoverProvider);
    expect(state.current.presetId, 'eu-zec-stardust');

    chainNameByUrl
      ..clear()
      ..[primaryUrl] = 'main';
    heightByUrl
      ..clear()
      ..[primaryUrl] = BigInt.from(12);

    final switched = await container
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(
          Exception('connection reset'),
          endpoint: state.current,
          operation: 'fallback sync',
        );

    state = container.read(rpcEndpointFailoverProvider);
    expect(switched, isFalse);
    expect(state.current.presetId, 'eu-zec-stardust');
  });

  test('does not fallback when all candidates fail health checks', () async {
    final primary = defaultRpcEndpointConfig('main');
    final container = _container(
      primary: primary,
      chainNameByUrl: const {},
      heightByUrl: const {},
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(rpcEndpointFailoverProvider.notifier)
          .runWithEndpointFallback(
            operation: 'test read',
            action: (_) async =>
                throw Exception('gRPC connect failed: connection refused'),
          ),
      throwsA(isA<Exception>()),
    );

    expect(
      container.read(rpcEndpointFailoverProvider).isUsingFallback,
      isFalse,
    );
  });

  test('does not fallback for wallet-state errors', () async {
    final primary = defaultRpcEndpointConfig('main');
    final container = _container(
      primary: primary,
      chainNameByUrl: {'https://eu.zec.stardust.rest:443': 'main'},
      heightByUrl: {'https://eu.zec.stardust.rest:443': BigInt.from(10)},
    );
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(rpcEndpointFailoverProvider.notifier)
          .runWithEndpointFallback(
            operation: 'test read',
            action: (_) async =>
                throw Exception('Proposal not found (expired)'),
          ),
      throwsA(isA<Exception>()),
    );

    expect(
      container.read(rpcEndpointFailoverProvider).isUsingFallback,
      isFalse,
    );
  });

  test('periodic primary probe switches back after recovery', () async {
    var now = DateTime(2026);
    final primary = defaultRpcEndpointConfig('main');
    final primaryUrl = primary.normalizedLightwalletdUrl;
    final container = _container(
      primary: primary,
      clock: () => now,
      chainNameByUrl: {
        'https://eu.zec.stardust.rest:443': 'main',
        primaryUrl: 'main',
      },
      heightByUrl: {
        'https://eu.zec.stardust.rest:443': BigInt.from(10),
        primaryUrl: BigInt.from(11),
      },
      settings: const RpcEndpointFailoverSettings(
        primaryProbeInterval: Duration(seconds: 5),
      ),
    );
    addTearDown(container.dispose);

    await container
        .read(rpcEndpointFailoverProvider.notifier)
        .switchToFallbackFor(
          Exception('DeadlineExceeded'),
          operation: 'test sync',
        );
    expect(container.read(rpcEndpointFailoverProvider).isUsingFallback, isTrue);
    expect(
      await container
          .read(rpcEndpointFailoverProvider.notifier)
          .maybeProbePrimary(),
      isFalse,
    );

    now = now.add(const Duration(seconds: 5));
    final recovered = await container
        .read(rpcEndpointFailoverProvider.notifier)
        .maybeProbePrimary();

    final state = container.read(rpcEndpointFailoverProvider);
    expect(recovered, isTrue);
    expect(state.isUsingFallback, isFalse);
    expect(
      state.lastEvent?.kind,
      RpcEndpointFailoverEventKind.switchedToPrimary,
    );
  });

  test('switches when current endpoint height progresses too slowly', () async {
    var now = DateTime(2026);
    final primary = defaultRpcEndpointConfig('main');
    final primaryUrl = primary.normalizedLightwalletdUrl;
    final heightByUrl = <String, BigInt>{
      primaryUrl: BigInt.from(100),
      'https://eu.zec.stardust.rest:443': BigInt.from(103),
    };
    final container = _container(
      primary: primary,
      clock: () => now,
      chainNameByUrl: {'https://eu.zec.stardust.rest:443': 'main'},
      heightByUrl: heightByUrl,
    );
    addTearDown(container.dispose);

    final notifier = container.read(rpcEndpointFailoverProvider.notifier);
    expect(await notifier.getLatestBlockHeight(), BigInt.from(100));

    now = now.add(const Duration(minutes: 5));
    heightByUrl[primaryUrl] = BigInt.from(101);

    expect(await notifier.getLatestBlockHeight(), BigInt.from(103));

    final state = container.read(rpcEndpointFailoverProvider);
    expect(state.current.presetId, 'eu-zec-stardust');
    expect(
      state.lastEvent?.kind,
      RpcEndpointFailoverEventKind.switchedToFallback,
    );
  });

  test(
    'keeps current slow endpoint when no candidate is far enough ahead',
    () async {
      var now = DateTime(2026);
      final primary = defaultRpcEndpointConfig('main');
      final primaryUrl = primary.normalizedLightwalletdUrl;
      final heightByUrl = <String, BigInt>{
        primaryUrl: BigInt.from(100),
        'https://eu.zec.stardust.rest:443': BigInt.from(102),
      };
      final container = _container(
        primary: primary,
        clock: () => now,
        chainNameByUrl: {'https://eu.zec.stardust.rest:443': 'main'},
        heightByUrl: heightByUrl,
      );
      addTearDown(container.dispose);

      final notifier = container.read(rpcEndpointFailoverProvider.notifier);
      expect(await notifier.getLatestBlockHeight(), BigInt.from(100));

      now = now.add(const Duration(minutes: 5));
      heightByUrl[primaryUrl] = BigInt.from(101);

      expect(await notifier.getLatestBlockHeight(), BigInt.from(101));

      final state = container.read(rpcEndpointFailoverProvider);
      expect(state.isUsingFallback, isFalse);
      expect(state.lastEvent, isNull);
      expect(state.heightWindowStartHeight, BigInt.from(101));
    },
  );

  test('skips slow fallback candidates and checks the next preset', () async {
    var now = DateTime(2026);
    final primary = defaultRpcEndpointConfig('main');
    final primaryUrl = primary.normalizedLightwalletdUrl;
    final heightByUrl = <String, BigInt>{
      primaryUrl: BigInt.from(100),
      'https://eu.zec.stardust.rest:443': BigInt.from(102),
      'https://eu2.zec.stardust.rest:443': BigInt.from(104),
    };
    final container = _container(
      primary: primary,
      clock: () => now,
      chainNameByUrl: {
        'https://eu.zec.stardust.rest:443': 'main',
        'https://eu2.zec.stardust.rest:443': 'main',
      },
      heightByUrl: heightByUrl,
    );
    addTearDown(container.dispose);

    final notifier = container.read(rpcEndpointFailoverProvider.notifier);
    expect(await notifier.getLatestBlockHeight(), BigInt.from(100));

    now = now.add(const Duration(minutes: 5));
    heightByUrl[primaryUrl] = BigInt.from(101);

    expect(await notifier.getLatestBlockHeight(), BigInt.from(104));

    final state = container.read(rpcEndpointFailoverProvider);
    expect(state.current.presetId, 'eu2-zec-stardust');
  });

  test(
    'primary probe waits when primary is still behind current fallback',
    () async {
      var now = DateTime(2026);
      final primary = defaultRpcEndpointConfig('main');
      final primaryUrl = primary.normalizedLightwalletdUrl;
      final heightByUrl = <String, BigInt>{
        'https://eu.zec.stardust.rest:443': BigInt.from(110),
        primaryUrl: BigInt.from(108),
      };
      final container = _container(
        primary: primary,
        clock: () => now,
        chainNameByUrl: {
          'https://eu.zec.stardust.rest:443': 'main',
          primaryUrl: 'main',
        },
        heightByUrl: heightByUrl,
        settings: const RpcEndpointFailoverSettings(
          primaryProbeInterval: Duration(seconds: 5),
        ),
      );
      addTearDown(container.dispose);

      final notifier = container.read(rpcEndpointFailoverProvider.notifier);
      await notifier.switchToFallbackFor(
        Exception('DeadlineExceeded'),
        operation: 'primary sync',
      );

      now = now.add(const Duration(seconds: 5));
      expect(await notifier.maybeProbePrimary(), isFalse);
      expect(
        container.read(rpcEndpointFailoverProvider).isUsingFallback,
        isTrue,
      );

      heightByUrl[primaryUrl] = BigInt.from(109);
      expect(await notifier.maybeProbePrimary(force: true), isTrue);
      expect(
        container.read(rpcEndpointFailoverProvider).isUsingFallback,
        isFalse,
      );
    },
  );

  test(
    'primary probe compares against fresh current fallback height',
    () async {
      var now = DateTime(2026);
      final primary = defaultRpcEndpointConfig('main');
      final primaryUrl = primary.normalizedLightwalletdUrl;
      const fallbackUrl = 'https://eu.zec.stardust.rest:443';
      final heightByUrl = <String, BigInt>{
        fallbackUrl: BigInt.from(110),
        primaryUrl: BigInt.from(120),
      };
      final container = _container(
        primary: primary,
        clock: () => now,
        chainNameByUrl: {fallbackUrl: 'main', primaryUrl: 'main'},
        heightByUrl: heightByUrl,
        settings: const RpcEndpointFailoverSettings(
          primaryProbeInterval: Duration(seconds: 5),
        ),
      );
      addTearDown(container.dispose);

      final notifier = container.read(rpcEndpointFailoverProvider.notifier);
      await notifier.switchToFallbackFor(
        Exception('DeadlineExceeded'),
        operation: 'primary sync',
      );

      heightByUrl[fallbackUrl] = BigInt.from(150);
      now = now.add(const Duration(seconds: 5));

      expect(await notifier.maybeProbePrimary(), isFalse);
      var state = container.read(rpcEndpointFailoverProvider);
      expect(state.isUsingFallback, isTrue);
      expect(state.lastObservedHeight, BigInt.from(150));

      heightByUrl[primaryUrl] = BigInt.from(149);
      expect(await notifier.maybeProbePrimary(force: true), isTrue);
      state = container.read(rpcEndpointFailoverProvider);
      expect(state.isUsingFallback, isFalse);
    },
  );

  test(
    'ignores stale fallback when endpoint changes to custom during health check',
    () async {
      final primary = defaultRpcEndpointConfig('main');
      final customSameUrl = primary.copyWith(
        presetId: kCustomRpcEndpointPresetId,
      );
      final fallbackProbeStarted = Completer<void>();
      final releaseFallbackProbe = Completer<void>();
      final harness = _mutableContainer(
        primary: primary,
        getChainName: (url) async {
          if (url == 'https://eu.zec.stardust.rest:443') {
            if (!fallbackProbeStarted.isCompleted) {
              fallbackProbeStarted.complete();
            }
            await releaseFallbackProbe.future;
          }
          return 'main';
        },
        getLatestBlockHeight: (_) async => BigInt.from(10),
      );
      addTearDown(harness.container.dispose);

      final switchedFuture = harness.container
          .read(rpcEndpointFailoverProvider.notifier)
          .switchToFallbackFor(
            Exception('DeadlineExceeded'),
            operation: 'primary sync',
          );

      await fallbackProbeStarted.future;
      harness.endpointNotifier.setForTest(customSameUrl);
      harness.container.read(rpcEndpointFailoverProvider);
      releaseFallbackProbe.complete();

      expect(await switchedFuture, isFalse);
      final state = harness.container.read(rpcEndpointFailoverProvider);
      expect(state.current.effectivePresetId, kCustomRpcEndpointPresetId);
      expect(
        state.current.normalizedLightwalletdUrl,
        primary.normalizedLightwalletdUrl,
      );
      expect(state.fallbackCandidates, isEmpty);
      expect(state.lastEvent, isNull);
    },
  );

  test(
    'ignores stale slow-height fallback after endpoint changes to custom',
    () async {
      var now = DateTime(2026);
      final primary = defaultRpcEndpointConfig('main');
      final primaryUrl = primary.normalizedLightwalletdUrl;
      final customSameUrl = primary.copyWith(
        presetId: kCustomRpcEndpointPresetId,
      );
      final fallbackProbeStarted = Completer<void>();
      final releaseFallbackProbe = Completer<void>();
      final heightByUrl = <String, BigInt>{
        primaryUrl: BigInt.from(100),
        'https://eu.zec.stardust.rest:443': BigInt.from(103),
      };
      final harness = _mutableContainer(
        primary: primary,
        clock: () => now,
        getChainName: (url) async {
          if (url == 'https://eu.zec.stardust.rest:443') {
            if (!fallbackProbeStarted.isCompleted) {
              fallbackProbeStarted.complete();
            }
            await releaseFallbackProbe.future;
          }
          return 'main';
        },
        getLatestBlockHeight: (url) async =>
            heightByUrl[url] ?? (throw Exception('no height $url')),
      );
      addTearDown(harness.container.dispose);

      final notifier = harness.container.read(
        rpcEndpointFailoverProvider.notifier,
      );
      expect(await notifier.getLatestBlockHeight(), BigInt.from(100));

      now = now.add(const Duration(minutes: 5));
      heightByUrl[primaryUrl] = BigInt.from(101);
      final heightFuture = notifier.getLatestBlockHeight();

      await fallbackProbeStarted.future;
      harness.endpointNotifier.setForTest(customSameUrl);
      harness.container.read(rpcEndpointFailoverProvider);
      releaseFallbackProbe.complete();

      expect(await heightFuture, BigInt.from(101));
      final state = harness.container.read(rpcEndpointFailoverProvider);
      expect(state.current.effectivePresetId, kCustomRpcEndpointPresetId);
      expect(state.fallbackCandidates, isEmpty);
      expect(state.lastEvent, isNull);
    },
  );

  test(
    'ignores stale primary recovery after endpoint changes to custom',
    () async {
      var now = DateTime(2026);
      var blockPrimaryProbe = false;
      final primary = defaultRpcEndpointConfig('main');
      final primaryUrl = primary.normalizedLightwalletdUrl;
      final customSameUrl = primary.copyWith(
        presetId: kCustomRpcEndpointPresetId,
      );
      final primaryProbeStarted = Completer<void>();
      final releasePrimaryProbe = Completer<void>();
      final heightByUrl = <String, BigInt>{
        primaryUrl: BigInt.from(120),
        'https://eu.zec.stardust.rest:443': BigInt.from(110),
      };
      final harness = _mutableContainer(
        primary: primary,
        clock: () => now,
        settings: const RpcEndpointFailoverSettings(
          primaryProbeInterval: Duration(seconds: 5),
        ),
        getChainName: (url) async {
          if (blockPrimaryProbe && url == primaryUrl) {
            if (!primaryProbeStarted.isCompleted) {
              primaryProbeStarted.complete();
            }
            await releasePrimaryProbe.future;
          }
          return 'main';
        },
        getLatestBlockHeight: (url) async =>
            heightByUrl[url] ?? (throw Exception('no height $url')),
      );
      addTearDown(harness.container.dispose);

      final notifier = harness.container.read(
        rpcEndpointFailoverProvider.notifier,
      );
      await notifier.switchToFallbackFor(
        Exception('DeadlineExceeded'),
        operation: 'primary sync',
      );
      expect(
        harness.container.read(rpcEndpointFailoverProvider).isUsingFallback,
        isTrue,
      );

      blockPrimaryProbe = true;
      now = now.add(const Duration(seconds: 5));
      final probeFuture = notifier.maybeProbePrimary();

      await primaryProbeStarted.future;
      harness.endpointNotifier.setForTest(customSameUrl);
      harness.container.read(rpcEndpointFailoverProvider);
      releasePrimaryProbe.complete();

      expect(await probeFuture, isFalse);
      final state = harness.container.read(rpcEndpointFailoverProvider);
      expect(state.current.effectivePresetId, kCustomRpcEndpointPresetId);
      expect(state.fallbackCandidates, isEmpty);
      expect(state.lastEvent, isNull);
    },
  );
}

ProviderContainer _container({
  required RpcEndpointConfig primary,
  required Map<String, String> chainNameByUrl,
  required Map<String, BigInt> heightByUrl,
  DateTime Function()? clock,
  RpcEndpointFailoverSettings settings = const RpcEndpointFailoverSettings(),
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(primary)),
      rpcEndpointFailoverSettingsProvider.overrideWithValue(settings),
      if (clock != null)
        rpcEndpointFailoverClockProvider.overrideWithValue(clock),
      rpcEndpointFailoverChainNameGetterProvider.overrideWithValue(
        (url) async =>
            chainNameByUrl[url] ?? (throw Exception('no chain $url')),
      ),
      rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
        (url) async => heightByUrl[url] ?? (throw Exception('no height $url')),
      ),
    ],
  );
}

_MutableEndpointHarness _mutableContainer({
  required RpcEndpointConfig primary,
  required RpcEndpointChainNameGetter getChainName,
  required RpcEndpointLatestBlockHeightGetter getLatestBlockHeight,
  DateTime Function()? clock,
  RpcEndpointFailoverSettings settings = const RpcEndpointFailoverSettings(),
}) {
  late final _MutableRpcEndpointNotifier endpointNotifier;
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(primary)),
      rpcEndpointProvider.overrideWith(() {
        endpointNotifier = _MutableRpcEndpointNotifier(primary);
        return endpointNotifier;
      }),
      rpcEndpointFailoverSettingsProvider.overrideWithValue(settings),
      if (clock != null)
        rpcEndpointFailoverClockProvider.overrideWithValue(clock),
      rpcEndpointFailoverChainNameGetterProvider.overrideWithValue(
        getChainName,
      ),
      rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
        getLatestBlockHeight,
      ),
    ],
  );
  container.read(rpcEndpointProvider);
  return _MutableEndpointHarness(container, endpointNotifier);
}

class _MutableEndpointHarness {
  const _MutableEndpointHarness(this.container, this.endpointNotifier);

  final ProviderContainer container;
  final _MutableRpcEndpointNotifier endpointNotifier;
}

class _MutableRpcEndpointNotifier extends RpcEndpointNotifier {
  _MutableRpcEndpointNotifier(this.initial);

  final RpcEndpointConfig initial;

  @override
  RpcEndpointConfig build() => initial;

  void setForTest(RpcEndpointConfig next) {
    state = next;
  }
}

RpcEndpointConfig _customRegtestPrimary() {
  return const RpcEndpointConfig(
    networkName: 'regtest',
    lightwalletdUrl: 'http://127.0.0.1:19067',
    presetId: kCustomRpcEndpointPresetId,
  );
}

AppBootstrapState _bootstrap(RpcEndpointConfig endpoint) {
  return AppBootstrapState(
    initialLocation: '/welcome',
    initialAccountState: const AccountState(),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: endpoint.networkName,
    rpcEndpointConfig: endpoint,
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: false,
    isUnlocked: false,
    passwordRotationRecoveryFailed: false,
  );
}
