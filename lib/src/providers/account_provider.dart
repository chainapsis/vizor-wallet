import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../app_bootstrap.dart';
import '../core/account_name_policy.dart';
import '../core/config/network_config.dart';
import '../core/profile_pictures.dart';
import '../core/storage/app_secure_store.dart';
import '../core/storage/wallet_paths.dart';
import '../features/swap/providers/swap_activity_store.dart';
import '../features/voting/voting_flow_models.dart';
import '../rust/api/voting.dart' as rust_voting;
import '../rust/api/wallet.dart' as rust_wallet;
import 'account_models.dart';
import 'app_security_provider.dart';
import 'rpc_endpoint_failover_provider.dart';
import 'rpc_endpoint_provider.dart';
import 'voting/voting_submission_guard_provider.dart';

export 'account_models.dart';

const _accountsKey = 'zcash_accounts';
const _activeAccountKey = 'zcash_active_account';
const _networkKey = 'zcash_wallet_network';
// Keep in sync with zcash_voting::storage::VotingDb::wallet_sidecar_path,
// which appends ".voting" to the wallet DB path for sidecar persistence.
const _votingSidecarSuffix = '.voting';
const _sqliteCompanionSuffixes = ['', '-journal', '-wal', '-shm'];

const kWalletCreationCurrentBlockHeightErrorMessage =
    'We need the current Zcash block height to create your wallet. '
    'Check your network connection and try again.';

class WalletCreationCurrentBlockHeightException implements Exception {
  const WalletCreationCurrentBlockHeightException(this.cause);

  final Object cause;

  @override
  String toString() => kWalletCreationCurrentBlockHeightErrorMessage;
}

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

      final birthday = await _fetchCreationBirthdayHeight();
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
      await _storage.writeAccountMnemonic(accountUuid, mnemonic);

      // Update account list
      final newAccount = AccountInfo(
        uuid: accountUuid,
        name: accountName,
        order: accounts.length,
        isSeedAnchor: accounts.isEmpty,
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

      final birthday = await _fetchCreationBirthdayHeight();
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

      await _storage.writeAccountMnemonic(accountUuid, mnemonic);

      final newAccount = AccountInfo(
        uuid: accountUuid,
        name: accountName,
        order: accounts.length,
        isSeedAnchor: accounts.isEmpty,
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

      await _storage.writeAccountMnemonic(accountUuid, mnemonic);

      final newAccount = AccountInfo(
        uuid: accountUuid,
        name: accountName,
        order: accounts.length,
        isSeedAnchor: accounts.isEmpty,
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
    final previousActiveUuid = state.value?.activeAccountUuid;
    if (previousActiveUuid != null && previousActiveUuid != uuid) {
      final guardedSubmission = ref
          .read(votingSubmissionGuardProvider.notifier)
          .guardForAccount(previousActiveUuid);
      if (guardedSubmission == null) {
        await _resetVotingProcessStateForAccount(previousActiveUuid);
      }
    }
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
    validateAccountName(newName);
    final normalizedName = normalizeAccountName(newName);
    final prev = state.value ?? const AccountState();
    final updated = prev.accounts
        .map((a) => a.uuid == uuid ? a.copyWith(name: normalizedName) : a)
        .toList();
    await _saveAccounts(updated);
    state = AsyncData(prev.copyWith(accounts: updated));
    log('renameAccount: $uuid → $normalizedName');
  }

  /// Update an account profile picture.
  Future<void> updateProfilePicture(
    String uuid,
    String profilePictureId,
  ) async {
    final normalizedProfilePictureId = normalizeProfilePictureId(
      profilePictureId,
    );
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
              ? a.copyWith(profilePictureId: normalizedProfilePictureId)
              : a,
        )
        .toList();
    await _saveAccounts(updated);
    state = AsyncData(prev.copyWith(accounts: updated));
    log('updateProfilePicture: $uuid → $normalizedProfilePictureId');
  }

  /// Remove an account from the wallet.
  ///
  /// Destructive account changes are blocked while any vote submission is in
  /// progress. Once removal is allowed, process-local voting state is cleared
  /// before the wallet delete. Durable voting rows, hotkeys, and other
  /// account-scoped sidecars are cleared after the wallet account is deleted.
  Future<void> removeAccount(String uuid) async {
    ref.read(votingSubmissionGuardProvider.notifier).throwIfActive();
    final prev = state.value ?? const AccountState();
    final targetIndex = prev.accounts.indexWhere((a) => a.uuid == uuid);
    if (targetIndex < 0) {
      throw ArgumentError.value(uuid, 'uuid', 'Unknown account UUID');
    }

    final target = prev.accounts[targetIndex];
    final remaining = [
      for (final account in prev.accounts)
        if (account.uuid != uuid) account,
    ];
    final seedAnchorCount = prev.accounts
        .where((account) => account.isSeedAnchor)
        .length;
    if (target.isSeedAnchor && seedAnchorCount <= 1 && remaining.isNotEmpty) {
      throw StateError(
        'The last seed anchor account cannot be removed while other accounts remain.',
      );
    }

    final dbPath = await _getDbPath();
    final network = await _getNetwork();
    await _resetVotingProcessStateForAccount(uuid, dbPath: dbPath);
    final rustDeleteWatch = Stopwatch()..start();
    await rust_wallet.deleteAccount(
      dbPath: dbPath,
      network: network,
      accountUuid: uuid,
    );
    log(
      'removeAccount: rust delete complete in '
      '${rustDeleteWatch.elapsedMilliseconds}ms uuid=$uuid',
    );
    try {
      await _deleteDurableVotingStateForAccount(uuid, dbPath: dbPath);
    } catch (e, st) {
      log(
        'removeAccount: failed to delete durable voting state for '
        '$uuid after wallet deletion: $e\n$st',
      );
    }
    try {
      await _storage.deleteAccountMnemonic(uuid);
    } catch (e, st) {
      log('removeAccount: failed to delete mnemonic for $uuid: $e\n$st');
    }
    try {
      await ref
          .read(swapActivityStoreProvider)
          .deleteForAccount(accountUuid: uuid);
    } catch (_) {}
    try {
      await _storage.deleteVotingHotkeysForAccount(uuid);
    } catch (e, st) {
      log('removeAccount: failed to delete voting hotkeys for $uuid: $e\n$st');
    }
    try {
      await ref.read(votingDraftPersistenceProvider).deleteForAccount(uuid);
    } catch (e, st) {
      log('removeAccount: failed to delete voting drafts for $uuid: $e\n$st');
    }

    final updated = [
      for (var i = 0; i < remaining.length; i++)
        remaining[i].copyWith(order: i),
    ];
    final nextActiveUuid = _nextActiveAccountUuid(
      previousState: prev,
      removedAccount: target,
      remainingAccounts: updated,
    );
    final nextActiveAddress = await _nextActiveAddress(
      prev,
      nextActiveUuid,
      dbPath,
      network,
    );

    await _saveAccounts(updated);
    if (nextActiveUuid == null) {
      await _storage.delete(_activeAccountKey);
    } else {
      await _storage.writeString(_activeAccountKey, nextActiveUuid);
    }

    state = AsyncData(
      AccountState(
        accounts: updated,
        activeAccountUuid: nextActiveUuid,
        activeAddress: nextActiveAddress,
      ),
    );
    log('removeAccount: $uuid');
  }

  /// Delete all wallet data (DB + keychain). Caller must stop sync first.
  ///
  /// This also clears voting state held in this process for every account
  /// before the wallet DB and voting sidecar DB are deleted.
  Future<void> resetWallet() async {
    ref.read(votingSubmissionGuardProvider.notifier).throwIfActive();
    final dbPath = await _getDbPath();
    for (final account in state.value?.accounts ?? const <AccountInfo>[]) {
      await _resetVotingProcessStateForAccount(account.uuid, dbPath: dbPath);
    }
    await _deleteExistingDb(dbPath);
    await _storage.deleteAll();
    ref.read(appSecurityProvider.notifier).reset();
    state = const AsyncData(AccountState());
    log('resetWallet: all data cleared');
  }

  void clearSensitiveStateForLock() {
    final prev = state.value ?? const AccountState();
    final activeAccountUuid = prev.activeAccountUuid;
    if (activeAccountUuid != null) {
      final guardedSubmission = ref
          .read(votingSubmissionGuardProvider.notifier)
          .guardForAccount(activeAccountUuid);
      if (guardedSubmission == null) {
        // Do not delay routing to unlock while best-effort process cleanup runs.
        unawaited(_resetVotingProcessStateForAccount(activeAccountUuid));
      } else {
        log(
          'AccountNotifier: skipped voting process reset for lock while '
          'submission is guarded for $activeAccountUuid',
        );
      }
    }
    state = AsyncData(
      AccountState(
        accounts: prev.accounts,
        activeAccountUuid: prev.activeAccountUuid,
      ),
    );
    log('AccountNotifier: cleared in-memory address state for lock');
  }

  /// Clear process-local voting caches scoped to an account.
  ///
  /// This is best-effort cleanup for lifecycle boundaries where account-scoped
  /// Rust state must not outlive the account/session. Failures are logged and do
  /// not block wallet/account mutations.
  Future<void> _resetVotingProcessStateForAccount(
    String accountUuid, {
    String? dbPath,
  }) async {
    try {
      await rust_voting.resetVotingSessionState(
        dbPath: dbPath ?? await _getDbPath(),
        accountUuid: accountUuid,
        roundId: null,
      );
      log('AccountNotifier: reset voting process state for $accountUuid');
    } catch (e, st) {
      log(
        'AccountNotifier: failed to reset voting process state for '
        '$accountUuid: $e\n$st',
      );
    }
  }

  /// Delete durable voting sidecar rows scoped to an account.
  ///
  /// This runs only after the wallet account delete succeeds. The caller decides
  /// whether a cleanup failure should abort the broader lifecycle.
  Future<void> _deleteDurableVotingStateForAccount(
    String accountUuid, {
    required String dbPath,
  }) async {
    final deletedRounds = await rust_voting.deleteVotingAccountState(
      dbPath: dbPath,
      accountUuid: accountUuid,
    );
    log(
      'AccountNotifier: deleted durable voting state for '
      '$accountUuid rounds=$deletedRounds',
    );
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
  /// Keystone accounts may be the first account in the wallet. If no `Derived`
  /// account exists yet, this can create a wallet DB containing only `Imported`
  /// accounts. That future seed-requiring migration risk is a product tradeoff
  /// we accept for Keystone-first onboarding.
  Future<void> importKeystoneAccount({
    required String name,
    required String ufvk,
    required List<int> seedFingerprint,
    required int zip32Index,
    required int birthdayHeight,
  }) async {
    try {
      final prev = state.value ?? const AccountState();
      final dbPath = await _getDbPath();
      final network = await _getNetwork();

      final result = await rust_wallet.importHardwareAccount(
        dbPath: dbPath,
        network: network,
        name: name,
        ufvkString: ufvk,
        seedFingerprint: seedFingerprint,
        zip32Index: zip32Index,
        birthdayHeight: BigInt.from(birthdayHeight),
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
    return _storage.readAccountMnemonic(uuid, requireUnlockedSession: true);
  }

  /// Get the mnemonic for a specific account.
  Future<String?> getMnemonicForAccount(String uuid) async {
    return _storage.readAccountMnemonic(uuid, requireUnlockedSession: true);
  }

  Future<Uint8List?> getMnemonicBytesForAccount(String uuid) async {
    return _storage.readAccountMnemonicBytes(
      uuid,
      requireUnlockedSession: true,
    );
  }

  // ======================== Helpers ========================

  Future<void> _saveAccounts(List<AccountInfo> accounts) async {
    final json = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await _storage.writeString(_accountsKey, json);
  }

  String? _nextActiveAccountUuid({
    required AccountState previousState,
    required AccountInfo removedAccount,
    required List<AccountInfo> remainingAccounts,
  }) {
    return resolveNextActiveAccountUuidAfterRemoval(
      previousState: previousState,
      removedAccount: removedAccount,
      remainingAccounts: remainingAccounts,
    );
  }

  Future<String?> _nextActiveAddress(
    AccountState prev,
    String? nextActiveUuid,
    String dbPath,
    String network,
  ) async {
    if (nextActiveUuid == null) return null;
    if (nextActiveUuid == prev.activeAccountUuid) return prev.activeAddress;
    try {
      return await rust_wallet.getUnifiedAddress(
        dbPath: dbPath,
        network: network,
        accountUuid: nextActiveUuid,
      );
    } catch (e) {
      log('removeAccount: failed to get next active address: $e');
      return null;
    }
  }

  Future<String> _getDbPath() async {
    return getWalletDbPath();
  }

  Future<BigInt> _fetchCreationBirthdayHeight() async {
    try {
      return await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .getLatestBlockHeight();
    } catch (e, st) {
      Error.throwWithStackTrace(
        WalletCreationCurrentBlockHeightException(e),
        st,
      );
    }
  }

  Future<String> _getNetwork() async {
    return resolveStoredOrDefaultZcashNetworkName(
      await _storage.readString(_networkKey),
    );
  }

  Future<void> _deleteExistingDb(String dbPath) async {
    for (final path in walletDbCleanupPaths(dbPath)) {
      final file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }
}

final accountProvider = AsyncNotifierProvider<AccountNotifier, AccountState>(
  AccountNotifier.new,
);

@visibleForTesting
String? resolveNextActiveAccountUuidAfterRemoval({
  required AccountState previousState,
  required AccountInfo removedAccount,
  required List<AccountInfo> remainingAccounts,
}) {
  if (remainingAccounts.isEmpty) return null;
  if (previousState.activeAccountUuid != removedAccount.uuid &&
      remainingAccounts.any((a) => a.uuid == previousState.activeAccountUuid)) {
    return previousState.activeAccountUuid;
  }
  final nextIndex = removedAccount.order
      .clamp(0, remainingAccounts.length - 1)
      .toInt();
  return remainingAccounts[nextIndex].uuid;
}

@visibleForTesting
List<String> walletDbCleanupPaths(String dbPath) {
  // Voting persists to a deterministic SQLite sidecar next to the wallet DB.
  final targets = [dbPath, '$dbPath$_votingSidecarSuffix'];
  return [
    for (final target in targets)
      for (final suffix in _sqliteCompanionSuffixes) '$target$suffix',
  ];
}
