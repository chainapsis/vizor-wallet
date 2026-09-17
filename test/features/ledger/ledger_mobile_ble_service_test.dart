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
    'location-disabled native failure keeps its own classification',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(
              code: 'location_disabled',
              message: 'Location must be enabled',
            );
          });
      await expectLater(
        service.connect(
          const LedgerBleDevice(id: 'device', name: 'Ledger', model: 'Nano X'),
        ),
        throwsA(
          isA<LedgerMobileException>().having(
            (error) => error.failure,
            'failure',
            LedgerMobileFailure.locationDisabled,
          ),
        ),
      );
    },
  );

  for (final method in [
    'currentApp',
    'openZcashApp',
    'exchangeApdus',
    'disconnect',
  ]) {
    test(
      '$method transport failure invalidates identity before retry',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'connect') return null;
              throw PlatformException(
                code: 'disconnected',
                message: 'link failed',
              );
            });
        await service.connect(
          const LedgerBleDevice(id: 'device', name: 'Ledger', model: 'Nano X'),
        );
        expect(service.connectedDeviceId, 'device');
        await expectLater(switch (method) {
          'currentApp' => service.currentApp(),
          'openZcashApp' => service.requestOpenZcashApp(),
          'disconnect' => service.disconnect(),
          _ => service.exchangeApdus([]),
        }, throwsA(isA<LedgerMobileException>()));
        expect(service.connectedDeviceId, isNull);
      },
    );
  }

  test(
    'cancellation invalidates cached connection before native cleanup replies',
    () async {
      final cancelled = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'cancelSigning') await cancelled.future;
            return null;
          });
      await service.connect(
        const LedgerBleDevice(id: 'nano-x', name: 'Ledger', model: 'Nano X'),
      );
      final result = service.cancelSigning();
      expect(service.connectedDeviceId, isNull);
      cancelled.complete();
      await result;
    },
  );

  test(
    'native progress is scoped to the active request and ignored after cancellation',
    () async {
      final reply = Completer<Object?>();
      String? requestId;
      final phases = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'cancelSigning') return null;
            requestId = (call.arguments as Map)['progressId'] as String;
            return reply.future;
          });
      Future<void> emit(String id, String phase) async {
        final done = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'com.zcash.wallet/ledger_mobile/signing_progress',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('progress', {'requestId': id, 'phase': phase}),
              ),
              (_) => done.complete(),
            );
        await done.future;
      }

      final pending = service.exchangeApdusWithProgress([
        LedgerApduCommand(
          cla: 0xe0,
          ins: 0x58,
          p1: 0,
          p2: 1,
          data: Uint8List.fromList([0]),
        ),
      ], phases.add);
      final expectation = expectLater(pending, throwsA(_cancelledFailure));
      await Future<void>.delayed(Duration.zero);
      await emit('unrelated', 'finishing');
      await emit(requestId!, 'sending');
      await emit(requestId!, 'reviewing');
      expect(phases, ['sending', 'reviewing']);
      await service.cancelSigning();
      await emit(requestId!, 'finishing');
      reply.complete([
        [0x90, 0],
      ]);
      await expectation;
      await emit(requestId!, 'finishing');
      expect(phases, ['sending', 'reviewing']);
    },
  );

  for (final method in ['connect', 'currentApp', 'openZcashApp']) {
    for (final cancel in ['cancelSigning', 'disconnect']) {
      test('$cancel ignores a late $method response', () async {
        final pending = Completer<Object?>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == cancel) return null;
              return pending.future;
            });
        final Future<Object?> result = switch (method) {
          'connect' => service.connect(
            const LedgerBleDevice(
              id: 'old-device',
              name: 'Ledger',
              model: 'Flex',
            ),
          ),
          'currentApp' => service.currentApp(),
          _ => service.requestOpenZcashApp(),
        };
        final expectation = expectLater(result, throwsA(_cancelledFailure));
        await Future<void>.delayed(Duration.zero);
        if (cancel == 'disconnect') {
          await service.disconnect();
        } else {
          await service.cancelSigning();
        }
        pending.complete(
          method == 'connect' ? null : {'name': 'Zcash', 'version': '3.9.3'},
        );
        await expectation;
        expect(service.connectedDeviceId, isNull);
      });
    }
  }

  test(
    'invalid pairing retains recovery metadata across the native channel',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(
              code: 'pairing_invalid',
              message: 'Native description',
              details: {'nativeDomain': 'CBErrorDomain', 'nativeCode': 14},
            );
          });
      await expectLater(
        service.connect(
          const LedgerBleDevice(id: 'device', name: 'Ledger', model: 'Flex'),
        ),
        throwsA(
          isA<LedgerMobileException>()
              .having((e) => e.nativeDomain, 'nativeDomain', 'CBErrorDomain')
              .having((e) => e.nativeCode, 'nativeCode', 14)
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
  {
    for (final cancellation in ['cancelSigning', 'disconnect']) {
      test('$cancellation stops pending signing retries', () async {
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

        final pending = service.exchangeApdus([_ufvkPlan().first]);
        final cancelled = expectLater(pending, throwsA(_cancelledFailure));
        await waiting.future;
        if (cancellation == 'disconnect') {
          await service.disconnect();
        } else {
          await service.cancelSigning();
        }
        resume.complete();
        await cancelled;
        expect(calls, ['exchangeApdus', cancellation]);
      });
    }
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
