import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../main.dart' show log;
import '../core/config/network_config.dart';
import '../rust/api/wallet.dart' as rust_wallet;

const _accountsKey = 'zcash_accounts';
const _activeAccountKey = 'zcash_active_account';
const _networkKey = 'zcash_wallet_network';

class AccountInfo {
  final String uuid;
  final String name;
  final int order;

  const AccountInfo({required this.uuid, required this.name, required this.order});

  Map<String, dynamic> toJson() => {'uuid': uuid, 'name': name, 'order': order};

  factory AccountInfo.fromJson(Map<String, dynamic> json) => AccountInfo(
    uuid: json['uuid'] as String,
    name: json['name'] as String,
    order: json['order'] as int? ?? 0,
  );
}

class AccountState {
  final List<AccountInfo> accounts;
  final String? activeAccountUuid;
  final String? activeAddress;

  const AccountState({
    this.accounts = const [],
    this.activeAccountUuid,
    this.activeAddress,
  });

  bool get hasAccounts => accounts.isNotEmpty;

  AccountInfo? get activeAccount {
    if (activeAccountUuid == null) return null;
    try {
      return accounts.firstWhere((a) => a.uuid == activeAccountUuid);
    } catch (_) {
      return null;
    }
  }

  AccountState copyWith({
    List<AccountInfo>? accounts,
    String? activeAccountUuid,
    String? activeAddress,
  }) => AccountState(
    accounts: accounts ?? this.accounts,
    activeAccountUuid: activeAccountUuid ?? this.activeAccountUuid,
    activeAddress: activeAddress ?? this.activeAddress,
  );
}

class AccountNotifier extends AsyncNotifier<AccountState> {
  static const _storage = FlutterSecureStorage();

  @override
  Future<AccountState> build() async {
    log('AccountNotifier.build: starting');

    // Load account list from secure storage
    final accountsJson = await _storage.read(key: _accountsKey);
    if (accountsJson == null || accountsJson.isEmpty) {
      log('AccountNotifier.build: no accounts found');
      return const AccountState();
    }

    final List<dynamic> decoded = jsonDecode(accountsJson);
    final accounts = decoded.map((e) => AccountInfo.fromJson(e as Map<String, dynamic>)).toList();
    final activeUuid = await _storage.read(key: _activeAccountKey);

    // Resolve active account address
    String? address;
    final effectiveUuid = activeUuid ?? (accounts.isNotEmpty ? accounts.first.uuid : null);
    if (effectiveUuid != null) {
      try {
        final dbPath = await _getDbPath();
        final network = await _getNetwork();
        address = await rust_wallet.getUnifiedAddress(
          dbPath: dbPath, network: network, accountUuid: effectiveUuid,
        );
        log('AccountNotifier.build: active=$effectiveUuid, address=${address.substring(0, 20)}...');
      } catch (e) {
        log('AccountNotifier.build: failed to get address: $e');
      }
    }

    return AccountState(
      accounts: accounts,
      activeAccountUuid: effectiveUuid,
      activeAddress: address,
    );
  }

  /// Create a new wallet with a fresh mnemonic. Returns the mnemonic.
  Future<String> createAccount({String? name}) async {
    final dbPath = await _getDbPath();
    final network = await _getNetwork();
    final networkConfig = network == 'main' ? ZcashNetwork.mainnet : ZcashNetwork.testnet;

    // Fetch chain tip as birthday
    final birthday = await rust_wallet.getLatestBlockHeight(
      lightwalletdUrl: networkConfig.lightwalletdUrl,
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
        network: network, dbPath: dbPath, birthdayHeight: birthday,
      );
      mnemonic = result.mnemonic;
      accountUuid = result.accountUuid;
      unifiedAddress = result.unifiedAddress;
      await _storage.write(key: _networkKey, value: network);
    } else {
      // Additional account — generate mnemonic + add to existing DB
      mnemonic = rust_wallet.generateMnemonic();
      final result = await rust_wallet.addAccount(
        dbPath: dbPath, network: network, name: accountName,
        mnemonic: mnemonic, birthdayHeight: birthday,
      );
      accountUuid = result.accountUuid;
      unifiedAddress = result.unifiedAddress;
    }

    // Store mnemonic per-account
    await _storage.write(key: 'zcash_account_mnemonic_$accountUuid', value: mnemonic);

    // Update account list
    final newAccount = AccountInfo(uuid: accountUuid, name: accountName, order: accounts.length);
    final updatedAccounts = [...accounts, newAccount];
    await _saveAccounts(updatedAccounts);
    await _storage.write(key: _activeAccountKey, value: accountUuid);

    state = AsyncData(AccountState(
      accounts: updatedAccounts,
      activeAccountUuid: accountUuid,
      activeAddress: unifiedAddress,
    ));

    log('createAccount: success, uuid=$accountUuid');
    return mnemonic;
  }

  /// Import a wallet from mnemonic.
  Future<void> importAccount({
    required String mnemonic,
    int? birthdayHeight,
    String? name,
  }) async {
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
        birthdayHeight: birthdayHeight != null ? BigInt.from(birthdayHeight) : null,
        network: network, dbPath: dbPath,
      );
      accountUuid = result.accountUuid;
      unifiedAddress = result.unifiedAddress;
      await _storage.write(key: _networkKey, value: network);
    } else {
      // Additional account
      final result = await rust_wallet.addAccount(
        dbPath: dbPath, network: network, name: accountName,
        mnemonic: mnemonic,
        birthdayHeight: birthdayHeight != null ? BigInt.from(birthdayHeight) : null,
      );
      accountUuid = result.accountUuid;
      unifiedAddress = result.unifiedAddress;
    }

    await _storage.write(key: 'zcash_account_mnemonic_$accountUuid', value: mnemonic);

    final newAccount = AccountInfo(uuid: accountUuid, name: accountName, order: accounts.length);
    final updatedAccounts = [...accounts, newAccount];
    await _saveAccounts(updatedAccounts);
    await _storage.write(key: _activeAccountKey, value: accountUuid);

    state = AsyncData(AccountState(
      accounts: updatedAccounts,
      activeAccountUuid: accountUuid,
      activeAddress: unifiedAddress,
    ));

    log('importAccount: success, uuid=$accountUuid');
  }

  /// Switch active account.
  Future<void> switchAccount(String uuid) async {
    await _storage.write(key: _activeAccountKey, value: uuid);

    String? address;
    try {
      final dbPath = await _getDbPath();
      final network = await _getNetwork();
      address = await rust_wallet.getUnifiedAddress(
        dbPath: dbPath, network: network, accountUuid: uuid,
      );
    } catch (e) {
      log('switchAccount: failed to get address: $e');
    }

    final prev = state.value ?? const AccountState();
    state = AsyncData(prev.copyWith(
      activeAccountUuid: uuid,
      activeAddress: address,
    ));

    log('switchAccount: switched to $uuid');
  }

  /// Rename an account.
  Future<void> renameAccount(String uuid, String newName) async {
    final prev = state.value ?? const AccountState();
    final updated = prev.accounts.map((a) =>
      a.uuid == uuid ? AccountInfo(uuid: a.uuid, name: newName, order: a.order) : a
    ).toList();
    await _saveAccounts(updated);
    state = AsyncData(prev.copyWith(accounts: updated));
    log('renameAccount: $uuid → $newName');
  }

  /// Get the mnemonic for the active account.
  Future<String?> getActiveMnemonic() async {
    final uuid = state.value?.activeAccountUuid;
    if (uuid == null) return null;
    return _storage.read(key: 'zcash_account_mnemonic_$uuid');
  }

  // ======================== Helpers ========================

  Future<void> _saveAccounts(List<AccountInfo> accounts) async {
    final json = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await _storage.write(key: _accountsKey, value: json);
  }

  Future<String> _getDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}${Platform.pathSeparator}zcash_wallet.db';
  }

  Future<String> _getNetwork() async {
    return await _storage.read(key: _networkKey) ?? 'main';
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

final accountProvider =
    AsyncNotifierProvider<AccountNotifier, AccountState>(AccountNotifier.new);
