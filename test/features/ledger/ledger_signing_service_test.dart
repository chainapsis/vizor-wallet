import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_connection_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_wallet_identity_guard.dart';

void main() {
  test('Linux cancellation reaches both native transports', () async {
    var cancelCalls = 0;
    final ble = _CancelBleService();
    final container = ProviderContainer(
      overrides: [
        ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.linux),
        ledgerRustOperationCancellerProvider.overrideWithValue(() async {
          cancelCalls++;
        }),
        ledgerMobileBleServiceProvider.overrideWithValue(ble),
      ],
    );
    addTearDown(container.dispose);
    await container.read(ledgerOperationCancellerProvider)();
    expect(cancelCalls, 1);
    expect(ble.cancelCalls, 1);
  });

  test('Windows cancellation reaches both native transports', () async {
    var cancelCalls = 0;
    final ble = _CancelBleService();
    final container = ProviderContainer(
      overrides: [
        ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.windows),
        ledgerRustOperationCancellerProvider.overrideWithValue(() async {
          cancelCalls++;
        }),
        ledgerMobileBleServiceProvider.overrideWithValue(ble),
      ],
    );
    addTearDown(container.dispose);
    await container.read(ledgerOperationCancellerProvider)();
    expect(cancelCalls, 1);
    expect(ble.cancelCalls, 1);
  });

  for (final bluetooth in [false, true]) {
    test(
      'signers verify the wallet before requesting ${bluetooth ? 'Bluetooth' : 'USB'} signatures',
      () async {
        final events = <String>[];
        final ble = _CancelBleService();
        final container = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
            ledgerTargetPlatformProvider.overrideWithValue(
              bluetooth ? TargetPlatform.android : TargetPlatform.macOS,
            ),
            ledgerWalletDbPathProvider.overrideWithValue(
              () async => '/tmp/wallet.db',
            ),
            ledgerMobileBleServiceProvider.overrideWithValue(ble),
            ledgerConnectionServiceProvider.overrideWith(
              (ref) => _DirectConnectionService(ref, bluetooth ? ble : null),
            ),
            ledgerWalletIdentityGuardProvider.overrideWithValue((
              accountUuid, {
              mobile,
            }) async {
              events.add('guard:$accountUuid:${identical(mobile, ble)}');
              throw const LedgerWrongWalletException();
            }),
          ],
        );
        addTearDown(container.dispose);

        await expectLater(
          container.read(ledgerPcztTransportSignerProvider)('acct', const [1]),
          throwsA(isA<LedgerWrongWalletException>()),
        );
        await expectLater(
          container.read(ledgerActionPcztSignerProvider)('acct', const [2]),
          throwsA(isA<LedgerWrongWalletException>()),
        );
        expect(events, ['guard:acct:$bluetooth', 'guard:acct:$bluetooth']);
      },
    );
  }

  test('release validation runs before the Ledger transport signer', () async {
    final events = <String>[];
    final container = ProviderContainer(
      overrides: [
        ledgerPcztSupportValidatorProvider.overrideWithValue((pczt) async {
          events.add('validate:$pczt');
        }),
        ledgerPcztTransportSignerProvider.overrideWithValue((
          account,
          pczt,
        ) async {
          events.add('sign:$account:$pczt');
          return const [9];
        }),
      ],
    );
    addTearDown(container.dispose);

    final signed = await container.read(ledgerPcztSignerProvider)(
      'account-1',
      const [1, 2],
    );

    expect(signed, const [9]);
    expect(events, const ['validate:[1, 2]', 'sign:account-1:[1, 2]']);
  });

  test('unsupported legacy Orchard recovery never opens transport', () async {
    var transportCalls = 0;
    final container = ProviderContainer(
      overrides: [
        ledgerPcztSupportValidatorProvider.overrideWithValue(
          (_) async => throw StateError(
            '$kLedgerLegacyOrchardRecoveryErrorCode: test fixture',
          ),
        ),
        ledgerPcztTransportSignerProvider.overrideWithValue((_, _) async {
          transportCalls++;
          return const [9];
        }),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(ledgerPcztSignerProvider)('account-1', const [1]),
      throwsA(predicate<Object>(isLedgerLegacyOrchardRecoveryUnsupported)),
    );
    expect(transportCalls, 0);
  });
}

/// Runs the requested transport callback directly, without device discovery.
class _DirectConnectionService extends LedgerConnectionService {
  _DirectConnectionService(super.ref, this.ble);

  final LedgerMobileBleService? ble;

  @override
  Future<T> run<T>({
    required String accountUuid,
    required Future<T> Function() usb,
    required Future<T> Function(LedgerMobileBleService mobile) bluetooth,
    bool refreshBluetooth = false,
  }) {
    final mobile = ble;
    return mobile == null ? usb() : bluetooth(mobile);
  }
}

class _CancelBleService implements LedgerMobileBleService {
  int cancelCalls = 0;

  @override
  Future<void> cancelSigning() async => cancelCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
