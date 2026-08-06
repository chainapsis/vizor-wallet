import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show log;
import '../app_bootstrap.dart';
import '../core/account_name_policy.dart';
import '../core/config/network_config.dart';
import '../core/profile_pictures.dart';
import '../core/security/software_wallet_secret.dart';
import '../core/storage/app_secure_store.dart';
import '../core/storage/wallet_paths.dart';
import '../features/swap/providers/swap_activity_store.dart';
import '../features/migration/services/ironwood_migration_background_credential_store.dart';
import '../features/migration/services/ironwood_migration_operation_registry.dart';
import '../features/voting/voting_flow_models.dart';
import '../rust/api/sync.dart' as rust_sync;
import '../rust/api/voting.dart' as rust_voting;
import '../rust/api/wallet.dart' as rust_wallet;
import 'account_models.dart';
import 'app_security_provider.dart';
import 'network_privacy_provider.dart';
import 'rpc_endpoint_failover_provider.dart';
import 'rpc_endpoint_provider.dart';
import 'voting/voting_submission_guard_provider.dart';

export 'account_models.dart';

const _accountsKey = 'zcash_accounts';
const _activeAccountKey = 'zcash_active_account';
const _networkKey = 'zcash_wallet_network';
const _derivedAccountRecoveryKey = 'zcash_derived_account_recovery';
// Keep in sync with zcash_voting::storage::VotingDb::wallet_sidecar_path,
// which appends ".voting" to the wallet DB path for sidecar persistence.
const _votingSidecarSuffix = '.voting';
// Keep in sync with wallet::transparent_receive_cache::RECEIVE_CACHE_SIDECAR_SUFFIX.
const _receiveCacheSidecarSuffix = '.receive.redb';
const _sqliteCompanionSuffixes = ['', '-journal', '-wal', '-shm'];

const kWalletCreationCurrentBlockHeightErrorMessage =
    'We need the current Zcash block height to create your wallet. '
    'Check your network connection and try again.';
const _duplicateSoftwareAccountImportMessage =
    'This account is already in your wallet.';
const _duplicateKeystoneAccountImportMessage =
    'This Keystone account is already in your wallet.';

class WalletCreationCurrentBlockHeightException implements Exception {
  const WalletCreationCurrentBlockHeightException(this.cause);

  final Object cause;

  @override
  String toString() => kWalletCreationCurrentBlockHeightErrorMessage;
}

class WalletResetException implements Exception {
  const WalletResetException({required this.cause, required this.dbDeleted});

  final Object cause;
  final bool dbDeleted;

  @override
  String toString() => cause.toString();
}

/// A post-Rust derived-account write failed and durable rollback also failed.
///
/// The original write failure is retained alongside every cleanup failure so
/// callers do not mistake an incomplete rollback for a clean retry state.
class DerivedAccountCompensationException implements Exception {
  const DerivedAccountCompensationException({
    required this.cause,
    required this.cleanupFailures,
  });

  final Object cause;
  final List<Object> cleanupFailures;

  @override
  String toString() {
    final cleanup = cleanupFailures
        .map((failure) => failure.toString())
        .join('; ');
    return 'Derived account compensation failed after: $cause. '
        'Cleanup failures: $cleanup. The wallet must be reconciled before '
        'retrying.';
  }
}

/// A derived account was retained because its Rust rollback could not delete
/// it. Its secret and local metadata were durably reconciled, but a later
/// derive is blocked until the retained account has been reviewed.
class DerivedAccountRecoveryRequiredException implements Exception {
  const DerivedAccountRecoveryRequiredException({
    required this.accountUuid,
    required this.cause,
    this.cleanupFailures = const [],
  });

  final String accountUuid;
  final Object cause;
  final List<Object> cleanupFailures;

  @override
  String toString() {
    final diagnostics = cleanupFailures.isEmpty
        ? ''
        : ' Diagnostics: ${cleanupFailures.join('; ')}.';
    return 'Derived account recovered as $accountUuid after: $cause. '
        'Review the recovered account before deriving another one.$diagnostics';
  }
}

/// Persistent fence written before Rust can allocate a derived account.
///
/// The baseline lets a later process identify the one Rust account added after
/// an interruption even if the result UUID was never written back to Dart
/// storage. Keep this representation deliberately small and versioned because
/// it is a recovery journal, not user-facing account metadata.
class _DerivedAccountRecoveryFence {
  const _DerivedAccountRecoveryFence({
    required this.sourceAccountUuid,
    required this.name,
    required this.profilePictureId,
    required this.accountGroupName,
    required this.baselineAccountUuids,
    required this.hasExactPresentationIntent,
    this.operationToken,
    this.legacyAccountUuid,
  });

  final String sourceAccountUuid;
  final String name;
  final String profilePictureId;
  final String? accountGroupName;
  final Set<String> baselineAccountUuids;

  /// Version-three fences record every presentation field, including an
  /// intentional `null` group name. Earlier fences predate that contract.
  final bool hasExactPresentationIntent;

  /// Opaque Rust lease token for diagnostics. It is never trusted as durable
  /// ownership after a restart; only a currently held native lease authorizes
  /// journal mutation.
  final String? operationToken;

  /// Round 2 persisted only a UUID. It remains a recovery barrier until the
  /// same durable checks used by the new format prove it is safe to clear.
  final String? legacyAccountUuid;

  bool get isLegacy => legacyAccountUuid != null;

  String encode() => jsonEncode({
    'version': 3,
    'sourceAccountUuid': sourceAccountUuid,
    'name': name,
    'profilePictureId': profilePictureId,
    'accountGroupName': accountGroupName,
    'baselineAccountUuids': baselineAccountUuids.toList()..sort(),
    'operationToken': operationToken,
  });

  static _DerivedAccountRecoveryFence decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> &&
          (decoded['version'] == 1 ||
              decoded['version'] == 2 ||
              decoded['version'] == 3)) {
        final sourceAccountUuid = decoded['sourceAccountUuid'];
        final name = decoded['name'];
        final profilePictureId = decoded['profilePictureId'];
        final baseline = decoded['baselineAccountUuids'];
        if (sourceAccountUuid is String &&
            sourceAccountUuid.isNotEmpty &&
            name is String &&
            profilePictureId is String &&
            baseline is List) {
          final baselineAccountUuids = baseline
              .whereType<String>()
              .where((uuid) => uuid.isNotEmpty)
              .toSet();
          if (baselineAccountUuids.isNotEmpty) {
            return _DerivedAccountRecoveryFence(
              sourceAccountUuid: sourceAccountUuid,
              name: name,
              profilePictureId: profilePictureId,
              accountGroupName: decoded['accountGroupName'] as String?,
              baselineAccountUuids: baselineAccountUuids,
              hasExactPresentationIntent: decoded['version'] == 3,
              operationToken: decoded['operationToken'] as String?,
            );
          }
        }
      }
    } catch (_) {
      // Fall through to the legacy UUID case below.
    }

    if (raw.isNotEmpty && !raw.contains('{')) {
      return _DerivedAccountRecoveryFence(
        sourceAccountUuid: '',
        name: '',
        profilePictureId: kDefaultProfilePictureId,
        accountGroupName: null,
        baselineAccountUuids: const {},
        hasExactPresentationIntent: false,
        legacyAccountUuid: raw,
      );
    }
    throw StateError('Invalid derived account recovery fence.');
  }
}

/// Rebuild a missing Dart fence exclusively from native durable intent. A
/// record from before this protocol cannot be guessed: it remains a recovery
/// barrier until a fence-backed or manual resolution proves its delta.
_DerivedAccountRecoveryFence _recoveryFenceFromNativeLease(
  rust_wallet.SoftwareAccountDerivationLease lease, {
  bool requireStoredIntent = false,
}) {
  final name = lease.recoveryName;
  final profilePictureId = lease.recoveryProfilePictureId;
  if (name == null || profilePictureId == null) {
    if (requireStoredIntent) {
      throw StateError(
        'The native derivation recovery record lacks the exact intent needed '
        'to rebuild its missing Dart fence. Recovery is required before '
        'creating another account.',
      );
    }
    throw StateError('Native derivation recovery intent is incomplete.');
  }
  return _DerivedAccountRecoveryFence(
    sourceAccountUuid: lease.sourceAccountUuid,
    name: name,
    profilePictureId: profilePictureId,
    accountGroupName: lease.recoveryAccountGroupName,
    baselineAccountUuids: {...lease.baselineAccountUuids},
    hasExactPresentationIntent: true,
    operationToken: lease.operationToken,
  );
}

void _assertRecoveryFenceMatchesNative(
  _DerivedAccountRecoveryFence fence,
  rust_wallet.SoftwareAccountDerivationLease lease,
) {
  if (fence.operationToken != lease.operationToken ||
      fence.sourceAccountUuid != lease.sourceAccountUuid ||
      fence.baselineAccountUuids.length != lease.baselineAccountUuids.length ||
      !fence.baselineAccountUuids.containsAll(lease.baselineAccountUuids)) {
    throw StateError(
      'The Dart derivation recovery fence does not match native durable intent.',
    );
  }
  // Versions one and two predate exact nullable presentation intent. In
  // particular, a native null group cannot authenticate a group supplied in
  // a modified older fence. Keep the journal as a recovery barrier instead
  // of inventing display metadata for a recovered account.
  if (!fence.hasExactPresentationIntent) {
    throw StateError(
      'This legacy derived-account recovery marker cannot prove its exact '
      'presentation intent. Recovery is required before proceeding.',
    );
  }
  if (lease.recoveryName != fence.name ||
      lease.recoveryProfilePictureId != fence.profilePictureId ||
      lease.recoveryAccountGroupName != fence.accountGroupName) {
    throw StateError(
      'The Dart derivation recovery fence presentation does not match native durable intent.',
    );
  }
}

/// Picks the software account whose recovery phrase should derive a new
/// account. Prefers the active account, then falls back to list order.
String? defaultDeriveSourceAccountUuid(AccountState state) {
  final softwareAccounts = state.accounts.where((a) => !a.isHardware).toList()
    ..sort((a, b) => a.order.compareTo(b.order));
  if (softwareAccounts.isEmpty) return null;

  for (final account in softwareAccounts) {
    if (account.uuid == state.activeAccountUuid) return account.uuid;
  }
  return softwareAccounts.first.uuid;
}

class LinkedWalletAccountImport {
  const LinkedWalletAccountImport({
    required this.name,
    required this.birthdayHeight,
    required this.zip32AccountIndex,
    required this.isHardware,
    required this.isSeedAnchor,
    this.mnemonic,
    this.bip39Passphrase = '',
    this.ufvk,
    this.seedFingerprint,
    this.profilePictureId,
    this.sourceAccountUuid,
  });

  final String name;
  final int birthdayHeight;
  final int zip32AccountIndex;
  final bool isHardware;
  final bool isSeedAnchor;
  final String? mnemonic;
  final String bip39Passphrase;
  final String? ufvk;
  final List<int>? seedFingerprint;
  final String? profilePictureId;
  final String? sourceAccountUuid;
}

class LinkedWalletAccountsImportResult {
  const LinkedWalletAccountsImportResult({
    required this.importedCount,
    required this.skippedDuplicateCount,
  });

  final int importedCount;
  final int skippedDuplicateCount;
}

class AccountNotifier extends AsyncNotifier<AccountState> {
  static final _storage = AppSecureStore.instance;
  static var _deriveOperationInFlight = false;

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
      String? seedFamilyId;

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
        seedFamilyId = result.seedFamilyId;
        await _storage.writeString(_networkKey, network);
      } else {
        // Additional account — generate mnemonic + add to existing DB
        mnemonic = rust_wallet.generateMnemonic();
        final result = await rust_wallet.addAccount(
          dbPath: dbPath,
          network: network,
          name: accountName,
          mnemonic: mnemonic,
          bip39Passphrase: '',
          birthdayHeight: birthday,
        );
        accountUuid = result.accountUuid;
        unifiedAddress = result.unifiedAddress;
        seedFamilyId = result.seedFamilyId;
      }

      // Store mnemonic per-account
      await _storage.writeAccountMnemonic(accountUuid, mnemonic);

      // Update account list
      final newAccount = AccountInfo(
        uuid: accountUuid,
        name: accountName,
        order: accounts.length,
        isSeedAnchor: accounts.isEmpty,
        seedFamilyId: seedFamilyId,
        accountGroupName: existingAccountGroupNameForSeedFamily(
          accounts,
          seedFamilyId,
        ),
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
    String profilePictureId = kDefaultProfilePictureId,
  }) async {
    try {
      final dbPath = await _getDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final network = endpoint.networkName;

      final birthday = await _fetchCreationBirthdayHeight();
      log('createAccountFromMnemonic: birthday=$birthday');

      final accounts = state.value?.accounts ?? [];
      final accountName = normalizeAccountName(
        name ?? 'Account ${accounts.length + 1}',
      );
      validateAccountName(accountName);
      if (!isKnownProfilePictureId(profilePictureId)) {
        throw ArgumentError.value(
          profilePictureId,
          'profilePictureId',
          'Unknown profile picture id',
        );
      }
      final normalizedProfilePictureId = normalizeProfilePictureId(
        profilePictureId,
      );

      late final String accountUuid;
      late final String unifiedAddress;
      late final String? seedFamilyId;

      if (accounts.isEmpty) {
        await _deleteExistingDb(dbPath);
        final result = await rust_wallet.importWallet(
          mnemonic: mnemonic,
          bip39Passphrase: '',
          birthdayHeight: birthday,
          network: network,
          dbPath: dbPath,
          accountName: accountName,
        );
        accountUuid = result.accountUuid;
        unifiedAddress = result.unifiedAddress;
        seedFamilyId = result.seedFamilyId;
        await _storage.writeString(_networkKey, network);
      } else {
        final result = await rust_wallet.addAccount(
          dbPath: dbPath,
          network: network,
          name: accountName,
          mnemonic: mnemonic,
          bip39Passphrase: '',
          birthdayHeight: birthday,
        );
        accountUuid = result.accountUuid;
        unifiedAddress = result.unifiedAddress;
        seedFamilyId = result.seedFamilyId;
      }

      await _storage.writeAccountMnemonic(accountUuid, mnemonic);

      final newAccount = AccountInfo(
        uuid: accountUuid,
        name: accountName,
        order: accounts.length,
        isSeedAnchor: accounts.isEmpty,
        profilePictureId: normalizedProfilePictureId,
        seedFamilyId: seedFamilyId,
        accountGroupName: existingAccountGroupNameForSeedFamily(
          accounts,
          seedFamilyId,
        ),
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

  /// Derive the next ZIP 32 account from an existing software account's
  /// recovery phrase. The phrase is resolved from secure storage and never
  /// passes through the UI.
  Future<void> deriveAccountFromExistingSeed({
    required String sourceAccountUuid,
    String? name,
    String profilePictureId = kDefaultProfilePictureId,
  }) async {
    if (_deriveOperationInFlight) {
      throw StateError('A derived account operation is already in progress.');
    }
    _deriveOperationInFlight = true;
    try {
      final dbPath = await _getDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final network = endpoint.networkName;
      // Validate and freeze the requested intent before native begin. The
      // native record owns this data so a crash before the first Dart storage
      // write can rebuild the exact recovery fence without inventing account
      // metadata from a later UI request.
      final requestedAccounts = state.value?.accounts ?? [];
      final requestedSourceAccount = requestedAccounts.firstWhere(
        (account) => account.uuid == sourceAccountUuid,
        orElse: () => throw ArgumentError.value(
          sourceAccountUuid,
          'sourceAccountUuid',
          'Unknown account UUID',
        ),
      );
      if (requestedSourceAccount.isHardware) {
        throw ArgumentError.value(
          sourceAccountUuid,
          'sourceAccountUuid',
          'A hardware account cannot derive a software account.',
        );
      }
      final requestedAccountName = normalizeAccountName(
        name ?? 'Account ${requestedAccounts.length + 1}',
      );
      validateAccountName(requestedAccountName);
      if (!isKnownProfilePictureId(profilePictureId)) {
        throw ArgumentError.value(
          profilePictureId,
          'profilePictureId',
          'Unknown profile picture id',
        );
      }
      final requestedProfilePictureId = normalizeProfilePictureId(
        profilePictureId,
      );
      // Rust owns this OS-level lease until this method has either committed
      // the local metadata or retained its journal. A second process must not
      // inspect, clear, or replace this operation's recovery fence.
      final existingRawFence = await _storage.readString(
        _derivedAccountRecoveryKey,
      );
      late final rust_wallet.SoftwareAccountDerivationLease nativeLease;
      late final _DerivedAccountRecoveryFence recoveryFence;
      var sourceSeedFamilyPersistedBeforeLease = false;
      if (existingRawFence != null && existingRawFence.isNotEmpty) {
        final existingFence = _DerivedAccountRecoveryFence.decode(
          existingRawFence,
        );
        if (existingFence.isLegacy || existingFence.operationToken == null) {
          throw StateError(
            'This legacy derived-account recovery marker cannot prove its '
            'origin. Recovery is required before creating another account.',
          );
        }
        nativeLease = await rust_wallet.resumeSoftwareAccountDerivationLease(
          dbPath: dbPath,
          previousOperationToken: existingFence.operationToken!,
        );
        recoveryFence = existingFence;
      } else {
        final claimed = await rust_wallet
            .claimPendingSoftwareAccountDerivationLease(dbPath: dbPath);
        if (claimed != null) {
          nativeLease = claimed;
          try {
            recoveryFence = _recoveryFenceFromNativeLease(
              nativeLease,
              requireStoredIntent: true,
            );
          } catch (_) {
            // A legacy native record without a Dart fence cannot be guessed.
            // Release only this process lease; leave its persistent barrier in
            // place so every constructor remains denied pending manual repair.
            await rust_wallet.finishSoftwareAccountDerivationLease(
              operationToken: nativeLease.operationToken,
            );
            rethrow;
          }
        } else {
          // Do not create a durable native operation until this source is
          // proven to have a local software secret. In particular, a
          // hardware account cannot leave a fence that no process can use.
          final sourceSecret = await getSoftwareWalletSecretForAccount(
            sourceAccountUuid,
          );
          if (sourceSecret == null) {
            throw StateError(
              'No recovery phrase available for account $sourceAccountUuid',
            );
          }
          // Bootstrap can recover the opaque family identifier from Rust for
          // an older wallet without writing it back to secure storage. Make
          // that authenticated source metadata durable before native records
          // an allocation intent, so crash recovery can prove the delta.
          await _persistDurableSourceSeedFamilyMetadata(
            dbPath: dbPath,
            network: network,
            sourceAccountUuid: sourceAccountUuid,
          );
          sourceSeedFamilyPersistedBeforeLease = true;
          nativeLease = await rust_wallet.beginSoftwareAccountDerivationLease(
            dbPath: dbPath,
            network: network,
            sourceAccountUuid: sourceAccountUuid,
            recoveryName: requestedAccountName,
            recoveryProfilePictureId: requestedProfilePictureId,
            recoveryAccountGroupName: requestedSourceAccount.accountGroupName,
          );
          recoveryFence = _recoveryFenceFromNativeLease(nativeLease);
        }
      }
      final operationToken = nativeLease.operationToken;
      // Preserve the exact serialized legacy/current fence that was
      // authenticated. Version-two fences written before optional JSON fields
      // were introduced need not byte-match a fresh encode.
      final recoveryFenceRaw = existingRawFence ?? recoveryFence.encode();
      try {
        if (!sourceSeedFamilyPersistedBeforeLease) {
          await _persistDurableSourceSeedFamilyMetadata(
            dbPath: dbPath,
            network: network,
            sourceAccountUuid: recoveryFence.sourceAccountUuid,
          );
        }
        // Once source metadata is durable, this is the first persistent Dart
        // write after a no-fence native claim or begin. If it fails without
        // persisting, Rust proves the baseline still has no delta before
        // aborting; otherwise its authoritative intent remains claimable on
        // the next restart.
        if (existingRawFence == null || existingRawFence.isEmpty) {
          try {
            await _storage.writeString(
              _derivedAccountRecoveryKey,
              recoveryFenceRaw,
            );
          } catch (_) {
            final persistedFence = await _storage.readString(
              _derivedAccountRecoveryKey,
            );
            if (persistedFence != recoveryFenceRaw) {
              await rust_wallet.resolveSoftwareAccountDerivationLease(
                operationToken: operationToken,
              );
            }
            rethrow;
          }
        }
        // A retry is a recovery opportunity, never a second blind allocation.
        if (await _recoverPendingDerivedAccount(
          dbPath: dbPath,
          network: network,
          nativeLease: nativeLease,
        )) {
          return;
        }

        if (!nativeLease.isPending) {
          throw StateError(
            'The native derivation recovery record is resolved but its Dart '
            'fence could not be reconciled safely.',
          );
        }

        final secret = await getSoftwareWalletSecretForAccount(
          recoveryFence.sourceAccountUuid,
        );
        if (secret == null) {
          throw StateError(
            'No recovery phrase available for account '
            '${recoveryFence.sourceAccountUuid}',
          );
        }

        final birthday = await _fetchCreationBirthdayHeight();
        log('deriveAccountFromExistingSeed: birthday=$birthday');

        final accounts = state.value?.accounts ?? [];
        if (!accounts.any(
          (account) => account.uuid == recoveryFence.sourceAccountUuid,
        )) {
          throw StateError(
            'The durable derivation recovery intent names an unknown source account.',
          );
        }
        final accountName = recoveryFence.name;
        final normalizedProfilePictureId = recoveryFence.profilePictureId;

        final result = await rust_wallet.deriveNextSoftwareAccount(
          mnemonic: secret.mnemonic,
          bip39Passphrase: secret.bip39Passphrase,
          birthdayHeight: birthday,
          network: network,
          dbPath: dbPath,
          name: accountName,
          operationToken: operationToken,
        );

        final newAccount = AccountInfo(
          uuid: result.accountUuid,
          name: accountName,
          order: accounts.length,
          isSeedAnchor: result.isSeedAnchor,
          profilePictureId: normalizedProfilePictureId,
          seedFamilyId: result.seedFamilyId,
          accountGroupName: recoveryFence.accountGroupName,
        );
        final updatedAccounts = [
          for (final account in accounts)
            if (account.uuid == recoveryFence.sourceAccountUuid &&
                result.seedFamilyId != null)
              account.copyWith(seedFamilyId: result.seedFamilyId)
            else
              account,
          newAccount,
        ];

        var mnemonicWriteAttempted = false;
        var accountsWriteAttempted = false;
        var activeAccountWriteAttempted = false;
        try {
          mnemonicWriteAttempted = true;
          await _storage.writeAccountMnemonic(
            result.accountUuid,
            secret.mnemonic,
            bip39Passphrase: secret.bip39Passphrase,
          );
          accountsWriteAttempted = true;
          await _saveAccounts(updatedAccounts);
          activeAccountWriteAttempted = true;
          await _storage.writeString(_activeAccountKey, result.accountUuid);
        } catch (error, stackTrace) {
          Future<List<Object>> attemptOperations(
            Iterable<Future<void> Function()> operations,
            String phase,
          ) async {
            final failures = <Object>[];
            for (final operation in operations) {
              try {
                await operation();
              } catch (cleanupError, cleanupStackTrace) {
                failures.add(cleanupError);
                log(
                  'deriveAccountFromExistingSeed: $phase failed: '
                  '$cleanupError\n$cleanupStackTrace',
                );
              }
            }
            return failures;
          }

          Object? rustDeleteFailure;
          try {
            await rust_wallet.deleteAccountUnderSoftwareAccountDerivationLease(
              dbPath: dbPath,
              network: network,
              accountUuid: result.accountUuid,
              operationToken: operationToken,
            );
          } catch (deleteError, deleteStackTrace) {
            rustDeleteFailure = deleteError;
            log(
              'deriveAccountFromExistingSeed: Rust rollback failed: '
              '$deleteError\n$deleteStackTrace',
            );
          }

          if (rustDeleteFailure != null) {
            try {
              final recoveredAccountUuid = await _reconcileDerivedAccountFence(
                recoveryFence,
                dbPath: dbPath,
                network: network,
              );
              if (recoveredAccountUuid == null) {
                throw StateError(
                  'Rust deletion failed but no derived account was found for '
                  'the durable recovery fence.',
                );
              }
            } catch (recoveryError) {
              Error.throwWithStackTrace(
                DerivedAccountCompensationException(
                  cause: error,
                  cleanupFailures: [rustDeleteFailure, recoveryError],
                ),
                stackTrace,
              );
            }
            Error.throwWithStackTrace(
              DerivedAccountRecoveryRequiredException(
                accountUuid: result.accountUuid,
                cause: error,
                cleanupFailures: [rustDeleteFailure],
              ),
              stackTrace,
            );
          }

          final cleanupOperations = <Future<void> Function()>[];
          if (activeAccountWriteAttempted) {
            cleanupOperations.add(() async {
              final previousActiveUuid = state.value?.activeAccountUuid;
              if (previousActiveUuid == null) {
                await _storage.delete(_activeAccountKey);
              } else {
                await _storage.writeString(
                  _activeAccountKey,
                  previousActiveUuid,
                );
              }
            });
          }
          if (accountsWriteAttempted) {
            cleanupOperations.add(() => _saveAccounts(accounts));
          }
          if (mnemonicWriteAttempted) {
            cleanupOperations.add(
              () => _storage.deleteAccountMnemonic(result.accountUuid),
            );
          }
          final cleanupFailures = await attemptOperations(
            cleanupOperations,
            'rollback cleanup',
          );

          if (cleanupFailures.isNotEmpty) {
            Error.throwWithStackTrace(
              DerivedAccountCompensationException(
                cause: error,
                cleanupFailures: cleanupFailures,
              ),
              stackTrace,
            );
          }
          // If fence deletion fails, it remains a safe cross-process barrier.
          // The next derive will first prove no Rust delta remains and clear it.
          try {
            await rust_wallet.resolveSoftwareAccountDerivationLease(
              operationToken: operationToken,
            );
            await _clearRecoveryFence(expectedRawFence: recoveryFenceRaw);
          } catch (cleanupError) {
            Error.throwWithStackTrace(
              DerivedAccountCompensationException(
                cause: error,
                cleanupFailures: [cleanupError],
              ),
              stackTrace,
            );
          }
          Error.throwWithStackTrace(error, stackTrace);
        }

        state = AsyncData(
          AccountState(
            accounts: updatedAccounts,
            activeAccountUuid: result.accountUuid,
            activeAddress: result.unifiedAddress,
          ),
        );

        try {
          await _clearRecoveryFenceAfterDurableValidation(
            result.accountUuid,
            dbPath: dbPath,
            network: network,
            expectedRawFence: recoveryFenceRaw,
            operationToken: operationToken,
            nativeRecordIsPending: nativeLease.isPending,
          );
        } catch (recoveryError, recoveryStackTrace) {
          log(
            'deriveAccountFromExistingSeed: completed account but retained '
            'recovery fence: $recoveryError\n$recoveryStackTrace',
          );
          throw DerivedAccountRecoveryRequiredException(
            accountUuid: result.accountUuid,
            cause: recoveryError,
          );
        }

        log(
          'deriveAccountFromExistingSeed: success, uuid=${result.accountUuid}, '
          'zip32Index=${result.zip32AccountIndex}',
        );
      } finally {
        await rust_wallet.finishSoftwareAccountDerivationLease(
          operationToken: operationToken,
        );
      }
    } catch (e, st) {
      log('deriveAccountFromExistingSeed: ERROR: $e\n$st');
      rethrow;
    } finally {
      _deriveOperationInFlight = false;
    }
  }

  /// Clears the safety marker after the retained derived account's locally
  /// stored signing secret and metadata have been reviewed. This deliberately
  /// requires an explicit caller action so a retry cannot silently advance the
  /// ZIP 32 index after a failed Rust rollback.
  Future<void> acknowledgeDerivedAccountRecovery() async {
    final dbPath = await _getDbPath();
    final network = ref.read(rpcEndpointProvider).networkName;
    final rawFence = await _storage.readString(_derivedAccountRecoveryKey);
    if (rawFence == null || rawFence.isEmpty) return;
    final fence = _DerivedAccountRecoveryFence.decode(rawFence);
    if (fence.isLegacy || fence.operationToken == null) {
      throw StateError(
        'This legacy derived-account recovery marker cannot prove its origin. '
        'Do not remove or activate accounts until it is resolved manually.',
      );
    }
    final nativeLease = await rust_wallet.resumeSoftwareAccountDerivationLease(
      dbPath: dbPath,
      previousOperationToken: fence.operationToken!,
    );
    try {
      await _recoverPendingDerivedAccount(
        dbPath: dbPath,
        network: network,
        nativeLease: nativeLease,
      );
    } finally {
      await rust_wallet.finishSoftwareAccountDerivationLease(
        operationToken: nativeLease.operationToken,
      );
    }
  }

  /// Resolves the durable derivation fence before a retry can reach Rust.
  /// Returns true when a retained account was recovered for the caller's
  /// original derive action, so the UI can complete that action without
  /// allocating a second account.
  Future<bool> _recoverPendingDerivedAccount({
    required String dbPath,
    required String network,
    required rust_wallet.SoftwareAccountDerivationLease nativeLease,
  }) async {
    final rawFence = await _storage.readString(_derivedAccountRecoveryKey);
    if (rawFence == null || rawFence.isEmpty) return false;

    final fence = _DerivedAccountRecoveryFence.decode(rawFence);
    if (fence.isLegacy) {
      throw StateError(
        'This legacy derived-account recovery marker cannot prove which '
        'operation created its UUID. Recovery is required before proceeding.',
      );
    }
    _assertRecoveryFenceMatchesNative(fence, nativeLease);

    final recoveredAccountUuid = await _reconcileDerivedAccountFence(
      fence,
      dbPath: dbPath,
      network: network,
    );
    if (recoveredAccountUuid == null) {
      // The fence persisted before a Rust call that never committed. Retain
      // it while the same native pending lease proceeds: deleting it first
      // recreates the crash window where SQLite is pending but Dart has no
      // authenticated fence. Once native has already resolved the exact
      // no-delta operation, retaining it would create a permanent barrier
      // after a crash between native resolution and Dart deletion.
      if (!nativeLease.isPending) {
        await _clearRecoveryFence(expectedRawFence: rawFence);
        return true;
      }
      return false;
    }

    await _clearRecoveryFenceAfterDurableValidation(
      recoveredAccountUuid,
      dbPath: dbPath,
      network: network,
      expectedRawFence: rawFence,
      operationToken: nativeLease.operationToken,
      nativeRecordIsPending: nativeLease.isPending,
    );
    return true;
  }

  /// Reconstructs a Dart account from the Rust delta held behind [fence].
  /// The fence is intentionally left in place until a later durable
  /// validation clears it.
  Future<String?> _reconcileDerivedAccountFence(
    _DerivedAccountRecoveryFence fence, {
    required String dbPath,
    required String network,
  }) async {
    final rustAccounts = await rust_wallet.listAccounts(
      dbPath: dbPath,
      network: network,
    );
    final durableAccounts = await _readDurableAccounts();
    final source = durableAccounts.where(
      (account) => account.uuid == fence.sourceAccountUuid,
    );
    if (source.length != 1 || source.single.seedFamilyId == null) {
      throw StateError(
        'Cannot reconcile a derived account without durable source seed '
        'family metadata.',
      );
    }
    final sourceSeedFamilyId = source.single.seedFamilyId;
    final deltas = rustAccounts
        .where((account) => !fence.baselineAccountUuids.contains(account.uuid))
        .toList();
    if (deltas.isEmpty) return null;
    if (deltas.length != 1 ||
        deltas.single.isHardware ||
        deltas.single.seedFamilyId != sourceSeedFamilyId) {
      throw StateError(
        'Derived account recovery fence has Rust deltas that cannot be proven '
        'to belong to its source seed family.',
      );
    }

    final candidate = deltas.single;
    final sourceSecret = await getSoftwareWalletSecretForAccount(
      fence.sourceAccountUuid,
    );
    if (sourceSecret == null) {
      throw StateError(
        'Cannot reconcile derived account ${candidate.uuid} without the '
        'source signing secret.',
      );
    }

    final recoveredAccount = AccountInfo(
      uuid: candidate.uuid,
      name: fence.name,
      order: durableAccounts.length,
      isSeedAnchor: candidate.isSeedAnchor,
      profilePictureId: fence.profilePictureId,
      seedFamilyId: candidate.seedFamilyId,
      accountGroupName: fence.accountGroupName,
    );
    final hasCandidate = durableAccounts.any(
      (account) => account.uuid == candidate.uuid,
    );
    final reconciledAccounts = [
      for (final account in durableAccounts)
        if (account.uuid == fence.sourceAccountUuid &&
            candidate.seedFamilyId != null)
          account.copyWith(seedFamilyId: candidate.seedFamilyId)
        else
          account,
      if (!hasCandidate) recoveredAccount,
    ];

    await _storage.writeAccountMnemonic(
      candidate.uuid,
      sourceSecret.mnemonic,
      bip39Passphrase: sourceSecret.bip39Passphrase,
    );
    await _saveAccounts(reconciledAccounts);
    await _storage.writeString(_activeAccountKey, candidate.uuid);
    await _publishDurablyRecoveredAccount(
      candidate.uuid,
      dbPath: dbPath,
      network: network,
    );
    return candidate.uuid;
  }

  /// Reads from secure storage rather than Riverpod so acknowledgement remains
  /// safe after bootstrap recreated in-memory accounts from Rust alone.
  Future<List<AccountInfo>> _readDurableAccounts() async {
    final rawAccounts = await _storage.readString(_accountsKey);
    if (rawAccounts == null) return const [];
    final decoded = jsonDecode(rawAccounts);
    if (decoded is! List) {
      throw StateError('Stored account metadata is not a list.');
    }
    return decoded.map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw StateError('Stored account metadata contains an invalid row.');
      }
      return AccountInfo.fromJson(entry);
    }).toList();
  }

  Future<void> _persistDurableSourceSeedFamilyMetadata({
    required String dbPath,
    required String network,
    required String sourceAccountUuid,
  }) async {
    final rustSources = (await rust_wallet.listAccounts(
      dbPath: dbPath,
      network: network,
    )).where((account) => account.uuid == sourceAccountUuid).toList();
    if (rustSources.length != 1 ||
        rustSources.single.isHardware ||
        rustSources.single.seedFamilyId == null) {
      throw StateError(
        'Cannot derive an account without authenticated software seed family metadata.',
      );
    }

    final rustSeedFamilyId = rustSources.single.seedFamilyId!;
    final durableAccounts = await _readDurableAccounts();
    final sourceIndex = durableAccounts.indexWhere(
      (account) => account.uuid == sourceAccountUuid,
    );
    if (sourceIndex < 0 || durableAccounts[sourceIndex].isHardware) {
      throw StateError(
        'Cannot derive an account without durable software source metadata.',
      );
    }

    final durableSeedFamilyId = durableAccounts[sourceIndex].seedFamilyId;
    if (durableSeedFamilyId != null &&
        durableSeedFamilyId != rustSeedFamilyId) {
      throw StateError(
        'Durable source seed family metadata does not match the wallet database.',
      );
    }
    if (durableSeedFamilyId == rustSeedFamilyId) return;

    final updatedAccounts = [...durableAccounts];
    updatedAccounts[sourceIndex] = durableAccounts[sourceIndex].copyWith(
      seedFamilyId: rustSeedFamilyId,
    );
    await _saveAccounts(updatedAccounts);
  }

  Future<void> _publishDurablyRecoveredAccount(
    String accountUuid, {
    required String dbPath,
    required String network,
  }) async {
    final durableAccounts = await _readDurableAccounts();
    if (!durableAccounts.any((account) => account.uuid == accountUuid)) {
      throw StateError(
        'Cannot acknowledge derived account recovery for $accountUuid until '
        'its durable local account metadata is restored.',
      );
    }
    final secret = await getSoftwareWalletSecretForAccount(accountUuid);
    if (secret == null) {
      throw StateError(
        'Cannot acknowledge derived account recovery for $accountUuid until '
        'its encrypted signing secret is restored.',
      );
    }
    final rustAccounts = await rust_wallet.listAccounts(
      dbPath: dbPath,
      network: network,
    );
    final rustAccount = rustAccounts.where(
      (account) => account.uuid == accountUuid,
    );
    if (rustAccount.isEmpty) {
      throw StateError(
        'Cannot acknowledge derived account recovery for $accountUuid because '
        'Rust no longer contains that account.',
      );
    }

    state = AsyncData(
      AccountState(
        accounts: durableAccounts,
        activeAccountUuid: accountUuid,
        activeAddress: rustAccount.single.unifiedAddress,
      ),
    );
  }

  Future<void> _clearRecoveryFenceAfterDurableValidation(
    String accountUuid, {
    required String dbPath,
    required String network,
    required String expectedRawFence,
    required String operationToken,
    required bool nativeRecordIsPending,
  }) async {
    await _publishDurablyRecoveredAccount(
      accountUuid,
      dbPath: dbPath,
      network: network,
    );
    if (nativeRecordIsPending) {
      await rust_wallet.resolveSoftwareAccountDerivationLease(
        operationToken: operationToken,
        accountUuid: accountUuid,
      );
    }
    await _clearRecoveryFence(expectedRawFence: expectedRawFence);
  }

  /// Clears only the exact journal inspected under the caller's native lease.
  /// This compare-before-delete prevents stale metadata from deleting a fence
  /// written by a later operation.
  Future<void> _clearRecoveryFence({required String expectedRawFence}) async {
    final current = await _storage.readString(_derivedAccountRecoveryKey);
    if (current != expectedRawFence) {
      throw StateError('Derived account recovery fence ownership changed.');
    }
    try {
      await _storage.delete(_derivedAccountRecoveryKey);
    } catch (error) {
      // A keychain write can persist and still report an error. Read-after-
      // failure distinguishes a cleared fence from one that must remain.
      final remaining = await _storage.readString(_derivedAccountRecoveryKey);
      if (remaining == null || remaining.isEmpty) return;
      rethrow;
    }
    final remaining = await _storage.readString(_derivedAccountRecoveryKey);
    if (remaining != null && remaining.isNotEmpty) {
      throw StateError('Derived account recovery fence could not be cleared.');
    }
  }

  /// Import a wallet from mnemonic.
  Future<void> importAccount({
    required String mnemonic,
    String bip39Passphrase = '',
    int? birthdayHeight,
    String? name,
    String profilePictureId = kDefaultProfilePictureId,
    List<int> additionalAccountIndices = const [],
  }) async {
    try {
      final dbPath = await _getDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final network = (state.value?.accounts ?? const <AccountInfo>[]).isEmpty
          ? endpoint.networkName
          : await _getNetwork();
      final accounts = state.value?.accounts ?? [];
      final accountName = normalizeAccountName(
        name ?? 'Account ${accounts.length + 1}',
      );
      validateAccountName(accountName);
      if (!isKnownProfilePictureId(profilePictureId)) {
        throw ArgumentError.value(
          profilePictureId,
          'profilePictureId',
          'Unknown profile picture id',
        );
      }
      final normalizedProfilePictureId = normalizeProfilePictureId(
        profilePictureId,
      );
      final isFirstWalletAccount = accounts.isEmpty;
      final previousActiveAccountUuid = state.value?.activeAccountUuid;
      final previousActiveAddress = state.value?.activeAddress;

      if (isFirstWalletAccount) {
        await _deleteExistingDb(dbPath);
      }

      final result = await rust_wallet.importSoftwareWalletWithAccountDiscovery(
        mnemonic: mnemonic,
        bip39Passphrase: bip39Passphrase,
        birthdayHeight: birthdayHeight != null
            ? BigInt.from(birthdayHeight)
            : null,
        network: network,
        dbPath: dbPath,
        firstAccountName: accountName,
        isFirstWalletAccount: isFirstWalletAccount,
        nextAccountNumber: accounts.length + 1,
        additionalAccountIndices: additionalAccountIndices,
      );
      if (result.accounts.isEmpty) {
        throw StateError('Software wallet import did not return an account.');
      }
      if (isFirstWalletAccount) {
        await _storage.writeString(_networkKey, network);
      }

      for (final account in result.accounts) {
        await _storage.writeAccountMnemonic(
          account.accountUuid,
          mnemonic,
          bip39Passphrase: bip39Passphrase,
        );
      }

      final importedAccounts = [
        for (var i = 0; i < result.accounts.length; i++)
          AccountInfo(
            uuid: result.accounts[i].accountUuid,
            name: result.accounts[i].name,
            order: accounts.length + i,
            isSeedAnchor: result.accounts[i].isSeedAnchor,
            profilePictureId: i == 0
                ? normalizedProfilePictureId
                : kDefaultProfilePictureId,
            seedFamilyId: result.accounts[i].seedFamilyId,
            accountGroupName: existingAccountGroupNameForSeedFamily(
              accounts,
              result.accounts[i].seedFamilyId,
            ),
          ),
      ];
      final updatedAccounts = [...accounts, ...importedAccounts];
      await _saveAccounts(updatedAccounts);
      final activeAccountUuid = result.didImportPrimaryAccount
          ? result.accounts.first.accountUuid
          : previousActiveAccountUuid;
      final activeAddress = result.didImportPrimaryAccount
          ? result.accounts.first.unifiedAddress
          : previousActiveAddress;
      if (activeAccountUuid == null) {
        await _storage.delete(_activeAccountKey);
      } else if (result.didImportPrimaryAccount) {
        await _storage.writeString(_activeAccountKey, activeAccountUuid);
      }

      state = AsyncData(
        AccountState(
          accounts: updatedAccounts,
          activeAccountUuid: activeAccountUuid,
          activeAddress: activeAddress,
        ),
      );

      log(
        'importAccount: success, active=$activeAccountUuid, '
        'accounts=${result.accounts.map((a) => a.zip32AccountIndex).join(',')}',
      );
    } catch (e, st) {
      log('importAccount: ERROR: $e\n$st');
      rethrow;
    }
  }

  Future<rust_wallet.SoftwareWalletImportDiscoveryResult>
  discoverAdditionalSoftwareAccounts({
    required String mnemonic,
    String bip39Passphrase = '',
    int? birthdayHeight,
  }) async {
    try {
      final dbPath = await _getDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final accounts = state.value?.accounts ?? const <AccountInfo>[];
      final isFirstWalletAccount = accounts.isEmpty;
      final network = isFirstWalletAccount
          ? endpoint.networkName
          : await _getNetwork();

      return rust_wallet.discoverSoftwareWalletImportAccounts(
        mnemonic: mnemonic,
        bip39Passphrase: bip39Passphrase,
        birthdayHeight: birthdayHeight != null
            ? BigInt.from(birthdayHeight)
            : null,
        network: network,
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        isFirstWalletAccount: isFirstWalletAccount,
      );
    } catch (e, st) {
      log('discoverAdditionalSoftwareAccounts: ERROR: $e\n$st');
      rethrow;
    }
  }

  Future<BigInt> previewSoftwareAccountTransparentBalance({
    required String mnemonic,
    String bip39Passphrase = '',
    required int accountIndex,
  }) async {
    try {
      final endpoint = ref.read(rpcEndpointProvider);
      final accounts = state.value?.accounts ?? const <AccountInfo>[];
      final isFirstWalletAccount = accounts.isEmpty;
      final network = isFirstWalletAccount
          ? endpoint.networkName
          : await _getNetwork();

      return rust_wallet.previewSoftwareAccountTransparentBalance(
        mnemonic: mnemonic,
        bip39Passphrase: bip39Passphrase,
        network: network,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        zip32AccountIndex: accountIndex,
      );
    } catch (e, st) {
      log('previewSoftwareAccountTransparentBalance: ERROR: $e\n$st');
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

  /// Rename the seed family containing [anchorAccountUuid].
  ///
  /// Accounts without seed-family metadata are intentionally treated as a
  /// one-account family, matching how the Accounts UI groups legacy and
  /// hardware records.
  Future<void> renameAccountGroup(
    String anchorAccountUuid,
    String newName,
  ) async {
    validateAccountName(newName);
    final normalizedName = normalizeAccountName(newName);
    final prev = state.value ?? const AccountState();
    final anchorIndex = prev.accounts.indexWhere(
      (account) => account.uuid == anchorAccountUuid,
    );
    if (anchorIndex < 0) {
      throw ArgumentError.value(
        anchorAccountUuid,
        'anchorAccountUuid',
        'Unknown account UUID',
      );
    }
    final anchor = prev.accounts[anchorIndex];
    final seedFamilyId = _normalizedOptionalString(anchor.seedFamilyId);
    final updated = [
      for (final account in prev.accounts)
        if (anchor.isHardware || seedFamilyId == null || account.isHardware
            ? account.uuid == anchor.uuid
            : _normalizedOptionalString(account.seedFamilyId) == seedFamilyId)
          account.copyWith(accountGroupName: normalizedName)
        else
          account,
    ];
    await _saveAccounts(updated);
    state = AsyncData(prev.copyWith(accounts: updated));
    log('renameAccountGroup: $anchorAccountUuid → $normalizedName');
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
    final dbPath = await _getDbPath();
    final network = await _getNetwork();
    if (await rust_wallet.isSoftwareAccountDerivationLocked(dbPath: dbPath)) {
      throw StateError(
        'Finish the in-progress software account creation before removing an account.',
      );
    }
    // A crashed process releases its OS lease, but its durable fence can still
    // need this source mnemonic and metadata to reconcile the Rust delta. A
    // legacy fence has no source UUID, so fail closed for every removal.
    final rawRecoveryFence = await _storage.readString(
      _derivedAccountRecoveryKey,
    );
    if (rawRecoveryFence != null && rawRecoveryFence.isNotEmpty) {
      final recoveryFence = _DerivedAccountRecoveryFence.decode(
        rawRecoveryFence,
      );
      if (recoveryFence.isLegacy || recoveryFence.sourceAccountUuid == uuid) {
        throw StateError(
          'Resolve the pending software account recovery before removing its source account.',
        );
      }
    }
    final migrationRevocation = await IronwoodMigrationOperationRegistry
        .instance
        .revokeAndWait(network: network, accountUuid: uuid);
    final migrationLifecycle = IronwoodMigrationBackgroundLifecycle.instance;
    final migrationQuiescenceManagedByCaller =
        migrationLifecycle.isQuiescenceManagedByCaller;
    try {
      if (!migrationQuiescenceManagedByCaller) {
        await migrationLifecycle.quiesce();
      }
      await _resetVotingProcessStateForAccount(uuid, dbPath: dbPath);
      await migrationLifecycle.revokeAccount(
        network: network,
        accountUuid: uuid,
      );
      final rustDeleteWatch = Stopwatch()..start();
      await rust_wallet.deleteAccount(
        dbPath: dbPath,
        network: network,
        accountUuid: uuid,
      );
      migrationRevocation.commit();
      log(
        'removeAccount: rust delete complete in '
        '${rustDeleteWatch.elapsedMilliseconds}ms uuid=$uuid',
      );
    } catch (_) {
      migrationRevocation.rollback();
      if (!migrationQuiescenceManagedByCaller) {
        try {
          await migrationLifecycle.resumeAfterFailedMutation();
        } catch (e, st) {
          log(
            'removeAccount: failed to resume migration after keeping '
            '$uuid: $e\n$st',
          );
        }
      }
      rethrow;
    }
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
    if (!migrationQuiescenceManagedByCaller) {
      try {
        await migrationLifecycle.resumeAfterMutation();
      } catch (e, st) {
        log(
          'removeAccount: failed to resume migration for remaining '
          'accounts: $e\n$st',
        );
      }
    }
    log('removeAccount: $uuid');
  }

  /// Delete all wallet data (DB + keychain). Caller must stop sync first.
  ///
  /// This also clears voting state held in this process for every account
  /// before the wallet DB and voting sidecar DB are deleted.
  ///
  /// Migration work must first stop without deleting its credential. After
  /// that fail-closed preflight, the wipe is best-effort: deletion steps remain
  /// retryable and the first error is rethrown after all safe cleanup attempts.
  ///
  /// Once the durable wallet data is gone, the Tor route is returned to Direct
  /// and its on-disk state is cleared too — see [clearTorPrivacyStateForReset].
  Future<void> resetWallet() async {
    ref.read(votingSubmissionGuardProvider.notifier).throwIfActive();

    // Resolve the DB path before touching anything. Secure storage holds the
    // randomized wallet DB name, so if this lookup fails we must abort with
    // NOTHING deleted: wiping storage now would orphan the still-existing DB
    // file (a retry would generate a fresh name and never find the old one).
    final dbPath = await _getDbPath();
    final resetLeaseToken = await rust_wallet.beginWalletResetLease(
      dbPath: dbPath,
    );
    try {
      await _resetWalletUnderAccountMutationLease(dbPath);
    } finally {
      await rust_wallet.finishWalletResetLease(operationToken: resetLeaseToken);
    }
  }

  Future<void> _resetWalletUnderAccountMutationLease(String dbPath) async {
    Object? firstError;
    StackTrace? firstStackTrace;
    void recordError(String step, Object e, StackTrace st) {
      log('resetWallet: $step failed: $e\n$st');
      firstError ??= e;
      firstStackTrace ??= st;
    }

    final network = await _getNetwork();
    final migrationRevocations = <IronwoodMigrationAccountRevocation>[];
    final migrationLifecycle = IronwoodMigrationBackgroundLifecycle.instance;
    final migrationQuiescenceManagedByCaller =
        migrationLifecycle.isQuiescenceManagedByCaller;
    Future<void> rollbackMigrationPreflight() async {
      for (final revocation in migrationRevocations) {
        revocation.rollback();
      }
      if (migrationQuiescenceManagedByCaller) return;
      try {
        await migrationLifecycle.resumeAfterFailedMutation();
      } catch (e, st) {
        log('resetWallet: failed to resume retained migration: $e\n$st');
      }
    }

    try {
      for (final account in state.value?.accounts ?? const <AccountInfo>[]) {
        migrationRevocations.add(
          await IronwoodMigrationOperationRegistry.instance.revokeAndWait(
            network: network,
            accountUuid: account.uuid,
          ),
        );
      }
    } catch (_) {
      for (final revocation in migrationRevocations) {
        revocation.rollback();
      }
      rethrow;
    }

    // Stop native work before changing the DB. The signed outbox is revoked
    // below before the destructive step is allowed to begin.
    try {
      if (!migrationQuiescenceManagedByCaller) {
        await migrationLifecycle.quiesce();
      }
    } catch (_) {
      await rollbackMigrationPreflight();
      rethrow;
    }

    // Full reset bypasses Rust's per-account delete path, so explicitly drop
    // any unsigned or partially proved Keystone migration requests first.
    try {
      await rust_sync.discardAllKeystoneMigrationRequests();
    } catch (_) {
      await rollbackMigrationPreflight();
      rethrow;
    }

    // A signed outbox transaction must not survive deletion of the wallet DB.
    // Revoke native work first so a failed cleanup leaves the wallet intact.
    try {
      await migrationLifecycle.revokeAll();
    } catch (_) {
      await rollbackMigrationPreflight();
      rethrow;
    }

    // Best-effort internally; tolerates per-account failures.
    for (final account in state.value?.accounts ?? const <AccountInfo>[]) {
      await _resetVotingProcessStateForAccount(account.uuid, dbPath: dbPath);
    }

    var dbDeleted = false;
    try {
      await _deleteExistingDb(dbPath);
      dbDeleted = true;
      for (final revocation in migrationRevocations) {
        revocation.commit();
      }
    } catch (e, st) {
      await rollbackMigrationPreflight();
      recordError('wallet db deletion', e, st);
    }
    // Only wipe secure storage once the DB file is confirmed gone: the wipe
    // destroys the stored DB name, which is the only way a retry can target
    // the original DB file. After a successful DB delete the wipe stays
    // retryable (deleteAll is idempotent and a regenerated DB name only
    // no-ops the next, already-satisfied DB delete).
    if (dbDeleted) {
      try {
        await rust_wallet.evictWalletSummaryCache(dbPath: dbPath);
      } catch (e, st) {
        // The durable reset already succeeded. Cache cleanup is best-effort
        // and must not prevent the secure-storage wipe from completing.
        log('resetWallet: failed to evict wallet summary cache: $e\n$st');
      }
      try {
        await _storage.deleteAll();
      } catch (e, st) {
        recordError('secure storage wipe', e, st);
      }
      final privacyRuntime = ref.read(networkPrivacyRuntimeProvider);
      final directRequests = ref.read(networkPrivacyDirectRequestGateProvider);
      await clearTorPrivacyStateForReset(
        switchRouteToDirect: () async {
          await privacyRuntime.configure(enabled: false);
          // Fail-closed routing blocks direct requests for the rest of the
          // session, and the wallet this route belonged to no longer exists.
          directRequests.allow();
          // Onboarding can reach the network setting again, so the published
          // route has to match the one Rust is now on. Going through
          // setTorEnabled instead would restart sync in the middle of the wipe.
          ref.read(networkPrivacyProvider.notifier).markRouteDirectAfterReset();
        },
      );
    }

    final error = firstError;
    if (error != null) {
      Error.throwWithStackTrace(
        WalletResetException(cause: error, dbDeleted: dbDeleted),
        firstStackTrace ?? StackTrace.current,
      );
    }
    // Clear the account state BEFORE flipping security back to locked: the
    // router derives requiresUnlock from hasWallet && !isUnlocked, so the
    // reverse order bounces a locked-start session to /unlock mid-uninstall
    // (the /settings/uninstall exemption only covers the no-wallet branch).
    state = const AsyncData(AccountState());
    try {
      ref.read(appSecurityProvider.notifier).reset();
    } catch (e, st) {
      log('resetWallet: app security reset failed: $e\n$st');
    }
    if (!migrationQuiescenceManagedByCaller) {
      try {
        await migrationLifecycle.resumeAfterMutation();
      } catch (e, st) {
        log('resetWallet: failed to leave migration quiescence: $e\n$st');
      }
    }
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
    String profilePictureId = kDefaultProfilePictureId,
  }) async {
    try {
      final accountName = normalizeAccountName(name);
      validateAccountName(accountName);
      if (!isKnownProfilePictureId(profilePictureId)) {
        throw ArgumentError.value(
          profilePictureId,
          'profilePictureId',
          'Unknown profile picture id',
        );
      }
      final normalizedProfilePictureId = normalizeProfilePictureId(
        profilePictureId,
      );
      final prev = state.value ?? const AccountState();
      final dbPath = await _getDbPath();
      final network = await _getNetwork();

      final result = await rust_wallet.importHardwareAccount(
        dbPath: dbPath,
        network: network,
        name: accountName,
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
        name: accountName,
        order: prev.accounts.length,
        isHardware: true,
        profilePictureId: normalizedProfilePictureId,
        seedFamilyId: result.seedFamilyId,
        accountGroupName: existingAccountGroupNameForSeedFamily(
          prev.accounts,
          result.seedFamilyId,
          isHardware: true,
        ),
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

  Future<LinkedWalletAccountsImportResult> importLinkedWalletAccounts({
    required String network,
    required List<LinkedWalletAccountImport> accountsToImport,
  }) async {
    if (accountsToImport.isEmpty) {
      throw ArgumentError.value(
        accountsToImport,
        'accountsToImport',
        'Select at least one wallet link account.',
      );
    }

    try {
      final prev = state.value ?? const AccountState();
      final normalizedNetwork = await _validateLinkedWalletNetwork(
        network: network,
        current: prev,
      );

      final dbPath = await _getDbPath();
      if (prev.accounts.isEmpty) {
        await _deleteExistingDb(dbPath);
        await _storage.writeString(_networkKey, normalizedNetwork);
      }

      final importedAccounts = <AccountInfo>[];
      String? firstImportedUuid;
      String? firstImportedAddress;
      var nextOrder = prev.accounts.length;
      var skippedDuplicateCount = 0;

      for (final input in accountsToImport) {
        late final String accountUuid;
        late final String unifiedAddress;
        late final bool isSeedAnchor;
        late final String? seedFamilyId;
        try {
          if (input.isHardware) {
            final result = await rust_wallet.importHardwareAccount(
              dbPath: dbPath,
              network: normalizedNetwork,
              name: input.name,
              ufvkString: input.ufvk ?? '',
              seedFingerprint: input.seedFingerprint ?? const [],
              zip32Index: input.zip32AccountIndex,
              birthdayHeight: BigInt.from(input.birthdayHeight),
            );
            accountUuid = result.accountUuid;
            unifiedAddress = result.unifiedAddress;
            isSeedAnchor = false;
            seedFamilyId = result.seedFamilyId;
          } else {
            final result = await rust_wallet.importSoftwareAccountAtIndex(
              mnemonic: input.mnemonic ?? '',
              bip39Passphrase: input.bip39Passphrase,
              birthdayHeight: BigInt.from(input.birthdayHeight),
              network: normalizedNetwork,
              dbPath: dbPath,
              name: input.name,
              zip32AccountIndex: input.zip32AccountIndex,
              isFirstWalletAccount:
                  prev.accounts.isEmpty && importedAccounts.isEmpty,
            );
            accountUuid = result.accountUuid;
            unifiedAddress = result.unifiedAddress;
            isSeedAnchor = result.isSeedAnchor;
            seedFamilyId = result.seedFamilyId;
          }
        } catch (error) {
          if (isWalletLinkDuplicateImportError(error)) {
            skippedDuplicateCount += 1;
            log(
              'importLinkedWalletAccounts: skipped duplicate '
              '${input.isHardware ? 'hardware' : 'software'} account '
              '"${input.name}"',
            );
            continue;
          }
          rethrow;
        }
        if (!input.isHardware) {
          await _storage.writeAccountMnemonic(
            accountUuid,
            input.mnemonic ?? '',
            bip39Passphrase: input.bip39Passphrase,
          );
        }
        firstImportedUuid ??= accountUuid;
        firstImportedAddress ??= unifiedAddress;
        importedAccounts.add(
          AccountInfo(
            uuid: accountUuid,
            name: input.name,
            order: nextOrder,
            isHardware: input.isHardware,
            isSeedAnchor: isSeedAnchor,
            profilePictureId: normalizeProfilePictureId(
              input.profilePictureId ?? kDefaultProfilePictureId,
            ),
            walletLinkSourceAccountUuid: _normalizedOptionalString(
              input.sourceAccountUuid,
            ),
            seedFamilyId: seedFamilyId,
            accountGroupName: existingAccountGroupNameForSeedFamily(
              [...prev.accounts, ...importedAccounts],
              seedFamilyId,
              isHardware: input.isHardware,
            ),
          ),
        );
        nextOrder += 1;
      }

      final updated = [...prev.accounts, ...importedAccounts];
      final activeAccountUuid = prev.activeAccountUuid ?? firstImportedUuid;
      final activeAddress = prev.activeAccountUuid == null
          ? firstImportedAddress
          : prev.activeAddress;
      await _saveAccounts(updated);
      if (activeAccountUuid == null) {
        await _storage.delete(_activeAccountKey);
      } else {
        await _storage.writeString(_activeAccountKey, activeAccountUuid);
      }

      state = AsyncData(
        AccountState(
          accounts: updated,
          activeAccountUuid: activeAccountUuid,
          activeAddress: activeAddress,
        ),
      );
      log(
        'importLinkedWalletAccounts: success, '
        'imported=${importedAccounts.length}, '
        'duplicates=$skippedDuplicateCount, active=$activeAccountUuid',
      );
      return LinkedWalletAccountsImportResult(
        importedCount: importedAccounts.length,
        skippedDuplicateCount: skippedDuplicateCount,
      );
    } catch (e, st) {
      log('importLinkedWalletAccounts: ERROR: $e\n$st');
      rethrow;
    }
  }

  Future<void> validateLinkedWalletNetwork(String network) async {
    final current = state.value ?? await future;
    await _validateLinkedWalletNetwork(network: network, current: current);
  }

  Future<Set<String>> alreadyImportedWalletLinkSourceAccountUuids({
    required String network,
    required Iterable<LinkedWalletAccountImport> accountsToCheck,
  }) async {
    final inputs = accountsToCheck.toList(growable: false);
    if (inputs.isEmpty) return const <String>{};

    final prev = await future;
    if (prev.accounts.isEmpty) return const <String>{};

    final normalizedNetwork = normalizeZcashNetworkName(network);
    final storedNetwork = await _getNetwork();
    if (storedNetwork != normalizedNetwork) return const <String>{};

    final importedSourceUuids = <String>{};
    for (final account in prev.accounts) {
      final sourceUuid = _normalizedOptionalString(
        account.walletLinkSourceAccountUuid,
      );
      if (sourceUuid != null) importedSourceUuids.add(sourceUuid);
    }
    final alreadyImported = <String>{};
    final dbPath = await _getDbPath();

    for (final input in inputs) {
      final sourceUuid = _normalizedOptionalString(input.sourceAccountUuid);
      if (sourceUuid == null) continue;
      if (importedSourceUuids.contains(sourceUuid)) {
        alreadyImported.add(sourceUuid);
        continue;
      }
      if (input.isHardware) continue;

      final mnemonic = input.mnemonic?.trim();
      if (mnemonic == null || mnemonic.isEmpty) continue;
      try {
        final isImported = await rust_wallet
            .isSoftwareWalletLinkAccountImported(
              mnemonic: mnemonic,
              bip39Passphrase: input.bip39Passphrase,
              network: normalizedNetwork,
              dbPath: dbPath,
              zip32AccountIndex: input.zip32AccountIndex,
            );
        if (isImported) alreadyImported.add(sourceUuid);
      } catch (error, stackTrace) {
        log(
          'alreadyImportedWalletLinkSourceAccountUuids: '
          'software preflight failed for "${input.name}": $error\n$stackTrace',
        );
      }
    }

    return alreadyImported;
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

  Future<SoftwareWalletSecret?> getSoftwareWalletSecretForAccount(
    String uuid,
  ) async {
    return _storage.readAccountSoftwareWalletSecret(
      uuid,
      requireUnlockedSession: true,
    );
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

  Future<String> _validateLinkedWalletNetwork({
    required String network,
    required AccountState current,
  }) async {
    final normalizedNetwork = normalizeZcashNetworkName(network);
    if (current.accounts.isEmpty) {
      final currentNetwork = normalizeZcashNetworkName(
        ref.read(rpcEndpointProvider).networkName,
      );
      if (currentNetwork != normalizedNetwork) {
        throw StateError(
          'Linked wallet network does not match the current app network.',
        );
      }
    } else {
      final storedNetwork = await _getNetwork();
      if (storedNetwork != normalizedNetwork) {
        throw StateError(
          'Linked wallet network does not match the current wallet.',
        );
      }
    }
    return normalizedNetwork;
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

@visibleForTesting
bool isWalletLinkDuplicateImportError(Object error) {
  final message = _normalizedExceptionMessage(error);
  return message == _duplicateSoftwareAccountImportMessage ||
      message == _duplicateKeystoneAccountImportMessage ||
      (message.contains('account corresponding to the data provided') &&
          message.contains('already exists in the wallet'));
}

String? _normalizedOptionalString(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

@visibleForTesting
String? existingAccountGroupNameForSeedFamily(
  List<AccountInfo> accounts,
  String? seedFamilyId, {
  bool isHardware = false,
}) {
  if (isHardware) return null;
  final normalizedSeedFamilyId = _normalizedOptionalString(seedFamilyId);
  if (normalizedSeedFamilyId == null) return null;
  for (final account in accounts) {
    if (account.isHardware) continue;
    if (_normalizedOptionalString(account.seedFamilyId) !=
        normalizedSeedFamilyId) {
      continue;
    }
    final groupName = _normalizedOptionalString(account.accountGroupName);
    if (groupName != null) return groupName;
  }
  return null;
}

String _normalizedExceptionMessage(Object error) {
  const exceptionPrefix = 'Exception: ';
  var message = error.toString();
  if (message.startsWith(exceptionPrefix)) {
    message = message.substring(exceptionPrefix.length);
  }
  final anyhowMatch = RegExp(r'^AnyhowException\((.*)\)$').firstMatch(message);
  if (anyhowMatch != null) {
    message = anyhowMatch.group(1)!;
  }
  return message;
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

/// Removes the Tor state a wallet reset leaves outside the wallet DB and
/// secure storage: the arti data directory (persisted guard selection and
/// directory cache) and the saved route preference. Neither holds key
/// material, but both are durable evidence of Tor use on this machine.
///
/// [switchRouteToDirect] must leave Rust off the Tor client: arti keeps the
/// files in its data directory open for as long as the client runs, so the
/// directory is left alone when that step fails.
///
/// Best-effort by contract — a reset that already destroyed the wallet must
/// not be reported as failed because this cleanup could not finish.
@visibleForTesting
Future<void> clearTorPrivacyStateForReset({
  required Future<void> Function() switchRouteToDirect,
  Future<String> Function() resolveTorDirectory = getTorDataDirectoryPath,
  Future<SharedPreferences> Function() openPreferences =
      SharedPreferences.getInstance,
}) async {
  try {
    await switchRouteToDirect();
    final directory = Directory(await resolveTorDirectory());
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  } catch (e, st) {
    log('resetWallet: tor data directory cleanup failed: $e\n$st');
  }
  try {
    final preferences = await openPreferences();
    await preferences.remove(kTorEnabledPreferenceKey);
  } catch (e, st) {
    log('resetWallet: tor route preference cleanup failed: $e\n$st');
  }
}

@visibleForTesting
List<String> walletDbCleanupPaths(String dbPath) {
  // Voting persists to a deterministic SQLite sidecar next to the wallet DB.
  final targets = [dbPath, '$dbPath$_votingSidecarSuffix'];
  return [
    for (final target in targets)
      for (final suffix in _sqliteCompanionSuffixes) '$target$suffix',
    '$dbPath$_receiveCacheSidecarSuffix',
  ];
}
