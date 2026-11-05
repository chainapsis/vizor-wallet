import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/lifecycle/app_shutdown_signal.dart';
import 'package:zcash_wallet/src/core/layout/app_process_work_policy.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/automatic_rpc_endpoint_selection.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_provider.dart';
import 'package:zcash_wallet/src/providers/sync_failure.dart';

const _eu = 'https://eu.zec.stardust.rest:443';
const _kr = 'https://kr.zec.stardust.rest:443';
const _tor = NetworkPrivacyState(
  torEnabled: true,
  status: NetworkPrivacyConnectionStatus.connected,
);

RpcEndpointCandidateSample _sample(String url, int height, [int ms = 20]) =>
    RpcEndpointCandidateSample(
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
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('warm timeout follows route latency within recovery bounds', () {
    const settings = AutomaticRpcEndpointSettings();
    for (final (tor, latency, expectedMs) in <(bool, Duration?, int)>[
      (false, null, 1500),
      (true, null, 5000),
      (false, Duration.zero, 1500),
      (true, const Duration(milliseconds: -1), 5000),
      (false, const Duration(milliseconds: 600), 2300),
      (true, const Duration(seconds: 2), 7000),
      (false, const Duration(seconds: 2), 4000),
      (true, const Duration(seconds: 3), 8000),
      (false, const Duration(microseconds: 0x7fffffffffffffff), 4000),
      (true, const Duration(microseconds: 0x7fffffffffffffff), 8000),
    ]) {
      expect(
        settings.warmTipTimeout(tor: tor, recentLatency: latency),
        Duration(milliseconds: expectedMs),
      );
    }
    const smallerBudget = AutomaticRpcEndpointSettings(
      directBudget: Duration(seconds: 3),
      torBudget: Duration(seconds: 6),
    );
    for (final (tor, expectedSeconds) in [(false, 2), (true, 4)]) {
      expect(
        smallerBudget.warmTipTimeout(
          tor: tor,
          recentLatency: const Duration(seconds: 10),
        ),
        Duration(seconds: expectedSeconds),
      );
    }
  });

  for (final tor in [false, true]) {
    test(
      '${tor ? 'Tor' : 'direct'} healthy warm read uses cached and resumed latency',
      () async {
        final url = tor ? _kr : _eu;
        final harness =
            _WarmHarness(route: tor ? _tor : const NetworkPrivacyState.off())
              ..seedTrusted(
                tor ? 'kr-zec-stardust' : 'eu-zec-stardust',
                tor: tor,
                latencyMs: tor ? 2000 : 600,
              );
        harness.warmRead = (_) => Future.delayed(
          Duration(milliseconds: tor ? 2200 : 850),
          () => _sample(url, 111, tor ? 3000 : 900),
        );
        await harness.notifier.ensureReady();
        expect(
          harness.warmReads.single.timeout,
          Duration(milliseconds: tor ? 7000 : 2300),
        );
        expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));

        harness.warmRead = (_) async => _sample(url, 112);
        harness.notifier.cancelAutomaticSelection();
        await harness.notifier.ensureReady();
        expect(
          harness.warmReads.last.timeout,
          Duration(milliseconds: tor ? 8000 : 3200),
        );
        expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(112));
        expect(harness.warmReads, hasLength(2));
        expect(harness.probes, isEmpty);
        expect(harness.ordinaryReads, isEmpty);
      },
    );
  }

  test(
    'secure cache serialization round-trips URL and evaluation clocks without persisting a height',
    () async {
      const store = SecureAutomaticRpcEndpointStore();
      final now = DateTime.utc(2026, 11, 5);
      for (final tor in [false, true]) {
        final original = AutomaticRpcEndpointCache(
          presetId: tor ? 'kr-zec-stardust' : 'eu-zec-stardust',
          endpointUrl: tor ? _kr : _eu,
          observedAt: now,
          lastSuccessAt: now.subtract(const Duration(seconds: 1)),
          lastPeerValidatedAt: now.subtract(const Duration(minutes: 2)),
          lastBenchmarkAt: now.subtract(const Duration(minutes: 3)),
          lastNetworkVerifiedAt: now.subtract(const Duration(minutes: 4)),
          latencyMs: 37,
        );
        await store.write('main', tor, original);
        final decoded = await const SecureAutomaticRpcEndpointStore().read(
          'main',
          tor,
        );
        expect(decoded, isNotNull);
        expect(decoded!.presetId, original.presetId);
        expect(decoded.endpointUrl, original.endpointUrl);
        expect(decoded.observedAt, original.observedAt);
        expect(decoded.lastSuccessAt, original.lastSuccessAt);
        expect(decoded.lastPeerValidatedAt, original.lastPeerValidatedAt);
        expect(decoded.lastBenchmarkAt, original.lastBenchmarkAt);
        expect(decoded.lastNetworkVerifiedAt, original.lastNetworkVerifiedAt);
        expect(decoded.latencyMs, 37);
        expect(
          decoded.isWarm(
            now,
            const AutomaticRpcEndpointSettings(),
            expectedUrl: original.endpointUrl,
          ),
          isTrue,
        );
        final raw = await AppSecureStore.instance.readPlain(
          'zcash_automatic_rpc_v1_main_${tor ? 'tor' : 'direct'}',
        );
        final fields = jsonDecode(raw!) as Map<String, dynamic>;
        expect(fields.keys.toSet(), {
          'preset',
          'endpointUrl',
          'observedAt',
          'lastSuccessAt',
          'lastPeerValidatedAt',
          'lastBenchmarkAt',
          'lastNetworkVerifiedAt',
          'latencyMs',
        });
        expect(
          fields.keys.any((key) => key.toLowerCase().contains('height')),
          isFalse,
        );
      }
      await store.clear();
      expect(await store.read('main', false), isNull);
      expect(await store.read('main', true), isNull);
    },
  );

  test(
    'legacy secure-store JSON loads only as an untrusted endpoint hint',
    () async {
      final now = DateTime.utc(2026, 11, 5);
      final fields = {
        'preset': 'kr-zec-stardust',
        'observedAt': now.toIso8601String(),
      };
      FlutterSecureStorage.setMockInitialValues({
        'zcash_automatic_rpc_v1_main_direct': jsonEncode(fields),
      });
      const store = SecureAutomaticRpcEndpointStore();
      final legacy = await store.read('main', false);
      expect(legacy, isNotNull);
      expect(legacy!.presetId, 'kr-zec-stardust');
      expect(legacy.observedAt, now);
      expect(legacy.endpointUrl, isNull);
      expect(legacy.lastSuccessAt, isNull);
      expect(legacy.lastPeerValidatedAt, isNull);
      expect(legacy.lastBenchmarkAt, isNull);
      expect(legacy.lastNetworkVerifiedAt, isNull);
      expect(legacy.latencyMs, isNull);
      expect(
        legacy.isWarm(
          now,
          const AutomaticRpcEndpointSettings(),
          expectedUrl: _kr,
        ),
        isFalse,
      );
      await store.write('main', false, legacy);
      final raw = await AppSecureStore.instance.readPlain(
        'zcash_automatic_rpc_v1_main_direct',
      );
      expect((jsonDecode(raw!) as Map<String, dynamic>).keys.toSet(), {
        'preset',
        'observedAt',
      });
      expect(await store.read('main', true), isNull);
    },
  );

  for (final (id, url) in [
    ('eu-zec-stardust', _eu),
    ('kr-zec-stardust', _kr),
  ]) {
    test(
      'trusted $id cache restores without candidate probes or a persisted tip',
      () async {
        final harness = _WarmHarness()..seedTrusted(id);
        BigInt? baselineBeforeActualRead;
        harness.warmRead = (call) async {
          baselineBeforeActualRead = harness.state.lastObservedHeight;
          return _sample(call.endpoint.normalizedLightwalletdUrl, 111);
        };
        final endpoint = await harness.notifier.ensureReady();
        expect(endpoint.normalizedLightwalletdUrl, url);
        expect(harness.probes, isEmpty);
        expect(harness.warmReads, hasLength(1));
        expect(harness.ordinaryReads, isEmpty);
        expect(baselineBeforeActualRead, isNull);
        expect(harness.state.automaticProvisional, isFalse);
        expect(
          isAutomaticRpcEndpointConfig(
            harness.container.read(rpcEndpointProvider),
          ),
          isTrue,
        );

        expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));
        await _flush();
        expect(harness.warmReads, hasLength(1));
        expect(
          harness.warmReads.single.endpoint.normalizedLightwalletdUrl,
          url,
        );
        expect(
          harness.warmReads.single.timeout,
          const Duration(milliseconds: 1500),
        );
        expect(harness.ordinaryReads, isEmpty);
        expect(harness.probes, isEmpty);
      },
    );
  }

  test(
    'Tor warm cache uses its own chosen host and five-second minimum tip budget',
    () async {
      final harness = _WarmHarness(route: _tor)
        ..seedTrusted('eu-zec-stardust')
        ..seedTrusted('kr-zec-stardust', tor: true);
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _kr);
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));
      await _flush();
      expect(harness.warmReads.single.endpoint.lightwalletdUrl, _kr);
      expect(harness.warmReads.single.timeout, const Duration(seconds: 5));
      expect(harness.probes, isEmpty);
      expect(harness.store.reads, [('main', true)]);
    },
  );

  test(
    'old cache record remains a hint and cannot invent recent success or peer proof',
    () async {
      final harness = _WarmHarness();
      harness.store.values[('main', false)] = AutomaticRpcEndpointCache(
        presetId: 'kr-zec-stardust',
        observedAt: harness.now.subtract(const Duration(minutes: 1)),
      );
      await harness.notifier.ensureReady();
      expect(harness.probes, isNotEmpty);
      expect(harness.probes.first.urls, [_kr]);
      expect(harness.warmReads, isEmpty);
    },
  );

  for (final oldUrl in [null, 'https://old-region.example:443']) {
    test(
      'recent cache ${oldUrl == null ? 'without physical URL' : 'for repointed preset'} cannot skip chain verification',
      () async {
        final harness = _WarmHarness();
        harness.store.values[('main', false)] = AutomaticRpcEndpointCache(
          presetId: 'kr-zec-stardust',
          endpointUrl: oldUrl,
          observedAt: harness.now.subtract(const Duration(minutes: 1)),
          lastSuccessAt: harness.now.subtract(const Duration(minutes: 1)),
          lastPeerValidatedAt: harness.now.subtract(const Duration(minutes: 2)),
          lastBenchmarkAt: harness.now.subtract(const Duration(minutes: 3)),
          latencyMs: 20,
        );
        await harness.notifier.ensureReady();
        expect(harness.probes, isNotEmpty);
        expect(harness.probes.first.urls, [_kr]);
        expect(harness.warmReads, isEmpty);
        if (oldUrl != null) {
          expect(
            harness.probes.every((call) => !call.urls.contains(oldUrl)),
            isTrue,
          );
        }
      },
    );
  }

  for (final successAge in [
    const Duration(minutes: 6),
    const Duration(minutes: -1),
  ]) {
    test(
      'success age $successAge does not permit an unchecked warm restore',
      () async {
        final harness = _WarmHarness()
          ..seedTrusted('eu-zec-stardust', successAge: successAge);
        await harness.notifier.ensureReady();
        expect(harness.probes, isNotEmpty);
      },
    );
  }

  for (final explicitNetworkProof in [false, true]) {
    test(
      'chain-info proof older than twelve hours forces a full probe (${explicitNetworkProof ? 'explicit' : 'benchmark fallback'})',
      () async {
        final harness = _WarmHarness();
        harness.store.values[('main', false)] = AutomaticRpcEndpointCache(
          presetId: 'kr-zec-stardust',
          endpointUrl: _kr,
          observedAt: harness.now.subtract(const Duration(minutes: 1)),
          lastSuccessAt: harness.now.subtract(const Duration(minutes: 1)),
          lastPeerValidatedAt: harness.now.subtract(const Duration(minutes: 2)),
          lastBenchmarkAt: harness.now.subtract(
            explicitNetworkProof
                ? const Duration(minutes: 3)
                : const Duration(hours: 13),
          ),
          lastNetworkVerifiedAt: explicitNetworkProof
              ? harness.now.subtract(const Duration(hours: 13))
              : null,
          latencyMs: 20,
        );
        await harness.notifier.ensureReady();
        expect(harness.probes, isNotEmpty);
        expect(harness.warmReads, isEmpty);
      },
    );
  }

  test(
    'cold selection reuses its live tip once instead of making a duplicate read',
    () async {
      final harness = _WarmHarness();
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(110));
      expect(harness.probes, hasLength(1));
      expect(harness.warmReads, isEmpty);
      expect(harness.ordinaryReads, isEmpty);

      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));
      expect(harness.ordinaryReads, hasLength(1));
      expect(harness.warmReads, isEmpty);
      expect(harness.probes, hasLength(1));
    },
  );

  test('live selection tip is not reused beyond five seconds', () async {
    final harness = _WarmHarness();
    await harness.notifier.ensureReady();
    harness.now = harness.now.add(const Duration(seconds: 6));
    expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));
    expect(harness.warmReads.length + harness.ordinaryReads.length, 1);
  });

  test(
    'ten short lock cycles retain healthy server evaluation without new candidate probes',
    () async {
      final harness = _WarmHarness()..seedTrusted('kr-zec-stardust');
      await harness.notifier.ensureReady();
      final peerAt = harness.store.values[('main', false)]!.lastPeerValidatedAt;
      final benchmarkAt =
          harness.store.values[('main', false)]!.lastBenchmarkAt;
      for (var i = 0; i < 10; i++) {
        harness.security.publish(
          const AppSecurityState(isPasswordConfigured: true, isUnlocked: false),
        );
        await _flush();
        await expectLater(harness.notifier.ensureReady(), throwsStateError);
        harness.now = harness.now.add(const Duration(seconds: 10));
        harness.security.publish(
          const AppSecurityState(isPasswordConfigured: true, isUnlocked: true),
        );
        expect((await harness.notifier.ensureReady()).lightwalletdUrl, _kr);
      }
      expect(harness.probes, isEmpty);
      expect(
        harness.store.values[('main', false)]!.lastPeerValidatedAt,
        peerAt,
      );
      expect(
        harness.store.values[('main', false)]!.lastBenchmarkAt,
        benchmarkAt,
      );
    },
  );

  testWidgets(
    'short background resume retains evaluation under the selected process policy',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final harness = _WarmHarness()..seedTrusted('kr-zec-stardust');
      await harness.notifier.ensureReady();
      final original = harness.store.values[('main', false)]!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      if (canRunAppProcessWork(isInForeground: false)) {
        expect((await harness.notifier.ensureReady()).lightwalletdUrl, _kr);
      } else {
        await expectLater(harness.notifier.ensureReady(), throwsStateError);
      }
      harness.now = harness.now.add(const Duration(seconds: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _kr);
      expect(harness.probes, isEmpty);
      expect(
        harness.store.values[('main', false)]!.lastPeerValidatedAt,
        original.lastPeerValidatedAt,
      );
      expect(
        harness.store.values[('main', false)]!.lastBenchmarkAt,
        original.lastBenchmarkAt,
      );
    },
  );

  test(
    'soft cancellation clears one-use live tip without discarding evaluation',
    () async {
      final harness = _WarmHarness();
      await harness.notifier.ensureReady();
      harness.notifier.cancelAutomaticSelection();
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));
      expect(harness.probes, hasLength(1));
      expect(harness.warmReads.length + harness.ordinaryReads.length, 1);
    },
  );

  test(
    'actual tip success refreshes success time without extending peer or benchmark proof',
    () async {
      final harness = _WarmHarness()..seedTrusted('eu-zec-stardust');
      final initial = harness.store.values[('main', false)]!;
      await harness.notifier.ensureReady();
      await harness.notifier.getLatestBlockHeight();
      await _flush();
      final first = harness.store.values[('main', false)]!;
      expect(first.lastSuccessAt, harness.now);
      expect(first.lastPeerValidatedAt, initial.lastPeerValidatedAt);
      expect(first.lastBenchmarkAt, initial.lastBenchmarkAt);
      harness.now = harness.now.add(const Duration(minutes: 1));
      await harness.notifier.getLatestBlockHeight();
      await _flush();
      final next = harness.store.values[('main', false)]!;
      expect(next.lastSuccessAt, harness.now);
      expect(next.lastPeerValidatedAt, initial.lastPeerValidatedAt);
      expect(next.lastBenchmarkAt, initial.lastBenchmarkAt);
      expect(harness.probes, isEmpty);
    },
  );

  test(
    'frequent actual tips throttle cache writes while keeping success fresh in memory',
    () async {
      final harness = _WarmHarness()..seedTrusted('eu-zec-stardust');
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));
      await _flush();
      for (var i = 0; i < 5; i++) {
        harness.now = harness.now.add(const Duration(seconds: 5));
        expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));
        await _flush();
      }
      expect(harness.warmReads, hasLength(1));
      expect(harness.ordinaryReads, hasLength(5));
      expect(harness.store.writes.length, lessThanOrEqualTo(1));
      // The last actual success is newer than the throttled disk snapshot. A
      // short lock must use that in-memory evidence, not age from the first read.
      harness.now = harness.now.add(const Duration(minutes: 4, seconds: 40));
      harness.notifier.cancelAutomaticSelection();
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
      expect(harness.probes, isEmpty);
    },
  );

  test(
    'expired peer confidence cannot be renewed by ordinary successful reads',
    () async {
      final harness = _WarmHarness()
        ..seedTrusted('eu-zec-stardust', peerAge: const Duration(minutes: 16));
      final oldPeerAt =
          harness.store.values[('main', false)]!.lastPeerValidatedAt;
      harness.probe = (_) async => [];
      final response = Completer<RpcEndpointCandidateSample>();
      harness.warmRead = (_) => response.future;
      final preparing = harness.notifier.ensureReady();
      await _flush();
      expect(harness.warmReads, hasLength(1));
      // A restored hint contains no current chain observation. Peer validation
      // has to wait for this real tip rather than compare against a saved height.
      expect(harness.probes, isEmpty);
      response.complete(_sample(_eu, 111));
      await preparing;
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));
      await _flush();
      expect(harness.probes, isNotEmpty);
      expect(harness.probes.every((call) => !call.urls.contains(_eu)), isTrue);
      expect(harness.state.automaticProvisional, isTrue);
      expect(
        harness.store.values[('main', false)]!.lastPeerValidatedAt,
        anyOf(isNull, oldPeerAt),
      );
      expect(harness.store.values[('main', false)]!.lastSuccessAt, harness.now);
    },
  );

  test(
    'failed first actual warm tip falls through to bounded candidate selection',
    () async {
      final harness = _WarmHarness()..seedTrusted('eu-zec-stardust');
      harness.warmRead = (_) async =>
          throw StateError('network: warm tip timed out');
      harness.probe = (call) async => [
        if (call.urls.contains(_kr)) _sample(_kr, 120),
        if (call.urls.contains('https://eu.zec.rocks:443'))
          _sample('https://eu.zec.rocks:443', 120, 50),
      ];
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(120));
      expect(harness.warmReads, hasLength(1));
      expect(harness.probes, isNotEmpty);
      expect(harness.state.current.lightwalletdUrl, _kr);
      expect(harness.ordinaryReads, isEmpty);
    },
  );

  for (final tor in [false, true]) {
    for (final (label, error) in <(String, Object)>[
      ('Dart deadline', TimeoutException('warm read deadline')),
      (
        'native failure',
        StateError('automatic endpoint selection: no healthy candidates'),
      ),
      ('local runtime', StateError('tokio: Too many open files (os error 24)')),
      ('panic', StateError('Rust panic: local failure')),
      (
        'admission',
        StateError('automatic endpoint selection: too many active selections'),
      ),
      ('unknown', StateError('unrecognized failure')),
      ('connection reset', StateError('network: connection reset by peer')),
    ]) {
      test(
        '${tor ? 'Tor' : 'direct'} warm failure only excludes the current request: $label',
        () async {
          const peer = 'https://eu.zec.rocks:443';
          const global = 'https://zec.rocks:443';
          final harness = _WarmHarness(
            route: tor ? _tor : const NetworkPrivacyState.off(),
          )..seedTrusted('eu-zec-stardust', tor: tor);
          harness.warmRead = (_) async => throw error;
          harness.probe = (call) async {
            expect(harness.state.automaticReady, isFalse);
            return [
              if (call.urls.contains(_eu)) _sample(_eu, 120, 10),
              if (call.urls.contains(_kr)) _sample(_kr, 120, 20),
              if (call.urls.contains(peer)) _sample(peer, 120, 40),
              if (call.urls.contains(global)) _sample(global, 120, 60),
            ];
          };

          expect(
            await harness.notifier.getLatestBlockHeight(),
            BigInt.from(120),
          );
          expect(harness.probes.single.urls, isNot(contains(_eu)));
          expect(harness.state.current.lightwalletdUrl, _kr);

          // Still in the same minute: a warm-read failure must not exclude A
          // from B's ordinary RPC recovery. A new successful sample is needed.
          expect(
            await harness.notifier.switchToFallbackFor(
              StateError('network: connection reset'),
              endpoint: harness.state.current,
              operation: 'ordinary RPC on replacement',
            ),
            isTrue,
          );
          expect(harness.probes.last.urls, contains(_eu));
          expect(harness.probes.last.urls, isNot(contains(_kr)));
          expect(harness.state.current.lightwalletdUrl, _eu);

          // Ordinary RPC failures continue to create the existing cooldown.
          expect(
            await harness.notifier.switchToFallbackFor(
              StateError('network: connection reset'),
              endpoint: harness.state.current,
              operation: 'ordinary RPC on original',
            ),
            isTrue,
          );
          expect(harness.probes.last.urls, isNot(contains(_eu)));
          expect(harness.probes.last.urls, isNot(contains(_kr)));
          expect(harness.state.current.lightwalletdUrl, peer);
          expect(harness.probes, hasLength(3));
          expect(harness.warmReads, hasLength(1));
          expect(harness.ordinaryReads, isEmpty);
        },
      );
    }
  }

  test(
    'isolated replacement cannot inherit the previous server peer proof',
    () async {
      final harness = _WarmHarness()..seedTrusted('eu-zec-stardust');
      final first = await harness.notifier.ensureReady();
      harness.probe = (call) async => [
        if (call.urls.contains(_kr)) _sample(_kr, 120),
      ];
      expect(
        await harness.notifier.switchToFallbackFor(
          StateError('network: connection reset'),
          endpoint: first,
          operation: 'failed cached endpoint',
        ),
        isTrue,
      );
      await _flush();
      expect(harness.state.current.lightwalletdUrl, _kr);
      expect(harness.state.automaticProvisional, isTrue);
      expect(
        harness.store.values[('main', false)]!.presetId,
        'kr-zec-stardust',
      );
      expect(
        harness.store.values[('main', false)]!.lastPeerValidatedAt,
        isNull,
      );
    },
  );

  test('concurrent first warm tip requests share one native read', () async {
    final harness = _WarmHarness()..seedTrusted('kr-zec-stardust');
    final response = Completer<RpcEndpointCandidateSample>();
    harness.warmRead = (_) => response.future;
    final first = harness.notifier.getLatestBlockHeight();
    final second = harness.notifier.getLatestBlockHeight();
    await _flush();
    expect(harness.warmReads, hasLength(1));
    response.complete(_sample(_kr, 111));
    expect(await first, BigInt.from(111));
    expect(await second, BigInt.from(111));
    expect(harness.probes, isEmpty);
    expect(harness.ordinaryReads, isEmpty);
  });

  for (final reset in [false, true]) {
    test(
      '${reset ? 'reset' : 'lock'} cancels warm tip and cannot persist a late success',
      () async {
        final harness = _WarmHarness()..seedTrusted('eu-zec-stardust');
        final response = Completer<RpcEndpointCandidateSample>();
        harness.warmRead = (_) => response.future;
        final pending = expectLater(
          harness.notifier.getLatestBlockHeight(),
          throwsStateError,
        );
        await _flush();
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
        await pending;
        response.complete(_sample(_eu, 999));
        await _flush();
        expect(harness.cancelled, isNotEmpty);
        expect(harness.probes, isEmpty);
        expect(harness.store.writes.length, writes);
        if (reset) expect(harness.store.values, isEmpty);
      },
    );
  }

  test(
    'Tor warm-read cancellation preserves a failed route for Retry',
    () async {
      final harness = _WarmHarness(route: _tor)
        ..seedTrusted('kr-zec-stardust', tor: true);
      final response = Completer<RpcEndpointCandidateSample>();
      harness.warmRead = (_) => response.future;
      final result = harness.notifier.getLatestBlockHeight().then<Object>(
        (_) => throw TestFailure('Expected failed Tor warm read'),
        onError: (Object error, StackTrace _) => error,
      );
      await _flush();
      expect(harness.warmReads, hasLength(1));
      harness.privacy.publish(
        const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.failed,
        ),
      );
      expect(classifySyncFailure(await result).retriesTorRoute, isTrue);
      expect(harness.probes, isEmpty);
      expect(harness.cancelled, hasLength(1));
      response.complete(_sample(_kr, 999));
      await _flush();
      expect(harness.store.writes, isEmpty);
      expect(harness.state.automaticReady, isFalse);
    },
  );

  test(
    'route switch restores only the new route cache and never carries its live tip across',
    () async {
      final harness = _WarmHarness(route: _tor)
        ..seedTrusted('eu-zec-stardust')
        ..seedTrusted('kr-zec-stardust', tor: true);
      await harness.notifier.ensureReady();
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));
      harness.privacy.publish(const NetworkPrivacyState.off());
      await _flush();
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _eu);
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));
      expect(harness.warmReads.map((call) => call.endpoint.lightwalletdUrl), [
        _kr,
        _eu,
      ]);
      expect(harness.probes, isEmpty);
      expect(harness.store.reads, [('main', true), ('main', false)]);
    },
  );

  test(
    'route cancellation does not leave a new reader attached to an old ordinary flight',
    () async {
      final harness = _WarmHarness()
        ..seedTrusted('eu-zec-stardust')
        ..seedTrusted('kr-zec-stardust', tor: true);
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));
      final oldRead = Completer<BigInt>();
      harness.ordinaryRead = (_) => oldRead.future;
      final previous = harness.notifier.getLatestBlockHeight();
      await _flush();
      expect(harness.ordinaryReads, [_eu]);
      harness.privacy.publish(_tor);
      final next = harness.notifier.getLatestBlockHeight();
      await _flush();
      expect(harness.warmReads.map((call) => call.endpoint.lightwalletdUrl), [
        _eu,
        _kr,
      ]);
      expect(await next.timeout(const Duration(seconds: 1)), BigInt.from(111));
      oldRead.complete(BigInt.from(999));
      await previous;
      await _flush();
      expect(harness.state.current.lightwalletdUrl, _kr);
      expect(harness.state.lastObservedHeight, BigInt.from(111));
    },
  );

  test(
    'warm single-use tip is bound to the current selected endpoint',
    () async {
      final harness = _WarmHarness();
      await harness.notifier.ensureReady();
      harness.notifier.invalidateAutomaticSelection();
      harness.store.values[('main', false)] = harness.trusted(
        'kr-zec-stardust',
      );
      expect((await harness.notifier.ensureReady()).lightwalletdUrl, _kr);
      expect(await harness.notifier.getLatestBlockHeight(), BigInt.from(111));
      expect(harness.warmReads.single.endpoint.lightwalletdUrl, _kr);
      expect(harness.ordinaryReads, isEmpty);
    },
  );
}

class _WarmCall {
  const _WarmCall(this.endpoint, this.selectionId, this.timeout);
  final RpcEndpointConfig endpoint;
  final String selectionId;
  final Duration timeout;
}

class _ProbeCall {
  const _ProbeCall(this.urls, this.totalTimeout);
  final List<String> urls;
  final Duration totalTimeout;
}

class _WarmHarness {
  _WarmHarness({NetworkPrivacyState route = const NetworkPrivacyState.off()})
    : privacy = _Privacy(route) {
    container = ProviderContainer(
      overrides: [
        rpcEndpointProvider.overrideWith(_Endpoint.new),
        networkPrivacyProvider.overrideWith(() => privacy),
        appSecurityProvider.overrideWith(() => security),
        appShutdownSignalProvider.overrideWithValue(shutdown),
        automaticRpcEndpointStoreProvider.overrideWithValue(store),
        rpcEndpointFailoverClockProvider.overrideWithValue(() => now),
        rpcEndpointSelectionCancelProvider.overrideWithValue(cancelled.add),
        rpcEndpointWarmTipReaderProvider.overrideWithValue(({
          required endpoint,
          required selectionId,
          required timeout,
        }) {
          final call = _WarmCall(endpoint, selectionId, timeout);
          warmReads.add(call);
          return warmRead(call);
        }),
        rpcEndpointFailoverLatestBlockHeightGetterProvider.overrideWithValue((
          url,
          network,
        ) async {
          expect(network, 'main');
          ordinaryReads.add(url);
          return ordinaryRead(url);
        }),
        rpcEndpointFailoverChainNameGetterProvider.overrideWithValue(
          (_) async => throw StateError('Unexpected manual-primary probe'),
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
          final call = _ProbeCall(urls, totalTimeout);
          probes.add(call);
          return probe(call).then((samples) {
            expect(
              samples.every((sample) => urls.contains(sample.url)),
              isTrue,
            );
            return samples;
          });
        }),
      ],
    );
    addTearDown(() {
      container.dispose();
      shutdown.dispose();
    });
  }
  late final ProviderContainer container;
  final _Privacy privacy;
  final _Security security = _Security();
  final _Store store = _Store();
  final AppShutdownSignal shutdown = AppShutdownSignal();
  final List<_WarmCall> warmReads = [];
  final List<_ProbeCall> probes = [];
  final List<String> ordinaryReads = [];
  final List<String> cancelled = [];
  DateTime now = DateTime.utc(2026, 11, 5);
  Future<BigInt> Function(String) ordinaryRead = (_) async => BigInt.from(111);
  Future<RpcEndpointCandidateSample> Function(_WarmCall) warmRead =
      (call) async => _sample(call.endpoint.normalizedLightwalletdUrl, 111);
  Future<List<RpcEndpointCandidateSample>> Function(_ProbeCall) probe =
      (call) async => [
        if (call.urls.contains(_eu)) _sample(_eu, 110),
        if (call.urls.contains(_kr)) _sample(_kr, 110, 60),
      ];
  RpcEndpointFailoverNotifier get notifier =>
      container.read(rpcEndpointFailoverProvider.notifier);
  RpcEndpointFailoverState get state =>
      container.read(rpcEndpointFailoverProvider);

  AutomaticRpcEndpointCache trusted(
    String presetId, {
    Duration successAge = const Duration(minutes: 1),
    Duration peerAge = const Duration(minutes: 2),
    Duration benchmarkAge = const Duration(minutes: 3),
    int latencyMs = 20,
  }) => AutomaticRpcEndpointCache(
    presetId: presetId,
    endpointUrl: findRpcEndpointPresetById('main', presetId)!.url,
    observedAt: now.subtract(const Duration(minutes: 1)),
    lastSuccessAt: now.subtract(successAge),
    lastPeerValidatedAt: now.subtract(peerAge),
    lastBenchmarkAt: now.subtract(benchmarkAge),
    latencyMs: latencyMs,
  );
  void seedTrusted(
    String presetId, {
    bool tor = false,
    Duration successAge = const Duration(minutes: 1),
    Duration peerAge = const Duration(minutes: 2),
    Duration benchmarkAge = const Duration(minutes: 3),
    int latencyMs = 20,
  }) => store.values[('main', tor)] = trusted(
    presetId,
    successAge: successAge,
    peerAge: peerAge,
    benchmarkAge: benchmarkAge,
    latencyMs: latencyMs,
  );
}

class _Endpoint extends RpcEndpointNotifier {
  @override
  RpcEndpointConfig build() => defaultRpcEndpointConfig('main');
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
  @override
  Future<AutomaticRpcEndpointCache?> read(String network, bool tor) async {
    reads.add((network, tor));
    return values[(network, tor)];
  }

  @override
  Future<void> write(
    String network,
    bool tor,
    AutomaticRpcEndpointCache cache,
  ) async {
    writes.add((network, tor));
    values[(network, tor)] = cache;
  }

  @override
  Future<void> clear() async => values.clear();
}
