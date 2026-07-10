import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart' show log;
import 'core/profile_pictures.dart';
import 'core/config/app_version_config.dart';
import 'core/config/rpc_endpoint_config.dart';
import 'core/config/swap_remote_enable_config.dart';
import 'core/storage/app_secure_store.dart';
import 'core/storage/wallet_paths.dart';
import 'providers/account_models.dart';
import 'rust/api/sync.dart' as rust_sync;
import 'rust/api/wallet.dart' as rust_wallet;

const _accountsKey = 'zcash_accounts';
const _activeAccountKey = 'zcash_active_account';
const _networkKey = 'zcash_wallet_network';
// Mirrors kBiometricUnlockEnabledKey in providers/biometric_unlock_provider.dart;
// kept local to avoid a bootstrap → provider import cycle.
const _biometricUnlockEnabledKey = 'zcash_biometric_unlock_enabled';
const _backgroundSyncChannel = MethodChannel(
  'com.zcash.wallet/background_sync',
);
const _e2eLightwalletdUrlOverride = String.fromEnvironment(
  'ZCASH_E2E_LIGHTWALLETD_URL',
);

final appBootstrapProvider = Provider<AppBootstrapState>((_) {
  throw StateError('appBootstrapProvider must be overridden in main()');
});

typedef AppBootstrapRetry = Future<void> Function();

final appBootstrapRetryProvider = Provider<AppBootstrapRetry>((_) {
  return () async {};
});

enum AppBootstrapFailureKind {
  secureStorageUnavailable,
  startupFailure,
  walletDbMigrationFailed,
}

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
    this.swapEnabledOverrideCachedForRelease = false,
    this.biometricUnlockEnabled = false,
    this.syncKeepAwakeEnabled = false,
    this.syncKeepAwakePromptSeen = false,
    this.failureKind,
    this.failureMessage,
  });

  final String initialLocation;
  final AccountState initialAccountState;
  final AppSyncSnapshot initialSyncSnapshot;
  final String network;
  final RpcEndpointConfig rpcEndpointConfig;
  final ThemeMode themeMode;
  final bool privacyModeEnabled;
  final bool swapEnabledOverrideCachedForRelease;
  final bool syncKeepAwakeEnabled;
  final bool syncKeepAwakePromptSeen;

  /// Whether biometric unlock was enabled at startup, read synchronously from
  /// secure storage. The unlock screen uses this to paint the biometric
  /// backdrop on the first frame before the async availability probe resolves.
  final bool biometricUnlockEnabled;
  final bool isPasswordConfigured;
  final bool isUnlocked;
  final bool passwordRotationRecoveryFailed;
  final AppBootstrapFailureKind? failureKind;
  final String? failureMessage;

  bool get hasWallet => initialAccountState.hasAccounts;
  bool get requiresUnlock => hasWallet && !isUnlocked;
  bool get hasBlockingFailure => failureKind != null;

  static final empty = AppBootstrapState(
    initialLocation: '/welcome',
    initialAccountState: AccountState(),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: kZcashDefaultNetworkName,
    rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: false,
    isUnlocked: false,
    passwordRotationRecoveryFailed: false,
  );

  static AppBootstrapState blocked({
    required AppBootstrapFailureKind failureKind,
    required String failureMessage,
  }) => AppBootstrapState(
    initialLocation: '/storage-unavailable',
    initialAccountState: AccountState(),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: kZcashDefaultNetworkName,
    rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
    themeMode: ThemeMode.system,
    privacyModeEnabled: false,
    isPasswordConfigured: false,
    isUnlocked: false,
    passwordRotationRecoveryFailed: false,
    failureKind: failureKind,
    failureMessage: failureMessage,
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
    await _applyE2eBootstrapOverrides(storage);
    var passwordRotationRecoveryFailed = false;
    try {
      await storage.recoverInterruptedPasswordRotation();
    } on PasswordRotationRecoveryFailedException catch (e) {
      // Fail open so the user can still try either password, but keep the
      // sticky journal visible to the UI instead of silently clearing it.
      passwordRotationRecoveryFailed = true;
      log('bootstrap: unsafe password rotation recovery state: $e');
    } on SecureStorageUnavailableException {
      rethrow;
    } catch (e) {
      log('bootstrap: failed to recover password rotation: $e');
    }
    final network = resolveStoredOrDefaultZcashNetworkName(
      await storage.readString(_networkKey),
    );
    final rpcEndpointConfig = await _readRpcEndpointConfig(storage, network);
    await _seedNativeRpcEndpointMirror(rpcEndpointConfig);
    final themeMode = await _readThemeMode(storage);
    final privacyModeEnabled = await _readPrivacyModeEnabled(storage);
    final swapEnabledOverrideCachedForRelease =
        await _readSwapEnabledOverrideCachedForRelease();
    final biometricUnlockEnabled = await _readBiometricUnlockEnabled(storage);
    final syncKeepAwakeEnabled = await _readPlainBool(
      storage,
      key: kSyncKeepAwakeEnabledKey,
      label: 'sync keep-awake enabled flag',
    );
    final syncKeepAwakePromptSeen = await _readPlainBool(
      storage,
      key: kSyncKeepAwakePromptSeenKey,
      label: 'sync keep-awake prompt seen flag',
    );
    final isPasswordConfigured = await storage.isPasswordConfigured();
    final isUnlocked = storage.hasSessionPassword;
    final dbPath = await _getDbPath();
    if (rust_wallet.walletExists(dbPath: dbPath)) {
      try {
        log('bootstrap: ensuring wallet DB migrations before startup snapshot');
        await rust_wallet.ensureWalletDbMigrated(
          dbPath: dbPath,
          network: network,
        );
      } catch (e) {
        log('bootstrap: wallet DB migration preflight failed: $e');
        return AppBootstrapState.blocked(
          failureKind: AppBootstrapFailureKind.walletDbMigrationFailed,
          failureMessage: _walletDbMigrationFailureMessage(e),
        );
      }
    }
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
              isHardware: account.isHardware,
              isSeedAnchor: account.isSeedAnchor,
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
      swapEnabledOverrideCachedForRelease: swapEnabledOverrideCachedForRelease,
      biometricUnlockEnabled: biometricUnlockEnabled,
      syncKeepAwakeEnabled: syncKeepAwakeEnabled,
      syncKeepAwakePromptSeen: syncKeepAwakePromptSeen,
      isPasswordConfigured: isPasswordConfigured,
      isUnlocked: isUnlocked,
      passwordRotationRecoveryFailed: passwordRotationRecoveryFailed,
    );
  } on SecureStorageUnavailableException catch (e) {
    log('bootstrap: secure storage unavailable: $e');
    return AppBootstrapState.blocked(
      failureKind: AppBootstrapFailureKind.secureStorageUnavailable,
      failureMessage:
          'Vizor needs access to secure storage before it can open your wallet.',
    );
  } catch (e) {
    log('bootstrap: failed, blocking startup: $e');
    return AppBootstrapState.blocked(
      failureKind: AppBootstrapFailureKind.startupFailure,
      failureMessage: 'Vizor could not load its startup state.',
    );
  }
}

String _walletDbMigrationFailureMessage(Object error) {
  final message = error.toString().toLowerCase();
  if (message.contains('seedrequired') ||
      message.contains('seed is required') ||
      message.contains('wallet seed is required')) {
    return 'This wallet requires a database update that cannot be completed automatically.';
  }
  if (message.contains('seednotrelevant') ||
      message.contains('seed is not relevant') ||
      message.contains('not relevant to any derived accounts')) {
    return 'The available wallet seed does not match the database update requirement.';
  }
  if (message.contains('sqlite') &&
      (message.contains('not supported') ||
          message.contains('database not supported'))) {
    return 'The local SQLite version cannot open this wallet database.';
  }
  return 'The wallet database update did not complete.';
}

Future<void> _applyE2eBootstrapOverrides(AppSecureStore storage) async {
  final lightwalletdUrl = _e2eLightwalletdUrlOverride.trim();
  if (lightwalletdUrl.isEmpty) return;

  if (!kDebugMode) {
    log('bootstrap: ignoring E2E overrides outside debug mode');
    return;
  }

  await storage.writePlain(kRpcEndpointUrlKey, lightwalletdUrl);
  await storage.writePlain(kRpcEndpointPresetKey, kCustomRpcEndpointPresetId);
  log(
    'bootstrap: applied E2E lightwalletd override '
    'lightwalletd=$lightwalletdUrl',
  );
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
    order: storedAccount?.order ?? order,
    // Rust can recover Keystone accounts when older stored metadata lost this bit.
    isHardware: (storedAccount?.isHardware ?? false) || rustAccount.isHardware,
    isSeedAnchor: rustAccount.isSeedAnchor,
    profilePictureId: normalizeProfilePictureId(
      storedAccount?.profilePictureId ?? kDefaultProfilePictureId,
    ),
    walletLinkSourceAccountUuid: storedAccount?.walletLinkSourceAccountUuid,
  );
}

Future<void> _seedNativeRpcEndpointMirror(RpcEndpointConfig endpoint) async {
  if (!Platform.isIOS) return;
  try {
    final success = await _backgroundSyncChannel
        .invokeMethod<bool>('updateEndpoint', {
          'lightwalletdUrl': endpoint.normalizedLightwalletdUrl,
          'network': endpoint.networkName,
          'presetId': endpoint.effectivePresetId,
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
    return resolveStoredRpcEndpointConfig(
      networkName: zcashNetworkFromName(network).name,
      storedUrl: storedUrl,
      storedPresetId: storedPreset,
    );
  } on SecureStorageUnavailableException {
    rethrow;
  } catch (e) {
    log('bootstrap: failed to read RPC endpoint: $e');
    return defaultRpcEndpointConfig(network);
  }
}

Future<ThemeMode> _readThemeMode(AppSecureStore storage) async {
  try {
    return _decodeThemeMode(await storage.readString(kThemeModeKey));
  } on SecureStorageUnavailableException {
    rethrow;
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
  } on SecureStorageUnavailableException {
    rethrow;
  } catch (e) {
    log('bootstrap: failed to read privacy mode: $e');
    return false;
  }
}

Future<bool> _readBiometricUnlockEnabled(AppSecureStore storage) async {
  // The enabled flag is written via writePlain (unencrypted), so it must be
  // read back via readPlain to match the biometric unlock provider's storage.
  return _readPlainBool(
    storage,
    key: _biometricUnlockEnabledKey,
    label: 'biometric unlock flag',
  );
}

Future<bool> _readPlainBool(
  AppSecureStore storage, {
  required String key,
  required String label,
}) async {
  try {
    return (await storage.readPlain(key)) == 'true';
  } on SecureStorageUnavailableException {
    rethrow;
  } catch (e) {
    log('bootstrap: failed to read $label: $e');
    return false;
  }
}

Future<bool> _readSwapEnabledOverrideCachedForRelease() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(swapEnabledOverrideStorageKey(kVizorReleaseVersion)) ??
        false;
  } catch (e) {
    log('bootstrap: failed to read swap override cache: $e');
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
    if (balance.availability !=
        rust_sync.WalletBalanceAvailability.available) {
      throw StateError(
        'Wallet balance unavailable during bootstrap: '
        '${balance.availability.name}',
      );
    }
    final recentTransactions = await rust_sync.getTransactionHistory(
      dbPath: dbPath,
      network: network,
      limit: 10,
      accountUuid: accountUuid,
    );
    var canShieldTransparentBalance = false;
    var shieldTransparentFee = BigInt.zero;
    var shieldTransparentAmount = BigInt.zero;
    if (balance.transparent > BigInt.zero) {
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
