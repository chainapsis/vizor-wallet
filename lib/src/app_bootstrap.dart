import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../main.dart' show log;
import 'core/profile_pictures.dart';
import 'core/config/rpc_endpoint_config.dart';
import 'core/storage/app_secure_store.dart';
import 'core/storage/wallet_paths.dart';
import 'providers/account_models.dart';
import 'rust/api/sync.dart' as rust_sync;
import 'rust/api/wallet.dart' as rust_wallet;

const _accountsKey = 'zcash_accounts';
const _activeAccountKey = 'zcash_active_account';
const _networkKey = 'zcash_wallet_network';
const _backgroundSyncChannel = MethodChannel(
  'com.zcash.wallet/background_sync',
);

final appBootstrapProvider = Provider<AppBootstrapState>((_) {
  throw StateError('appBootstrapProvider must be overridden in main()');
});

class AppBootstrapState {
  const AppBootstrapState({
    required this.initialLocation,
    required this.initialAccountState,
    required this.initialSyncSnapshot,
    required this.network,
    required this.rpcEndpointConfig,
    required this.themeMode,
    required this.privacyModeEnabled,
    required this.isPasswordConfigured,
    required this.isUnlocked,
    required this.passwordRotationRecoveryFailed,
  });

  final String initialLocation;
  final AccountState initialAccountState;
  final AppSyncSnapshot initialSyncSnapshot;
  final String network;
  final RpcEndpointConfig rpcEndpointConfig;
  final ThemeMode themeMode;
  final bool privacyModeEnabled;
  final bool isPasswordConfigured;
  final bool isUnlocked;
  final bool passwordRotationRecoveryFailed;

  bool get hasWallet => initialAccountState.hasAccounts;
  bool get requiresUnlock => hasWallet && !isUnlocked;

  static final empty = AppBootstrapState(
    initialLocation: '/welcome',
    initialAccountState: AccountState(),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: 'main',
    rpcEndpointConfig: defaultRpcEndpointConfig('main'),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: false,
    isUnlocked: false,
    passwordRotationRecoveryFailed: false,
  );
}

class AppSyncSnapshot {
  const AppSyncSnapshot({
    this.accountUuid,
    this.hasAccountScopedData = false,
    required this.scannedHeight,
    required this.chainTipHeight,
    required this.percentage,
    required this.transparentBalance,
    required this.saplingBalance,
    required this.orchardBalance,
    required this.transparentPendingBalance,
    required this.saplingPendingBalance,
    required this.orchardPendingBalance,
    required this.canShieldTransparentBalance,
    required this.shieldTransparentFee,
    required this.shieldTransparentAmount,
    required this.spendableBalance,
    required this.totalBalance,
    required this.recentTransactions,
  });

  final String? accountUuid;
  final bool hasAccountScopedData;
  final int scannedHeight;
  final int chainTipHeight;
  final double percentage;
  final BigInt transparentBalance;
  final BigInt saplingBalance;
  final BigInt orchardBalance;
  final BigInt transparentPendingBalance;
  final BigInt saplingPendingBalance;
  final BigInt orchardPendingBalance;
  final bool canShieldTransparentBalance;
  final BigInt shieldTransparentFee;
  final BigInt shieldTransparentAmount;
  final BigInt spendableBalance;
  final BigInt totalBalance;
  final List<rust_sync.TransactionInfo> recentTransactions;

  static final empty = AppSyncSnapshot(
    scannedHeight: 0,
    chainTipHeight: 0,
    percentage: 0,
    transparentBalance: BigInt.zero,
    saplingBalance: BigInt.zero,
    orchardBalance: BigInt.zero,
    transparentPendingBalance: BigInt.zero,
    saplingPendingBalance: BigInt.zero,
    orchardPendingBalance: BigInt.zero,
    canShieldTransparentBalance: false,
    shieldTransparentFee: BigInt.zero,
    shieldTransparentAmount: BigInt.zero,
    spendableBalance: BigInt.zero,
    totalBalance: BigInt.zero,
    recentTransactions: [],
  );

  static AppSyncSnapshot emptyForAccount(String accountUuid) => AppSyncSnapshot(
    accountUuid: accountUuid,
    scannedHeight: 0,
    chainTipHeight: 0,
    percentage: 0,
    transparentBalance: BigInt.zero,
    saplingBalance: BigInt.zero,
    orchardBalance: BigInt.zero,
    transparentPendingBalance: BigInt.zero,
    saplingPendingBalance: BigInt.zero,
    orchardPendingBalance: BigInt.zero,
    canShieldTransparentBalance: false,
    shieldTransparentFee: BigInt.zero,
    shieldTransparentAmount: BigInt.zero,
    spendableBalance: BigInt.zero,
    totalBalance: BigInt.zero,
    recentTransactions: [],
  );
}

Future<AppBootstrapState> loadAppBootstrap() async {
  final storage = AppSecureStore.instance;

  try {
    log('bootstrap: loading startup snapshot');
    await storage.ensureWalletDbName();
    var passwordRotationRecoveryFailed = false;
    try {
      await storage.recoverInterruptedPasswordRotation();
    } on PasswordRotationRecoveryFailedException catch (e) {
      // Fail open so the user can still try either password, but keep the
      // sticky journal visible to the UI instead of silently clearing it.
      passwordRotationRecoveryFailed = true;
      log('bootstrap: unsafe password rotation recovery state: $e');
    } catch (e) {
      log('bootstrap: failed to recover password rotation: $e');
    }
    final network = await storage.readString(_networkKey) ?? 'main';
    final rpcEndpointConfig = await _readRpcEndpointConfig(storage, network);
    await _seedNativeRpcEndpointMirror(rpcEndpointConfig);
    final themeMode = await _readThemeMode(storage);
    final privacyModeEnabled = await _readPrivacyModeEnabled(storage);
    final isPasswordConfigured = await storage.isPasswordConfigured();
    final isUnlocked = storage.hasSessionPassword;
    final dbPath = await _getDbPath();
    final storedAccounts = await _readStoredAccounts(storage);
    final storedAccountsByUuid = {
      for (final account in storedAccounts) account.uuid: account,
    };
    final storedActiveUuid = await storage.readString(_activeAccountKey);

    var rustAccounts = <AccountInfo>[];
    final rustAddressesByUuid = <String, String>{};
    if (rust_wallet.walletExists(dbPath: dbPath)) {
      try {
        final listed = await rust_wallet.listAccounts(
          dbPath: dbPath,
          network: network,
        );
        rustAccounts = listed.indexed.map((entry) {
          final (index, account) = entry;
          rustAddressesByUuid[account.uuid] = account.unifiedAddress;
          final stored = storedAccountsByUuid[account.uuid];
          return mergeBootstrappedAccountInfo(
            rustAccount: AccountInfo(
              uuid: account.uuid,
              name: account.name,
              order: index,
            ),
            storedAccount: stored,
            order: index,
          );
        }).toList();
        log('bootstrap: rust accounts=${rustAccounts.length}');
      } catch (e) {
        log('bootstrap: failed to list Rust accounts: $e');
      }
    }

    final accounts = rustAccounts.isNotEmpty ? rustAccounts : storedAccounts;
    final activeAccountUuid = _resolveActiveUuid(storedActiveUuid, accounts);
    final activeAddress = !isUnlocked || activeAccountUuid == null
        ? null
        : rustAddressesByUuid[activeAccountUuid];
    final hasWallet = accounts.isNotEmpty;
    var initialSyncSnapshot = AppSyncSnapshot.empty;

    if (isUnlocked &&
        hasWallet &&
        activeAccountUuid != null &&
        rust_wallet.walletExists(dbPath: dbPath)) {
      initialSyncSnapshot = await _loadInitialSyncSnapshot(
        dbPath: dbPath,
        network: network,
        accountUuid: activeAccountUuid,
        isHardwareAccount: accounts.any(
          (account) => account.uuid == activeAccountUuid && account.isHardware,
        ),
      );
    }

    final initialLocation = !hasWallet
        ? '/welcome'
        : !isUnlocked
        ? '/unlock'
        : '/home';

    log(
      'bootstrap: hasWallet=$hasWallet, passwordConfigured=$isPasswordConfigured, '
      'unlocked=$isUnlocked, initialLocation=$initialLocation',
    );

    return AppBootstrapState(
      initialLocation: initialLocation,
      initialAccountState: AccountState(
        accounts: accounts,
        activeAccountUuid: activeAccountUuid,
        activeAddress: activeAddress,
      ),
      initialSyncSnapshot: initialSyncSnapshot,
      network: network,
      rpcEndpointConfig: rpcEndpointConfig,
      themeMode: themeMode,
      privacyModeEnabled: privacyModeEnabled,
      isPasswordConfigured: isPasswordConfigured,
      isUnlocked: isUnlocked,
      passwordRotationRecoveryFailed: passwordRotationRecoveryFailed,
    );
  } catch (e) {
    log('bootstrap: failed, falling back to welcome: $e');
    return AppBootstrapState.empty;
  }
}

@visibleForTesting
AccountInfo mergeBootstrappedAccountInfo({
  required AccountInfo rustAccount,
  required AccountInfo? storedAccount,
  required int order,
}) {
  // Rust is authoritative for account existence/address. Dart secure storage
  // owns UI metadata that Rust does not update, so preserve it across relaunch.
  return AccountInfo(
    uuid: rustAccount.uuid,
    name: storedAccount?.name ?? rustAccount.name,
    order: order,
    isHardware: storedAccount?.isHardware ?? false,
    profilePictureId:
        storedAccount?.profilePictureId ?? kDefaultProfilePictureId,
  );
}

Future<void> _seedNativeRpcEndpointMirror(RpcEndpointConfig endpoint) async {
  if (!Platform.isIOS) return;
  try {
    final success = await _backgroundSyncChannel
        .invokeMethod<bool>('updateEndpoint', {
          'lightwalletdUrl': endpoint.normalizedLightwalletdUrl,
          'network': endpoint.networkName,
        });
    if (success != true) {
      log('bootstrap: iOS RPC endpoint mirror seed returned $success');
    }
  } catch (e) {
    log('bootstrap: failed to seed iOS RPC endpoint mirror: $e');
  }
}

Future<RpcEndpointConfig> _readRpcEndpointConfig(
  AppSecureStore storage,
  String network,
) async {
  try {
    final storedUrl = await storage.readString(kRpcEndpointUrlKey);
    final storedPreset = await storage.readString(kRpcEndpointPresetKey);
    if (storedUrl == null || storedUrl.trim().isEmpty) {
      return defaultRpcEndpointConfig(network);
    }

    return RpcEndpointConfig(
      networkName: zcashNetworkFromName(network).name,
      lightwalletdUrl: normalizeRpcEndpointUrl(
        storedUrl,
        allowDefaultPort: true,
      ),
      presetId: storedPreset == null || storedPreset.trim().isEmpty
          ? findRpcEndpointPresetByUrl(storedUrl, networkName: network)?.id
          : storedPreset,
    );
  } catch (e) {
    log('bootstrap: failed to read RPC endpoint: $e');
    return defaultRpcEndpointConfig(network);
  }
}

Future<ThemeMode> _readThemeMode(AppSecureStore storage) async {
  try {
    return _decodeThemeMode(await storage.readString(kThemeModeKey));
  } catch (e) {
    log('bootstrap: failed to read theme mode: $e');
    return ThemeMode.system;
  }
}

ThemeMode _decodeThemeMode(String? raw) {
  return switch (raw) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

Future<bool> _readPrivacyModeEnabled(AppSecureStore storage) async {
  try {
    return (await storage.readString(kPrivacyModeEnabledKey)) == 'true';
  } catch (e) {
    log('bootstrap: failed to read privacy mode: $e');
    return false;
  }
}

Future<List<AccountInfo>> _readStoredAccounts(AppSecureStore storage) async {
  final accountsJson = await storage.readString(_accountsKey);
  if (accountsJson == null || accountsJson.isEmpty) return const [];

  final List<dynamic> decoded = jsonDecode(accountsJson);
  return decoded
      .map((e) => AccountInfo.fromJson(e as Map<String, dynamic>))
      .toList();
}

String? _resolveActiveUuid(
  String? storedActiveUuid,
  List<AccountInfo> accounts,
) {
  if (accounts.isEmpty) return null;
  if (storedActiveUuid != null &&
      accounts.any((account) => account.uuid == storedActiveUuid)) {
    return storedActiveUuid;
  }
  return accounts.first.uuid;
}

Future<String> _getDbPath() async {
  return getWalletDbPath();
}

Future<AppSyncSnapshot> _loadInitialSyncSnapshot({
  required String dbPath,
  required String network,
  required String accountUuid,
  required bool isHardwareAccount,
}) async {
  try {
    final syncStatus = await rust_sync.getSyncStatus(
      dbPath: dbPath,
      network: network,
    );
    final balance = await rust_sync.getBalance(
      dbPath: dbPath,
      network: network,
      accountUuid: accountUuid,
    );
    final recentTransactions = await rust_sync.getTransactionHistory(
      dbPath: dbPath,
      network: network,
      limit: 10,
      accountUuid: accountUuid,
    );
    var canShieldTransparentBalance = false;
    var shieldTransparentFee = BigInt.zero;
    var shieldTransparentAmount = BigInt.zero;
    if (!isHardwareAccount && balance.transparent > BigInt.zero) {
      try {
        final shieldStatus = await rust_sync.getShieldTransparentStatus(
          dbPath: dbPath,
          network: network,
          accountUuid: accountUuid,
        );
        canShieldTransparentBalance = shieldStatus.canShield;
        shieldTransparentFee = shieldStatus.feeZatoshi;
        shieldTransparentAmount = shieldStatus.shieldedZatoshi;
      } catch (e) {
        log('bootstrap: failed to load shield transparent status: $e');
      }
    }
    final scannedHeight = syncStatus.scannedHeight.toInt();
    final chainTipHeight = syncStatus.chainTipHeight.toInt();
    final percentage = chainTipHeight == 0
        ? 0.0
        : (scannedHeight / chainTipHeight).clamp(0.0, 1.0);

    log(
      'bootstrap: loaded initial sync snapshot '
      '(scanned=$scannedHeight, tip=$chainTipHeight, txs=${recentTransactions.length})',
    );

    return AppSyncSnapshot(
      accountUuid: accountUuid,
      hasAccountScopedData: true,
      scannedHeight: scannedHeight,
      chainTipHeight: chainTipHeight,
      percentage: percentage,
      transparentBalance: balance.transparent,
      saplingBalance: balance.sapling,
      orchardBalance: balance.orchard,
      transparentPendingBalance: balance.transparentPending,
      saplingPendingBalance: balance.saplingPending,
      orchardPendingBalance: balance.orchardPending,
      canShieldTransparentBalance: canShieldTransparentBalance,
      shieldTransparentFee: shieldTransparentFee,
      shieldTransparentAmount: shieldTransparentAmount,
      spendableBalance: balance.spendable,
      totalBalance: balance.total,
      recentTransactions: recentTransactions,
    );
  } catch (e) {
    log('bootstrap: failed to load initial sync snapshot: $e');
    return AppSyncSnapshot.emptyForAccount(accountUuid);
  }
}
