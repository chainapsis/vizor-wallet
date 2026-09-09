import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/security/password_policy.dart';
import '../core/storage/app_secure_store.dart';
import '../core/storage/linux_keyring_coordinator.dart';
import '../core/storage/wallet_paths.dart';
import '../core/storage/wallet_recovery.dart';
import '../features/migration/models/ironwood_migration_phases.dart';
import '../rust/api/sync.dart' as rust_sync;
import '../rust/api/wallet.dart' as rust_wallet;
import 'rpc_endpoint_provider.dart';

const kIronwoodMigrationPasswordChangeBlockedMessage =
    'Cannot change wallet password while Ironwood migration is in progress.';

class IronwoodMigrationPasswordChangeBlockedException implements Exception {
  const IronwoodMigrationPasswordChangeBlockedException([this.message]);

  final String? message;

  @override
  String toString() =>
      message ?? kIronwoodMigrationPasswordChangeBlockedMessage;
}

typedef PasswordChangePreflight = Future<void> Function();
typedef PasswordChangeWalletDbPathGetter = Future<String> Function();
typedef PasswordChangeAccountLister =
    Future<List<rust_wallet.AccountInfo>> Function({
      required String dbPath,
      required String network,
    });
typedef PasswordChangeMigrationStatusGetter =
    Future<rust_sync.MigrationStatus> Function({
      required String dbPath,
      required String network,
      required String accountUuid,
    });

final passwordChangeWalletDbPathProvider =
    Provider<PasswordChangeWalletDbPathGetter>((_) => getWalletDbPath);

final passwordChangeAccountListerProvider =
    Provider<PasswordChangeAccountLister>((_) => rust_wallet.listAccounts);

final passwordChangeMigrationStatusProvider =
    Provider<PasswordChangeMigrationStatusGetter>(
      (_) => rust_sync.getOrchardMigrationStatus,
    );

final passwordChangePreflightProvider = Provider<PasswordChangePreflight>((
  ref,
) {
  return () async {
    final network = ref.read(rpcEndpointProvider).networkName;
    final dbPath = await ref.read(passwordChangeWalletDbPathProvider)();
    final accounts = await ref.read(passwordChangeAccountListerProvider)(
      dbPath: dbPath,
      network: network,
    );
    if (accounts.isEmpty) return;

    final getStatus = ref.read(passwordChangeMigrationStatusProvider);
    for (final account in accounts) {
      final status = await getStatus(
        dbPath: dbPath,
        network: network,
        accountUuid: account.uuid,
      );
      if (status.activeRunId != null ||
          isIronwoodMigrationInProgressPhase(status.phase)) {
        throw const IronwoodMigrationPasswordChangeBlockedException();
      }
    }
  };
});

/// A failed import may already have committed an account in Rust. Only an
/// inspectable, account-free database permits removing its setup password.
final passwordSetupRollbackSafetyProvider = Provider<Future<bool> Function()>((
  ref,
) {
  return () async {
    final network = ref.read(rpcEndpointProvider).networkName;
    if (await readWalletDbName() == null) {
      return (await findWalletRecoveryCandidates(network: network)).isEmpty;
    }
    final path = await getWalletDbPath();
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return (await findWalletRecoveryCandidates(network: network)).isEmpty;
    }
    if (type != FileSystemEntityType.file) return false;
    final accounts = await rust_wallet.inspectWalletForRecovery(
      dbPath: path,
      network: network,
    );
    return accounts.isEmpty;
  };
});

class AppSecurityState {
  const AppSecurityState({
    required this.isPasswordConfigured,
    required this.isUnlocked,
  });

  final bool isPasswordConfigured;
  final bool isUnlocked;

  bool get requiresUnlock => isPasswordConfigured && !isUnlocked;

  AppSecurityState copyWith({bool? isPasswordConfigured, bool? isUnlocked}) {
    return AppSecurityState(
      isPasswordConfigured: isPasswordConfigured ?? this.isPasswordConfigured,
      isUnlocked: isUnlocked ?? this.isUnlocked,
    );
  }
}

class AppSecurityNotifier extends Notifier<AppSecurityState> {
  AppSecurityNotifier() : _store = AppSecureStore.instance;

  @visibleForTesting
  AppSecurityNotifier.testing({required AppSecureStore store}) : _store = store;

  final AppSecureStore _store;
  bool _isPasswordSetupPrepared = false;
  int? _passwordSetupSessionGeneration;
  int _lifecycleGeneration = 0;
  int _unlockRequestGeneration = 0;
  int _confirmRequestGeneration = 0;
  int? _pendingUnlockSessionGeneration;
  bool _requiresWalletSetupRecovery = false;

  bool get requiresWalletSetupRecovery => _requiresWalletSetupRecovery;

  @override
  AppSecurityState build() {
    _lifecycleGeneration++;
    ref.onDispose(() {
      _lifecycleGeneration++;
      final pendingGeneration = _pendingUnlockSessionGeneration;
      if (_store.enforcesSessionGeneration &&
          pendingGeneration != null &&
          _store.isSessionGenerationCurrent(pendingGeneration)) {
        _store.clearSessionPassword();
      }
    });
    final bootstrap = ref.watch(appBootstrapProvider);
    return AppSecurityState(
      isPasswordConfigured: bootstrap.isPasswordConfigured,
      isUnlocked: bootstrap.isUnlocked,
    );
  }

  Future<void> configurePassword(String password) => ref
      .read(linuxKeyringCoordinatorProvider)
      .runMutation(() => _configurePassword(password));

  Future<void> _configurePassword(String password) async {
    await preparePasswordSetup(password);
    await commitPasswordSetup();
  }

  Future<void> preparePasswordSetup(String password) => ref
      .read(linuxKeyringCoordinatorProvider)
      .runMutation(() => _preparePasswordSetup(password));

  Future<void> _preparePasswordSetup(String password) async {
    final lifecycleGeneration = _lifecycleGeneration;
    final requestGeneration = _unlockRequestGeneration;
    final sessionGeneration = _store.sessionGeneration;
    if (_requiresWalletSetupRecovery) {
      throw StateError('Recover the existing wallet before continuing setup.');
    }
    if (state.isPasswordConfigured || await _store.isPasswordConfigured()) {
      final canResumeEmptySetup =
          await _store.readPlain(kWalletRecoveryPendingKey) ==
              kWalletSetupPendingValue &&
          await ref.read(passwordSetupRollbackSafetyProvider)();
      if (!canResumeEmptySetup) {
        throw StateError('Password is already configured.');
      }
    }
    if (_isPasswordSetupPrepared) {
      throw StateError('Password setup is already pending.');
    }
    final error = validateRequiredWalletPassword(password);
    if (error != null) {
      throw ArgumentError(error);
    }
    // Persist the verifier and open the secure-storage session before account
    // creation/import writes the encrypted mnemonic. Publishing provider state
    // is still delayed until commit so the router never sees half-completed
    // onboarding.
    await _store.configurePassword(password);
    try {
      // Establish recovery before the first native DB mutation. A later
      // keyring failure must not prevent recording the incomplete setup.
      await _store.writePlain(
        kWalletRecoveryPendingKey,
        kWalletSetupPendingValue,
      );
    } catch (_) {
      // The caller has not started account creation yet.
      await _store.clearPasswordConfiguration();
      rethrow;
    }
    _isPasswordSetupPrepared = true;
    _passwordSetupSessionGeneration = _store.sessionGeneration;
    if (_store.enforcesSessionGeneration &&
        (lifecycleGeneration != _lifecycleGeneration ||
            requestGeneration != _unlockRequestGeneration ||
            !_store.isSessionGenerationCurrent(sessionGeneration + 1) ||
            !_store.hasSessionPassword)) {
      // Account creation has not started. Discard the stale attempt without
      // reopening its session; the normal setup flow can be retried.
      _isPasswordSetupPrepared = false;
      _passwordSetupSessionGeneration = null;
      if (_store.isSessionGenerationCurrent(sessionGeneration + 1)) {
        _store.clearSessionPassword();
      }
      throw const SecureStorageSessionChangedException();
    }
  }

  Future<void> commitPasswordSetup() async {
    if (!_isPasswordSetupPrepared) {
      throw StateError('Password setup was not prepared.');
    }
    await _store.delete(kWalletRecoveryPendingKey);
    if (await _store.readPlain(kWalletRecoveryPendingKey) != null) {
      throw StateError('Wallet setup could not be saved. Retry recovery.');
    }
    final sessionGeneration = _passwordSetupSessionGeneration;
    _isPasswordSetupPrepared = false;
    _passwordSetupSessionGeneration = null;
    state = AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked:
          !_store.enforcesSessionGeneration ||
          (sessionGeneration != null &&
              _store.isSessionGenerationCurrent(sessionGeneration) &&
              _store.hasSessionPassword),
    );
  }

  Future<void> rollbackPasswordSetup() => ref
      .read(linuxKeyringCoordinatorProvider)
      .runMutation(() => _rollbackPasswordSetup());

  Future<void> _rollbackPasswordSetup() async {
    if (!_isPasswordSetupPrepared) return;
    var canRollback = false;
    try {
      canRollback = await ref.read(passwordSetupRollbackSafetyProvider)();
    } catch (_) {
      // An unreadable database is not evidence that no account was created.
    }
    if (canRollback) {
      await _store.clearPasswordConfiguration();
      final name = await readWalletDbName();
      if (name != null &&
          await FileSystemEntity.type(
                await getWalletDbPath(),
                followLinks: false,
              ) ==
              FileSystemEntityType.notFound) {
        // An explicit setup attempt allocated a name but never created a DB.
        // Do not leave that unused locator looking like a missing wallet.
        await _store.delete(kWalletDbNameKey);
      }
      // Keep the setup marker so a restart can distinguish this unused DB
      // from a wallet whose password configuration was unexpectedly lost.
      _isPasswordSetupPrepared = false;
      _passwordSetupSessionGeneration = null;
      return;
    }

    _requiresWalletSetupRecovery = true;
    _isPasswordSetupPrepared = false;
    _passwordSetupSessionGeneration = null;
    _store.clearSessionPassword();
    // Keep the verifier, any saved signing material, and the marker written
    // before account creation. No further keyring write is needed to recover.
  }

  Future<bool> unlock(String password) async {
    final lifecycleGeneration = _lifecycleGeneration;
    final requestGeneration = ++_unlockRequestGeneration;
    final verification = _store.verifyPassword(password);
    final sessionGeneration = _store.sessionGeneration;
    _pendingUnlockSessionGeneration = sessionGeneration;
    try {
      final isValid = await verification;
      _checkAuthenticationRequest(
        lifecycleGeneration: lifecycleGeneration,
        sessionGeneration: sessionGeneration,
        isCurrentRequest: requestGeneration == _unlockRequestGeneration,
      );
      if (isValid) {
        state = state.copyWith(isUnlocked: true);
      }
      return isValid;
    } finally {
      if (requestGeneration == _unlockRequestGeneration) {
        _pendingUnlockSessionGeneration = null;
      }
    }
  }

  Future<bool> confirmPassword(String password) async {
    final lifecycleGeneration = _lifecycleGeneration;
    final requestGeneration = ++_confirmRequestGeneration;
    final sessionGeneration = _store.sessionGeneration;
    if (!isWalletPasswordValid(password)) {
      return false;
    }
    final isValid = await _store.verifyPasswordOnly(password);
    _checkAuthenticationRequest(
      lifecycleGeneration: lifecycleGeneration,
      sessionGeneration: sessionGeneration,
      isCurrentRequest: requestGeneration == _confirmRequestGeneration,
    );
    return isValid;
  }

  void _checkAuthenticationRequest({
    required int lifecycleGeneration,
    required int sessionGeneration,
    required bool isCurrentRequest,
  }) {
    if (_store.enforcesSessionGeneration &&
        (lifecycleGeneration != _lifecycleGeneration ||
            !_store.isSessionGenerationCurrent(sessionGeneration) ||
            !isCurrentRequest)) {
      throw const SecureStorageSessionChangedException();
    }
  }

  String requireSessionPasswordForNativeSecretUse() {
    return _store.requireSessionPasswordForNativeSecretUse();
  }

  /// Changes the wallet password without using the setup path. The store must
  /// rotate encrypted secure-storage payloads before the verifier is updated.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => ref
      .read(linuxKeyringCoordinatorProvider)
      .runMutation(
        () => _changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        ),
      );

  Future<bool> _changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final lifecycleGeneration = _lifecycleGeneration;
    final unlockRequestGeneration = _unlockRequestGeneration;
    final sessionGeneration = _store.sessionGeneration;
    if (!state.isUnlocked) {
      throw StateError('Wallet must be unlocked to change the password.');
    }
    if (currentPassword == newPassword) {
      throw ArgumentError(kWalletPasswordMustDifferMessage);
    }
    final newPasswordError = validateRequiredWalletPassword(newPassword);
    if (newPasswordError != null) {
      throw ArgumentError(newPasswordError);
    }
    await ref.read(passwordChangePreflightProvider)();
    _checkAuthenticationRequest(
      lifecycleGeneration: lifecycleGeneration,
      sessionGeneration: sessionGeneration,
      isCurrentRequest: unlockRequestGeneration == _unlockRequestGeneration,
    );
    final didChange = await _store.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    // A committed rotation still succeeds after locking, but must not reopen
    // the session. The store only installs the new password for its own session.
    if (didChange &&
        (!_store.enforcesSessionGeneration ||
            (lifecycleGeneration == _lifecycleGeneration &&
                unlockRequestGeneration == _unlockRequestGeneration &&
                _store.hasSessionPassword))) {
      state = state.copyWith(isPasswordConfigured: true, isUnlocked: true);
    }
    return didChange;
  }

  void lock() {
    _unlockRequestGeneration++;
    _confirmRequestGeneration++;
    _store.clearSessionPassword();
    state = state.copyWith(isUnlocked: false);
  }

  void reset() {
    _unlockRequestGeneration++;
    _confirmRequestGeneration++;
    _isPasswordSetupPrepared = false;
    _passwordSetupSessionGeneration = null;
    _requiresWalletSetupRecovery = false;
    _store.clearSessionPassword();
    state = const AppSecurityState(
      isPasswordConfigured: false,
      isUnlocked: false,
    );
  }
}

final appSecurityProvider =
    NotifierProvider<AppSecurityNotifier, AppSecurityState>(
      AppSecurityNotifier.new,
    );
