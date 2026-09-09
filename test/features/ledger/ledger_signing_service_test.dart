import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';

void main() {
  test(
    'Windows cancellation uses Rust without initializing native BLE',
    () async {
      var cancelCalls = 0;
      final container = ProviderContainer(
        overrides: [
          ledgerTargetPlatformProvider.overrideWithValue(
            TargetPlatform.windows,
          ),
          ledgerRustOperationCancellerProvider.overrideWithValue(() async {
            cancelCalls++;
          }),
          ledgerMobileBleServiceProvider.overrideWith((_) {
            throw StateError('Windows must not initialize BLE');
          }),
        ],
      );
      addTearDown(container.dispose);
      await container.read(ledgerOperationCancellerProvider)();
      expect(cancelCalls, 1);
      expect(container.exists(ledgerMobileBleServiceProvider), isFalse);
    },
  );

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
