import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_exchange.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';

void main() {
  LedgerApduCommand command(int instruction) => LedgerApduCommand(
    cla: 0xe0,
    ins: instruction,
    p1: 0,
    p2: 0,
    data: Uint8List(0),
  );
  LedgerPcztApduPlan plan() => LedgerPcztApduPlan(
    deviceAccountKeyRequest: command(0x40),
    expectedDevicePublicKey: Uint8List(33),
    commands: [command(0x52), command(0x59)],
  );

  test('account key is verified before the first transaction APDU', () async {
    final events = <String>[];
    final mobile = _ProbeTransport(events);
    await exchangeLedgerSigningPlan(
      mobile: mobile,
      plan: plan(),
      check: () {},
      progress: (_) {},
      validateDeviceAccount:
          ({required expectedPublicKey, required response}) async {
            events.add('verified');
          },
    );
    expect(events, ['probe', 'verified', 'transaction']);
  });

  test('wrong Ledger receives no transaction bytes', () async {
    final events = <String>[];
    await expectLater(
      exchangeLedgerSigningPlan(
        mobile: _ProbeTransport(events),
        plan: plan(),
        check: () {},
        progress: (_) {},
        validateDeviceAccount:
            ({required expectedPublicKey, required response}) async {
              throw StateError(
                'ledger_signature_mismatch: Connect the correct Ledger',
              );
            },
      ),
      throwsA(isA<StateError>()),
    );
    expect(events, ['probe']);
  });

  test(
    'cancellation during key verification prevents transaction exchange',
    () async {
      final events = <String>[];
      var cancelled = false;
      await expectLater(
        exchangeLedgerSigningPlan(
          mobile: _ProbeTransport(events),
          plan: plan(),
          check: () {
            if (cancelled) throw StateError('cancelled');
          },
          progress: (_) {},
          validateDeviceAccount:
              ({required expectedPublicKey, required response}) async {
                cancelled = true;
              },
        ),
        throwsA(isA<StateError>()),
      );
      expect(events, ['probe']);
    },
  );

  test('a missing probe response fails before transaction exchange', () async {
    final events = <String>[];
    var validated = false;
    await expectLater(
      exchangeLedgerSigningPlan(
        mobile: _ProbeTransport(events, missingResponse: true),
        plan: plan(),
        check: () {},
        progress: (_) {},
        validateDeviceAccount:
            ({required expectedPublicKey, required response}) async {
              validated = true;
            },
      ),
      throwsA(isA<StateError>()),
    );
    expect(validated, isFalse);
    expect(events, ['probe']);
  });
}

class _ProbeTransport implements LedgerMobileBleService {
  _ProbeTransport(this.events, {this.missingResponse = false});
  final List<String> events;
  final bool missingResponse;

  @override
  Future<List<Uint8List>> exchangeApdus(
    List<LedgerApduCommand> commands,
  ) async {
    events.add(commands.singleOrNull?.ins == 0x40 ? 'probe' : 'transaction');
    return missingResponse
        ? []
        : [
            Uint8List.fromList([0x90, 0x00]),
          ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
