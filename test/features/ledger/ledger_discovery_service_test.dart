import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';

import '../../support/ledger_discovery_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LedgerDiscoveryChannel native;
  setUp(() => native = LedgerDiscoveryChannel());
  tearDown(() => native.dispose());

  for (final hasDevice in [false, true]) {
    for (final paused in [false, true]) {
      test(
        'quiet discovery cancels (device: $hasDevice, paused: $paused)',
        () async {
          final subscription = native.service.discoverDevices().listen((_) {});
          await Future<void>.delayed(Duration.zero);
          if (hasDevice) {
            await native.devices();
            await Future<void>.delayed(Duration.zero);
          }
          if (paused) subscription.pause();
          await Future.wait([
            subscription.cancel(),
            native.service.stopDiscovery(),
          ]).timeout(const Duration(seconds: 1));
          await Future<void>.delayed(Duration.zero);
          expect(native.eventCalls, ['listen', 'cancel']);
        },
      );
    }
  }

  test('cancelling a pending start suppresses its late failure', () async {
    final start = Completer<void>();
    native.starting = start.future;
    native.startError = PlatformException(code: 'bluetooth_off');
    final updates = <LedgerDiscoveryUpdate>[];
    final subscription = native.service.discoverDevices().listen(updates.add);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel().timeout(const Duration(seconds: 1));
    start.complete();
    await Future<void>.delayed(Duration.zero);
    expect(updates, isEmpty);
    expect(native.eventCalls, ['listen', 'cancel']);
  });

  for (final terminal in [
    'ended',
    'error',
    'platform error',
    'malformed',
    'EOF',
  ]) {
    test(
      '$terminal closes discovery and detaches the native listener',
      () async {
        final updates = <LedgerDiscoveryUpdate>[];
        final errors = <Object>[];
        final done = Completer<void>();
        native.service.discoverDevices().listen(
          updates.add,
          onError: errors.add,
          onDone: done.complete,
        );
        await Future<void>.delayed(Duration.zero);
        switch (terminal) {
          case 'ended':
            await native.emit({'type': 'ended'});
          case 'error':
            await native.emit({'type': 'error', 'code': 'bluetooth_off'});
          case 'platform error':
            await native.error('bluetooth_off');
          case 'malformed':
            await native.emit('not a discovery event');
          case 'EOF':
            await native.emit(null);
        }
        await done.future.timeout(const Duration(seconds: 1));
        expect(native.eventCalls, ['listen', 'cancel']);
        if (terminal == 'malformed') {
          expect(errors, hasLength(1));
        } else if (terminal == 'EOF') {
          expect(updates, isEmpty);
        } else {
          expect(
            updates.single,
            terminal == 'ended'
                ? isA<LedgerDiscoveryEnded>()
                : isA<LedgerDiscoveryFailed>(),
          );
          expect(errors, isEmpty);
        }
      },
    );
  }

  test('a failed start emits its classified failure and closes', () async {
    native.startError = PlatformException(code: 'bluetooth_off');
    final updates = await native.service.discoverDevices().toList().timeout(
      const Duration(seconds: 1),
    );
    expect(
      (updates.single as LedgerDiscoveryFailed).error.failure,
      LedgerMobileFailure.bluetoothOff,
    );
    expect(native.eventCalls, ['listen', 'cancel']);
  });

  test(
    'repeated scans detach old listeners before the next native listen',
    () async {
      for (var i = 0; i < 3; i++) {
        final updates = <LedgerDiscoveryUpdate>[];
        final subscription = native.service.discoverDevices().listen(
          updates.add,
        );
        await Future<void>.delayed(Duration.zero);
        await native.devices();
        await Future<void>.delayed(Duration.zero);
        expect(updates, hasLength(1));
        await subscription.cancel().timeout(const Duration(seconds: 1));
        await native.service.stopDiscovery();
      }
      expect(native.eventCalls, [
        'listen',
        'cancel',
        'listen',
        'cancel',
        'listen',
        'cancel',
      ]);
    },
  );
}
