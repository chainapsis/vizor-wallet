import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/security/password_policy.dart';
import '../core/storage/app_secure_store.dart';
import '../core/storage/wallet_paths.dart';
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
  static final _store = AppSecureStore.instance;
  bool _isPasswordSetupPrepared = false;

  @override
  AppSecurityState build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    return AppSecurityState(
      isPasswordConfigured: bootstrap.isPasswordConfigured,
      isUnlocked: bootstrap.isUnlocked,
    );
  }

  Future<void> configurePassword(String password) async {
    await preparePasswordSetup(password);
    commitPasswordSetup();
  }

  Future<void> preparePasswordSetup(String password) async {
    if (state.isPasswordConfigured) {
      throw StateError('Password is already configured.');
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
    _isPasswordSetupPrepared = true;
  }

  void commitPasswordSetup() {
    if (!_isPasswordSetupPrepared) {
      throw StateError('Password setup was not prepared.');
    }
    _isPasswordSetupPrepared = false;
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
  }

  Future<void> rollbackPasswordSetup() async {
    if (!_isPasswordSetupPrepared) return;
    _isPasswordSetupPrepared = false;
    await _store.clearPasswordConfiguration();
  }

  Future<bool> unlock(String password) async {
    if (!isWalletPasswordValid(password)) {
      return false;
    }
    final isValid = await _store.verifyPassword(password);
    if (isValid) {
      state = state.copyWith(isUnlocked: true);
    }
    return isValid;
  }

  Future<bool> confirmPassword(String password) async {
    if (!isWalletPasswordValid(password)) {
      return false;
    }
    return _store.verifyPasswordOnly(password);
  }

  String requireSessionPasswordForNativeSecretUse() {
    return _store.requireSessionPasswordForNativeSecretUse();
  }

  /// Changes the wallet password without using the setup path. The store must
  /// rotate encrypted secure-storage payloads before the verifier is updated.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
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
    final didChange = await _store.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    if (didChange) {
      state = state.copyWith(isPasswordConfigured: true, isUnlocked: true);
    }
    return didChange;
  }

  void lock() {
    _store.clearSessionPassword();
    state = state.copyWith(isUnlocked: false);
  }

  void reset() {
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
