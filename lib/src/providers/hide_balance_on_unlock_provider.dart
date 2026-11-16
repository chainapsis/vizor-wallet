import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/storage/app_secure_store.dart';
import 'privacy_mode_provider.dart';

/// A wallet-wide preference, independent of the current eye-button state.
class HideBalanceOnUnlockNotifier extends Notifier<bool> {
  HideBalanceOnUnlockNotifier() : _store = AppSecureStore.instance;

  HideBalanceOnUnlockNotifier.testing({required AppSecureStore store})
    : _store = store;

  final AppSecureStore _store;
  Future<void> _writes = Future<void>.value();
  bool _resetting = false;

  @override
  bool build() => ref.watch(appBootstrapProvider).hideBalanceOnUnlockEnabled;

  Future<void> set(bool enabled) {
    if (_resetting) return Future.error(StateError('Wallet reset in progress'));
    final write = _writes.then((_) async {
      await _store.writePlain(
        kHideBalanceOnUnlockKey,
        enabled ? 'true' : 'false',
      );
      if (ref.mounted) state = enabled;
    });
    _writes = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  /// Drain accepted preference and eye-button writes before the storage wipe.
  /// Reject new changes until it finishes, including when the wipe fails.
  Future<void> clearForWalletReset(Future<void> Function() clearStorage) async {
    _resetting = true;
    try {
      await _writes;
      await ref
          .read(privacyModeProvider.notifier)
          .clearForWalletReset(clearStorage);
      if (ref.mounted) state = false;
    } finally {
      _resetting = false;
    }
  }
}

final hideBalanceOnUnlockProvider =
    NotifierProvider<HideBalanceOnUnlockNotifier, bool>(
      HideBalanceOnUnlockNotifier.new,
    );

/// Call only after successful authentication and before uncovering the wallet.
Future<void> applyHideBalanceOnUnlock(Ref ref) async {
  if (ref.read(hideBalanceOnUnlockProvider)) {
    await ref.read(privacyModeProvider.notifier).hideForUnlock();
  }
}

final hideBalanceOnUnlockActionProvider = Provider<Future<void> Function()>((
  ref,
) {
  return () => applyHideBalanceOnUnlock(ref);
});
