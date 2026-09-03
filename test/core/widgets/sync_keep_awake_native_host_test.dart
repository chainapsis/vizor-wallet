@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/sync_keep_awake_native_host.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/services/native_screen_awake.dart';

import '../../fakes/fake_sync_notifier.dart';

void main() {
  test('uses the production native retry backoff', () {
    expect(kNativeScreenAwakeRetryDelays, const [
      Duration(seconds: 1),
      Duration(seconds: 4),
      Duration(seconds: 16),
    ]);
  });

  testWidgets('does not call native API for near-tip catch-up', (tester) async {
    final calls = _recordScreenAwakeCalls();
    final syncNotifier = FakeSyncNotifier(
      _sync(
        scannedHeight: 100,
        chainTipHeight: 102,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );

    await tester.pumpWidget(_app(syncNotifier: syncNotifier));
    await _drainNativeQueue(tester);

    expect(calls, isEmpty);
  });

  testWidgets('does not enable native keep-awake for known near-tip setup', (
    tester,
  ) async {
    final calls = _recordScreenAwakeCalls();
    final syncNotifier = FakeSyncNotifier(
      _sync(
        percentage: 0,
        scannedHeight: 100,
        chainTipHeight: 102,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
        phase: kSyncPhasePreflight,
      ),
    );

    await tester.pumpWidget(_app(syncNotifier: syncNotifier));
    await _drainNativeQueue(tester);

    expect(calls, isEmpty);
  });

  testWidgets('enables native keep-awake only while sync is eligible', (
    tester,
  ) async {
    final calls = _recordScreenAwakeCalls();
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );

    await tester.pumpWidget(_app(syncNotifier: syncNotifier));
    await _drainNativeQueue(tester);

    expect(_enabledArgs(calls), [true]);

    syncNotifier.emit(
      _sync(
        scannedHeight: 100,
        chainTipHeight: 102,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );
    await _drainNativeQueue(tester);

    expect(_enabledArgs(calls), [true, false]);
  });

  testWidgets('enables native keep-awake during zero-percent first batch', (
    tester,
  ) async {
    final calls = _recordScreenAwakeCalls();
    final syncNotifier = FakeSyncNotifier(
      _sync(
        percentage: 0,
        displayTargetBlocks: 100,
        scannedHeight: 0,
        chainTipHeight: 0,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );

    await tester.pumpWidget(_app(syncNotifier: syncNotifier));
    await _drainNativeQueue(tester);

    expect(_enabledArgs(calls), [true]);
  });

  testWidgets(
    'stays enabled through preparation then disables when sync is near tip',
    (tester) async {
      final calls = _recordScreenAwakeCalls();
      final startedAt = DateTime(2026, 7, 9, 12);
      final syncNotifier = FakeSyncNotifier(
        _sync(
          percentage: 0,
          scannedHeight: 0,
          chainTipHeight: 0,
          lastSyncStartedAt: startedAt,
          phase: kSyncPhasePreflight,
        ),
      );

      await tester.pumpWidget(_app(syncNotifier: syncNotifier));
      await _drainNativeQueue(tester);
      expect(_enabledArgs(calls), [true]);

      for (final phase in [
        kSyncPhaseSetup,
        kSyncPhaseActiveUtxo,
        kSyncPhaseChainPrepare,
      ]) {
        syncNotifier.emit(
          _sync(
            percentage: 0,
            scannedHeight: 0,
            chainTipHeight: 200,
            lastSyncStartedAt: startedAt,
            phase: phase,
          ),
        );
        await _drainNativeQueue(tester);
        expect(
          _enabledArgs(calls),
          [true],
          reason: '$phase must not disable keep-awake during preparation',
        );
      }

      syncNotifier.emit(
        _sync(
          percentage: 0,
          scannedHeight: 100,
          chainTipHeight: 102,
          lastSyncStartedAt: startedAt,
        ),
      );
      await _drainNativeQueue(tester);

      expect(_enabledArgs(calls), [true, false]);
    },
  );

  testWidgets('disables native keep-awake while the app is not foreground', (
    tester,
  ) async {
    final calls = _recordScreenAwakeCalls();
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );

    await tester.pumpWidget(_app(syncNotifier: syncNotifier));
    await _drainNativeQueue(tester);
    expect(_enabledArgs(calls), [true]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _drainNativeQueue(tester);
    expect(_enabledArgs(calls), [true, false]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _drainNativeQueue(tester);
    expect(_enabledArgs(calls), [true, false, true]);
  });

  testWidgets('does not call native API when the setting is disabled', (
    tester,
  ) async {
    final calls = _recordScreenAwakeCalls();
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );

    await tester.pumpWidget(
      _app(syncNotifier: syncNotifier, syncKeepAwakeEnabled: false),
    );
    await _drainNativeQueue(tester);

    expect(calls, isEmpty);
  });

  testWidgets('disables native keep-awake when the host is disposed', (
    tester,
  ) async {
    final calls = _recordScreenAwakeCalls();
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );

    await tester.pumpWidget(_app(syncNotifier: syncNotifier));
    await _drainNativeQueue(tester);
    expect(_enabledArgs(calls), [true]);

    await tester.pumpWidget(const SizedBox.shrink());
    await _drainNativeQueue(tester);

    expect(_enabledArgs(calls), [true, false]);
  });

  testWidgets('retries a failed native request while the state is unchanged', (
    tester,
  ) async {
    final calls = _recordScreenAwakeCalls(
      shouldFail: (_, callIndex) => callIndex == 0,
    );
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );

    await tester.pumpWidget(
      _app(
        syncNotifier: syncNotifier,
        retryDelays: const [Duration(milliseconds: 10)],
      ),
    );
    await _drainNativeQueue(tester);
    expect(_enabledArgs(calls), [true]);

    await tester.pump(const Duration(milliseconds: 10));
    await _drainNativeQueue(tester);

    expect(_enabledArgs(calls), [true, true]);
  });

  testWidgets('stops retrying after the configured attempts are exhausted', (
    tester,
  ) async {
    final calls = _recordScreenAwakeCalls(shouldFail: (_, _) => true);
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );

    await tester.pumpWidget(
      _app(
        syncNotifier: syncNotifier,
        retryDelays: const [
          Duration(milliseconds: 10),
          Duration(milliseconds: 20),
          Duration(milliseconds: 30),
        ],
      ),
    );
    await _drainNativeQueue(tester);

    for (final delay in const [
      Duration(milliseconds: 10),
      Duration(milliseconds: 20),
      Duration(milliseconds: 30),
    ]) {
      await tester.pump(delay);
      await _drainNativeQueue(tester);
    }
    await tester.pump(const Duration(seconds: 1));
    await _drainNativeQueue(tester);

    expect(_enabledArgs(calls), [true, true, true, true]);
  });

  testWidgets('cancels a stale enable retry when the desired state changes', (
    tester,
  ) async {
    final calls = _recordScreenAwakeCalls(
      shouldFail: (enabled, callIndex) => enabled && callIndex == 0,
    );
    final startedAt = DateTime(2026, 7, 9, 12);
    final syncNotifier = FakeSyncNotifier(_sync(lastSyncStartedAt: startedAt));

    await tester.pumpWidget(
      _app(
        syncNotifier: syncNotifier,
        retryDelays: const [Duration(milliseconds: 10)],
      ),
    );
    await _drainNativeQueue(tester);
    expect(_enabledArgs(calls), [true]);

    syncNotifier.emit(
      _sync(
        scannedHeight: 100,
        chainTipHeight: 102,
        lastSyncStartedAt: startedAt,
      ),
    );
    await _drainNativeQueue(tester);
    await tester.pump(const Duration(milliseconds: 20));
    await _drainNativeQueue(tester);

    expect(_enabledArgs(calls), [true, false]);
  });

  testWidgets('retries a failed native disable request', (tester) async {
    var failedDisable = false;
    final calls = _recordScreenAwakeCalls(
      shouldFail: (enabled, _) {
        if (enabled || failedDisable) return false;
        failedDisable = true;
        return true;
      },
    );
    final startedAt = DateTime(2026, 7, 9, 12);
    final syncNotifier = FakeSyncNotifier(_sync(lastSyncStartedAt: startedAt));

    await tester.pumpWidget(
      _app(
        syncNotifier: syncNotifier,
        retryDelays: const [Duration(milliseconds: 10)],
      ),
    );
    await _drainNativeQueue(tester);

    syncNotifier.emit(
      _sync(
        scannedHeight: 100,
        chainTipHeight: 102,
        lastSyncStartedAt: startedAt,
      ),
    );
    await _drainNativeQueue(tester);
    await tester.pump(const Duration(milliseconds: 10));
    await _drainNativeQueue(tester);

    expect(_enabledArgs(calls), [true, false, false]);
  });

  testWidgets('dispose cancels a pending enable retry and forces disable', (
    tester,
  ) async {
    final calls = _recordScreenAwakeCalls(
      shouldFail: (enabled, callIndex) => enabled && callIndex == 0,
    );
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );

    await tester.pumpWidget(
      _app(
        syncNotifier: syncNotifier,
        retryDelays: const [Duration(milliseconds: 10)],
      ),
    );
    await _drainNativeQueue(tester);
    expect(_enabledArgs(calls), [true]);

    await tester.pumpWidget(const SizedBox.shrink());
    await _drainNativeQueue(tester);
    await tester.pump(const Duration(milliseconds: 20));
    await _drainNativeQueue(tester);

    expect(_enabledArgs(calls), [true, false]);
  });

  testWidgets('handles an in-flight native failure after dispose', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    final enableResult = Completer<void>();
    const channel = MethodChannel(kNativeScreenAwakeChannelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final enabled =
              (call.arguments as Map<Object?, Object?>?)?['enabled'] as bool;
          if (enabled) await enableResult.future;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );

    await tester.pumpWidget(_app(syncNotifier: syncNotifier));
    await tester.pump();
    expect(_enabledArgs(calls), [true]);

    await tester.pumpWidget(const SizedBox.shrink());
    enableResult.completeError(PlatformException(code: 'delayed_failure'));
    await _drainNativeQueue(tester);

    expect(tester.takeException(), isNull);
    expect(_enabledArgs(calls), [true, false]);
  });
}

List<MethodCall> _recordScreenAwakeCalls({
  bool Function(bool enabled, int callIndex)? shouldFail,
}) {
  final calls = <MethodCall>[];
  const channel = MethodChannel(kNativeScreenAwakeChannelName);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        final enabled =
            (call.arguments as Map<Object?, Object?>?)?['enabled'] as bool;
        calls.add(call);
        if (shouldFail?.call(enabled, calls.length - 1) ?? false) {
          throw PlatformException(code: 'transient_failure');
        }
        return null;
      });
  addTearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  return calls;
}

List<bool?> _enabledArgs(List<MethodCall> calls) {
  return [
    for (final call in calls)
      (call.arguments as Map<Object?, Object?>?)?['enabled'] as bool?,
  ];
}

Future<void> _drainNativeQueue(WidgetTester tester) async {
  await tester.pump();
  await tester.idle();
  await tester.pump();
}

Widget _app({
  required FakeSyncNotifier syncNotifier,
  bool syncKeepAwakeEnabled = true,
  List<Duration> retryDelays = kNativeScreenAwakeRetryDelays,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(syncKeepAwakeEnabled: syncKeepAwakeEnabled),
      ),
      syncProvider.overrideWith(() => syncNotifier),
    ],
    child: MaterialApp(
      home: SyncKeepAwakeNativeHost(
        retryDelays: retryDelays,
        child: const SizedBox.shrink(),
      ),
    ),
  );
}

AppBootstrapState _bootstrap({required bool syncKeepAwakeEnabled}) {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: const AccountState(),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: kZcashDefaultNetworkName,
    rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
    themeMode: ThemeMode.dark,
    privacyModeEnabled: false,
    syncKeepAwakeEnabled: syncKeepAwakeEnabled,
    syncKeepAwakePromptSeen: true,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

SyncState _sync({
  bool isSyncing = true,
  bool isBackgroundMode = false,
  double percentage = 0.25,
  int displayTargetBlocks = 0,
  int scannedHeight = 100,
  int chainTipHeight = 200,
  DateTime? lastSyncStartedAt,
  String phase = '',
}) {
  return SyncState(
    isSyncing: isSyncing,
    isBackgroundMode: isBackgroundMode,
    percentage: percentage,
    displayTargetBlocks: displayTargetBlocks,
    scannedHeight: scannedHeight,
    chainTipHeight: chainTipHeight,
    lastSyncStartedAt: lastSyncStartedAt,
    phase: phase,
  );
}
