import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ledger_mobile_ble_service.dart';

/// Cancellation spans preparation as well as the eventual native command.
/// This is separate from the durable broadcast/deletion drain: device approval
/// is cancellable, whereas already-submitted transactions must finish handling.
class LedgerDeviceRequests {
  int _generation = 0;
  int _readinessRequest = 0;
  int _cancellations = 0;

  final _listeners = <void Function()>{};
  void addCancellationListener(void Function() listener) =>
      _listeners.add(listener);
  void removeCancellationListener(void Function() listener) =>
      _listeners.remove(listener);
  void cancel() {
    _generation++;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  Future<void> cancelWhile(Future<void> Function() cancelNative) async {
    cancel();
    _cancellations++;
    try {
      await cancelNative();
    } finally {
      _cancellations--;
    }
  }

  void Function() capture() {
    if (_cancellations != 0) _cancelled();
    final generation = _generation;
    return () {
      if (generation != _generation || _cancellations != 0) _cancelled();
    };
  }

  // Readiness providers for all transports publish into one state provider.
  // Only its latest request may publish, even without explicit cancellation.
  void Function() beginReadiness() {
    final check = capture();
    final request = ++_readinessRequest;
    return () {
      check();
      if (request != _readinessRequest) _cancelled();
    };
  }

  Never _cancelled() => throw const LedgerMobileException(
    LedgerMobileFailure.cancelled,
    'Ledger operation was cancelled.',
  );
}

final ledgerDeviceRequestsProvider = Provider<LedgerDeviceRequests>((ref) {
  final requests = LedgerDeviceRequests();
  ref.onDispose(requests.cancel);
  return requests;
});
