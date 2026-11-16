import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';

/// Completion and ownership of one privacy request, including reentrant inputs.
class PrivacyModeChange {
  PrivacyModeChange._(this.completed, this._isCurrent);

  final Future<bool> completed;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();
}

class PrivacyModeNotifier extends Notifier<bool> {
  PrivacyModeNotifier() : _store = AppSecureStore.instance;

  PrivacyModeNotifier.testing({required AppSecureStore store}) : _store = store;

  final AppSecureStore _store;
  Future<void> _writes = Future<void>.value();
  int _revision = 0;
  bool _resetting = false;
  bool? _requestedHidden;

  /// Includes a reveal waiting for storage, so a subsequent flip can hide it.
  bool get requestedHidden => _requestedHidden ?? state;

  @override
  bool build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    return bootstrap.privacyModeEnabled ||
        (bootstrap.isUnlocked && bootstrap.hideBalanceOnUnlockEnabled);
  }

  Future<void> set(bool enabled) async {
    await _set(enabled).completed;
  }

  Future<void> toggle() => set(!requestedHidden);

  /// Hiding takes effect immediately and survives a failed save. Revealing
  /// waits for persistence and is abandoned if its sensor session has ended.
  PrivacyModeChange setFromFlip(
    bool enabled, {
    required bool Function() isActive,
  }) => _set(enabled, hideImmediately: true, canReveal: isActive);

  /// Mask immediately, even when storage is slow or fails. Authentication
  /// owners keep their lock up until this future settles.
  Future<void> hideForUnlock() async {
    if (_resetting) return;
    try {
      await _set(true, hideImmediately: true).completed;
    } catch (error) {
      debugPrint(
        'Could not persist balance hiding after unlock: ${error.runtimeType}',
      );
    }
  }

  Future<void> clearForWalletReset(Future<void> Function() clearStorage) async {
    _resetting = true;
    ++_revision;
    _requestedHidden = null;
    try {
      await _writes;
      await clearStorage();
      // Cleanup still awaits native work before routing away from the old
      // wallet. Preserve its mask throughout that interval, as before.
    } finally {
      _resetting = false;
    }
  }

  PrivacyModeChange _set(
    bool enabled, {
    bool hideImmediately = false,
    bool Function()? canReveal,
  }) {
    if (_resetting) {
      return PrivacyModeChange._(
        Future.error(StateError('Wallet reset in progress')),
        () => false,
      );
    }
    final revision = ++_revision;
    _requestedHidden = enabled;

    void finishRequest() {
      if (ref.mounted && revision == _revision) _requestedHidden = null;
    }

    final write = _writes.then((_) async {
      try {
        if (!enabled && canReveal != null && !canReveal()) {
          finishRequest();
          return false;
        }
        await _store.writePlain(
          kPrivacyModeEnabledKey,
          enabled ? 'true' : 'false',
        );
        if (!ref.mounted || revision != _revision) return false;
        if (!enabled && canReveal != null && !canReveal()) {
          // The write may have completed after locking/backgrounding. Restore
          // the current mask on disk before the next queued change or reset.
          finishRequest();
          await _store.writePlain(
            kPrivacyModeEnabledKey,
            state ? 'true' : 'false',
          );
          return false;
        }
        state = enabled;
        finishRequest();
        return true;
      } catch (_) {
        finishRequest();
        rethrow;
      }
    });
    // Keep later changes ordered even after a failed write. The caller still
    // receives its own error; a late completion never overrides a newer hide.
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    // Reserve the queue slot before notifying state listeners: a listener may
    // immediately issue another request, which must persist after this one.
    if (enabled && hideImmediately) state = true;
    return PrivacyModeChange._(
      write,
      () => ref.mounted && revision == _revision,
    );
  }
}

final privacyModeProvider = NotifierProvider<PrivacyModeNotifier, bool>(
  PrivacyModeNotifier.new,
);
