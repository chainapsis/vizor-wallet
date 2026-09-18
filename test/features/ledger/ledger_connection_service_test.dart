import 'package:zcash_wallet/src/features/ledger/services/ledger_failure_guidance.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_bluetooth_access.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_request.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_app_readiness_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';

import 'package:zcash_wallet/src/features/ledger/services/ledger_device_selection.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_pairing_recovery_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';

const selectedDevice = LedgerBleDevice(
  id: 'selected',
  name: 'My Ledger',
  model: 'Flex',
);
Future<LedgerDeviceSelectionRequest> pending(ProviderContainer c) async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
    final request = c.read(ledgerDeviceSelectionProvider);
    if (request != null) return request;
  }
  throw StateError('No selection request');
}

// Models the explicit second discovery/selection after saving a new device.
Future<void> selectAndReconnect(LedgerDeviceSelectionRequest request) async {
  final outcome = await request.select(selectedDevice, () {}, () {});
  if (outcome == LedgerDeviceSelectionOutcome.saved) {
    expect(request.completed, false);
    await request.prepare();
    expect(
      await request.select(selectedDevice, () {}, () {}),
      LedgerDeviceSelectionOutcome.selected,
    );
  }
}

Future<String> run(
  ProviderContainer c, {
  Future<String> Function()? sign,
  Future<String> Function()? usb,
}) => c
    .read(ledgerConnectionServiceProvider)
    .run(
      accountUuid: 'ledger-1',
      usb: usb ?? () async => 'usb',
      bluetooth: (_) => sign == null ? Future.value('ble') : sign(),
    );
void main() {
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    for (final saved in ['device-1', 'selected', null, '']) {
      test(
        '$platform waits for selection even with saved ID $saved and live connection',
        () async {
          final ble = _FakeBleService().._connectedDeviceId = 'selected';
          final initial = AccountInfo(
            uuid: 'ledger-1',
            name: 'Ledger',
            order: 0,
            isHardware: true,
            hardwareSignerKind: HardwareSignerKind.ledger,
            zip32AccountIndex: 0,
            ledgerDeviceId: saved,
          );
          final accounts = _FakeAccountNotifier(initial);
          final c = _container(
            notifier: accounts,
            ble: ble,
            platform: platform,
          );
          addTearDown(c.dispose);
          var signs = 0;
          final result = run(
            c,
            sign: () async {
              signs++;
              return 'signed';
            },
          );
          final request = await pending(c);
          expect(signs, 0);
          expect(ble.connectCalls, 0);
          await request.prepare();
          expect(ble.connectCalls, 0);
          expect(signs, 0);
          final outcome = await request.select(selectedDevice, () {}, () {});
          if (saved != 'selected') {
            expect(outcome, LedgerDeviceSelectionOutcome.saved);
            expect(request.completed, false);
            expect(signs, 0);
            expect(ble.connectCalls, 1);
            expect(
              c
                  .read(accountProvider)
                  .requireValue
                  .accounts
                  .single
                  .ledgerDeviceId,
              'selected',
            );
            await request.prepare();
            expect(
              await request.select(selectedDevice, () {}, () {}),
              LedgerDeviceSelectionOutcome.selected,
            );
          } else {
            expect(outcome, LedgerDeviceSelectionOutcome.selected);
          }
          expect(await result, 'signed');
          expect(ble.connectedDeviceIds, [
            'selected',
            if (saved != 'selected') 'selected',
          ]);
          expect(signs, 1);
          expect(ble.keyReads, saved == 'selected' ? 0 : 1);
          expect(ble.exports, saved == 'selected' ? 0 : 1);
          expect(accounts.recordedTransports, [
            LedgerConnectionTransport.bluetooth,
          ]);
        },
      );
    }
  }
  test(
    'macOS waits for an explicit choice regardless of last transport',
    () async {
      final ble = _PermissionBle();
      final c = _container(
        notifier: _FakeAccountNotifier(
          _ledgerAccount(
            deviceModel: 'Flex',
          ).copyWith(ledgerLastTransport: LedgerConnectionTransport.bluetooth),
        ),
        ble: ble,
      );
      addTearDown(c.dispose);
      final operation = run(c);
      final request = await pending(c);
      expect(request.canChooseTransport, isTrue);
      expect(request.initialTransport, isNull);
      expect(ble.reads, 0);
      await request.selectUsb();
      expect(await operation, 'usb');
      expect(c.read(ledgerDeviceSelectionProvider), isNull);
      expect(ble.reads, 0);
    },
  );
  test(
    'failed USB preparation keeps the request pending until an explicit Bluetooth choice',
    () async {
      final c = _container(
        notifier: _FakeAccountNotifier(_ledgerAccount(deviceModel: 'Flex')),
        ble: _FakeBleService(),
        usbReady: false,
      );
      addTearDown(c.dispose);
      final result = run(c);
      final request = await pending(c);
      await expectLater(
        request.selectUsb(),
        throwsA(isA<LedgerAppReadinessException>()),
      );
      expect(request.completed, false);
      request.chooseTransport(LedgerConnectionTransport.bluetooth);
      await selectAndReconnect(request);
      expect(await result, 'ble');
    },
  );
  test(
    'USB choice from Bluetooth picker preserves USB operation errors without fallback',
    () async {
      final accounts = _FakeAccountNotifier(
        _ledgerAccount(deviceModel: 'Flex'),
      );
      final c = _container(notifier: accounts, ble: _FakeBleService());
      addTearDown(c.dispose);
      final result = run(
        c,
        usb: () async => throw StateError('HID operation failed'),
      );
      final expectation = expectLater(result, throwsStateError);
      (await pending(c)).selectUsb();
      await expectation;
      expect(accounts.recordedTransports, isEmpty);
    },
  );
  test('explicit USB choice records USB rather than Bluetooth', () async {
    final accounts = _FakeAccountNotifier(_ledgerAccount(deviceModel: 'Flex'));
    final c = _container(notifier: accounts, ble: _FakeBleService());
    addTearDown(c.dispose);
    final result = run(c);
    (await pending(c)).selectUsb();
    expect(await result, 'usb');
    expect(accounts.recordedTransports, [LedgerConnectionTransport.usb]);
  });
  test('USB rounds and retries keep only this operation choice', () async {
    final device = _CountingUsbDevice();
    final c = _container(
      notifier: _FakeAccountNotifier(_ledgerAccount(deviceModel: 'Flex')),
      ble: _FakeBleService(),
      usbDevice: device,
    );
    addTearDown(c.dispose);
    final scope = LedgerConnectionScope();
    final first = scope.run(() => run(c));
    final request = await pending(c);
    expect(device.queries, 0);
    await request.selectUsb();
    expect(await first, 'usb');
    expect(device.queries, 1);
    expect(await scope.run(() => run(c)), 'usb');
    expect(c.read(ledgerDeviceSelectionProvider), isNull);
    await expectLater(
      scope.run(
        () => run(c, usb: () async => throw StateError('Signing failed')),
      ),
      throwsStateError,
    );
    final retry = scope.run(() => run(c));
    final retryRequest = await pending(c);
    expect(retryRequest.initialTransport, LedgerConnectionTransport.usb);
    await retryRequest.selectUsb();
    expect(await retry, 'usb');
    final next = LedgerConnectionScope().run(() => run(c));
    final nextRequest = await pending(c);
    expect(nextRequest.initialTransport, isNull);
    final cancelled = expectLater(next, throwsA(isA<LedgerMobileException>()));
    nextRequest.cancel();
    await cancelled;
  });
  test('rounds share a selection; a new user operation asks again', () async {
    final ble = _FakeBleService();
    final c = _container(
      notifier: _FakeAccountNotifier(_ledgerAccount(deviceModel: 'Flex')),
      ble: ble,
    );
    addTearDown(c.dispose);
    final scope = LedgerConnectionScope();
    final first = scope.run(() => run(c));
    await selectAndReconnect(await pending(c));
    expect(await first, 'ble');
    expect(await scope.run(() => run(c)), 'ble');
    expect(ble.connectCalls, 2);
    final next = LedgerConnectionScope().run(() => run(c));
    final request = await pending(c);
    expect(ble.connectCalls, 2);
    await selectAndReconnect(request);
    expect(await next, 'ble');
    expect(ble.connectCalls, 3);
  });
  test('sign failure is not replayed and invalidates selection', () async {
    final ble = _FakeBleService();
    final c = _container(
      notifier: _FakeAccountNotifier(_ledgerAccount(deviceModel: 'Flex')),
      ble: ble,
    );
    addTearDown(c.dispose);
    final scope = LedgerConnectionScope();
    var signs = 0;
    final first = scope.run(
      () => run(
        c,
        sign: () async {
          signs++;
          throw const LedgerMobileException(
            LedgerMobileFailure.disconnected,
            'lost',
          );
        },
      ),
    );
    final expectation = expectLater(
      first,
      throwsA(isA<LedgerMobileException>()),
    );
    await selectAndReconnect(await pending(c));
    await expectation;
    expect(signs, 1);
    expect(scope.selected, isNull);
    final next = scope.run(() => run(c));
    (await pending(c)).cancel();
    await expectLater(next, throwsA(isA<LedgerMobileException>()));
  });
  for (final failure in [
    'mismatch',
    'save',
    'permission',
    'connect',
    'cleanup',
  ]) {
    test(
      '$failure cannot sign or overwrite metadata before a verified selection',
      () async {
        final ble = _FakeBleService();
        final accounts = _FakeAccountNotifier(
          _ledgerAccount(deviceModel: 'Flex'),
        )..failRecording = failure == 'save';
        if (failure == 'mismatch') ble.exportKey = 'wrong';
        if (failure == 'connect') {
          ble.connectError = const LedgerMobileException(
            LedgerMobileFailure.pairingInvalid,
            'pairing',
          );
        }
        if (failure == 'cleanup') {
          ble.disconnectError = const LedgerMobileException(
            LedgerMobileFailure.disconnected,
            'cleanup',
          );
        }
        final transport = failure == 'permission' ? _PermissionBle() : ble;
        final c = _container(notifier: accounts, ble: transport);
        addTearDown(c.dispose);
        var signs = 0;
        final result = run(
          c,
          sign: () async {
            signs++;
            return 'signed';
          },
        );
        final request = await pending(c);
        await expectLater(
          request.select(selectedDevice, () {}, () {}),
          throwsA(isA<Object>()),
        );
        expect(signs, 0);
        expect(accounts.recordedTransports, isEmpty);
        expect(request.completed, false);
        request.cancel();
        await expectLater(result, throwsA(isA<LedgerMobileException>()));
      },
    );
  }
  for (final stage in [
    'waiting',
    'disconnect',
    'connect',
    'currentApp',
    'save',
  ]) {
    test(
      'cancel during $stage drains accepted work and prevents signing',
      () async {
        final gate = Completer<void>();
        final ble = _FakeBleService()
          ..pauseStage = stage
          ..pause = gate.future;
        final accounts = _FakeAccountNotifier(
          _ledgerAccount(deviceModel: 'Flex'),
        );
        if (stage == 'save') accounts.recordGate = gate.future;
        final c = _container(notifier: accounts, ble: ble);
        addTearDown(c.dispose);
        var signs = 0;
        final result = run(
          c,
          sign: () async {
            signs++;
            return 'signed';
          },
        );
        final expectation = expectLater(
          result,
          throwsA(isA<LedgerMobileException>()),
        );
        final request = await pending(c);
        Future<void>? checking;
        if (stage != 'waiting') {
          checking = expectLater(
            request.select(selectedDevice, () {}, () {}),
            throwsA(isA<LedgerMobileException>()),
          );
          await Future<void>.delayed(Duration.zero);
        }
        c.read(ledgerDeviceRequestsProvider).cancel();
        if (stage != 'waiting') {
          await expectLater(
            run(c),
            throwsA(
              isA<LedgerMobileException>().having(
                (e) => e.failure,
                'busy',
                LedgerMobileFailure.busy,
              ),
            ),
          );
        }
        gate.complete();
        await checking;
        await expectation;
        expect(signs, 0);
      },
    );
  }

  test(
    'another selection of the same ID invalidates earlier operation ownership',
    () async {
      final ble = _FakeBleService();
      final c = _container(
        notifier: _FakeAccountNotifier(_ledgerAccount(deviceModel: 'Flex')),
        ble: ble,
      );
      addTearDown(c.dispose);
      final firstScope = LedgerConnectionScope();
      final first = firstScope.run(() => run(c));
      await selectAndReconnect(await pending(c));
      await first;
      final second = LedgerConnectionScope().run(() => run(c));
      await selectAndReconnect(await pending(c));
      await second;
      var signs = 0;
      await expectLater(
        firstScope.run(
          () => run(
            c,
            sign: () async {
              signs++;
              return 'bad';
            },
          ),
        ),
        throwsA(isA<LedgerMobileException>()),
      );
      expect(signs, 0);
      expect(firstScope.selected, isNull);
    },
  );
  test(
    'cached USB choice suppresses a result cancelled during device work',
    () async {
      final c = _container(
        notifier: _FakeAccountNotifier(_ledgerAccount(deviceModel: 'Flex')),
        ble: _FakeBleService(),
      );
      addTearDown(c.dispose);
      final scope = LedgerConnectionScope();
      final first = scope.run(() => run(c));
      (await pending(c)).selectUsb();
      await first;
      await expectLater(
        scope.run(
          () => run(
            c,
            usb: () async {
              c.read(ledgerDeviceRequestsProvider).cancel();
              return 'late';
            },
          ),
        ),
        throwsA(isA<LedgerMobileException>()),
      );
    },
  );
  test(
    'account switch cancels native approval and drains it before releasing exclusion',
    () async {
      final gate = Completer<void>();
      final ble = _FakeBleService()
        ..pauseStage = 'currentApp'
        ..pause = gate.future
        ..onCancel = (() {
          if (!gate.isCompleted) gate.complete();
        });
      final accounts = _FakeAccountNotifier(
        _ledgerAccount(deviceModel: 'Flex'),
      );
      final c = _container(notifier: accounts, ble: ble);
      addTearDown(c.dispose);
      var signs = 0;
      final operation = run(
        c,
        sign: () async {
          signs++;
          return 'late';
        },
      );
      final expectation = expectLater(
        operation,
        throwsA(isA<LedgerMobileException>()),
      );
      final request = await pending(c);
      final selected = expectLater(
        request.select(selectedDevice, () {}, () {}),
        throwsA(isA<LedgerMobileException>()),
      );
      await Future<void>.delayed(Duration.zero);
      accounts.switchAway();
      await expectation;
      await selected;
      expect(ble.cancelCalls, 1);
      expect(signs, 0);
      expect(accounts.recordedTransports, isEmpty);
    },
  );

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    for (final stage in ['connect', 'readiness', 'sign']) {
      for (final failure in [
        LedgerMobileFailure.permissionDenied,
        LedgerMobileFailure.pairingInvalid,
        LedgerMobileFailure.pairingRejected,
        LedgerMobileFailure.bluetoothOff,
        LedgerMobileFailure.locationDisabled,
      ]) {
        test(
          '$platform preserves $failure guidance after selection at $stage',
          () async {
            final original = LedgerMobileException(
              failure,
              'native diagnostic',
            );
            final ble = _FakeBleService();
            if (stage == 'connect') ble.connectError = original;
            if (stage == 'readiness') ble.appError = original;
            final c = _container(
              notifier: _FakeAccountNotifier(
                _ledgerAccount(deviceModel: 'Flex'),
              ),
              ble: ble,
              platform: platform,
            );
            addTearDown(c.dispose);
            var signs = 0;
            final result = run(
              c,
              sign: () async {
                signs++;
                throw original;
              },
            );
            final request = await pending(c);
            final matcher = throwsA(
              predicate<Object>(
                (e) =>
                    ledgerFailureGuidance(e)?.message ==
                    ledgerFailureGuidance(original)!.message,
              ),
            );
            if (stage == 'sign') {
              final expectation = expectLater(result, matcher);
              await selectAndReconnect(request);
              await expectation;
            } else {
              await expectLater(
                request.select(selectedDevice, () {}, () {}),
                matcher,
              );
              request.cancel();
              await expectLater(result, throwsA(isA<LedgerMobileException>()));
            }
            expect(signs, stage == 'sign' ? 1 : 0);
            expect(ble.connectCalls, stage == 'sign' ? 2 : 1);
          },
        );
      }
    }
  }

  test(
    'reset saved device propagates signing failure without requesting a viewing key',
    () async {
      final ble = _FakeBleService()..exportKey = 'different-seed';
      final accounts = _FakeAccountNotifier(
        _ledgerAccount(deviceModel: 'Flex').copyWith(
          ledgerDeviceId: 'selected',
          ledgerLastTransport: LedgerConnectionTransport.bluetooth,
        ),
      );
      final c = _container(notifier: accounts, ble: ble);
      addTearDown(c.dispose);
      for (var attempt = 0; attempt < 2; attempt++) {
        final result = run(
          c,
          sign: () async =>
              throw StateError('Invalid spend authorization signature'),
        );
        final expected = expectLater(result, throwsStateError);
        await selectAndReconnect(await pending(c));
        await expected;
      }
      expect(ble.exports, 0);
      expect(ble.keyReads, 0);
      expect(accounts.recordedTransports, isEmpty);
    },
  );
  for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
    for (final usbReady in [true, false]) {
      test('$platform uses USB directly (ready: $usbReady)', () async {
        final notifier = _FakeAccountNotifier(
          _ledgerAccount(
            deviceModel: 'Nano X',
          ).copyWith(ledgerLastTransport: LedgerConnectionTransport.bluetooth),
        );
        final ble = _FakeBleService();
        final container = _container(
          notifier: notifier,
          ble: ble,
          platform: platform,
          usbReady: usbReady,
        );
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        final operation = container
            .read(ledgerConnectionServiceProvider)
            .run(
              accountUuid: 'ledger-1',
              usb: () async => 'usb',
              bluetooth: (_) async =>
                  fail('unsupported native BLE must never be called'),
            );
        if (usbReady) {
          expect(await operation, 'usb');
        } else {
          await expectLater(
            operation,
            throwsA(
              isA<LedgerConnectionRequiredException>()
                  .having(
                    (e) => e.message,
                    'USB instructions',
                    contains('with USB'),
                  )
                  .having(
                    (e) => e.message,
                    'no BLE instructions',
                    isNot(contains('Bluetooth')),
                  ),
            ),
          );
        }
        expect(ble.connectCalls, 0);
      });
    }
  }

  // Only a lost or unusable USB connection asks the user to reconnect;
  // refusals of the request, a busy or stuck app, and other keys keep their
  // own error so the caller can classify it.
  for (final (usbError, needsConnection) in const [
    ('ledger_transport: No Ledger device found. Connect and unlock.', true),
    (
      'ledger_linux_usb_access: Open Ledger HID device: Permission denied',
      true,
    ),
    ('ledger_status_6985: Ledger request was rejected', false),
    ('ledger_status_5515: Ledger device is locked', false),
    ('ledger_status_6a80: Ledger rejected the PCZT data or key path', false),
    ('ledger_status_6986: Ledger Zcash app returned status 0x6986', false),
    ('ledger_status_6601: Ledger device is busy switching apps', false),
    ('ledger_status_b007: Ledger Zcash app is in the wrong state', false),
    (
      'ledger_signature_mismatch: Validate Ledger transparent signature 0',
      false,
    ),
  ]) {
    test(
      'USB readiness failure ${usbError.split(':').first} '
      '${needsConnection ? 'asks to reconnect' : 'keeps its error'}',
      () async {
        final notifier = _FakeAccountNotifier(
          _ledgerAccount(deviceModel: 'Nano X'),
        );
        final ble = _FakeBleService();
        final container = _container(
          notifier: notifier,
          ble: ble,
          platform: TargetPlatform.windows,
          usbDevice: _ReadyDevice(error: StateError(usbError)),
        );
        addTearDown(container.dispose);
        await container.read(accountProvider.future);

        final operation = container
            .read(ledgerConnectionServiceProvider)
            .run(
              accountUuid: 'ledger-1',
              usb: () => throw StateError('operation must not start'),
              bluetooth: (_) async => fail('must not use Bluetooth'),
            );

        await expectLater(
          operation,
          throwsA(
            needsConnection
                ? isA<LedgerConnectionRequiredException>().having(
                    (e) => (e.cause! as LedgerAppReadinessException).cause
                        .toString(),
                    'cause',
                    contains(usbError),
                  )
                : isA<LedgerAppReadinessException>(),
          ),
        );
        expect(ble.connectCalls, 0);
      },
    );
  }

  for (final metadataFailure in [false, true]) {
    test(
      'does not replay an operation (metadata failure: $metadataFailure)',
      () async {
        final notifier = _FakeAccountNotifier(
          _ledgerAccount(deviceModel: 'Nano X'),
        )..failRecording = metadataFailure;
        final ble = _FakeBleService();
        final container = _container(
          notifier: notifier,
          ble: ble,
          platform: TargetPlatform.windows,
        );
        addTearDown(container.dispose);
        await container.read(accountProvider.future);
        final operation = container
            .read(ledgerConnectionServiceProvider)
            .run(
              accountUuid: 'ledger-1',
              usb: () async {
                if (!metadataFailure) {
                  throw StateError(
                    'Ledger HID disconnected after signing started',
                  );
                }
                return 'signed';
              },
              bluetooth: (_) async => fail('must not replay'),
            );
        if (metadataFailure) {
          expect(await operation, 'signed');
        } else {
          await expectLater(operation, throwsStateError);
        }
        expect(ble.connectCalls, 0);
      },
    );
  }

  test('explicit USB never probes Bluetooth', () async {
    final notifier = _FakeAccountNotifier(
      _ledgerAccount(deviceModel: 'Nano X'),
    );
    final ble = _FakeBleService();
    final container = _container(notifier: notifier, ble: ble);
    addTearDown(container.dispose);
    await container.read(accountProvider.future);

    final result = container
        .read(ledgerConnectionServiceProvider)
        .run(
          accountUuid: 'ledger-1',
          usb: () async => 'signed-over-usb',
          bluetooth: (_) async => 'unexpected',
        );

    await (await pending(container)).selectUsb();
    expect(await result, 'signed-over-usb');
    expect(ble.connectCalls, 0);
    expect(notifier.recordedTransports, [LedgerConnectionTransport.usb]);
  });
}

ProviderContainer _container({
  required _FakeAccountNotifier notifier,
  required _FakeBleService ble,
  TargetPlatform platform = TargetPlatform.macOS,
  bool usbReady = true,
  LedgerAppReadinessDevice? usbDevice,
}) {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap(notifier.initial)),
      accountProvider.overrideWith(() => notifier),
      ledgerTargetPlatformProvider.overrideWithValue(platform),
      ledgerMobileBleServiceProvider.overrideWithValue(ble),
      ledgerRecoveryAccountKeyLoaderProvider.overrideWithValue((_) async {
        ble.keyReads++;
        return 'expected';
      }),
      ledgerBluetoothAccountConnectorProvider.overrideWithValue((
        index,
        device,
      ) async {
        ble.exports++;
        await ble.currentApp();
        return LedgerDeviceAccount(
          ufvk: ble.exportKey,
          seedFingerprint: [],
          accountIndex: index,
          appVersion: '3.9.3',
        );
      }),
      ledgerAppReadinessDeviceForTransportProvider(
        LedgerConnectionTransport.usb,
      ).overrideWithValue(usbDevice ?? _ReadyDevice(available: usbReady)),
      ledgerAppReadinessDeviceForTransportProvider(
        LedgerConnectionTransport.bluetooth,
      ).overrideWithValue(_ReadyDevice(ble: ble)),
    ],
  );
}

AccountInfo _ledgerAccount({required String deviceModel}) {
  return AccountInfo(
    uuid: 'ledger-1',
    name: 'Ledger',
    order: 0,
    isHardware: true,
    hardwareSignerKind: HardwareSignerKind.ledger,
    zip32AccountIndex: 0,
    ledgerDeviceId: 'device-1',
    ledgerDeviceName: 'Rowan Ledger',
    ledgerDeviceModel: deviceModel,
  );
}

AppBootstrapState _bootstrap(AccountInfo account) => AppBootstrapState(
  initialLocation: '/home',
  initialAccountState: AccountState(
    accounts: [account],
    activeAccountUuid: account.uuid,
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _ReadyDevice implements LedgerAppReadinessDevice {
  const _ReadyDevice({this.available = true, this.ble, this.error});
  final bool available;
  final LedgerMobileBleService? ble;
  final Object? error;

  @override
  Future<LedgerDeviceAppSnapshot> queryZcashApp() async {
    if (error case final error?) throw error;
    if (ble != null) await ble!.currentApp();
    return LedgerDeviceAppSnapshot(
      status: available
          ? LedgerDeviceAppStatus.open
          : LedgerDeviceAppStatus.disconnected,
      version: '3.9.3',
    );
  }

  @override
  Future<LedgerDeviceAppSnapshot> requestOpenZcashApp() => queryZcashApp();
}

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier(this.initial);

  final AccountInfo initial;
  void switchAway() => state = AsyncData(
    state.requireValue.copyWith(activeAccountUuid: 'other'),
  );
  bool failRecording = false;
  Future<void>? recordGate;
  Completer<void>? recordStarted;
  final recordedTransports = <LedgerConnectionTransport>[];

  @override
  FutureOr<AccountState> build() =>
      AccountState(accounts: [initial], activeAccountUuid: initial.uuid);

  @override
  Future<void> recordLedgerConnection({
    required String uuid,
    required LedgerConnectionTransport transport,
    String? deviceId,
    String? deviceName,
    String? deviceModel,
  }) async {
    recordStarted?.complete();
    if (recordGate != null) await recordGate;
    if (failRecording) throw StateError('metadata write failed');
    recordedTransports.add(transport);
    final current = state.requireValue;
    state = AsyncData(
      current.copyWith(
        accounts: [
          initial.copyWith(
            ledgerLastTransport: transport,
            ledgerDeviceId: deviceId,
            ledgerDeviceName: deviceName,
            ledgerDeviceModel: deviceModel,
          ),
        ],
      ),
    );
  }
}

class _FakeBleService implements LedgerMobileBleService {
  int keyReads = 0;
  int exports = 0;
  int cancelCalls = 0;
  void Function()? onCancel;
  String exportKey = 'expected';
  Object? appError;
  bool clearAppErrorOnConnect = false;
  Object? disconnectError;
  Object? connectError;
  String? pauseStage;
  Future<void>? pause;
  var connectCalls = 0;
  var disconnectCalls = 0;
  final connectedDeviceIds = <String>[];
  String? _connectedDeviceId;

  @override
  String? get connectedDeviceId => _connectedDeviceId;

  @override
  Future<void> connect(LedgerBleDevice device) async {
    connectCalls++;
    if (connectError != null) throw connectError!;
    if (pauseStage == 'connect') await pause;
    if (clearAppErrorOnConnect) appError = null;
    connectedDeviceIds.add(device.id);
    _connectedDeviceId = device.id;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    if (disconnectError != null) throw disconnectError!;
    if (pauseStage == 'disconnect') await pause;
    _connectedDeviceId = null;
  }

  @override
  Future<LedgerMobileAppInfo> currentApp() async {
    if (pauseStage == 'currentApp') await pause;
    if (appError != null) throw appError!;
    return const LedgerMobileAppInfo(name: 'Zcash', version: '3.9.3');
  }

  @override
  Future<LedgerMobileAppInfo> requestOpenZcashApp() => currentApp();

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() => const Stream.empty();

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<List<Uint8List>> exchangeUfvk(LedgerUfvkApduPlan plan) async =>
      const [];

  @override
  Future<List<Uint8List>> exchangeApdus(
    List<LedgerApduCommand> commands,
  ) async => const [];

  @override
  Future<void> cancelSigning() async {
    cancelCalls++;
    onCancel?.call();
  }
}

class _PermissionBle extends _FakeBleService implements LedgerBluetoothAccess {
  int reads = 0;
  @override
  Future<LedgerBluetoothAccessStatus> bluetoothAccessStatus() async {
    reads++;
    return const LedgerBluetoothAccessStatus(
      LedgerBluetoothPermission.settings,
    );
  }

  @override
  Future<bool> openBluetoothSettings() async => true;
}

class _CountingUsbDevice extends _ReadyDevice {
  int queries = 0;
  @override
  Future<LedgerDeviceAppSnapshot> queryZcashApp() {
    queries++;
    return super.queryZcashApp();
  }
}
