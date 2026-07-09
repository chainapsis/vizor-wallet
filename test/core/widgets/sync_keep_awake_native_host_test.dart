@Tags(['mobile'])
library;

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
}

List<MethodCall> _recordScreenAwakeCalls() {
  final calls = <MethodCall>[];
  const channel = MethodChannel(kNativeScreenAwakeChannelName);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
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
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(syncKeepAwakeEnabled: syncKeepAwakeEnabled),
      ),
      syncProvider.overrideWith(() => syncNotifier),
    ],
    child: const MaterialApp(
      home: SyncKeepAwakeNativeHost(child: SizedBox.shrink()),
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
  int scannedHeight = 100,
  int chainTipHeight = 200,
  DateTime? lastSyncStartedAt,
}) {
  return SyncState(
    isSyncing: isSyncing,
    isBackgroundMode: isBackgroundMode,
    percentage: percentage,
    scannedHeight: scannedHeight,
    chainTipHeight: chainTipHeight,
    lastSyncStartedAt: lastSyncStartedAt,
  );
}
