import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.zcash.wallet/ledger_mobile');
  late MethodChannelLedgerMobileBleService service;

  setUp(() {
    service = MethodChannelLedgerMobileBleService(
      reviewBusyDelay: (_) async {},
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'invalid pairing retains recovery metadata across the native channel',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(
              code: 'pairing_invalid',
              message: 'Native description',
            );
          });
      await expectLater(
        service.connect(
          const LedgerBleDevice(id: 'device', name: 'Ledger', model: 'Flex'),
        ),
        throwsA(
          isA<LedgerMobileException>()
              .having(
                (e) => e.failure,
                'failure',
                LedgerMobileFailure.pairingInvalid,
              )
              .having(
                (e) => e.message,
                'message',
                kLedgerPairingInvalidMessage,
              ),
        ),
      );
      expect(
        ledgerPairingNeedsReset(
          const LedgerMobileException(
            LedgerMobileFailure.pairingRejected,
            'Rejected',
          ),
        ),
        isFalse,
      );
    },
  );

  test('maps native permission failure to a typed error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(
            code: 'permission_denied',
            message: 'Bluetooth permission is required.',
          );
        });

    await expectLater(
      service.connect(
        const LedgerBleDevice(
          id: 'nano-x',
          name: 'Rowan Ledger',
          model: 'Nano X',
        ),
      ),
      throwsA(
        isA<LedgerMobileException>().having(
          (error) => error.failure,
          'failure',
          LedgerMobileFailure.permissionDenied,
        ),
      ),
    );
  });

  test('requests Bluetooth permission through the native contract', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'requestPermissions');
          return true;
        });

    expect(await service.requestPermissions(), isTrue);
  });

  test('queries the current app and requests opening Zcash', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return switch (call.method) {
            'currentApp' => {'name': 'BOLOS', 'version': '2.2.4'},
            'openZcashApp' => {'name': 'Zcash', 'version': '3.9.3'},
            _ => throw StateError('Unexpected method ${call.method}'),
          };
        });

    final current = await service.currentApp();
    final opened = await service.requestOpenZcashApp();

    expect((current.name, current.version), ('BOLOS', '2.2.4'));
    expect((opened.name, opened.version), ('Zcash', '3.9.3'));
    expect(calls, ['currentApp', 'openZcashApp']);
  });

  test(
    'passes the selected device identity to the native connection',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return null;
          });

      await service.connect(
        const LedgerBleDevice(
          id: 'nano-x',
          name: 'Rowan Ledger',
          model: 'Nano X',
        ),
      );

      expect(received?.method, 'connect');
      expect(received?.arguments, {
        'deviceId': 'nano-x',
        'deviceName': 'Rowan Ledger',
        'deviceModel': 'Nano X',
      });
      expect(service.connectedDeviceId, 'nano-x');

      await service.disconnect();
      expect(service.connectedDeviceId, isNull);
    },
  );

  test(
    'transports Rust APDU plans and preserves status-bearing responses',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return <List<int>>[
              <int>[0, 3, 117, 0x90, 0],
              <int>[102, 118, 0x90, 0],
            ];
          });
      final plan = LedgerUfvkApduPlan(
        first: LedgerApduCommand(
          cla: 0xe0,
          ins: 0x50,
          p1: 0,
          p2: 0,
          data: Uint8List.fromList(<int>[1, 2, 3]),
        ),
        continuation: LedgerApduCommand(
          cla: 0xe0,
          ins: 0x50,
          p1: 0x80,
          p2: 0,
          data: Uint8List(0),
        ),
      );

      final responses = await service.exchangeUfvk(plan);

      expect(received?.method, 'exchangeUfvk');
      final arguments = received?.arguments as Map<Object?, Object?>;
      expect((arguments['first'] as Map<Object?, Object?>)['ins'], 0x50);
      expect((arguments['continuation'] as Map<Object?, Object?>)['p1'], 0x80);
      expect(responses, hasLength(2));
      expect(responses.first, Uint8List.fromList(<int>[0, 3, 117, 0x90, 0]));
    },
  );

  test('persistent 0x6901 fault stops after three attempts', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          return <List<int>>[
            <int>[0x69, 0x01],
          ];
        });

    final responses = await service.exchangeUfvk(_ufvkPlan());

    expect(calls, 3);
    expect(responses, [
      Uint8List.fromList(<int>[0x69, 0x01]),
    ]);
  });

  test('non-busy rejection is preserved and never retried', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          return <List<int>>[
            <int>[0x69, 0x85],
          ];
        });
    final responses = await service.exchangeUfvk(_ufvkPlan());

    expect(calls, 1);
    expect(responses, [
      Uint8List.fromList(<int>[0x69, 0x85]),
    ]);
  });

  test('fault injection retries the UFVK review start after 0x6901', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          if (calls == 1) {
            return <List<int>>[
              <int>[0x69, 0x01],
            ];
          }
          return <List<int>>[
            <int>[0, 1, 117, 0x90, 0],
          ];
        });
    final plan = LedgerUfvkApduPlan(
      first: LedgerApduCommand(
        cla: 0xe0,
        ins: 0x50,
        p1: 0,
        p2: 0,
        data: Uint8List.fromList(<int>[1, 2, 3]),
      ),
      continuation: LedgerApduCommand(
        cla: 0xe0,
        ins: 0x50,
        p1: 0x80,
        p2: 0,
        data: Uint8List(0),
      ),
    );

    final responses = await service.exchangeUfvk(plan);

    expect(calls, 2);
    expect(responses, [
      Uint8List.fromList(<int>[0, 1, 117, 0x90, 0]),
    ]);
  });

  test('maps native UFVK cancellation to a stable typed error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'cancelled', message: 'Cancelled.');
        });

    await expectLater(
      service.exchangeUfvk(_ufvkPlan()),
      throwsA(
        isA<LedgerMobileException>().having(
          (error) => error.failure,
          'failure',
          LedgerMobileFailure.cancelled,
        ),
      ),
    );
  });

  {
    for (final cancellation in ['cancelSigning', 'disconnect']) {
      test('$cancellation stops pending UFVK retries', () async {
        final waiting = Completer<void>();
        final resume = Completer<void>();
        final calls = <String>[];
        service = MethodChannelLedgerMobileBleService(
          reviewBusyDelay: (_) {
            waiting.complete();
            return resume.future;
          },
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call.method);
              if (call.method == cancellation) return null;
              return <List<int>>[
                <int>[0x69, 0x01],
              ];
            });

        final pending = service.exchangeUfvk(_ufvkPlan());
        final cancelled = expectLater(pending, throwsA(_cancelledFailure));
        await waiting.future;
        if (cancellation == 'disconnect') {
          await service.disconnect();
        } else {
          await service.cancelSigning();
        }
        resume.complete();
        await cancelled;
        expect(calls, ['exchangeUfvk', cancellation]);
      });
    }

    test(
      'ignores late UFVK results without cancelling a new request',
      () async {
        final started = Completer<void>();
        final lateResponse = Completer<List<List<int>>>();
        var requests = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'cancelSigning') return null;
              if (++requests == 1) {
                started.complete();
                return lateResponse.future;
              }
              return <List<int>>[
                <int>[0x90, 0],
              ];
            });
        final pending = service.exchangeUfvk(_ufvkPlan());
        final cancelled = expectLater(pending, throwsA(_cancelledFailure));
        await started.future;
        await service.cancelSigning();
        final fresh = await service.exchangeUfvk(_ufvkPlan());
        expect(fresh.single, [0x90, 0]);
        lateResponse.complete([
          [0x90, 0],
        ]);
        await cancelled;
        expect(requests, 2);
      },
    );
  }
}

final _cancelledFailure = isA<LedgerMobileException>().having(
  (error) => error.failure,
  'failure',
  LedgerMobileFailure.cancelled,
);

LedgerUfvkApduPlan _ufvkPlan() => LedgerUfvkApduPlan(
  first: LedgerApduCommand(
    cla: 0xe0,
    ins: 0x50,
    p1: 0,
    p2: 0,
    data: Uint8List(4),
  ),
  continuation: LedgerApduCommand(
    cla: 0xe0,
    ins: 0x50,
    p1: 0x80,
    p2: 0,
    data: Uint8List(0),
  ),
);
