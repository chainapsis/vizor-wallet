import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../rust/api/ledger.dart' as rust_ledger;
import '../ledger_capability.dart';
import 'ledger_mobile_ble_service.dart';

typedef LedgerOperationCanceller = Future<void> Function();

final ledgerRustOperationCancellerProvider = Provider<LedgerOperationCanceller>(
  (_) => () async => rust_ledger.ledgerCancelOperation(),
);

final ledgerOperationCancellerProvider = Provider<LedgerOperationCanceller>((
  ref,
) {
  // Capture dependencies before disposal: a closing screen must still reach
  // the device even after its provider scope has gone away.
  final cancelRustOperation = ref.watch(ledgerRustOperationCancellerProvider);
  final bluetooth = isLedgerBluetoothPlatform(
    ref.watch(ledgerTargetPlatformProvider),
  );
  final ble = bluetooth ? ref.watch(ledgerMobileBleServiceProvider) : null;
  return () async {
    await cancelRustOperation();
    if (ble == null) return;
    try {
      await ble.cancelSigning();
    } catch (_) {
      // Only one transport owns the operation; cancelling the idle transport
      // is best-effort and must not hide the active operation's cancellation.
    }
  };
});
