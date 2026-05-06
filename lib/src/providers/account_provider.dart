import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../app_bootstrap.dart';
import '../core/config/network_config.dart';
import '../core/profile_pictures.dart';
import '../core/storage/app_secure_store.dart';
import '../core/storage/wallet_paths.dart';
import '../rust/api/wallet.dart' as rust_wallet;
import 'account_models.dart';
import 'app_security_provider.dart';
import 'rpc_endpoint_provider.dart';

export 'account_models.dart';

const _accountsKey = 'zcash_accounts';
const _activeAccountKey = 'zcash_active_account';
const _networkKey = 'zcash_wallet_network';

class AccountNotifier extends AsyncNotifier<AccountState> {
  static final _storage = AppSecureStore.instance;

  @override
  FutureOr<AccountState> build() {
    final bootstrap = ref.watch(appBootstrapProvider);
    log(
      'AccountNotifier.build: bootstrapped accounts=${bootstrap.initialAccountState.accounts.length}',
    );
    return bootstrap.initialAccountState;
  }

  /// Create a new wallet with a fresh mnemonic. Returns the mnemonic.
  Future<String> createAccount({String? name}) async {
    try {
      final dbPath = await _getDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final network = endpoint.networkName;

      // Fetch chain tip as birthday
      final birthday = await rust_wallet.getLatestBlockHeight(
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      );
      log('createAccount: birthday=$birthday');

      final accounts = state.value?.accounts ?? [];
      final accountName = name ?? 'Account ${accounts.length + 1}';

      String mnemonic;
      String accountUuid;
      String unifiedAddress;

      if (accounts.isEmpty) {
        // First account — create wallet (init DB + create account)
        await _deleteExistingDb(dbPath);
        final result = await rust_wallet.createWallet(
          network: network,
          dbPath: dbPath,
          birthdayHeight: birthday,
          accountName: accountName,
        );
        mnemonic = result.mnemonic;
        accountUuid = result.accountUuid;
        unifiedAddress = result.unifiedAddress;
        await _storage.writeString(_networkKey, network);
      } else {
        // Additional account — generate mnemonic + add to existing DB
        mnemonic = rust_wallet.generateMnemonic();
        final result = await rust_wallet.addAccount(
          dbPath: dbPath,
          network: network,
          name: accountName,
          mnemonic: mnemonic,
          birthdayHeight: birthday,
        );
        accountUuid = result.accountUuid;
        unifiedAddress = result.unifiedAddress;
      }

      // Store mnemonic per-account
      await _storage.writeSecretString(
        'zcash_account_mnemonic_$accountUuid',
        mnemonic,
      );

      // Update account list
      final newAccount = AccountInfo(
        uuid: accountUuid,
        name: accountName,
        order: accounts.length,
      );
      final updatedAccounts = [...accounts, newAccount];
      await _saveAccounts(updatedAccounts);
      await _storage.writeString(_activeAccountKey, accountUuid);

      state = AsyncData(
        AccountState(
          accounts: updatedAccounts,
          activeAccountUuid: accountUuid,
          activeAddress: unifiedAddress,
        ),
      );

      log('createAccount: success, uuid=$accountUuid');
      return mnemonic;
    } catch (e, st) {
      log('createAccount: ERROR: $e\n$st');
      rethrow;
    }
  }

  /// Create a new wallet/account from a caller-provided mnemonic.
  ///
  /// Used by onboarding flows that reveal the phrase before persisting the
  /// account. The mnemonic is only stored after the user confirms the final
  /// CTA, so the wallet is not created just by visiting the reveal screen.
  Future<void> createAccountFromMnemonic({
    required String mnemonic,
    String? name,
  }) async {
    try {
      final dbPath = await _getDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final network = endpoint.networkName;

      final birthday = await rust_wallet.getLatestBlockHeight(
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      );
      log('createAccountFromMnemonic: birthday=$birthday');

      final accounts = state.value?.accounts ?? [];
      final accountName = name ?? 'Account ${accounts.length + 1}';

      late final String accountUuid;
      late final String unifiedAddress;

      if (accounts.isEmpty) {
        await _deleteExistingDb(dbPath);
        final result = await rust_wallet.importWallet(
          mnemonic: mnemonic,
          birthdayHeight: birthday,
          network: network,
          dbPath: dbPath,
          accountName: accountName,
        );
        accountUuid = result.accountUuid;
        unifiedAddress = result.unifiedAddress;
        await _storage.writeString(_networkKey, network);
      } else {
        final result = await rust_wallet.addAccount(
          dbPath: dbPath,
          network: network,
          name: accountName,
          mnemonic: mnemonic,
          birthdayHeight: birthday,
        );
        accountUuid = result.accountUuid;
        unifiedAddress = result.unifiedAddress;
      }

      await _storage.writeSecretString(
        'zcash_account_mnemonic_$accountUuid',
        mnemonic,
      );

      final newAccount = AccountInfo(
        uuid: accountUuid,
        name: accountName,
        order: accounts.length,
      );
      final updatedAccounts = [...accounts, newAccount];
      await _saveAccounts(updatedAccounts);
      await _storage.writeString(_activeAccountKey, accountUuid);

      state = AsyncData(
        AccountState(
          accounts: updatedAccounts,
          activeAccountUuid: accountUuid,
          activeAddress: unifiedAddress,
        ),
      );

      log('createAccountFromMnemonic: success, uuid=$accountUuid');
    } catch (e, st) {
      log('createAccountFromMnemonic: ERROR: $e\n$st');
      rethrow;
    }
  }

  /// Import a wallet from mnemonic.
  Future<void> importAccount({
    required String mnemonic,
    int? birthdayHeight,
    String? name,
  }) async {
    try {
      final dbPath = await _getDbPath();
      final network = await _getNetwork();
      final accounts = state.value?.accounts ?? [];
      final accountName = name ?? 'Account ${accounts.length + 1}';

      String accountUuid;
      String unifiedAddress;

      if (accounts.isEmpty) {
        // First account — import wallet (init DB + import)
        await _deleteExistingDb(dbPath);
        final result = await rust_wallet.importWallet(
          mnemonic: mnemonic,
          birthdayHeight: birthdayHeight != null
              ? BigInt.from(birthdayHeight)
              : null,
          network: network,
          dbPath: dbPath,
          accountName: accountName,
        );
        accountUuid = result.accountUuid;
        unifiedAddress = result.unifiedAddress;
        await _storage.writeString(_networkKey, network);
      } else {
        // Additional account
        final result = await rust_wallet.addAccount(
          dbPath: dbPath,
          network: network,
          name: accountName,
          mnemonic: mnemonic,
          birthdayHeight: birthdayHeight != null
              ? BigInt.from(birthdayHeight)
              : null,
        );
        accountUuid = result.accountUuid;
        unifiedAddress = result.unifiedAddress;
      }

      await _storage.writeSecretString(
        'zcash_account_mnemonic_$accountUuid',
        mnemonic,
      );

      final newAccount = AccountInfo(
        uuid: accountUuid,
        name: accountName,
        order: accounts.length,
      );
      final updatedAccounts = [...accounts, newAccount];
      await _saveAccounts(updatedAccounts);
      await _storage.writeString(_activeAccountKey, accountUuid);

      state = AsyncData(
        AccountState(
          accounts: updatedAccounts,
          activeAccountUuid: accountUuid,
          activeAddress: unifiedAddress,
        ),
      );

      log('importAccount: success, uuid=$accountUuid');
    } catch (e, st) {
      log('importAccount: ERROR: $e\n$st');
      rethrow;
    }
  }

  /// Switch active account.
  Future<void> switchAccount(String uuid) async {
    await _storage.writeString(_activeAccountKey, uuid);

    String? address;
    try {
      final dbPath = await _getDbPath();
      final network = await _getNetwork();
      address = await rust_wallet.getUnifiedAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: uuid,
      );
    } catch (e) {
      log('switchAccount: failed to get address: $e');
    }

    final prev = state.value ?? const AccountState();
    state = AsyncData(
      prev.copyWith(activeAccountUuid: uuid, activeAddress: address),
    );

    log('switchAccount: switched to $uuid');
  }

  /// Rename an account.
  Future<void> renameAccount(String uuid, String newName) async {
    final prev = state.value ?? const AccountState();
    final updated = prev.accounts
        .map((a) => a.uuid == uuid ? a.copyWith(name: newName) : a)
        .toList();
    await _saveAccounts(updated);
    state = AsyncData(prev.copyWith(accounts: updated));
    log('renameAccount: $uuid → $newName');
  }

  /// Update an account profile picture.
  Future<void> updateProfilePicture(
    String uuid,
    String profilePictureId,
  ) async {
    if (!isKnownProfilePictureId(profilePictureId)) {
      throw ArgumentError.value(
        profilePictureId,
        'profilePictureId',
        'Unknown profile picture id',
      );
    }

    final prev = state.value ?? const AccountState();
    final updated = prev.accounts
        .map(
          (a) => a.uuid == uuid
              ? a.copyWith(profilePictureId: profilePictureId)
              : a,
        )
        .toList();
    await _saveAccounts(updated);
    state = AsyncData(prev.copyWith(accounts: updated));
    log('updateProfilePicture: $uuid → $profilePictureId');
  }

  /// Delete all wallet data (DB + keychain). Caller must stop sync first.
  Future<void> resetWallet() async {
    final dbPath = await _getDbPath();
    _deleteExistingDb(dbPath);
    await _storage.deleteAll();
    ref.read(appSecurityProvider.notifier).reset();
    state = const AsyncData(AccountState());
    log('resetWallet: all data cleared');
  }

  void clearSensitiveStateForLock() {
    final prev = state.value ?? const AccountState();
    state = AsyncData(
      AccountState(
        accounts: prev.accounts,
        activeAccountUuid: prev.activeAccountUuid,
      ),
    );
    log('AccountNotifier: cleared in-memory address state for lock');
  }

  Future<void> restoreAfterUnlock() async {
    final prev = state.value ?? const AccountState();
    final accountUuid = prev.activeAccountUuid;
    if (accountUuid == null) return;

    String? address;
    try {
      final dbPath = await _getDbPath();
      final network = await _getNetwork();
      address = await rust_wallet.getUnifiedAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: accountUuid,
      );
    } catch (e) {
      log('restoreAfterUnlock: failed to get address: $e');
    }

    state = AsyncData(
      AccountState(
        accounts: prev.accounts,
        activeAccountUuid: prev.activeAccountUuid,
        activeAddress: address,
      ),
    );
  }

  void updateActiveAddressForAccount(String accountUuid, String address) {
    final prev = state.value ?? const AccountState();
    if (prev.activeAccountUuid != accountUuid) return;

    state = AsyncData(prev.copyWith(activeAddress: address));
    log('AccountNotifier: active address updated for $accountUuid');
  }

  /// Import a hardware wallet account using UFVK from Keystone.
  ///
  /// Hardware accounts cannot be the first account in a wallet. librustzcash
  /// refuses to apply seed-requiring database migrations to a DB that contains
  /// only Imported accounts (see `CLAUDE.md` → "Hardware-first wallet
  /// constraint"), so the first account in any wallet must be a software
  /// (Derived) account. If the user wants to use Keystone on a fresh install,
  /// they must first create or import a software wallet, then add Keystone on
  /// top of it. The Rust side of `import_hardware_account` enforces this as a
  /// backstop; the pre-check here just gives a cleaner error message.
  Future<void> importKeystoneAccount({
    required String name,
    required String ufvk,
    required List<int> seedFingerprint,
    required int zip32Index,
  }) async {
    try {
      final prev = state.value ?? const AccountState();
      if (prev.accounts.isEmpty) {
        throw Exception(
          'Keystone accounts cannot be the first account in a wallet. '
          'Please create or import a software wallet first, then add your '
          'Keystone account.',
        );
      }

      final dbPath = await _getDbPath();
      final network = await _getNetwork();

      final result = await rust_wallet.importHardwareAccount(
        dbPath: dbPath,
        network: network,
        name: name,
        ufvkString: ufvk,
        seedFingerprint: seedFingerprint,
        zip32Index: zip32Index,
        birthdayHeight: null,
      );
      final accountUuid = result.accountUuid;
      final address = result.unifiedAddress;

      // Save account info (no mnemonic — hardware wallet)
      final newAccount = AccountInfo(
        uuid: accountUuid,
        name: name,
        order: prev.accounts.length,
        isHardware: true,
      );
      final updated = [...prev.accounts, newAccount];
      await _saveAccounts(updated);
      await _storage.writeString(_activeAccountKey, accountUuid);

      state = AsyncData(
        AccountState(
          accounts: updated,
          activeAccountUuid: accountUuid,
          activeAddress: address,
        ),
      );
      log('importKeystoneAccount: uuid=$accountUuid, address=$address');
    } catch (e, st) {
      log('importKeystoneAccount: ERROR: $e\n$st');
      rethrow;
    }
  }

  /// Check if the active account is a hardware wallet account.
  bool get isActiveAccountHardware {
    final active = state.value?.activeAccount;
    return active?.isHardware ?? false;
  }

  /// Check if a specific account is a hardware wallet account.
  bool isHardwareAccount(String uuid) {
    final accounts = state.value?.accounts ?? const <AccountInfo>[];
    for (final account in accounts) {
      if (account.uuid == uuid) return account.isHardware;
    }
    return false;
  }

  /// Get the mnemonic for the active account.
  Future<String?> getActiveMnemonic() async {
    final uuid = state.value?.activeAccountUuid;
    if (uuid == null) return null;
    return _storage.readSecretStringWithOptions(
      'zcash_account_mnemonic_$uuid',
      requireUnlockedSession: true,
    );
  }

  /// Get the mnemonic for a specific account.
  Future<String?> getMnemonicForAccount(String uuid) async {
    return _storage.readSecretStringWithOptions(
      'zcash_account_mnemonic_$uuid',
      requireUnlockedSession: true,
    );
  }

  // ======================== Helpers ========================

  Future<void> _saveAccounts(List<AccountInfo> accounts) async {
    final json = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await _storage.writeString(_accountsKey, json);
  }

  Future<String> _getDbPath() async {
    return getWalletDbPath();
  }

  Future<String> _getNetwork() async {
    return resolveStoredOrDefaultZcashNetworkName(
      await _storage.readString(_networkKey),
    );
  }

  Future<void> _deleteExistingDb(String dbPath) async {
    final file = File(dbPath);
    if (file.existsSync()) file.deleteSync();
    for (final suffix in ['-journal', '-wal', '-shm']) {
      final f = File('$dbPath$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }
}

final accountProvider = AsyncNotifierProvider<AccountNotifier, AccountState>(
  AccountNotifier.new,
);
