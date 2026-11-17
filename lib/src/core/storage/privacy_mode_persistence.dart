import 'package:flutter/foundation.dart' show debugPrint;

import 'app_secure_store.dart';

/// A reveal is not durable until its pending marker has been cleared. A crash
/// or a failed compensating write therefore restores hiding at the next start.
/// Callers serialize all writes, including cleanup, with privacy requests/reset.
class PrivacyModePersistence {
  const PrivacyModePersistence(this._store);

  final AppSecureStore _store;

  Future<void> prepareReveal() =>
      _store.writePlain(kPrivacyModeRevealPendingKey, 'true');

  Future<void> writeMode(bool hidden) =>
      _store.writePlain(kPrivacyModeEnabledKey, hidden ? 'true' : 'false');

  /// Only call after the mode has been saved and the request committed, or
  /// after restoring hiding. Failure leaves a conservative restart override;
  /// it must not turn an already-applied reveal into a misleading UI error.
  Future<void> clearPendingBestEffort() async {
    try {
      await _store.delete(kPrivacyModeRevealPendingKey);
    } catch (error) {
      debugPrint(
        'Could not clear pending balance reveal: ${error.runtimeType}',
      );
    }
  }

  /// Bootstrap runs before privacy writers exist. Any pending/unknown marker
  /// takes precedence over the old Boolean flag, including a saved `false`.
  Future<bool> readAndRecover() async {
    try {
      final pending = await _store.readPlain(kPrivacyModeRevealPendingKey);
      if (pending == null) {
        return await _store.readPlain(kPrivacyModeEnabledKey) == 'true';
      }
    } on SecureStorageUnavailableException {
      // Retain the app's existing blocking storage-recovery flow.
      rethrow;
    } catch (error) {
      debugPrint('Could not read balance privacy: ${error.runtimeType}');
      return true;
    }
    try {
      await writeMode(true);
      await clearPendingBestEffort();
    } catch (error) {
      // Keep the marker and the first-frame mask even if repair cannot save.
      debugPrint(
        'Could not restore saved balance hiding: ${error.runtimeType}',
      );
    }
    return true;
  }
}
