import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;
import 'package:zcash_wallet/src/rust/api/wallet.dart' as rust_wallet;
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _activeAccountKey = 'zcash_active_account';
const _accountsKey = 'zcash_accounts';
const _biometricUnlockEnabledKey = 'zcash_biometric_unlock_enabled';
const _networkKey = 'zcash_wallet_network';
const _passwordVerifierKey = 'zcash_password_verifier';
const _passwordVerifierSaltKey = 'zcash_password_verifier_salt';

const _firstWaveBootstrapKeys = <String>{
  _networkKey,
  kThemeModeKey,
  kPrivacyModeEnabledKey,
  _biometricUnlockEnabledKey,
  kSyncKeepAwakeEnabledKey,
  kSyncKeepAwakePromptSeenKey,
  _passwordVerifierKey,
  _passwordVerifierSaltKey,
  _accountsKey,
  _activeAccountKey,
};

const _dependentRpcKeys = <String>{kRpcEndpointUrlKey, kRpcEndpointPresetKey};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _RustBootstrapApiFake rustApi;

  setUpAll(() {
    rustApi = _RustBootstrapApiFake();
    RustLib.initMock(api: rustApi);
  });

  tearDownAll(RustLib.dispose);

  setUp(() {
    rustApi.reset();
    SharedPreferences.setMockInitialValues({});
  });

  test('AccountInfo.fromJson normalizes legacy profile picture ids', () {
    final account = AccountInfo.fromJson({
      'uuid': 'account-1',
      'name': 'Legacy Samurai',
      'order': 0,
      'profilePictureId': 'samurai',
    });

    expect(account.profilePictureId, 'pfp-03');
  });

  test('AccountInfo.fromJson keeps wallet link source account uuid', () {
    final account = AccountInfo.fromJson({
      'uuid': 'account-1',
      'name': 'Linked',
      'order': 0,
      'walletLinkSourceAccountUuid': ' 550e8400-e29b-41d4-a716-446655440000 ',
    });

    expect(
      account.walletLinkSourceAccountUuid,
      '550e8400-e29b-41d4-a716-446655440000',
    );
  });

  test('mergeBootstrappedAccountInfo keeps stored UI metadata', () {
    const rustAccount = AccountInfo(
      uuid: 'account-1',
      name: 'Rust Name',
      order: 0,
      isSeedAnchor: true,
    );
    const storedAccount = AccountInfo(
      uuid: 'account-1',
      name: 'Stored Name',
      order: 9,
      isHardware: true,
      isSeedAnchor: false,
      profilePictureId: 'pfp-04',
      walletLinkSourceAccountUuid: 'desktop-account-1',
    );

    final merged = mergeBootstrappedAccountInfo(
      rustAccount: rustAccount,
      storedAccount: storedAccount,
      order: 3,
    );

    expect(merged.uuid, 'account-1');
    expect(merged.name, 'Stored Name');
    expect(merged.order, 9);
    expect(merged.isHardware, isTrue);
    expect(merged.isSeedAnchor, isTrue);
    expect(merged.profilePictureId, 'pfp-04');
    expect(merged.walletLinkSourceAccountUuid, 'desktop-account-1');
  });

  test(
    'mergeBootstrappedAccountInfo normalizes legacy profile picture ids',
    () {
      const rustAccount = AccountInfo(
        uuid: 'account-1',
        name: 'Rust Name',
        order: 0,
      );
      const storedAccount = AccountInfo(
        uuid: 'account-1',
        name: 'Stored Name',
        order: 0,
        profilePictureId: 'samurai',
      );

      final merged = mergeBootstrappedAccountInfo(
        rustAccount: rustAccount,
        storedAccount: storedAccount,
        order: 0,
      );

      expect(merged.profilePictureId, 'pfp-03');
    },
  );

  test('mergeBootstrappedAccountInfo falls back to Rust metadata', () {
    const rustAccount = AccountInfo(
      uuid: 'account-2',
      name: 'Rust Name',
      order: 0,
    );

    final merged = mergeBootstrappedAccountInfo(
      rustAccount: rustAccount,
      storedAccount: null,
      order: 1,
    );

    expect(merged.uuid, 'account-2');
    expect(merged.name, 'Rust Name');
    expect(merged.order, 1);
    expect(merged.isHardware, isFalse);
    expect(merged.isSeedAnchor, isFalse);
  });

  test('mergeBootstrappedAccountInfo recovers Rust hardware metadata', () {
    const rustAccount = AccountInfo(
      uuid: 'account-3',
      name: 'Rust Keystone',
      order: 1,
      isHardware: true,
    );
    const storedAccount = AccountInfo(
      uuid: 'account-3',
      name: 'Stored Keystone',
      order: 1,
    );

    final merged = mergeBootstrappedAccountInfo(
      rustAccount: rustAccount,
      storedAccount: storedAccount,
      order: 1,
    );

    expect(merged.isHardware, isTrue);
    expect(merged.name, 'Stored Keystone');
  });

  test('empty bootstrap has no password rotation recovery failure', () {
    expect(AppBootstrapState.empty.passwordRotationRecoveryFailed, isFalse);
  });

  test('empty bootstrap starts with privacy mode disabled', () {
    expect(AppBootstrapState.empty.privacyModeEnabled, isFalse);
  });

  test(
    'empty bootstrap starts with sync keep-awake disabled and unprompted',
    () {
      expect(AppBootstrapState.empty.syncKeepAwakeEnabled, isFalse);
      expect(AppBootstrapState.empty.syncKeepAwakePromptSeen, isFalse);
    },
  );

  test('bootstrap launches independent reads before awaiting them', () async {
    final storage = _ControlledReadStorage(
      values: {
        _networkKey: 'test',
        kRpcEndpointUrlKey: 'https://custom.example:443',
        kRpcEndpointPresetKey: 'custom',
        kThemeModeKey: 'dark',
        kPrivacyModeEnabledKey: 'true',
        _biometricUnlockEnabledKey: 'true',
        kSyncKeepAwakeEnabledKey: 'true',
        kSyncKeepAwakePromptSeenKey: 'true',
        _passwordVerifierKey: 'verifier',
        _passwordVerifierSaltKey: 'salt',
        _accountsKey: jsonEncode([
          {'uuid': 'account-1', 'name': 'Stored account', 'order': 0},
        ]),
        _activeAccountKey: 'account-1',
      },
      blockedKeys: {..._firstWaveBootstrapKeys, ..._dependentRpcKeys},
    );
    final store = AppSecureStore.testing(storage: storage);
    final dbPath = Completer<String>();
    var dbPathStarted = false;

    final bootstrap = loadAppBootstrapForTesting(
      storage: store,
      getDbPath: () {
        dbPathStarted = true;
        return dbPath.future;
      },
    );

    await _waitUntil(
      () => storage.startedKeys.containsAll(_firstWaveBootstrapKeys),
    );
    expect(dbPathStarted, isTrue);
    expect(storage.startedKeys, isNot(containsAll(_dependentRpcKeys)));

    storage.complete(_networkKey);
    await _waitUntil(() => storage.startedKeys.containsAll(_dependentRpcKeys));

    for (final key in <String>{
      ..._firstWaveBootstrapKeys,
      ..._dependentRpcKeys,
    }.toList().reversed) {
      storage.complete(key);
    }
    dbPath.complete('/tmp/vizor-bootstrap-no-wallet.db');

    final result = await bootstrap;

    expect(result.hasBlockingFailure, isFalse);
    expect(result.initialLocation, '/unlock');
    expect(result.network, 'test');
    expect(
      result.rpcEndpointConfig.lightwalletdUrl,
      'https://custom.example:443',
    );
    expect(result.rpcEndpointConfig.presetId, 'custom');
    expect(result.themeMode.name, 'dark');
    expect(result.privacyModeEnabled, isTrue);
    expect(result.biometricUnlockEnabled, isTrue);
    expect(result.syncKeepAwakeEnabled, isTrue);
    expect(result.syncKeepAwakePromptSeen, isTrue);
    expect(result.isPasswordConfigured, isTrue);
    expect(result.initialAccountState.activeAccountUuid, 'account-1');
    expect(result.initialAccountState.accounts.single.name, 'Stored account');
  });

  test(
    'bootstrap preserves storage failure precedence over a path failure',
    () async {
      final blockedKeys = <String>{
        ..._firstWaveBootstrapKeys,
        ..._dependentRpcKeys,
      };
      final storage = _ControlledReadStorage(
        values: const {_networkKey: 'main'},
        blockedKeys: blockedKeys,
      );
      final store = AppSecureStore.testing(storage: storage);
      final dbPath = Completer<String>();
      var bootstrapCompleted = false;

      final bootstrap = loadAppBootstrapForTesting(
        storage: store,
        getDbPath: () => dbPath.future,
      );
      unawaited(
        bootstrap.then((_) {
          bootstrapCompleted = true;
        }),
      );

      await _waitUntil(
        () => storage.startedKeys.containsAll(_firstWaveBootstrapKeys),
      );
      storage.complete(_networkKey);
      await _waitUntil(
        () => storage.startedKeys.containsAll(_dependentRpcKeys),
      );
      dbPath.completeError(StateError('forced path failure'));
      storage.fail(
        kThemeModeKey,
        PlatformException(code: 'keychain_unavailable'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(bootstrapCompleted, isFalse);

      for (final key in blockedKeys) {
        storage.complete(key);
      }
      final result = await bootstrap;

      expect(result.initialLocation, '/storage-unavailable');
      expect(
        result.failureKind,
        AppBootstrapFailureKind.secureStorageUnavailable,
      );
      expect(
        result.failureMessage,
        'Vizor needs access to secure storage before it can open your wallet.',
      );
    },
  );

  test(
    'bootstrap loads independent Rust snapshot reads concurrently',
    () async {
      rustApi.prepareWalletSnapshot();
      final store = _unlockedBootstrapStore();
      var bootstrapCompleted = false;

      final bootstrap = loadAppBootstrapForTesting(
        storage: store,
        getDbPath: () async => '/tmp/vizor-bootstrap-wallet.db',
      );
      unawaited(
        bootstrap.then((_) {
          bootstrapCompleted = true;
        }),
      );

      await _waitUntil(
        () => rustApi.snapshotReadsStarted.containsAll(const {
          'sync status',
          'balance',
          'transaction history',
        }),
      );
      expect(bootstrapCompleted, isFalse);

      rustApi.completeTransactionHistory();
      rustApi.completeBalance();
      rustApi.completeSyncStatus();
      final result = await bootstrap;

      expect(result.initialLocation, '/home');
      expect(result.initialAccountState.activeAddress, 'u-test-account-1');
      expect(result.initialSyncSnapshot.accountUuid, 'account-1');
      expect(result.initialSyncSnapshot.hasAccountScopedData, isTrue);
      expect(result.initialSyncSnapshot.scannedHeight, 75);
      expect(result.initialSyncSnapshot.chainTipHeight, 100);
      expect(result.initialSyncSnapshot.percentage, 0.75);
      expect(result.initialSyncSnapshot.orchardBalance, BigInt.from(30));
      expect(result.initialSyncSnapshot.totalBalance, BigInt.from(30));
    },
  );

  test('bootstrap keeps the empty snapshot fallback on Rust failure', () async {
    rustApi.prepareWalletSnapshot();
    final store = _unlockedBootstrapStore();
    var bootstrapCompleted = false;

    final bootstrap = loadAppBootstrapForTesting(
      storage: store,
      getDbPath: () async => '/tmp/vizor-bootstrap-wallet.db',
    );
    unawaited(
      bootstrap.then((_) {
        bootstrapCompleted = true;
      }),
    );

    await _waitUntil(
      () => rustApi.snapshotReadsStarted.containsAll(const {
        'sync status',
        'balance',
        'transaction history',
      }),
    );
    rustApi.failBalance();
    await Future<void>.delayed(Duration.zero);
    expect(bootstrapCompleted, isFalse);

    rustApi.completeTransactionHistory();
    rustApi.completeSyncStatus();
    final result = await bootstrap;

    expect(result.initialLocation, '/home');
    expect(result.initialSyncSnapshot.accountUuid, 'account-1');
    expect(result.initialSyncSnapshot.hasAccountScopedData, isFalse);
    expect(result.initialSyncSnapshot.totalBalance, BigInt.zero);
    expect(result.initialSyncSnapshot.recentTransactions, isEmpty);
  });
}

AppSecureStore _unlockedBootstrapStore() {
  final storage = _ControlledReadStorage(
    values: {
      _networkKey: 'test',
      _passwordVerifierKey: 'verifier',
      _passwordVerifierSaltKey: 'salt',
      _accountsKey: jsonEncode([
        {'uuid': 'account-1', 'name': 'Stored account', 'order': 0},
      ]),
      _activeAccountKey: 'account-1',
    },
    blockedKeys: const {},
  );
  return AppSecureStore.testing(storage: storage)..setSessionPassword('test');
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 20 && !condition(); attempt += 1) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue, reason: 'Expected asynchronous work to start.');
}

class _ControlledReadStorage extends FlutterSecureStorage {
  _ControlledReadStorage({
    required this.values,
    required Set<String> blockedKeys,
  }) : _blockedKeys = blockedKeys;

  final Map<String, String?> values;
  final Set<String> _blockedKeys;
  final Set<String> startedKeys = {};
  final Map<String, Completer<String?>> _pendingReads = {};

  void complete(String key) {
    final pending = _pendingReads[key];
    if (pending != null && !pending.isCompleted) {
      pending.complete(values[key]);
    }
  }

  void fail(String key, Object error) {
    final pending = _pendingReads[key];
    if (pending != null && !pending.isCompleted) {
      pending.completeError(error, StackTrace.current);
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    startedKeys.add(key);
    if (!_blockedKeys.contains(key)) {
      return Future.value(values[key]);
    }
    return _pendingReads.putIfAbsent(key, Completer<String?>.new).future;
  }
}

class _RustBootstrapApiFake implements RustLibApi {
  bool _walletExists = false;
  final Set<String> snapshotReadsStarted = {};
  Completer<rust_sync.SyncProgress>? _syncStatus;
  Completer<rust_sync.WalletBalance>? _balance;
  Completer<List<rust_sync.TransactionInfo>>? _transactionHistory;

  void reset() {
    _walletExists = false;
    snapshotReadsStarted.clear();
    _syncStatus = null;
    _balance = null;
    _transactionHistory = null;
  }

  void prepareWalletSnapshot() {
    _walletExists = true;
    _syncStatus = Completer<rust_sync.SyncProgress>();
    _balance = Completer<rust_sync.WalletBalance>();
    _transactionHistory = Completer<List<rust_sync.TransactionInfo>>();
  }

  void completeSyncStatus() {
    _syncStatus!.complete(
      rust_sync.SyncProgress(
        scannedHeight: BigInt.from(75),
        chainTipHeight: BigInt.from(100),
        isSyncing: false,
        isComplete: false,
      ),
    );
  }

  void completeBalance() {
    _balance!.complete(
      rust_sync.WalletBalance(
        availability: rust_sync.WalletBalanceAvailability.available,
        transparent: BigInt.zero,
        sapling: BigInt.zero,
        orchard: BigInt.from(30),
        ironwood: BigInt.zero,
        transparentLocked: BigInt.zero,
        saplingLocked: BigInt.zero,
        orchardLocked: BigInt.zero,
        ironwoodLocked: BigInt.zero,
        transparentPending: BigInt.zero,
        saplingPending: BigInt.zero,
        orchardPending: BigInt.zero,
        ironwoodPending: BigInt.zero,
        changePendingConfirmation: BigInt.zero,
        valuePendingSpendability: BigInt.zero,
        uneconomicValue: BigInt.zero,
        spendable: BigInt.from(30),
        locked: BigInt.zero,
        total: BigInt.from(30),
      ),
    );
  }

  void failBalance() {
    _balance!.completeError(StateError('forced balance failure'));
  }

  void completeTransactionHistory() {
    _transactionHistory!.complete(const []);
  }

  @override
  Future<void> crateApiWalletEnsureWalletDbMigrated({
    required String dbPath,
    required String network,
  }) async {}

  @override
  Future<List<rust_wallet.AccountInfo>> crateApiWalletListAccounts({
    required String dbPath,
    required String network,
  }) async {
    return const [
      rust_wallet.AccountInfo(
        uuid: 'account-1',
        name: 'Rust account',
        unifiedAddress: 'u-test-account-1',
        isSeedAnchor: true,
        isHardware: false,
      ),
    ];
  }

  @override
  Future<rust_sync.SyncProgress> crateApiSyncGetSyncStatus({
    required String dbPath,
    required String network,
  }) {
    snapshotReadsStarted.add('sync status');
    return _syncStatus!.future;
  }

  @override
  Future<rust_sync.WalletBalance> crateApiSyncGetBalance({
    required String dbPath,
    required String network,
    required String accountUuid,
  }) {
    snapshotReadsStarted.add('balance');
    return _balance!.future;
  }

  @override
  Future<List<rust_sync.TransactionInfo>> crateApiSyncGetTransactionHistory({
    required String dbPath,
    required String network,
    int? limit,
    required String accountUuid,
  }) {
    snapshotReadsStarted.add('transaction history');
    return _transactionHistory!.future;
  }

  @override
  bool crateApiWalletWalletExists({required String dbPath}) => _walletExists;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
