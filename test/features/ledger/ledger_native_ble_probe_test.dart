import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_recovery.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';

// Explicit opt-in: host Flutter test -> adb loopback bridge -> unchanged native
// handler -> official SDK -> emulator Bluetooth -> synthetic Bumble peer.
// No real Flutter engine channel, wallet, signature finalizer, or broadcast.
void main() {
  if (Platform.environment['VIZOR_NATIVE_BLE_PROBE'] != '1') return;
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.zcash.wallet/ledger_mobile');

  Future<dynamic> invoke(String method, [dynamic arguments]) async {
    final socket = await Socket.connect('127.0.0.1', 18765);
    try {
      socket.writeln(jsonEncode({'method': method, 'arguments': arguments}));
      final line = await socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 20));
      final value = (jsonDecode(line) as Map<String, dynamic>)['value'];
      if (value is Map && value.containsKey('error')) {
        throw PlatformException(
          code: value['error'] as String,
          message: value['message'] as String?,
        );
      }
      return value;
    } finally {
      socket.destroy();
    }
  }

  test(
    'real signing gate recovers via rediscovery over native BLE',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) => invoke(call.method, call.arguments),
      );
      final service = MethodChannelLedgerMobileBleService();
      final gate = LedgerMobileSigningStatusGate();
      final recovery = LedgerConnectionRecoveryController();
      Future<void> connect() async {
        final peer = await invoke('probeDiscover') as Map;
        await service.connect(
          LedgerBleDevice(
            id: peer['id'] as String,
            name: peer['name'] as String,
            model: peer['model'] as String,
          ),
        );
      }

      List<LedgerApduCommand> command(int ins) => [
        LedgerApduCommand(
          cla: 0xe0,
          ins: ins,
          p1: 0,
          p2: 0,
          data: Uint8List(0),
        ),
      ];
      try {
        await connect();
        debugPrint('PASS bridge initial discovery/connect');
        expect(await service.exchangeApdus(command(0xf1)), [
          [1, 144, 0],
        ]);
        final pending = gate.run(() => service.exchangeApdus(command(0xf2)));
        final cancelled = expectLater(
          pending,
          throwsA(isA<LedgerMobileException>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        gate.cancelPending();
        await service.cancelSigning();
        await cancelled;
        final clock = Stopwatch()..start();
        await service.disconnect();
        debugPrint('PASS bridge cancellation/disconnect');
        var recoveryCalls = 0;
        Future<void> prepare(String _) async {
          recoveryCalls++;
          await connect();
        }

        final first = recovery.reconnect('probe', prepare);
        final duplicate = recovery.reconnect('probe', prepare);
        expect(identical(first, duplicate), isTrue);
        await first;
        expect(recovery.phase, LedgerConnectionRecoveryPhase.ready);
        expect(recoveryCalls, 1);
        debugPrint(
          'PASS common recovery deduplicated; ready without APDU replay',
        );
        // Simulates the explicit Continue action, not automatic signing.
        final fresh = await gate.run(() async {
          expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(3800));
          debugPrint(
            'PASS actual Dart cooldown elapsed: ${clock.elapsedMilliseconds}ms',
          );
          return service.exchangeApdus(command(0xf3));
        });
        expect(fresh, [
          [3, 144, 0],
        ]);
        debugPrint('PASS bridge fresh response after actual Dart gate');
      } finally {
        recovery.dispose();
        await service.disconnect();
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
