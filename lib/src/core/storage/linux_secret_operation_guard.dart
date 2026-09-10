import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/account_models.dart';
import 'app_secure_store.dart';
import 'linux_keyring_coordinator.dart';

final linuxSecretOperationStoreProvider = Provider<AppSecureStore>(
  (_) => AppSecureStore.instance,
);

/// Validates the owner of a Linux operation after a potentially long keyring
/// wait. The request check runs first so disposed provider refs are never read.
class LinuxSecretOperationGuard {
  LinuxSecretOperationGuard({
    required AppSecureStore store,
    required LinuxKeyringCoordinator coordinator,
    required bool Function() isRequestCurrent,
    required AccountState? Function() readAccounts,
    String? accountUuid,
    bool trackActiveAccount = true,
  }) : _store = store,
       _coordinator = coordinator,
       _generation = store.sessionGeneration,
       _isRequestCurrent = isRequestCurrent,
       _readAccounts = readAccounts,
       _trackActiveAccount = trackActiveAccount {
    if (!enabled) return;
    if (!_isRequestCurrent()) {
      throw const SecureStorageSessionChangedException();
    }
    final accounts = _readAccounts();
    _activeAccountUuid = accounts?.activeAccountUuid;
    _accountUuids = accountUuid == null
        ? {
            for (final account in accounts?.accounts ?? <AccountInfo>[])
              account.uuid,
          }
        : {accountUuid};
    check();
  }

  final AppSecureStore _store;
  final LinuxKeyringCoordinator _coordinator;
  final int _generation;
  final bool Function() _isRequestCurrent;
  final AccountState? Function() _readAccounts;
  final bool _trackActiveAccount;
  String? _activeAccountUuid;
  Set<String> _accountUuids = const {};

  bool get enabled => _store.enforcesSessionGeneration;

  void check() {
    if (!enabled) return;
    if (!_isRequestCurrent() ||
        _coordinator.hasPendingMutation ||
        !_store.isSessionGenerationCurrent(_generation) ||
        !_store.hasSessionPassword) {
      throw const SecureStorageSessionChangedException();
    }
    final accounts = _readAccounts();
    if (accounts == null ||
        _accountUuids.isEmpty ||
        (_trackActiveAccount &&
            accounts.activeAccountUuid != _activeAccountUuid) ||
        !_accountUuids.every(
          (uuid) => accounts.accounts.any((account) => account.uuid == uuid),
        )) {
      throw const SecureStorageSessionChangedException();
    }
  }
}
