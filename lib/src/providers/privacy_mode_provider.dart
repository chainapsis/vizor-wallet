import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';
import '../core/storage/privacy_mode_persistence.dart';

/// Completion and ownership of one privacy request, including reentrant inputs.
class PrivacyModeChange {
  PrivacyModeChange._(this.completed, this._isCurrent);

  final Future<bool> completed;
  final bool Function() _isCurrent;
  bool get isCurrent => _isCurrent();
}

class PrivacyModeNotifier extends Notifier<bool> {
  PrivacyModeNotifier()
    : _persistence = PrivacyModePersistence(AppSecureStore.instance);

  PrivacyModeNotifier.testing({required AppSecureStore store})
    : _persistence = PrivacyModePersistence(store);

  final PrivacyModePersistence _persistence;
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

    bool ownsRequest() => ref.mounted && revision == _revision;
    bool revealActive() => canReveal == null || canReveal();

    Future<bool> cancelReveal() async {
      // A superseding request/reset owns the next write. Keep its protection
      // intact instead of letting this request clear the durable marker.
      if (!ownsRequest()) return false;
      finishRequest();
      await _persistence.writeMode(true);
      if (ownsRequest()) await _persistence.clearPendingBestEffort();
      return false;
    }

    final write = _writes.then((_) async {
      try {
        if (!ownsRequest()) return false;
        if (!enabled && !revealActive()) {
          finishRequest();
          return false;
        }
        if (!enabled) {
          // Never persist `false` without a restart-safe hiding override.
          await _persistence.prepareReveal();
          if (!ownsRequest()) return false;
          if (!revealActive()) return await cancelReveal();
        }
        await _persistence.writeMode(enabled);
        if (!ownsRequest()) return false;
        if (!enabled && !revealActive()) return await cancelReveal();
        // Commit synchronously with the final ownership/session check. Session
        // changes during subsequent cleanup cannot cancel an accepted reveal.
        state = enabled;
        finishRequest();
        // A state listener may synchronously issue a newer hide or reset.
        if (ownsRequest()) await _persistence.clearPendingBestEffort();
        return ownsRequest();
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
