import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';

class PrivacyModeNotifier extends Notifier<bool> {
  PrivacyModeNotifier() : _store = AppSecureStore.instance;

  PrivacyModeNotifier.testing({required AppSecureStore store}) : _store = store;

  final AppSecureStore _store;
  Future<void> _writes = Future<void>.value();
  int _revision = 0;
  bool _resetting = false;

  @override
  bool build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    return bootstrap.privacyModeEnabled ||
        (bootstrap.isUnlocked && bootstrap.hideBalanceOnUnlockEnabled);
  }

  Future<void> set(bool enabled) async {
    if (_resetting) throw StateError('Wallet reset in progress');
    final revision = ++_revision;
    await _persist(enabled);
    if (ref.mounted && revision == _revision) state = enabled;
  }

  Future<void> toggle() => set(!state);

  /// Mask immediately, even when storage is slow or fails. Authentication
  /// owners keep their lock up until this future settles.
  Future<void> hideForUnlock() async {
    if (_resetting) return;
    ++_revision;
    state = true;
    try {
      await _persist(true);
    } catch (error) {
      debugPrint(
        'Could not persist balance hiding after unlock: ${error.runtimeType}',
      );
    }
  }

  Future<void> clearForWalletReset(Future<void> Function() clearStorage) async {
    _resetting = true;
    try {
      await _writes;
      await clearStorage();
      ++_revision;
      // Cleanup still awaits native work before routing away from the old
      // wallet. Preserve its mask throughout that interval, as before.
    } finally {
      _resetting = false;
    }
  }

  Future<void> _persist(bool enabled) {
    final write = _writes.then(
      (_) =>
          _store.writePlain(kPrivacyModeEnabledKey, enabled ? 'true' : 'false'),
    );
    // Keep later changes ordered even after a failed write. The caller still
    // receives its own error; a late completion never overrides a newer hide.
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}

final privacyModeProvider = NotifierProvider<PrivacyModeNotifier, bool>(
  PrivacyModeNotifier.new,
);
