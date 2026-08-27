import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_signing_service.dart';
import 'package:zcash_wallet/src/rust/api/ledger.dart';

void main() {
  test('accepts exactly one matching 64-byte Ironwood signature', () {
    final signature = LedgerVotingSignature(
      pool: 1,
      actionIndex: 7,
      signature: List<int>.filled(64, 9),
    );

    expect(
      requireMatchingLedgerVotingSignature(
        signatures: [signature],
        actionIndex: 7,
      ),
      same(signature),
    );
  });

  test('fails closed on signature count, pool, action, or length mismatch', () {
    LedgerVotingSignature signature({
      int pool = 1,
      int actionIndex = 7,
      int length = 64,
    }) => LedgerVotingSignature(
      pool: pool,
      actionIndex: actionIndex,
      signature: List<int>.filled(length, 9),
    );

    for (final candidate in <List<LedgerVotingSignature>>[
      const [],
      [signature(), signature()],
      [signature(pool: 0)],
      [signature(actionIndex: 8)],
      [signature(length: 63)],
    ]) {
      expect(
        () => requireMatchingLedgerVotingSignature(
          signatures: candidate,
          actionIndex: 7,
        ),
        throwsStateError,
      );
    }
  });

  test(
    'cancellation waits for Rust before cancelling the mobile transport',
    () async {
      final rustCancellation = Completer<void>();
      final mobile = _CancellationBleService();
      final container = ProviderContainer(
        overrides: [
          ledgerRustOperationCancellerProvider.overrideWithValue(
            () => rustCancellation.future,
          ),
          ledgerMobileBleServiceProvider.overrideWithValue(mobile),
        ],
      );
      addTearDown(container.dispose);

      var completed = false;
      final cancellation = container
          .read(ledgerOperationCancellerProvider)()
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);

      expect(completed, isFalse);
      expect(mobile.cancelCalls, 0);

      rustCancellation.complete();
      await cancellation;

      expect(completed, isTrue);
      expect(mobile.cancelCalls, 1);
    },
  );
}

class _CancellationBleService implements LedgerMobileBleService {
  var cancelCalls = 0;

  @override
  String? get connectedDeviceId => null;

  @override
  Future<void> cancelSigning() async {
    cancelCalls++;
  }

  @override
  Future<void> connect(LedgerBleDevice device) async {}

  @override
  Future<LedgerMobileAppInfo> currentApp() => throw UnimplementedError();

  @override
  Stream<LedgerDiscoveryUpdate> discoverDevices() => const Stream.empty();

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<Uint8List>> exchangeApdus(List<LedgerApduCommand> commands) =>
      throw UnimplementedError();

  @override
  Future<List<Uint8List>> exchangeUfvk(LedgerUfvkApduPlan plan) =>
      throw UnimplementedError();

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<LedgerMobileAppInfo> requestOpenZcashApp() =>
      throw UnimplementedError();

  @override
  Future<void> stopDiscovery() async {}
}
