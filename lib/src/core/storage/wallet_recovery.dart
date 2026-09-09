import 'dart:convert';
import 'dart:io';

import '../security/software_wallet_secret.dart';
import '../../providers/account_models.dart';
import '../../rust/api/sync.dart' as rust_sync;
import '../../rust/api/wallet.dart' as rust_wallet;
import 'app_secure_store.dart';
import 'wallet_paths.dart';

const kWalletRecoveryPendingKey = 'zcash_wallet_recovery_pending';
const kWalletSetupPendingValue = 'onboarding';

class WalletRecoveryCandidate {
  const WalletRecoveryCandidate({
    required this.path,
    required this.fileName,
    required this.network,
    required this.accounts,
    this.error,
    this.isEmptyDatabase = false,
  });

  final String path;
  final String fileName;
  final String network;
  final List<rust_wallet.AccountInfo> accounts;
  final String? error;
  final bool isEmptyDatabase;

  bool get canInspect => error == null && accounts.isNotEmpty;
}

class WalletRecoveryState {
  const WalletRecoveryState({
    required this.candidates,
    required this.network,
    required this.isPasswordConfigured,
  });

  final List<WalletRecoveryCandidate> candidates;
  final String network;
  final bool isPasswordConfigured;
}

/// Discover only recognized files in the current application's directory.
/// A malformed or unreadable candidate remains visible as an error; it must
/// never make an existing installation look empty.
Future<List<WalletRecoveryCandidate>> findWalletRecoveryCandidates({
  required String network,
}) async {
  final directory = await getWalletSupportDirectory();
  final names = <String>{};
  await for (final entry in directory.list(followLinks: false)) {
    final name = entry.uri.pathSegments.last;
    if (isWalletDbFileName(name)) {
      names.add(name);
    } else if ((name.endsWith('-wal') || name.endsWith('-shm')) &&
        isWalletDbFileName(name.substring(0, name.length - 4))) {
      names.add(name.substring(0, name.length - 4));
    }
  }
  final candidates = <WalletRecoveryCandidate>[];
  for (final name in names.toList()..sort()) {
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    List<rust_wallet.AccountInfo> accounts = const [];
    String? error;
    var isEmptyDatabase = false;
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError(
          'The original wallet database is missing or is not a regular file.',
        );
      }
      accounts = await rust_wallet.inspectWalletForRecovery(
        dbPath: file.path,
        network: network,
      );
      if (accounts.isEmpty) {
        isEmptyDatabase = true;
        error = 'No wallet accounts were found in this file.';
      }
    } catch (_) {
      error =
          'This wallet file could not be read. Keep the original file and try again.';
    }
    candidates.add(
      WalletRecoveryCandidate(
        path: file.path,
        fileName: file.uri.pathSegments.last,
        network: network,
        accounts: accounts,
        error: error,
        isEmptyDatabase: isEmptyDatabase,
      ),
    );
  }
  return candidates;
}

/// A recovery session never writes the DB. It verifies every account before
/// committing the existing file's locator and reconstructed account metadata.
/// Partial proofs stay in this session and are shown as recovery progress.
class WalletRecoverySession {
  WalletRecoverySession({required this.candidate, AppSecureStore? store})
    : _store = store ?? AppSecureStore.instance;

  final WalletRecoveryCandidate candidate;
  final AppSecureStore _store;
  final _softwareSecrets = <String, SoftwareWalletSecret>{};
  final _hardwareKeys = <String, String>{};
  bool _authenticated = false;
  bool _committing = false;

  bool get hasEstablishedPassword => _authenticated;

  bool isVerified(String uuid) =>
      _softwareSecrets.containsKey(uuid) || _hardwareKeys.containsKey(uuid);

  bool get canReconnect =>
      candidate.canInspect &&
      candidate.accounts.every((a) => isVerified(a.uuid));

  Future<bool> unlockExistingSecrets(String password) async {
    _authenticated = false;
    _store.clearSessionPassword();
    if (!await _store.verifyPassword(password)) return false;
    _authenticated = true;
    for (final account in candidate.accounts.where((a) => !a.isHardware)) {
      SoftwareWalletSecret? secret;
      try {
        secret = await _store.readAccountSoftwareWalletSecret(
          account.uuid,
          requireUnlockedSession: true,
        );
      } on SecureStorageUnavailableException {
        rethrow;
      } catch (_) {
        // Missing or damaged account secrets require recovery material.
        // Do not replace them until the supplied key matches this DB account.
        continue;
      }
      if (secret != null) await verifySoftwareSecret(account.uuid, secret);
    }
    return true;
  }

  Future<bool> verifySoftwareSecret(
    String uuid,
    SoftwareWalletSecret secret,
  ) async {
    final account = candidate.accounts.where((a) => a.uuid == uuid).firstOrNull;
    if (account == null || account.isHardware) return false;
    final matches = await rust_wallet.verifyRecoveryMnemonic(
      dbPath: candidate.path,
      network: candidate.network,
      accountUuid: uuid,
      mnemonic: secret.mnemonic,
      bip39Passphrase: secret.bip39Passphrase,
    );
    if (matches) _softwareSecrets[uuid] = secret;
    return matches;
  }

  Future<bool> verifyHardwareKey(String uuid, String ufvk) async {
    final account = candidate.accounts.where((a) => a.uuid == uuid).firstOrNull;
    if (account == null || !account.isHardware) return false;
    final matches = await rust_wallet.verifyRecoveryHardwareKey(
      dbPath: candidate.path,
      network: candidate.network,
      accountUuid: uuid,
      ufvk: ufvk,
    );
    if (matches) _hardwareKeys[uuid] = ufvk;
    return matches;
  }

  Future<void> reconnect({String? newPassword}) async {
    if (_committing) {
      throw StateError('Wallet recovery is already in progress.');
    }
    if (!canReconnect) {
      throw StateError('Verify every account before reconnecting this wallet.');
    }
    _committing = true;
    try {
      final support = await getWalletSupportDirectory();
      if (!isWalletDbFileName(candidate.fileName) ||
          candidate.path !=
              '${support.path}${Platform.pathSeparator}${candidate.fileName}' ||
          await FileSystemEntity.type(candidate.path, followLinks: false) !=
              FileSystemEntityType.file) {
        throw StateError(
          'This wallet file is no longer in the app data folder.',
        );
      }
      if (rust_sync.isSyncRunning()) {
        throw StateError(
          'Wallet sync is still running. Try recovery again after it stops.',
        );
      }
      final passwordConfigured = await _store.isPasswordConfigured();
      if (passwordConfigured &&
          (!_authenticated || !_store.hasSessionPassword)) {
        throw StateError(
          'Unlock with your existing password before reconnecting.',
        );
      }
      if (!passwordConfigured && newPassword == null) {
        throw StateError(
          'Set a password after verifying your recovery material.',
        );
      }
      // Inspect and prove again at commit time; the selected file may have
      // changed while the user was entering recovery material.
      final current = await rust_wallet.inspectWalletForRecovery(
        dbPath: candidate.path,
        network: candidate.network,
      );
      final expected = candidate.accounts.map((a) => a.uuid).toSet();
      if (current.length != expected.length ||
          !current.every((a) => expected.contains(a.uuid))) {
        throw StateError('This wallet file changed. Retry recovery.');
      }
      for (final account in current) {
        final verified = account.isHardware
            ? await rust_wallet.verifyRecoveryHardwareKey(
                dbPath: candidate.path,
                network: candidate.network,
                accountUuid: account.uuid,
                ufvk: _hardwareKeys[account.uuid] ?? '',
              )
            : await rust_wallet.verifyRecoveryMnemonic(
                dbPath: candidate.path,
                network: candidate.network,
                accountUuid: account.uuid,
                mnemonic: _softwareSecrets[account.uuid]?.mnemonic ?? '',
                bip39Passphrase:
                    _softwareSecrets[account.uuid]?.bip39Passphrase ?? '',
              );
        if (!verified) {
          throw StateError('An account no longer matches this wallet file.');
        }
      }

      final storedByUuid = <String, Map<String, dynamic>>{};
      final stored = await _store.readString('zcash_accounts');
      if (stored != null) {
        try {
          for (final item in jsonDecode(stored) as List<dynamic>) {
            final value = Map<String, dynamic>.from(item as Map);
            if (value['uuid'] case final String uuid) {
              storedByUuid[uuid] = value;
            }
          }
        } on FormatException {
          // Account presentation metadata can be reconstructed from the DB.
        } on TypeError {
          // Retain the original until the verified replacement is committed.
        }
      }
      final accounts = current.indexed.map((entry) {
        final (index, account) = entry;
        return AccountInfo.fromJson({
          ...?storedByUuid[account.uuid],
          'uuid': account.uuid,
          'name': storedByUuid[account.uuid]?['name'] ?? account.name,
          'order': index,
          'isHardware': account.isHardware,
          'isSeedAnchor': account.isSeedAnchor,
        });
      }).toList();
      final active = await _store.readString('zcash_active_account');
      final activeUuid = expected.contains(active)
          ? active!
          : accounts.first.uuid;
      final encodedAccounts = jsonEncode(
        accounts.map((a) => a.toJson()).toList(),
      );

      // A crash during credential or metadata writes must return to recovery,
      // including when an otherwise valid old pointer is still present.
      await _store.writePlain(kWalletRecoveryPendingKey, candidate.fileName);
      if (!passwordConfigured) {
        await _store.configurePassword(newPassword!);
        _authenticated = true;
      }
      for (final entry in _softwareSecrets.entries) {
        await _store.writeAccountMnemonic(
          entry.key,
          entry.value.mnemonic,
          bip39Passphrase: entry.value.bip39Passphrase,
        );
        final saved = await _store.readAccountSoftwareWalletSecret(
          entry.key,
          requireUnlockedSession: true,
        );
        if (saved?.mnemonic != entry.value.mnemonic ||
            saved?.bip39Passphrase != entry.value.bip39Passphrase) {
          throw StateError(
            'A recovered account could not be saved. Retry recovery.',
          );
        }
      }
      await _store.writeString('zcash_wallet_network', candidate.network);
      await _store.writeString('zcash_accounts', encodedAccounts);
      await _store.writeString('zcash_active_account', activeUuid);
      await _store.writePlain(kWalletDbNameKey, candidate.fileName);
      if (await _store.readPlain(kWalletDbNameKey) != candidate.fileName ||
          await _store.readString('zcash_wallet_network') !=
              candidate.network ||
          await _store.readString('zcash_accounts') != encodedAccounts ||
          await _store.readString('zcash_active_account') != activeUuid) {
        throw StateError(
          'The wallet connection could not be saved. Retry recovery.',
        );
      }
      await _store.delete(kWalletRecoveryPendingKey);
      // Re-enter through the ordinary unlock flow after bootstrap reload.
      _store.clearSessionPassword();
    } finally {
      _committing = false;
    }
  }

  void dispose() {
    _softwareSecrets.clear();
    _hardwareKeys.clear();
    _authenticated = false;
    _store.clearSessionPassword();
  }
}
