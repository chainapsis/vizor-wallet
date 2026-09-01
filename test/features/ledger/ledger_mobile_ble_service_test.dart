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

  test(
    'transports an ordered signing plan without interpreting responses',
    () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return <List<int>>[
              <int>[0x90, 0],
              <int>[1, 2, 0x69, 0x85],
            ];
          });
      final commands = <LedgerApduCommand>[
        LedgerApduCommand(
          cla: 0xe0,
          ins: 0x52,
          p1: 0,
          p2: 0,
          data: Uint8List.fromList(<int>[1]),
        ),
        LedgerApduCommand(
          cla: 0xe0,
          ins: 0x59,
          p1: 0,
          p2: 3,
          data: Uint8List(0),
        ),
      ];

      final responses = await service.exchangeApdus(commands);

      expect(received?.method, 'exchangeApdus');
      final arguments = received?.arguments as Map<Object?, Object?>;
      final encoded = arguments['commands'] as List<Object?>;
      expect((encoded.last as Map<Object?, Object?>)['ins'], 0x59);
      expect((encoded.last as Map<Object?, Object?>)['p2'], 3);
      expect(responses.last, Uint8List.fromList(<int>[1, 2, 0x69, 0x85]));
    },
  );

  test(
    'fault injection retries only the signing APDU rejected with 0x6901',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (calls.length == 1) {
              return <List<int>>[
                <int>[0x90, 0],
                <int>[0x69, 0x01],
              ];
            }
            return <List<int>>[
              <int>[1, 2, 0x90, 0],
            ];
          });
      final commands = <LedgerApduCommand>[
        LedgerApduCommand(
          cla: 0xe0,
          ins: 0x52,
          p1: 0,
          p2: 0,
          data: Uint8List.fromList(<int>[1]),
        ),
        LedgerApduCommand(
          cla: 0xe0,
          ins: 0x59,
          p1: 0,
          p2: 3,
          data: Uint8List(0),
        ),
      ];

      final responses = await service.exchangeApdus(commands);

      expect(calls, hasLength(2));
      final firstCommands =
          (calls.first.arguments as Map<Object?, Object?>)['commands']!
              as List<Object?>;
      final retryCommands =
          (calls.last.arguments as Map<Object?, Object?>)['commands']!
              as List<Object?>;
      expect(firstCommands, hasLength(2));
      expect(retryCommands, hasLength(1));
      expect((retryCommands.single as Map<Object?, Object?>)['ins'], 0x59);
      expect(responses, [
        Uint8List.fromList(<int>[0x90, 0]),
        Uint8List.fromList(<int>[1, 2, 0x90, 0]),
      ]);
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
    final command = LedgerApduCommand(
      cla: 0xe0,
      ins: 0x52,
      p1: 0,
      p2: 0,
      data: Uint8List.fromList(<int>[1]),
    );

    final responses = await service.exchangeApdus([command]);

    expect(calls, 3);
    expect(responses, [
      Uint8List.fromList(<int>[0x69, 0x01]),
    ]);
  });

  test('non-0x6901 status fault is never retried', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls++;
          return <List<int>>[
            <int>[0x69, 0x85],
          ];
        });
    final command = LedgerApduCommand(
      cla: 0xe0,
      ins: 0x52,
      p1: 0,
      p2: 0,
      data: Uint8List.fromList(<int>[1]),
    );

    final responses = await service.exchangeApdus([command]);

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

  test('maps native signing cancellation to a stable typed error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'cancelled', message: 'Cancelled.');
        });

    await expectLater(
      service.exchangeApdus(const []),
      throwsA(
        isA<LedgerMobileException>().having(
          (error) => error.failure,
          'failure',
          LedgerMobileFailure.cancelled,
        ),
      ),
    );
  });
}
