import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/automatic_rpc_endpoint_selection.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';

const _eu = 'https://eu.zec.stardust.rest:443';
const _kr = 'https://kr.zec.stardust.rest:443';
const _us = 'https://us.zec.stardust.rest:443';
const _custom = RpcEndpointConfig(
  networkName: 'main',
  lightwalletdUrl: 'https://private.example:443',
  presetId: kCustomRpcEndpointPresetId,
);
const _torReady = NetworkPrivacyState(
  torEnabled: true,
  status: NetworkPrivacyConnectionStatus.connected,
);

RpcEndpointCandidateSample _sample(
  String url, [
  int ms = 100,
  int height = 100,
]) => RpcEndpointCandidateSample(
  url: url,
  height: BigInt.from(height),
  latency: Duration(milliseconds: ms),
);

Future<void> _flush() async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('custom and manual selections never start automatic probes', () async {
    for (final endpoint in [
      _custom,
      const RpcEndpointConfig(
        networkName: 'main',
        lightwalletdUrl: _eu,
        presetId: 'eu-zec-stardust',
      ),
    ]) {
      final harness = _Harness(endpoint: endpoint);
      expect(await harness.notifier.ensureReady(), endpoint);
      expect(harness.calls, isEmpty);
    }
  });

  test(
    'selects a fast healthy server without changing automatic intent',
    () async {
      final harness = _Harness()
        ..respond = (_) async => [_sample(_eu, 400), _sample(_kr, 50)];
      final selected = await harness.notifier.ensureReady();
      expect(selected.lightwalletdUrl, _kr);
      expect(
        harness.container.read(rpcEndpointFailoverProvider).automaticReady,
        isTrue,
      );
      expect(
        isAutomaticRpcEndpointConfig(
          harness.container.read(rpcEndpointProvider),
        ),
        isTrue,
      );
      expect(harness.calls.single.maxConcurrency, 4);
      expect(
        harness.calls.single.totalTimeout,
        allOf(
          greaterThan(Duration.zero),
          lessThanOrEqualTo(const Duration(seconds: 6)),
        ),
      );
      await _flush();
      expect(
        harness.store.values[('main', false)]?.presetId,
        'kr-zec-stardust',
      );
      expect(
        harness.container.read(rpcEndpointFailoverProvider).lastEvent,
        isNull,
      );
    },
  );

  test('concurrent callers share a single selection', () async {
    final response = Completer<List<RpcEndpointCandidateSample>>();
    final harness = _Harness()..respond = (_) => response.future;
    final first = harness.notifier.ensureReady();
    final second = harness.notifier.ensureReady();
    await _flush();
    expect(harness.calls, hasLength(1));
    response.complete([_sample(_eu), _sample(_kr, 300)]);
    expect((await first).lightwalletdUrl, _eu);
    expect((await second).lightwalletdUrl, _eu);
  });

  test(
    'recent cache gets a bounded head start and is not replaced by the US primary',
    () async {
      final harness = _Harness();
      harness.store.values[('main', false)] = AutomaticRpcEndpointCache(
        presetId: 'eu-zec-stardust',
        observedAt: harness.now,
      );
      await harness.notifier.ensureReady();
      expect(harness.calls.first.urls, [_eu]);
      expect(
        harness.calls.first.totalTimeout,
        const Duration(milliseconds: 750),
      );
      await _flush();
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .automaticProvisional,
        isFalse,
      );
      harness.now = harness.now.add(const Duration(minutes: 2));
      expect(await harness.notifier.maybeProbePrimary(force: true), isFalse);
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
      expect(harness.calls, hasLength(2));
    },
  );

  test(
    'expired and failed caches do not block the normal candidate race',
    () async {
      final harness = _Harness();
      harness.store.values[('main', false)] = AutomaticRpcEndpointCache(
        presetId: 'eu-zec-stardust',
        observedAt: harness.now.subtract(const Duration(days: 1)),
      );
      await harness.notifier.ensureReady();
      expect(harness.calls.single.urls.length, greaterThan(1));
      final broken = _Harness(store: _Store()..fail = true);
      expect((await broken.notifier.ensureReady()).lightwalletdUrl, _eu);
      await _flush();
    },
  );

  test('a failed cached server falls through to other regions', () async {
    final harness = _Harness();
    harness.store.values[('main', false)] = AutomaticRpcEndpointCache(
      presetId: 'eu-zec-stardust',
      observedAt: harness.now,
    );
    harness.respond = (call) async =>
        call.urls.length == 1 ? [] : [_sample(_kr), _sample(_us, 300)];
    expect((await harness.notifier.ensureReady()).lightwalletdUrl, _kr);
    expect(harness.calls, hasLength(2));
    expect(
      harness.calls.last.totalTimeout,
      lessThanOrEqualTo(const Duration(seconds: 6)),
    );
  });

  test(
    'all-server failure backs off rather than continuously probing',
    () async {
      final harness = _Harness()..respond = (_) async => [];
      await expectLater(harness.notifier.ensureReady(), throwsStateError);
      await expectLater(harness.notifier.ensureReady(), throwsStateError);
      expect(harness.calls, hasLength(1));
      harness.now = harness.now.add(const Duration(seconds: 5));
      await expectLater(harness.notifier.ensureReady(), throwsStateError);
      expect(harness.calls, hasLength(2));
      harness.now = harness.now.add(const Duration(seconds: 9));
      await expectLater(harness.notifier.ensureReady(), throwsStateError);
      expect(harness.calls, hasLength(2));
      harness.now = harness.now.add(const Duration(seconds: 1));
      await expectLater(harness.notifier.ensureReady(), throwsStateError);
      expect(harness.calls, hasLength(3));
    },
  );

  test(
    'transport failure excludes the failed server from recovery probes',
    () async {
      final harness = _Harness();
      final original = await harness.notifier.ensureReady();
      harness.respond = (call) async => [
        if (call.urls.contains(_kr)) _sample(_kr),
        if (call.urls.contains(_eu)) _sample(_eu, 500),
        if (call.urls.contains(_us)) _sample(_us, 500),
      ];
      expect(
        await harness.notifier.switchToFallbackFor(
          StateError('network: connection reset'),
          endpoint: original,
          operation: 'test read',
        ),
        isTrue,
      );
      expect(harness.calls.last.urls, isNot(contains(_eu)));
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _kr,
      );
      expect(
        isAutomaticRpcEndpointConfig(
          harness.container.read(rpcEndpointProvider),
        ),
        isTrue,
      );
    },
  );

  test('late selection cannot overwrite a new manual preference', () async {
    final response = Completer<List<RpcEndpointCandidateSample>>();
    final harness = _Harness()..respond = (_) => response.future;
    final pending = expectLater(
      harness.notifier.ensureReady(),
      throwsStateError,
    );
    await _flush();
    harness.endpoint.publish(_custom);
    expect(
      harness.container.read(rpcEndpointFailoverProvider).current,
      _custom,
    );
    response.complete([_sample(_eu)]);
    await pending;
    await _flush();
    expect(harness.store.writes, isEmpty);
    expect(harness.cancelled, hasLength(1));
    expect(
      harness.container.read(rpcEndpointFailoverProvider).current,
      _custom,
    );
  });

  test(
    'locking cancels an in-flight race and prevents late cache writes',
    () async {
      final response = Completer<List<RpcEndpointCandidateSample>>();
      final harness = _Harness()..respond = (_) => response.future;
      final pending = expectLater(
        harness.notifier.ensureReady(),
        throwsStateError,
      );
      await _flush();
      harness.security.publish(
        const AppSecurityState(isPasswordConfigured: true, isUnlocked: false),
      );
      await _flush();
      response.complete([_sample(_eu)]);
      await pending;
      expect(harness.cancelled, hasLength(1));
      expect(harness.store.writes, isEmpty);
      expect(
        harness.container.read(rpcEndpointFailoverProvider).automaticReady,
        isFalse,
      );
      await expectLater(harness.notifier.ensureReady(), throwsStateError);
      expect(harness.calls, hasLength(1));
    },
  );

  test(
    'reset drains accepted cache writes and rejects an old race result',
    () async {
      final response = Completer<List<RpcEndpointCandidateSample>>();
      final harness = _Harness()..respond = (_) => response.future;
      final pending = expectLater(
        harness.notifier.ensureReady(),
        throwsStateError,
      );
      await _flush();
      await harness.notifier.clearAutomaticSelectionCache();
      response.complete([_sample(_eu)]);
      await pending;
      await _flush();
      expect(harness.store.clears, 1);
      expect(harness.store.values, isEmpty);
      expect(harness.store.writes, isEmpty);
    },
  );

  test(
    'reset waits for an accepted cache write before deleting history',
    () async {
      final release = Completer<void>();
      final harness = _Harness(store: _Store()..beforeWrite = release.future);
      await harness.notifier.ensureReady();
      await _flush();
      var cleared = false;
      final clearing = harness.notifier.clearAutomaticSelectionCache().then(
        (_) => cleared = true,
      );
      await _flush();
      expect(cleared, isFalse);
      release.complete();
      await clearing;
      expect(harness.store.writes, hasLength(1));
      expect(harness.store.clears, 1);
      expect(harness.store.values, isEmpty);
    },
  );

  test('Tor readiness is separate from the probe budget and cache', () async {
    final harness = _Harness(
      route: const NetworkPrivacyState(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connecting,
      ),
    );
    harness.store.values[('main', true)] = AutomaticRpcEndpointCache(
      presetId: 'kr-zec-stardust',
      observedAt: harness.now,
    );
    harness.respond = (call) async => [
      if (call.urls.contains(_kr)) _sample(_kr),
      if (call.urls.contains(_eu)) _sample(_eu, 500),
      if (call.urls.contains(_us)) _sample(_us, 500),
    ];
    final pending = harness.notifier.ensureReady();
    await _flush();
    expect(harness.calls, isEmpty);
    harness.privacy.publish(_torReady);
    expect((await pending).lightwalletdUrl, _kr);
    expect(harness.calls.single.urls, [_kr]);
    expect(harness.calls.single.maxConcurrency, 2);
    expect(harness.store.reads, [('main', true)]);
  });

  test('blocked Tor never falls back to a direct probe', () async {
    final harness = _Harness(
      route: const NetworkPrivacyState(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.failed,
      ),
    );
    await expectLater(harness.notifier.ensureReady(), throwsStateError);
    expect(harness.calls, isEmpty);
  });

  for (final phase in ['before selection', 'route wait', 'candidate probe']) {
    test('retained Tor failure remains retryable $phase', () async {
      final harness = _Harness(
        route: phase == 'before selection'
            ? const NetworkPrivacyState(
                torEnabled: true,
                status: NetworkPrivacyConnectionStatus.failed,
              )
            : phase == 'route wait'
            ? const NetworkPrivacyState(
                torEnabled: true,
                status: NetworkPrivacyConnectionStatus.connecting,
              )
            : _torReady,
      );
      final response = Completer<List<RpcEndpointCandidateSample>>();
      harness.respond = (_) => response.future;
      final result = harness.notifier.ensureReady().then<Object>(
        (_) => throw TestFailure('Expected failed Tor selection'),
        onError: (Object error, StackTrace _) => error,
      );
      await _flush();
      if (phase != 'before selection') {
        harness.privacy.publish(
          const NetworkPrivacyState(
            torEnabled: true,
            status: NetworkPrivacyConnectionStatus.failed,
          ),
        );
      }
      final failure = classifySyncFailure(await result);
      expect(failure.kind, SyncFailureKind.torUnavailable);
      expect(failure.retriesTorRoute, isTrue);
      expect(harness.calls, hasLength(phase == 'candidate probe' ? 1 : 0));
      expect(harness.store.writes, isEmpty);
      if (phase == 'candidate probe') {
        expect(harness.cancelled, hasLength(1));
        response.complete([_sample(_kr)]);
        await _flush();
        expect(harness.store.writes, isEmpty);
        expect(
          harness.container.read(rpcEndpointFailoverProvider).automaticReady,
          isFalse,
        );
      }
    });
  }

  test(
    'lock cancellation stays ordinary when Tor subsequently fails',
    () async {
      final harness = _Harness(route: _torReady);
      final response = Completer<List<RpcEndpointCandidateSample>>();
      harness.respond = (_) => response.future;
      final result = harness.notifier.ensureReady().then<Object>(
        (_) => throw TestFailure('Expected lock cancellation'),
        onError: (Object error, StackTrace _) => error,
      );
      await _flush();
      harness.security.publish(
        const AppSecurityState(isPasswordConfigured: true, isUnlocked: false),
      );
      harness.privacy.publish(
        const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.failed,
        ),
      );
      expect(classifySyncFailure(await result).retriesTorRoute, isFalse);
      response.complete([_sample(_kr)]);
      await _flush();
      expect(harness.store.writes, isEmpty);
    },
  );

  for (final route in const [
    NetworkPrivacyState(
      torEnabled: true,
      targetTorEnabled: false,
      status: NetworkPrivacyConnectionStatus.failed,
    ),
    NetworkPrivacyState(
      torEnabled: false,
      targetTorEnabled: true,
      status: NetworkPrivacyConnectionStatus.failed,
    ),
  ]) {
    test(
      'failed toggle without retained Tor does not request bootstrap: ${route.torEnabled}',
      () async {
        final harness = _Harness(route: route);
        final error = await harness.notifier.ensureReady().then<Object>(
          (_) => throw TestFailure('Expected a blocked route'),
          onError: (Object error, StackTrace _) => error,
        );
        expect(classifySyncFailure(error).retriesTorRoute, isFalse);
        expect(harness.calls, isEmpty);
      },
    );
  }

  test('turning Tor off while waiting remains ordinary cancellation', () async {
    final harness = _Harness(
      route: const NetworkPrivacyState(
        torEnabled: true,
        status: NetworkPrivacyConnectionStatus.connecting,
      ),
    );
    final result = harness.notifier.ensureReady().then<Object>(
      (_) => throw TestFailure('Expected route-change cancellation'),
      onError: (Object error, StackTrace _) => error,
    );
    await _flush();
    harness.privacy.publish(const NetworkPrivacyState.off());
    expect(classifySyncFailure(await result).retriesTorRoute, isFalse);
    expect(harness.calls, isEmpty);
  });

  test(
    'a new route can recover immediately from direct offline backoff',
    () async {
      final harness = _Harness()..respond = (_) async => [];
      await expectLater(harness.notifier.ensureReady(), throwsStateError);
      harness.privacy.publish(_torReady);
      await _flush();
      harness.respond = (call) async => [
        if (call.urls.contains(_kr)) _sample(_kr),
        if (call.urls.contains(_eu)) _sample(_eu, 500),
        if (call.urls.contains(_us)) _sample(_us, 500),
      ];
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _kr);
      expect(harness.calls.last.maxConcurrency, 2);
    },
  );

  test('direct and Tor cache entries never select each other', () async {
    final harness = _Harness(route: _torReady);
    harness.store.values[('main', false)] = AutomaticRpcEndpointCache(
      presetId: 'eu-zec-stardust',
      observedAt: harness.now,
    );
    harness.store.values[('main', true)] = AutomaticRpcEndpointCache(
      presetId: 'kr-zec-stardust',
      observedAt: harness.now,
    );
    harness.respond = (call) async => call.urls.length == 1
        ? [_sample(call.urls.single)]
        : [
            if (call.urls.contains(_eu)) _sample(_eu, 500),
            if (call.urls.contains(_kr)) _sample(_kr, 500),
          ];
    expect((await harness.notifier.ensureReady()).lightwalletdUrl, _kr);
    harness.privacy.publish(const NetworkPrivacyState.off());
    await _flush();
    expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
    expect(harness.store.reads, [('main', true), ('main', false)]);
  });

  test(
    'periodic rechecks require material improvement to replace a healthy server',
    () async {
      final harness = _Harness()
        ..respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 1500)];
      await harness.notifier.ensureReady();
      harness.now = harness.now.add(const Duration(minutes: 16));
      harness.respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 900)];
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
      await _flush();
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _eu,
      );
      harness.now = harness.now.add(const Duration(minutes: 16));
      harness.respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 500)];
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
      await _flush();
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _kr,
      );
      expect(harness.calls, hasLength(3));
    },
  );

  test(
    'minimum residence prevents rapid switching between fast servers',
    () async {
      final harness = _Harness(
        settings: const AutomaticRpcEndpointSettings(
          recheckInterval: Duration(minutes: 2),
          minimumResidence: Duration(minutes: 5),
        ),
      )..respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 1500)];
      await harness.notifier.ensureReady();
      harness.respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 100)];
      harness.now = harness.now.add(const Duration(minutes: 3));
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
      await _flush();
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _eu,
      );
      harness.now = harness.now.add(const Duration(minutes: 3));
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
      await _flush();
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _kr,
      );
    },
  );

  test(
    'periodic recheck does not hold an operation on a ready server',
    () async {
      final harness = _Harness()
        ..respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 1500)];
      await harness.notifier.ensureReady();
      harness.now = harness.now.add(const Duration(minutes: 16));
      final response = Completer<List<RpcEndpointCandidateSample>>();
      harness.respond = (_) => response.future;
      expect(
        (await harness.notifier.ensureReady().timeout(
          const Duration(milliseconds: 100),
        )).lightwalletdUrl,
        _eu,
      );
      await _flush();
      expect(harness.calls, hasLength(2));
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _eu,
      );
      response.complete([_sample(_eu, 1000), _sample(_kr, 100)]);
      await _flush();
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _kr,
      );
    },
  );

  for (final fail in [false, true]) {
    test(
      'late ${fail ? 'failed' : 'successful'} tip completion after lock cannot restart probes',
      () async {
        final harness = _Harness();
        await harness.notifier.ensureReady();
        // Consume the one-use live tip returned by candidate selection before
        // gating the ordinary network read whose late completion is tested.
        expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(100));
        final height = Completer<BigInt>();
        harness.readHeight = () => height.future;
        final pending = harness.notifier.getLatestBlockHeight();
        final failed = fail ? expectLater(pending, throwsStateError) : null;
        await _flush();
        harness.security.publish(
          const AppSecurityState(isPasswordConfigured: true, isUnlocked: false),
        );
        await _flush();
        if (fail) {
          height.completeError(StateError('network: connection reset'));
          await failed;
        } else {
          height.complete(BigInt.from(100));
          expect(await pending, BigInt.from(100));
        }
        await _flush();
        expect(harness.calls, hasLength(1));
        expect(
          harness.container.read(rpcEndpointFailoverProvider).automaticReady,
          isTrue,
        );
      },
    );
  }

  test('Dart wall budget cancels a probe that never returns', () async {
    final response = Completer<List<RpcEndpointCandidateSample>>();
    final harness = _Harness(
      settings: const AutomaticRpcEndpointSettings(
        directBudget: Duration(milliseconds: 30),
        directProbeTimeout: Duration(milliseconds: 30),
      ),
    )..respond = (_) => response.future;
    await expectLater(
      harness.notifier.ensureReady().timeout(const Duration(seconds: 2)),
      throwsA(isA<TimeoutException>()),
    );
    expect(harness.calls, hasLength(1));
    expect(harness.cancelled, hasLength(1));
    expect(
      harness.container.read(rpcEndpointFailoverProvider).automaticReady,
      isFalse,
    );
    response.complete([_sample(_eu)]);
    await _flush();
    expect(harness.store.writes, isEmpty);
    expect(
      harness.container.read(rpcEndpointFailoverProvider).automaticReady,
      isFalse,
    );
  });

  test(
    'nested pause blocks selection throughout reset cache drain and clearing',
    () async {
      final release = Completer<void>();
      final harness = _Harness(store: _Store()..beforeWrite = release.future);
      await harness.notifier.ensureReady();
      await _flush();
      harness.notifier.pauseAutomaticSelection();
      harness.notifier.pauseAutomaticSelection();
      var cleared = false;
      final clearing = harness.notifier.clearAutomaticSelectionCache().then(
        (_) => cleared = true,
      );
      await _flush();
      expect(cleared, isFalse);
      await expectLater(harness.notifier.ensureReady(), throwsStateError);
      harness.notifier.resumeAutomaticSelection();
      await expectLater(harness.notifier.ensureReady(), throwsStateError);
      expect(harness.calls, hasLength(1));
      release.complete();
      await clearing;
      expect(harness.store.values, isEmpty);
      await expectLater(harness.notifier.ensureReady(), throwsStateError);
      harness.notifier.resumeAutomaticSelection();
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
      expect(harness.calls, hasLength(2));
    },
  );

  test(
    'forced slow-height recovery supersedes an ordinary pending recheck',
    () async {
      final harness = _Harness(
        settings: const AutomaticRpcEndpointSettings(
          recheckInterval: Duration(minutes: 1),
          minimumResidence: Duration.zero,
        ),
      );
      await harness.notifier.ensureReady();
      final ordinary = Completer<List<RpcEndpointCandidateSample>>();
      harness.respond = (_) => harness.calls.length == 2
          ? ordinary.future
          : Future.value([
              _sample(_eu, 1, 100),
              _sample(_kr, 100, 105),
              _sample(_us, 300, 105),
            ]);
      harness.now = harness.now.add(const Duration(minutes: 6));
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(105));
      expect(harness.calls, hasLength(3));
      expect(harness.cancelled, hasLength(1));
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _kr,
      );
      ordinary.complete([_sample(_eu, 1, 100)]);
      await _flush();
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _kr,
      );
    },
  );

  test(
    'stale A failure retries on already selected B without another probe',
    () async {
      final harness = _Harness();
      await harness.notifier.ensureReady();
      final oldRequest = Completer<String>();
      final used = <String>[];
      final pending = harness.notifier.runWithEndpointFallback<String>(
        operation: 'overlapping read',
        action: (endpoint) {
          used.add(endpoint.lightwalletdUrl);
          return endpoint.lightwalletdUrl == _eu
              ? oldRequest.future
              : Future.value(endpoint.lightwalletdUrl);
        },
      );
      await _flush();
      expect(used, [_eu]);
      harness.now = harness.now.add(const Duration(minutes: 16));
      harness.respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 100)];
      await harness.notifier.ensureReady();
      await _flush();
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _kr,
      );
      oldRequest.completeError(StateError('network: connection reset'));
      expect(await pending, _kr);
      expect(used, [_eu, _kr]);
      expect(harness.calls, hasLength(2));
      harness.endpoint.publish(_custom);
      harness.container.read(rpcEndpointFailoverProvider);
      expect(
        await harness.notifier.switchToFallbackFor(
          StateError('network: connection reset'),
          endpoint: const RpcEndpointConfig(
            networkName: 'main',
            lightwalletdUrl: _eu,
            presetId: 'eu-zec-stardust',
          ),
          operation: 'old operation after preference change',
        ),
        isFalse,
      );
      expect(harness.calls, hasLength(2));
    },
  );

  test(
    'isolated fast winner is replaced after two slower peers agree',
    () async {
      final firstPeer = Completer<List<RpcEndpointCandidateSample>>();
      final secondPeer = Completer<List<RpcEndpointCandidateSample>>();
      final harness = _Harness();
      harness.respond = (_) => switch (harness.calls.length) {
        1 => Future.value([_sample(_eu, 20, 100)]),
        2 => firstPeer.future,
        _ => secondPeer.future,
      };
      final initial = await harness.notifier.ensureReady().timeout(
        const Duration(milliseconds: 100),
      );
      expect(initial.lightwalletdUrl, _eu);
      await _flush();
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .automaticProvisional,
        isTrue,
      );
      expect(harness.calls, hasLength(2));
      expect(harness.calls.last.urls, isNot(contains(_eu)));
      for (var i = 0; i < 3; i++) {
        await harness.notifier.ensureReady();
      }
      expect(harness.calls, hasLength(2));
      firstPeer.complete([_sample(_kr, 500, 110)]);
      await _flush();
      expect(harness.calls, hasLength(3));
      expect(harness.calls.last.urls, isNot(contains(_eu)));
      expect(harness.calls.last.urls, isNot(contains(_kr)));
      expect(
        harness.calls.last.totalTimeout,
        lessThanOrEqualTo(harness.calls[1].totalTimeout),
      );
      // This third host would lose every original 250ms comparison window to
      // both A and B. A distinct second round lets its response be observed.
      secondPeer.complete([_sample(_us, 1200, 110)]);
      await _flush();
      final state = harness.container.read(rpcEndpointFailoverProvider);
      expect(state.current.lightwalletdUrl, _kr);
      expect(state.automaticProvisional, isFalse);
      expect(state.lastObservedHeight, BigInt.from(110));
    },
  );

  test(
    'validation reaches a third peer beyond two conflicting faster hosts',
    () async {
      const fourth = 'https://eu.zec.rocks:443';
      final firstPeer = Completer<List<RpcEndpointCandidateSample>>();
      final secondPeer = Completer<List<RpcEndpointCandidateSample>>();
      final thirdPeer = Completer<List<RpcEndpointCandidateSample>>();
      final harness = _Harness();
      harness.respond = (_) => switch (harness.calls.length) {
        1 => Future.value([_sample(_eu, 20, 100)]),
        2 => firstPeer.future,
        3 => secondPeer.future,
        _ => thirdPeer.future,
      };
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
      await _flush();
      firstPeer.complete([_sample(_kr, 30, 150)]);
      await _flush();
      secondPeer.complete([_sample(_us, 500, 200)]);
      await _flush();
      expect(harness.calls, hasLength(4));
      expect(harness.calls.last.urls, isNot(contains(_eu)));
      expect(harness.calls.last.urls, isNot(contains(_kr)));
      expect(harness.calls.last.urls, isNot(contains(_us)));
      for (var i = 2; i < harness.calls.length; i++) {
        expect(
          harness.calls[i].urls.length,
          lessThan(harness.calls[i - 1].urls.length),
        );
        expect(
          harness.calls[i].totalTimeout,
          lessThanOrEqualTo(harness.calls[i - 1].totalTimeout),
        );
      }
      thirdPeer.complete([_sample(fourth, 1200, 200)]);
      await _flush();
      final state = harness.container.read(rpcEndpointFailoverProvider);
      expect(state.current.lightwalletdUrl, _us);
      expect(state.lastObservedHeight, BigInt.from(200));
      expect(state.automaticProvisional, isFalse);
    },
  );

  test(
    'conflicting singleton replies exhaust the finite peer pool once',
    () async {
      final harness = _Harness();
      harness.respond = (call) async => harness.calls.length == 1
          ? [_sample(_eu, 20, 100)]
          : [_sample(call.urls.first, 100, harness.calls.length * 100)];
      await harness.notifier.ensureReady();
      await _flush();
      final poolSize = automaticRpcEndpointCandidatesFor(
        defaultRpcEndpointConfig('main'),
      ).length;
      expect(harness.calls, hasLength(poolSize));
      final rounds = harness.calls.skip(1).toList();
      expect(
        rounds.map((call) => call.urls.length),
        List.generate(poolSize - 1, (i) => poolSize - 1 - i),
      );
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _eu,
      );
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .automaticProvisional,
        isTrue,
      );
      await harness.notifier.ensureReady();
      await _flush();
      expect(harness.calls, hasLength(poolSize));
    },
  );

  test(
    'empty peer response ends validation without spinning or discarding current',
    () async {
      final harness = _Harness();
      harness.respond = (_) async =>
          harness.calls.length == 1 ? [_sample(_eu, 20, 100)] : [];
      await harness.notifier.ensureReady();
      await _flush();
      expect(harness.calls, hasLength(2));
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _eu,
      );
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .automaticProvisional,
        isTrue,
      );
    },
  );

  test(
    'cached winner is also independently checked before freshness is trusted',
    () async {
      final peers = Completer<List<RpcEndpointCandidateSample>>();
      final harness = _Harness();
      harness.store.values[('main', false)] = AutomaticRpcEndpointCache(
        presetId: 'eu-zec-stardust',
        observedAt: harness.now,
      );
      harness.respond = (call) => call.urls.length == 1
          ? Future.value([_sample(_eu, 20, 100)])
          : peers.future;
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
      await _flush();
      expect(harness.calls.first.urls, [_eu]);
      expect(harness.calls.last.urls, isNot(contains(_eu)));
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .automaticProvisional,
        isTrue,
      );
      peers.complete([_sample(_kr, 500, 110), _sample(_us, 900, 110)]);
      await _flush();
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _kr,
      );
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .automaticProvisional,
        isFalse,
      );
    },
  );

  test(
    'one far-ahead peer cannot replace an independently confirmed current host',
    () async {
      final harness = _Harness();
      harness.respond = (_) async => switch (harness.calls.length) {
        1 => [_sample(_eu, 20, 100)],
        2 => [_sample(_kr, 1, 10000)],
        _ => [_sample(_us, 500, 100)],
      };
      await harness.notifier.ensureReady();
      await _flush();
      expect(harness.calls, hasLength(3));
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _eu,
      );
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .automaticProvisional,
        isFalse,
      );
    },
  );

  test(
    'unresolved peer checks retry at one-minute cadence even while current tip advances',
    () async {
      final harness = _Harness();
      harness.respond = (_) async =>
          harness.calls.length == 1 ? [_sample(_eu, 20, 100)] : [];
      await harness.notifier.ensureReady();
      await _flush();
      expect(harness.calls, hasLength(2));
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .automaticProvisional,
        isTrue,
      );
      harness.readHeight = () async => BigInt.from(101);
      harness.now = harness.now.add(const Duration(seconds: 30));
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(101));
      expect(harness.calls, hasLength(2));
      harness.now = harness.now.add(const Duration(seconds: 30));
      final peers = Completer<List<RpcEndpointCandidateSample>>();
      harness.respond = (_) => peers.future;
      harness.readHeight = () async => BigInt.from(102);
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(102));
      await _flush();
      expect(harness.calls, hasLength(3));
      peers.complete([_sample(_kr, 500, 110), _sample(_us, 900, 110)]);
      await _flush();
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _kr,
      );
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .automaticProvisional,
        isFalse,
      );
    },
  );

  for (final reset in [false, true]) {
    test(
      '${reset ? 'reset' : 'lock'} cancels independent peer validation and late cache writes',
      () async {
        final peers = Completer<List<RpcEndpointCandidateSample>>();
        final harness = _Harness();
        harness.respond = (_) => harness.calls.length == 1
            ? Future.value([_sample(_eu, 20, 100)])
            : peers.future;
        await harness.notifier.ensureReady();
        await _flush();
        expect(harness.calls, hasLength(2));
        final writes = harness.store.writes.length;
        if (reset) {
          harness.notifier.pauseAutomaticSelection();
          await harness.notifier.clearAutomaticSelectionCache();
        } else {
          harness.security.publish(
            const AppSecurityState(
              isPasswordConfigured: true,
              isUnlocked: false,
            ),
          );
        }
        await _flush();
        expect(harness.cancelled, hasLength(1));
        peers.complete([_sample(_kr, 500, 110), _sample(_us, 900, 110)]);
        await _flush();
        expect(
          harness.container.read(rpcEndpointFailoverProvider).automaticReady,
          isFalse,
        );
        expect(
          harness.container
              .read(rpcEndpointFailoverProvider)
              .current
              .lightwalletdUrl,
          _eu,
        );
        expect(harness.store.writes.length, writes);
        if (reset) expect(harness.store.values, isEmpty);
      },
    );
  }

  test(
    'forced failure recovery supersedes validation even with the same exclusion',
    () async {
      final peers = Completer<List<RpcEndpointCandidateSample>>();
      final harness = _Harness();
      harness.respond = (_) => switch (harness.calls.length) {
        1 => Future.value([_sample(_eu, 20, 100)]),
        2 => peers.future,
        _ => Future.value([_sample(_kr, 500, 110), _sample(_us, 900, 110)]),
      };
      final initial = await harness.notifier.ensureReady();
      await _flush();
      expect(harness.calls, hasLength(2));
      expect(
        await harness.notifier.switchToFallbackFor(
          StateError('network: connection reset'),
          endpoint: initial,
          operation: 'failed current read',
        ),
        isTrue,
      );
      expect(harness.calls, hasLength(3));
      expect(harness.cancelled, hasLength(1));
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _kr,
      );
      peers.complete([_sample(_us, 1, 100)]);
      await _flush();
      expect(
        harness.container
            .read(rpcEndpointFailoverProvider)
            .current
            .lightwalletdUrl,
        _kr,
      );
    },
  );

  test(
    'height ranking excludes stale servers and a lone implausible high outlier',
    () {
      final ranked = rankAutomaticRpcEndpointSamples([
        _sample(_eu, 100, 100),
        _sample(_kr, 200, 101),
        _sample('https://outlier.example', 1, 10000),
        _sample('https://stale.example', 2, 50),
      ]);
      expect(ranked.map((s) => s.url), [_eu, _kr]);
      final dense = rankAutomaticRpcEndpointSamples([
        _sample(_eu, 100, 100),
        _sample(_kr, 200, 100),
        _sample('https://ahead.example', 2, 103),
        _sample('https://outlier.example', 1, 10000),
      ]);
      expect(dense.map((s) => s.url), [_eu, _kr]);
      expect(
        rankAutomaticRpcEndpointSamples([
          _sample(_eu),
        ], minimumHeight: BigInt.from(101)),
        isEmpty,
      );
    },
  );

  test(
    'cold selection compares the full pool only after sync starts',
    () async {
      final full = Completer<List<RpcEndpointCandidateSample>>();
      final harness = _Harness()
        ..respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 1500)];
      harness.fullRespond = (_) => full.future;
      final selected = await harness.notifier.ensureReady();
      expect(selected.lightwalletdUrl, _eu);
      expect(harness.fullCalls, isEmpty);
      harness.notifier.startInitialComparisonAfterSyncStart();
      await _flush();
      expect(harness.fullCalls, hasLength(1));
      expect(harness.fullCalls.single.urls, hasLength(8));
      expect(harness.fullCalls.single.maxConcurrency, 4);
      expect(harness.fullCalls.single.totalTimeout, const Duration(seconds: 7));
      // The foreground operation is independent of the complete-pool future.
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
      const tail = 'https://sa.zec.rocks:443';
      full.complete([
        _sample(_eu, 1000),
        _sample(_kr, 1500),
        _sample(tail, 400),
      ]);
      await _flush();
      expect(harness.notifier.currentEndpoint.lightwalletdUrl, _eu);
      expect(harness.store.values[('main', false)]?.presetId, 'sa-zec-rocks');
      // Ordinary success must not overwrite the deferred recommendation.
      harness.now = harness.now.add(const Duration(minutes: 2));
      await harness.notifier.getLatestBlockHeight();
      await _flush();
      expect(harness.store.values[('main', false)]?.presetId, 'sa-zec-rocks');
      harness.notifier.applyPendingInitialComparison();
      expect(harness.notifier.currentEndpoint.lightwalletdUrl, tail);
      harness.notifier.startInitialComparisonAfterSyncStart();
      await _flush();
      expect(harness.fullCalls, hasLength(1));
    },
  );

  test('Tor complete comparison reserves all four timeout waves', () async {
    final harness = _Harness(route: _torReady)
      ..respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 1500)];
    await harness.notifier.ensureReady();
    harness.notifier.startInitialComparisonAfterSyncStart();
    await _flush();
    expect(harness.fullCalls.single.maxConcurrency, 2);
    expect(harness.fullCalls.single.probeTimeout, const Duration(seconds: 8));
    expect(harness.fullCalls.single.totalTimeout, const Duration(seconds: 33));
  });

  test('a restart reuses the completed comparison recommendation', () async {
    final harness = _Harness()
      ..respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 1500)];
    harness.fullRespond = (_) async => [_sample(_eu, 1000), _sample(_kr, 100)];
    await harness.notifier.ensureReady();
    harness.notifier.startInitialComparisonAfterSyncStart();
    await _flush();
    expect(harness.notifier.currentEndpoint.lightwalletdUrl, _eu);
    final restarted = _Harness(
      store: harness.store,
      warmRead:
          ({required endpoint, required selectionId, required timeout}) async =>
              _sample(endpoint.lightwalletdUrl),
    );
    expect((await restarted.notifier.ensureReady()).lightwalletdUrl, _kr);
    restarted.notifier.startInitialComparisonAfterSyncStart();
    await _flush();
    expect(restarted.calls, isEmpty);
    expect(restarted.fullCalls, isEmpty);
  });

  test(
    'uncorroborated cache survives only as a hint until peers confirm',
    () async {
      final first = _Harness();
      first.respond = (call) async =>
          call.urls.contains(_eu) ? [_sample(_eu)] : [];
      await first.notifier.ensureReady();
      await _flush();
      expect(first.store.values[('main', false)]!.lastPeerValidatedAt, isNull);

      var warmReads = 0;
      Future<RpcEndpointCandidateSample> warmRead({
        required RpcEndpointConfig endpoint,
        required String selectionId,
        required Duration timeout,
      }) async {
        warmReads++;
        return _sample(endpoint.normalizedLightwalletdUrl);
      }

      final second = _Harness(store: first.store, warmRead: warmRead);
      second.respond = (call) async =>
          call.urls.contains(_eu) ? [_sample(_eu)] : [];
      await second.notifier.ensureReady();
      await _flush();
      expect(warmReads, 0);
      expect(second.calls.first.urls, [_eu]);
      expect(
        second.container.read(rpcEndpointFailoverProvider).automaticProvisional,
        isTrue,
      );
      expect(second.store.values[('main', false)]!.lastPeerValidatedAt, isNull);

      second.now = second.now.add(const Duration(minutes: 1));
      second.respond = (call) async => [
        if (call.urls.contains(_kr)) _sample(_kr, 300),
        if (call.urls.contains(_us)) _sample(_us, 400),
      ];
      await second.notifier.ensureReady();
      await _flush();
      expect(
        second.container.read(rpcEndpointFailoverProvider).automaticProvisional,
        isFalse,
      );
      expect(
        second.store.values[('main', false)]!.lastPeerValidatedAt,
        second.now,
      );

      final third = _Harness(store: second.store, warmRead: warmRead)
        ..now = second.now;
      expect((await third.notifier.ensureReady()).lightwalletdUrl, _eu);
      expect(third.calls, isEmpty);
      expect(warmReads, 1);
    },
  );

  test(
    'a cache hint schedules one full comparison after sync starts',
    () async {
      final harness = _Harness();
      harness.store.values[('main', false)] = AutomaticRpcEndpointCache(
        presetId: 'eu-zec-stardust',
        observedAt: harness.now,
      );
      await harness.notifier.ensureReady();
      await _flush();
      expect(harness.fullCalls, isEmpty);
      harness.notifier.startInitialComparisonAfterSyncStart();
      await _flush();
      expect(harness.fullCalls, hasLength(1));
      expect(harness.fullCalls.single.urls, hasLength(8));
      harness.notifier.startInitialComparisonAfterSyncStart();
      await _flush();
      expect(harness.fullCalls, hasLength(1));
    },
  );

  for (final caseName in [
    'small improvement',
    'current failed',
    'height conflict',
    'failure',
  ]) {
    test('optional full comparison retains current on $caseName', () async {
      final harness = _Harness()
        ..respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 1500)];
      harness.fullRespond = (_) async => switch (caseName) {
        'small improvement' => [_sample(_eu, 1000), _sample(_kr, 900)],
        'current failed' => [_sample(_kr, 100), _sample(_us, 300)],
        'height conflict' => [
          _sample(_eu, 1000),
          _sample(_kr, 100, 110),
          _sample(_us, 300, 110),
        ],
        _ => throw StateError('optional timeout'),
      };
      await harness.notifier.ensureReady();
      harness.notifier.startInitialComparisonAfterSyncStart();
      await _flush();
      harness.notifier.applyPendingInitialComparison();
      expect(harness.notifier.currentEndpoint.lightwalletdUrl, _eu);
      expect(
        harness.container.read(rpcEndpointFailoverProvider).automaticReady,
        isTrue,
      );
      expect(
        harness.store.values[('main', false)]?.presetId,
        'eu-zec-stardust',
      );
    });
  }

  for (final action in ['lock', 'background', 'manual', 'Tor', 'reset']) {
    test('late complete comparison is discarded after $action', () async {
      final full = Completer<List<RpcEndpointCandidateSample>>();
      final harness = _Harness()
        ..respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 1500)];
      harness.fullRespond = (_) => full.future;
      await harness.notifier.ensureReady();
      harness.notifier.startInitialComparisonAfterSyncStart();
      await _flush();
      expect(harness.fullCalls, hasLength(1));
      switch (action) {
        case 'lock':
          harness.security.publish(
            const AppSecurityState(
              isPasswordConfigured: true,
              isUnlocked: false,
            ),
          );
        case 'background':
          harness.notifier.cancelAutomaticSelection();
        case 'manual':
          harness.endpoint.publish(_custom);
        case 'Tor':
          harness.privacy.publish(_torReady);
        case 'reset':
          await harness.notifier.clearAutomaticSelectionCache();
      }
      await _flush();
      final writes = harness.store.writes.length;
      full.complete([_sample(_eu, 1000), _sample(_kr, 100)]);
      await _flush();
      expect(harness.cancelled, hasLength(1));
      expect(harness.store.writes, hasLength(writes));
      expect(
        harness.notifier.currentEndpoint.lightwalletdUrl,
        action == 'manual' ? _custom.lightwalletdUrl : _eu,
      );
    });
  }

  test('failure recovery supersedes complete comparison', () async {
    final full = Completer<List<RpcEndpointCandidateSample>>();
    final harness = _Harness()
      ..respond = (call) async => [
        if (call.urls.contains(_eu)) _sample(_eu, 1000),
        _sample(_kr, 1500),
        _sample(_us, 1700),
      ];
    harness.fullRespond = (_) => full.future;
    final selected = await harness.notifier.ensureReady();
    harness.notifier.startInitialComparisonAfterSyncStart();
    await _flush();
    expect(
      await harness.notifier.switchToFallbackFor(
        StateError('network: connection reset'),
        endpoint: selected,
        operation: 'sync',
      ),
      isTrue,
    );
    expect(harness.cancelled, hasLength(1));
    full.complete([_sample(_eu, 1), _sample(_kr, 1000)]);
    await _flush();
    expect(harness.notifier.currentEndpoint.lightwalletdUrl, _kr);
  });

  test('an expired recommendation cannot replace the current server', () async {
    final harness = _Harness()
      ..respond = (_) async => [_sample(_eu, 1000), _sample(_kr, 1500)];
    harness.fullRespond = (_) async => [_sample(_eu, 1000), _sample(_kr, 100)];
    await harness.notifier.ensureReady();
    harness.notifier.startInitialComparisonAfterSyncStart();
    await _flush();
    harness.now = harness.now.add(const Duration(minutes: 6));
    harness.notifier.applyPendingInitialComparison();
    await _flush();
    expect(harness.notifier.currentEndpoint.lightwalletdUrl, _eu);
    expect(harness.store.values[('main', false)]?.presetId, 'eu-zec-stardust');
  });
  group('creation birthday confirmation', () {
    _Harness birthdayHarness({
      RpcEndpointConfig? endpoint,
      NetworkPrivacyState route = const NetworkPrivacyState.off(),
      RpcEndpointWarmTipReader? warmRead,
      AutomaticRpcEndpointSettings settings =
          const AutomaticRpcEndpointSettings(),
    }) => _Harness(
      endpoint: endpoint,
      route: route,
      warmRead: warmRead,
      settings: settings,
    )..respond = (call) async => [if (call.urls.contains(_eu)) _sample(_eu)];
    const rocks = 'https://eu.zec.rocks:443';

    test(
      'reuses a fresh two-operator pair and chooses the lower height',
      () async {
        final h = birthdayHarness();
        h.respond = (_) async => [
          _sample(_eu, 100, 102),
          _sample(rocks, 300, 100),
        ];
        expect(await h.notifier.getCreationBirthdayHeight(), BigInt.from(100));
        expect(h.calls, hasLength(1));
        expect(h.birthdayCalls, isEmpty);
        expect(h.notifier.currentEndpoint.lightwalletdUrl, _eu);
      },
    );

    test(
      'reuses a fresh same-operator pair without additional probes',
      () async {
        final h = birthdayHarness();
        h.respond = (_) async => [
          _sample(_eu, 100, 102),
          _sample(_kr, 300, 100),
        ];
        expect(await h.notifier.getCreationBirthdayHeight(), BigInt.from(100));
        expect(h.birthdayCalls, isEmpty);
        expect(h.calls, hasLength(1));
      },
    );

    test(
      'prefers an already available agreeing observation from another operator',
      () async {
        final h = birthdayHarness();
        h.respond = (call) async => [
          if (call.urls.contains(_eu)) _sample(_eu, 100, 100),
          if (call.urls.contains(_kr)) _sample(_kr, 200, 99),
          if (call.urls.contains(rocks)) _sample(rocks, 300, 101),
        ];
        expect(await h.notifier.getCreationBirthdayHeight(), BigInt.from(100));
        expect(h.birthdayCalls, isEmpty);
      },
    );

    test(
      'duplicate responses from the selected URL cannot confirm its height',
      () async {
        final h = birthdayHarness();
        h.respond = (call) async => [
          if (call.urls.contains(_eu)) ...[_sample(_eu), _sample(_eu)],
        ];
        h.birthdayRespond = (_) async => [];
        await expectLater(
          h.notifier.getCreationBirthdayHeight(),
          throwsStateError,
        );
        expect(h.birthdayCalls, isNotEmpty);
        expect(
          h.birthdayCalls.every((call) => !call.urls.contains(_eu)),
          isTrue,
        );
      },
    );

    for (final tor in [false, true]) {
      test(
        '${tor ? 'Tor' : 'direct'} peer race accepts a regional peer when the other operator is unavailable',
        () async {
          final h = birthdayHarness(
            route: tor ? _torReady : const NetworkPrivacyState.off(),
          );
          h.birthdayRespond = (call) async => [
            if (call.urls.contains(_us)) _sample(_us, 80, 99),
          ];
          expect(await h.notifier.getCreationBirthdayHeight(), BigInt.from(99));
          expect(h.birthdayCalls, hasLength(1));
          expect(h.birthdayCalls.single.urls, [rocks, _us]);
          expect(h.birthdayCalls.single.maxConcurrency, tor ? 2 : 4);
          expect(
            h.birthdayCalls.single.totalTimeout,
            lessThanOrEqualTo(
              tor ? const Duration(seconds: 15) : const Duration(seconds: 6),
            ),
          );
          expect(h.fullCalls, isEmpty);
          expect(h.notifier.currentEndpoint.lightwalletdUrl, _eu);
        },
      );
    }

    test('same-operator disagreement beyond two blocks still fails', () async {
      final h = birthdayHarness();
      h.respond = (call) async => [
        if (call.urls.contains(_eu)) _sample(_eu, 100, 100),
        if (call.urls.contains(_kr)) _sample(_kr, 300, 97),
      ];
      await expectLater(
        h.notifier.getCreationBirthdayHeight(),
        throwsStateError,
      );
      expect(h.birthdayCalls, isEmpty);
      expect(h.notifier.currentEndpoint.lightwalletdUrl, _eu);
    });

    test('a singleton future height cannot become a birthday', () async {
      final h = birthdayHarness();
      h.respond = (call) async => [
        if (call.urls.contains(_eu)) _sample(_eu, 20, 4000000000),
      ];
      h.birthdayRespond = (call) async => [
        for (final url in call.urls) _sample(url, 100, 3500000),
      ];
      await expectLater(
        h.notifier.getCreationBirthdayHeight(),
        throwsStateError,
      );
      expect(h.birthdayCalls, hasLength(1));
      expect(h.notifier.currentEndpoint.lightwalletdUrl, _eu);
      expect(
        h.container.read(rpcEndpointFailoverProvider).automaticReady,
        isTrue,
      );
    });

    for (final value in [0, -1, 0x100000000]) {
      test('rejects out-of-range birthday $value', () async {
        final h = birthdayHarness();
        h.respond = (call) async => [
          if (call.urls.contains(_eu)) _sample(_eu, 20, value),
        ];
        h.birthdayRespond = (call) async => [
          for (final url in call.urls) _sample(url, 100, value),
        ];
        await expectLater(
          h.notifier.getCreationBirthdayHeight(),
          throwsStateError,
        );
      });
    }

    test(
      'cached route and peer timestamps are not current-height proof',
      () async {
        final h = birthdayHarness(
          warmRead:
              ({
                required endpoint,
                required selectionId,
                required timeout,
              }) async => _sample(_eu),
        );
        h.store.values[('main', false)] = AutomaticRpcEndpointCache(
          presetId: 'eu-zec-stardust',
          endpointUrl: _eu,
          observedAt: h.now,
          lastSuccessAt: h.now,
          lastPeerValidatedAt: h.now,
          lastNetworkVerifiedAt: h.now,
          lastBenchmarkAt: h.now,
        );
        h.birthdayRespond = (call) async => [
          for (final url in call.urls) _sample(url),
        ];
        expect(await h.notifier.getCreationBirthdayHeight(), BigInt.from(100));
        expect(h.calls, isEmpty);
        expect(h.birthdayCalls.single.urls, [rocks, _us]);
      },
    );

    for (final future in [false, true]) {
      test('ignores ${future ? 'future' : 'old'} receipt times', () async {
        final h = birthdayHarness();
        h.respond = (call) async => [
          for (final url in [_eu, rocks].where(call.urls.contains))
            RpcEndpointCandidateSample(
              url: url,
              height: BigInt.from(900),
              latency: const Duration(milliseconds: 100),
              observedAt: h.now.add(Duration(seconds: future ? 10 : -10)),
            ),
        ];
        h.birthdayRespond = (call) async => [
          for (final url in call.urls) _sample(url, 100, 100),
        ];
        expect(await h.notifier.getCreationBirthdayHeight(), BigInt.from(100));
        expect(h.birthdayCalls.map((call) => call.urls), [
          [_eu],
          [rocks, _us],
        ]);
      });
    }

    test(
      'uses actual receipt time for a slow Tor response and refreshes only the expired observation',
      () async {
        final h = birthdayHarness(route: _torReady);
        h.birthdayRespond = (call) async {
          if (h.birthdayCalls.length == 1) {
            h.now = h.now.add(const Duration(seconds: 8));
          }
          return [
            for (final url in call.urls)
              RpcEndpointCandidateSample(
                url: url,
                height: BigInt.from(100),
                latency: const Duration(seconds: 8),
                observedAt: h.now,
              ),
          ];
        };
        expect(await h.notifier.getCreationBirthdayHeight(), BigInt.from(100));
        expect(h.birthdayCalls, hasLength(2));
        expect(h.birthdayCalls.first.urls, [rocks, _us]);
        expect(h.birthdayCalls.last.urls, [_eu]);
        expect(h.birthdayCalls.every((c) => c.maxConcurrency == 2), isTrue);
      },
    );

    test(
      'peer failure tries another region without cooling the current host',
      () async {
        final h = birthdayHarness();
        h.birthdayRespond = (call) async {
          if (h.birthdayCalls.length == 1) throw StateError('peer timeout');
          return [for (final url in call.urls) _sample(url)];
        };
        expect(await h.notifier.getCreationBirthdayHeight(), BigInt.from(100));
        expect(h.birthdayCalls, hasLength(2));
        expect(h.notifier.currentEndpoint.lightwalletdUrl, _eu);
        expect((await h.notifier.ensureReady()).lightwalletdUrl, _eu);
      },
    );

    for (final tor in [false, true]) {
      test(
        '${tor ? 'Tor' : 'direct'} confirmation has a single bounded deadline',
        () async {
          final h = birthdayHarness(
            route: tor ? _torReady : const NetworkPrivacyState.off(),
            settings: const AutomaticRpcEndpointSettings(
              directBudget: Duration(milliseconds: 100),
              torBudget: Duration(milliseconds: 120),
            ),
          );
          final peer = Completer<List<RpcEndpointCandidateSample>>();
          h.birthdayRespond = (_) => peer.future;
          final watch = Stopwatch()..start();
          await expectLater(
            h.notifier.getCreationBirthdayHeight(),
            throwsA(anyOf(isA<TimeoutException>(), isA<StateError>())),
          );
          expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
          expect(h.cancelled, isNotEmpty);
          peer.complete([_sample(rocks)]);
          await _flush();
          expect(h.notifier.currentEndpoint.lightwalletdUrl, _eu);
        },
      );
    }

    test(
      'concurrent birthday callers share a confirmation but ordinary work stays fast',
      () async {
        final peer = Completer<List<RpcEndpointCandidateSample>>();
        final h = birthdayHarness();
        h.birthdayRespond = (_) => peer.future;
        final first = h.notifier.getCreationBirthdayHeight();
        final second = h.notifier.getCreationBirthdayHeight();
        await _flush();
        expect(h.birthdayCalls, hasLength(1));
        expect((await h.notifier.ensureReady()).lightwalletdUrl, _eu);
        peer.complete([_sample(rocks)]);
        expect(await first, BigInt.from(100));
        expect(await second, BigInt.from(100));
      },
    );

    for (final action in [
      'lock',
      'background',
      'route',
      'manual',
      'reset',
      'dispose',
    ]) {
      test(
        'cancels birthday confirmation on $action and ignores a late peer',
        () async {
          final peer = Completer<List<RpcEndpointCandidateSample>>();
          final h = birthdayHarness();
          h.birthdayRespond = (_) => peer.future;
          final result = h.notifier.getCreationBirthdayHeight();
          final rejection = expectLater(result, throwsStateError);
          await _flush();
          switch (action) {
            case 'lock':
              h.security.publish(
                const AppSecurityState(
                  isPasswordConfigured: true,
                  isUnlocked: false,
                ),
              );
            case 'background':
              h.notifier.cancelAutomaticSelection();
            case 'route':
              h.privacy.publish(_torReady);
            case 'manual':
              h.endpoint.publish(_custom);
            case 'reset':
              await h.notifier.clearAutomaticSelectionCache();
            case 'dispose':
              h.container.dispose();
          }
          await rejection;
          peer.complete([_sample(rocks)]);
          await _flush();
          expect(h.cancelled, isNotEmpty);
        },
      );
    }

    test(
      'manual and custom selections retain their single-server policy',
      () async {
        for (final endpoint in [
          _custom,
          const RpcEndpointConfig(
            networkName: 'main',
            lightwalletdUrl: _eu,
            presetId: 'eu-zec-stardust',
          ),
        ]) {
          final h = birthdayHarness(endpoint: endpoint);
          h.readHeight = () async => BigInt.from(123);
          expect(
            await h.notifier.getCreationBirthdayHeight(),
            BigInt.from(123),
          );
          expect(h.calls, isEmpty);
          expect(h.birthdayCalls, isEmpty);
        }
      },
    );
  });
}

class _Call {
  const _Call(
    this.urls,
    this.probeTimeout,
    this.totalTimeout,
    this.maxConcurrency,
  );
  final List<String> urls;
  final Duration probeTimeout;
  final Duration totalTimeout;
  final int maxConcurrency;
}

class _Harness {
  _Harness({
    RpcEndpointConfig? endpoint,
    NetworkPrivacyState route = const NetworkPrivacyState.off(),
    _Store? store,
    RpcEndpointWarmTipReader? warmRead,
    AutomaticRpcEndpointSettings settings =
        const AutomaticRpcEndpointSettings(),
  }) : endpoint = _Endpoint(endpoint ?? defaultRpcEndpointConfig('main')),
       privacy = _Privacy(route),
       store = store ?? _Store() {
    container = ProviderContainer(
      overrides: [
        rpcEndpointProvider.overrideWith(() => this.endpoint),
        networkPrivacyProvider.overrideWith(() => privacy),
        appSecurityProvider.overrideWith(() => security),
        automaticRpcEndpointStoreProvider.overrideWithValue(this.store),
        automaticRpcEndpointSettingsProvider.overrideWithValue(settings),
        if (warmRead != null)
          rpcEndpointWarmTipReaderProvider.overrideWithValue(warmRead),
        rpcEndpointFailoverClockProvider.overrideWithValue(() => now),
        rpcEndpointSelectionCancelProvider.overrideWithValue(cancelled.add),
        rpcEndpointFailoverChainNameGetterProvider.overrideWithValue(
          (_) async => throw StateError('Unexpected manual-primary probe'),
        ),
        rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue(
          (_, _) => readHeight(),
        ),
        rpcEndpointCandidatesProbeProvider.overrideWithValue(({
          required urls,
          required network,
          required selectionId,
          required probeTimeout,
          required totalTimeout,
          required maxConcurrency,
        }) {
          expect(network, 'main');
          final call = _Call(urls, probeTimeout, totalTimeout, maxConcurrency);
          // Birthday confirmation uses the same early-return probe as selection.
          final birthday = selectionId.contains('-birthday-');
          (birthday ? birthdayCalls : calls).add(call);
          return (birthday ? birthdayRespond : respond)(call).then((samples) {
            expect(
              samples.every((sample) => urls.contains(sample.url)),
              isTrue,
              reason: 'A probe fixture must only return requested hosts',
            );
            return samples;
          });
        }),
        rpcEndpointFullCandidatesProbeProvider.overrideWithValue(({
          required urls,
          required network,
          required selectionId,
          required probeTimeout,
          required totalTimeout,
          required maxConcurrency,
        }) {
          expect(network, 'main');
          final call = _Call(urls, probeTimeout, totalTimeout, maxConcurrency);
          fullCalls.add(call);
          return fullRespond(call);
        }),
      ],
    );
    addTearDown(container.dispose);
  }
  late final ProviderContainer container;
  final _Endpoint endpoint;
  final _Privacy privacy;
  final _Security security = _Security();
  final _Store store;
  final List<_Call> calls = [];
  final List<_Call> fullCalls = [];
  final List<_Call> birthdayCalls = [];
  Future<List<RpcEndpointCandidateSample>> Function(_Call) birthdayRespond =
      (call) async => [for (final url in call.urls) _sample(url)];
  Future<List<RpcEndpointCandidateSample>> Function(_Call) fullRespond =
      (_) async => [_sample(_eu), _sample(_kr, 300)];
  final List<String> cancelled = [];
  DateTime now = DateTime.utc(2026, 11, 5);
  Future<BigInt> Function() readHeight = () async => BigInt.from(100);
  Future<List<RpcEndpointCandidateSample>> Function(_Call) respond =
      (call) async => [
        if (call.urls.contains(_eu)) _sample(_eu),
        if (call.urls.contains(_kr)) _sample(_kr, 300),
      ];
  RpcEndpointFailoverNotifier get notifier =>
      container.read(rpcEndpointFailoverProvider.notifier);
}

class _Endpoint extends RpcEndpointNotifier {
  _Endpoint(this.initial);
  final RpcEndpointConfig initial;
  @override
  RpcEndpointConfig build() => initial;
  void publish(RpcEndpointConfig next) => state = next;
}

class _Privacy extends NetworkPrivacyNotifier {
  _Privacy(this.initial);
  final NetworkPrivacyState initial;
  @override
  NetworkPrivacyState build() => initial;
  void publish(NetworkPrivacyState next) => state = next;
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: false);
  void publish(AppSecurityState next) => state = next;
}

class _Store implements AutomaticRpcEndpointStore {
  final Map<(String, bool), AutomaticRpcEndpointCache> values = {};
  final List<(String, bool)> reads = [];
  final List<(String, bool)> writes = [];
  int clears = 0;
  bool fail = false;
  Future<void>? beforeWrite;
  @override
  Future<AutomaticRpcEndpointCache?> read(String network, bool tor) async {
    if (fail) throw StateError('Storage unavailable');
    reads.add((network, tor));
    return values[(network, tor)];
  }

  @override
  Future<void> write(
    String network,
    bool tor,
    AutomaticRpcEndpointCache cache,
  ) async {
    if (fail) throw StateError('Storage unavailable');
    await beforeWrite;
    writes.add((network, tor));
    values[(network, tor)] = cache;
  }

  @override
  Future<void> clear() async {
    clears++;
    values.clear();
  }
}
