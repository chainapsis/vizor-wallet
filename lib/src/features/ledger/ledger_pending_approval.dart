import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'widgets/ledger_signing_modal.dart' show LedgerSigningModalPhase;

const kLedgerApprovalPendingMessage =
    'Approve or cancel the request on your Ledger before leaving.';

/// Screens that are still waiting on a Ledger device request.
///
/// Leaving such a screen disposes the request without telling the user, so
/// shell navigation consults this registry before moving away.
class LedgerPendingApprovalNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  // Handles write from a microtask, which can run after the scope that owned
  // this notifier was torn down together with the screen.
  void begin(String requestId) {
    if (!ref.mounted || state.contains(requestId)) return;
    state = {...state, requestId};
  }

  void end(String requestId) {
    if (!ref.mounted || !state.contains(requestId)) return;
    state = {...state}..remove(requestId);
  }
}

final ledgerPendingApprovalProvider =
    NotifierProvider<LedgerPendingApprovalNotifier, Set<String>>(
      LedgerPendingApprovalNotifier.new,
    );

/// Whether a modal in [phase] may still be waiting on the device.
bool ledgerPhaseAwaitsDevice(LedgerSigningModalPhase? phase) {
  return switch (phase) {
    LedgerSigningModalPhase.preparing ||
    LedgerSigningModalPhase.awaitingDevice => true,
    _ => false,
  };
}

int _nextHandleId = 0;

/// Keeps one screen's device request registered while its modal phase can
/// still be waiting on the Ledger.
///
/// Writes are deferred to a microtask because Riverpod refuses provider
/// mutations from widget lifecycles such as build and dispose.
class LedgerPendingApprovalHandle {
  LedgerPendingApprovalHandle(this._notifier)
    : requestId = 'ledger-approval-${_nextHandleId++}';

  final LedgerPendingApprovalNotifier _notifier;
  final String requestId;
  bool _pending = false;

  void update(LedgerSigningModalPhase? phase) {
    _set(ledgerPhaseAwaitsDevice(phase));
  }

  void release() => _set(false);

  void _set(bool pending) {
    if (pending == _pending) return;
    _pending = pending;
    scheduleMicrotask(() {
      if (pending) {
        _notifier.begin(requestId);
      } else {
        _notifier.end(requestId);
      }
    });
  }
}
