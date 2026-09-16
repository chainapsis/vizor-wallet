import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../rust/api/ledger.dart' as rust_ledger;
import '../ledger_capability.dart';
import 'ledger_mobile_ble_service.dart';

typedef LedgerOperationCanceller = Future<void> Function();
typedef LedgerSigningDelay = Future<void> Function(Duration duration);
typedef LedgerSigningClock = DateTime Function();

const kLedgerMobileSigningStatusCooldown = Duration(seconds: 4);

/// Serializes mobile signing streams and waits until the Zcash app can accept
/// another stream after returning its previous signatures.
class LedgerMobileSigningStatusGate {
  LedgerMobileSigningStatusGate({
    this.cooldown = kLedgerMobileSigningStatusCooldown,
    LedgerSigningDelay? delay,
    LedgerSigningClock? now,
  }) : _delay = delay ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  final Duration cooldown;
  final LedgerSigningDelay _delay;
  final LedgerSigningClock _now;
  Future<void> _previousOperation = Future<void>.value();
  DateTime? _readyAt;
  var _generation = 0;

  Future<T> run<T>(Future<T> Function() operation) async {
    final previousOperation = _previousOperation;
    final operationCompleted = Completer<void>();
    _previousOperation = operationCompleted.future;
    final generation = _generation;

    await previousOperation;
    try {
      _requireCurrent(generation);
      final readyAt = _readyAt;
      if (readyAt != null) {
        final remaining = readyAt.difference(_now());
        if (remaining > Duration.zero) await _delay(remaining);
      }
      _requireCurrent(generation);
      try {
        return await operation();
      } finally {
        _readyAt = _now().add(cooldown);
      }
    } finally {
      operationCompleted.complete();
    }
  }

  void cancelPending() => _generation++;

  void _requireCurrent(int generation) {
    if (generation == _generation) return;
    throw const LedgerMobileException(
      LedgerMobileFailure.cancelled,
      'Ledger signing was cancelled.',
    );
  }
}

final ledgerMobileSigningStatusGateProvider =
    Provider<LedgerMobileSigningStatusGate>((_) {
      return LedgerMobileSigningStatusGate();
    });

final ledgerRustOperationCancellerProvider = Provider<LedgerOperationCanceller>(
  (_) =>
      () async => rust_ledger.ledgerCancelOperation(),
);

final ledgerOperationCancellerProvider = Provider<LedgerOperationCanceller>((
  ref,
) {
  // Capture dependencies before disposal: a closing screen must still reach
  // the device even after its provider scope has gone away.
  final statusGate = ref.watch(ledgerMobileSigningStatusGateProvider);
  final cancelRustOperation = ref.watch(ledgerRustOperationCancellerProvider);
  final bluetooth = isLedgerBluetoothPlatform(
    ref.watch(ledgerTargetPlatformProvider),
  );
  final ble = bluetooth ? ref.watch(ledgerMobileBleServiceProvider) : null;
  return () async {
    statusGate.cancelPending();
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
