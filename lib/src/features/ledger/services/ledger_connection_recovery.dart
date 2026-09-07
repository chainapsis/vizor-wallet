import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ledger_app_readiness_service.dart';
import 'ledger_connection_service.dart';
import 'ledger_mobile_ble_service.dart';

bool ledgerFailureNeedsReconnect(Object error) =>
    error is LedgerConnectionRequiredException ||
    (error is LedgerMobileException &&
        (error.failure == LedgerMobileFailure.disconnected ||
            error.failure == LedgerMobileFailure.bluetoothOff)) ||
    (error is LedgerAppReadinessException &&
        error.failure == LedgerAppReadinessFailure.disconnected);

final ledgerReconnectProvider = Provider<Future<void> Function(String)>(
  (ref) => ref.read(ledgerConnectionServiceProvider).reconnect,
);

enum LedgerConnectionRecoveryPhase { idle, reconnecting, ready, failed }

/// Owns connection recovery only. It cannot sign, validate a proposal or broadcast.
/// Owners invalidate this controller when their account/operation changes.
class LedgerConnectionRecoveryController extends ChangeNotifier {
  LedgerConnectionRecoveryPhase phase = LedgerConnectionRecoveryPhase.idle;
  String? message;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _tail = Future<void>.value();
  Future<void>? _request;

  void reset() {
    _generation++;
    _request = null;
    phase = LedgerConnectionRecoveryPhase.idle;
    message = null;
    if (!_disposed) notifyListeners();
  }

  Future<void> reconnect(
    String accountUuid,
    Future<void> Function(String) prepare,
  ) {
    if (_disposed) return Future<void>.value();
    final existing = _request;
    if (existing != null) return existing;
    final generation = _generation;
    phase = LedgerConnectionRecoveryPhase.reconnecting;
    message = null;
    final request = _tail.then((_) async {
      if (_disposed || generation != _generation) return;
      try {
        await prepare(accountUuid);
        if (_disposed || generation != _generation) return;
        phase = LedgerConnectionRecoveryPhase.ready;
      } catch (error) {
        if (_disposed || generation != _generation) return;
        phase = LedgerConnectionRecoveryPhase.failed;
        message = error.toString();
      } finally {
        if (!_disposed && generation == _generation) {
          _request = null;
          notifyListeners();
        }
      }
    });
    _request = request;
    _tail = request;
    notifyListeners();
    return request;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
