import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.zcash.wallet/ledger_mobile');
  const service = MethodChannelLedgerMobileBleService();

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
