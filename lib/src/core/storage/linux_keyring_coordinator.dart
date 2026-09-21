import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'secure_storage_diagnostics.dart';

final linuxKeyringCoordinatorProvider = Provider<LinuxKeyringCoordinator>(
  (_) => LinuxKeyringCoordinator.instance,
);

enum LinuxKeyringPhase {
  ready,
  working,
  retrying,
  keyringLocked,
  serviceUnavailable,
  storageCorrupt,
  outcomeUnknown,
}

@immutable
class LinuxKeyringState {
  const LinuxKeyringState({
    this.phase = LinuxKeyringPhase.ready,
    this.canCancel = false,
    this.requestId,
  });

  final LinuxKeyringPhase phase;
  final bool canCancel;
  final int? requestId;

  bool get isWaiting => switch (phase) {
    LinuxKeyringPhase.ready || LinuxKeyringPhase.working => false,
    _ => true,
  };

  bool get canRetry =>
      requestId != null &&
      switch (phase) {
        LinuxKeyringPhase.keyringLocked ||
        LinuxKeyringPhase.serviceUnavailable ||
        LinuxKeyringPhase.storageCorrupt => true,
        _ => false,
      };
}

class LinuxWalletMutationBusyException implements Exception {
  const LinuxWalletMutationBusyException();

  @override
  String toString() =>
      'Finish the current wallet operation before starting another.';
}

enum _RecoveryAction { retry, cancel, disposed }

/// Serializes calls to the unmodified upstream Linux storage plugin.
///
/// Recovery starts only after a native call has returned an error. The plugin
/// does not report prompt progress or support cancelling an in-flight call.
/// Retry repeats that individual storage call, never the enclosing wallet
/// mutation. An ambiguous write failure blocks further calls until restart.
class LinuxKeyringCoordinator extends ChangeNotifier {
  LinuxKeyringCoordinator._() : isEnabled = Platform.isLinux;

  @visibleForTesting
  LinuxKeyringCoordinator.testing({bool enabled = true}) : isEnabled = enabled;

  static final instance = LinuxKeyringCoordinator._();
  final bool isEnabled;
  LinuxKeyringState _state = const LinuxKeyringState();
  Future<void> _storageTail = Future<void>.value();
  Completer<_RecoveryAction>? _recovery;
  int _nextRequestId = 0;
  bool _hasPendingMutation = false;
  bool _writeOutcomeUnknown = false;
  bool _disposed = false;
  final Object _mutationZoneKey = Object();
  Object? _mutationOwner;

  LinuxKeyringState get state => _state;
  bool get hasPendingMutation => _hasPendingMutation;

  Future<T> runStorageOperation<T>(
    Future<T> Function() action, {
    required bool isRead,
  }) {
    if (!isEnabled) return action();
    final result = _storageTail.then(
      (_) => _runStorageOperation(action, isRead),
    );
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<T> _runStorageOperation<T>(
    Future<T> Function() action,
    bool isRead,
  ) async {
    if (_disposed) throw StateError('The keyring coordinator was disposed.');
    if (_writeOutcomeUnknown) {
      throw PlatformException(code: 'StorageOutcomeUnknown');
    }
    final requestId = ++_nextRequestId;
    _setState(
      LinuxKeyringState(phase: LinuxKeyringPhase.working, requestId: requestId),
    );
    try {
      while (true) {
        try {
          return await action();
        } on PlatformException catch (error) {
          if (_disposed) rethrow;
          final phase = switch (error.code) {
            'KeyringLocked' => LinuxKeyringPhase.keyringLocked,
            'Libsecret error' ||
            'SecretNotFound' => LinuxKeyringPhase.serviceUnavailable,
            'StorageError' => LinuxKeyringPhase.storageCorrupt,
            _ => null,
          };
          if (phase == null) rethrow;

          // Only KeyringLocked positively rejects a mutation. Other upstream
          // errors do not identify whether a write reached Secret Service.
          // Do not replay a write or claim its result can be reconciled here.
          if (!isRead && error.code != 'KeyringLocked') {
            _writeOutcomeUnknown = true;
            _setState(
              const LinuxKeyringState(phase: LinuxKeyringPhase.outcomeUnknown),
            );
            rethrow;
          }

          final recovery = Completer<_RecoveryAction>();
          _recovery = recovery;
          _setState(
            LinuxKeyringState(
              phase: phase,
              requestId: requestId,
              canCancel: isRead,
            ),
          );
          final decision = await recovery.future;
          _recovery = null;
          if (decision != _RecoveryAction.retry) {
            throw PlatformException(code: 'storage_cancelled');
          }
          _setState(
            LinuxKeyringState(
              phase: LinuxKeyringPhase.retrying,
              requestId: requestId,
            ),
          );
        }
      }
    } finally {
      _recovery = null;
      if (!_writeOutcomeUnknown) _setState(const LinuxKeyringState());
    }
  }

  void _setState(LinuxKeyringState next) {
    if (_disposed) return;
    if (next.phase != _state.phase) {
      final stage = switch (next.phase) {
        LinuxKeyringPhase.ready => StorageKeyringStage.ready,
        LinuxKeyringPhase.working => StorageKeyringStage.working,
        LinuxKeyringPhase.retrying => StorageKeyringStage.retrying,
        LinuxKeyringPhase.keyringLocked => StorageKeyringStage.keyringLocked,
        LinuxKeyringPhase.serviceUnavailable =>
          StorageKeyringStage.serviceUnavailable,
        LinuxKeyringPhase.storageCorrupt => StorageKeyringStage.storageCorrupt,
        LinuxKeyringPhase.outcomeUnknown => StorageKeyringStage.outcomeUnknown,
      };
      unawaited(SecureStorageDiagnostics.instance.keyringState(stage));
    }
    _state = next;
    notifyListeners();
  }

  Future<void> retry({required int requestId}) async {
    if (!isEnabled ||
        _disposed ||
        !state.canRetry ||
        state.requestId != requestId) {
      return;
    }
    final recovery = _recovery;
    if (recovery == null || recovery.isCompleted) return;
    unawaited(
      SecureStorageDiagnostics.instance.keyringAction(
        StorageKeyringAction.retryRequested,
      ),
    );
    recovery.complete(_RecoveryAction.retry);
  }

  /// Abandons a failed read waiting for user action, not a native request.
  Future<void> cancel({required int requestId}) async {
    if (!isEnabled ||
        _disposed ||
        !state.canCancel ||
        _hasPendingMutation ||
        state.requestId != requestId) {
      return;
    }
    final recovery = _recovery;
    if (recovery == null || recovery.isCompleted) return;
    unawaited(
      SecureStorageDiagnostics.instance.keyringAction(
        StorageKeyringAction.cancelRequested,
      ),
    );
    recovery.complete(_RecoveryAction.cancel);
  }

  /// Nested calls retain ownership. Separate UI/job requests are rejected
  /// rather than queued with inputs captured before the current mutation.
  Future<T> runMutation<T>(Future<T> Function() action) async {
    if (!isEnabled) return action();
    if (_mutationOwner != null &&
        identical(Zone.current[_mutationZoneKey], _mutationOwner)) {
      return action();
    }
    if (_hasPendingMutation || _state.isWaiting) {
      throw const LinuxWalletMutationBusyException();
    }
    final owner = Object();
    _mutationOwner = owner;
    _hasPendingMutation = true;
    notifyListeners();
    try {
      return await runZoned(action, zoneValues: {_mutationZoneKey: owner});
    } finally {
      _mutationOwner = null;
      _hasPendingMutation = false;
      if (!_disposed) notifyListeners();
    }
  }

  @visibleForTesting
  void setStateForTesting(LinuxKeyringState state) => _setState(state);

  @override
  void dispose() {
    _disposed = true;
    final recovery = _recovery;
    if (recovery != null && !recovery.isCompleted) {
      recovery.complete(_RecoveryAction.disposed);
    }
    super.dispose();
  }
}
