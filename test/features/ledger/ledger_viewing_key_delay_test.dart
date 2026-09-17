import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_device_request.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_pairing_recovery_service.dart';
import 'ledger_pairing_recovery_test.dart' as fixture;

void main() {
  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    for (final cancel in [false, true]) {
      testWidgets(
        '$platform verified replacement waits one second (cancel: $cancel)',
        (tester) async {
          final accounts = fixture.FakeAccounts();
          final c = fixture.containerFor(
            fixture.FakeBle(),
            accounts,
            platform: platform,
          );
          addTearDown(c.dispose);
          var finished = false;
          Object? error;
          final result = c
              .read(ledgerPairingRecoveryServiceProvider)
              .verifyAndSave(
                accountUuid: 'a',
                device: fixture.device,
                checkCurrent: () {},
                onSaving: () {},
              )
              .then<void>(
                (_) {
                  finished = true;
                },
                onError: (Object e) {
                  error = e;
                },
              );
          await tester.pump();
          expect(error, isNull);
          expect(accounts.savedId, fixture.device.id);
          expect(finished, isFalse);
          await tester.pump(const Duration(milliseconds: 999));
          expect(finished, isFalse);
          if (cancel) c.read(ledgerDeviceRequestsProvider).cancel();
          await tester.pump(const Duration(milliseconds: 1));
          await result;
          expect(finished, !cancel);
          if (cancel) {
            expect(
              error,
              isA<LedgerMobileException>().having(
                (e) => e.failure,
                'failure',
                LedgerMobileFailure.cancelled,
              ),
            );
          } else {
            expect(error, isNull);
          }
        },
      );
    }
  }

  testWidgets('saved device skips viewing-key delay', (tester) async {
    final c = fixture.containerFor(
      fixture.FakeBle(),
      fixture.FakeAccounts(
        initial: fixture.account.copyWith(ledgerDeviceId: fixture.device.id),
      ),
    );
    addTearDown(c.dispose);
    var finished = false;
    final result = c
        .read(ledgerPairingRecoveryServiceProvider)
        .verifyAndSave(
          accountUuid: 'a',
          device: fixture.device,
          checkCurrent: () {},
          onSaving: () {},
        )
        .then((_) {
          finished = true;
        });
    await tester.pump();
    expect(finished, isTrue);
    await result;
  });
}
