import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:path_provider/path_provider.dart';

import '../config/app_version_config.dart';
import '../config/network_config.dart';

enum StorageBootstrapStage { started, metadata, ready, blocked }

enum StorageKeyringStage {
  ready,
  working,
  retrying,
  keyringLocked,
  serviceUnavailable,
  storageCorrupt,
  outcomeUnknown,
}

enum StorageKeyringAction { retryRequested, cancelRequested }

/// Local Linux evidence for missing keyring entries. Never records raw keys,
/// values, exception text, account identifiers, paths, or endpoint URLs.
class SecureStorageDiagnostics {
  SecureStorageDiagnostics._();

  @visibleForTesting
  SecureStorageDiagnostics.testing(
    Directory directory, {
    int maxFileBytes = 256 * 1024,
    int maxFiles = 8,
  }) : _directory = directory,
       _maxFileBytes = maxFileBytes,
       _maxFiles = maxFiles,
       assert(maxFileBytes >= 512),
       assert(maxFiles >= 1);

  static final instance = SecureStorageDiagnostics._();
  static final _filePattern = RegExp(
    r'^secure-storage-\d+-\d+-\d+-\d+\.jsonl$',
  );
  static int _nextInstanceId = 0;
  static final _dbNamePattern = RegExp(
    r'^zcash_wallet(?:_[a-zA-Z0-9_-]+)?\.db$',
  );

  Directory? _directory;
  File? _file;
  int _fileBytes = 0;
  int _fileSequence = 0;
  int _operationSequence = 0;
  final _session = DateTime.now().microsecondsSinceEpoch;
  final _instanceId = ++_nextInstanceId;
  int _maxFileBytes = 256 * 1024;
  int _maxFiles = 8;
  bool _initialized = false;
  bool _reportedFailure = false;
  Future<void> _tail = Future<void>.value();

  /// Called before runtime storage access. Other platforms retain their normal
  /// logging behavior; tests opt into a disposable directory explicitly.
  Future<void> initialize() async {
    if (_initialized) return;
    if (_directory == null && !Platform.isLinux) return;
    try {
      final support = _directory == null
          ? await getApplicationSupportDirectory()
          : null;
      _directory ??= Directory('${support!.path}/diagnostics');
      await _directory!.create(recursive: true);
      _initialized = true;
      await _append({
        'event': 'session',
        'version':
            kVizorReleaseVersion.length <= 64 &&
                RegExp(
                  r'^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.]+)?$',
                ).hasMatch(kVizorReleaseVersion)
            ? kVizorReleaseVersion
            : 'unknown',
        'build': kVizorReleaseBuildNumber,
        'network': kZcashDefaultNetworkName,
      });
    } catch (_) {
      _reportFailure();
    }
  }

  Future<T> trace<T>(String operation, Future<T> Function() action) async {
    if (!_initialized) return action();
    final verb = _verb(operation);
    final category = _category(operation);
    final id = ++_operationSequence;
    await _append({
      'event': 'storage_begin',
      'operation': id,
      'verb': verb,
      'category': category,
    });
    try {
      final result = await action();
      await _append({
        'event': 'storage_end',
        'operation': id,
        'verb': verb,
        'category': category,
        'outcome': 'success',
        if (verb == 'read')
          'read_state': result == null
              ? 'missing'
              : (result is String && result.isEmpty) ||
                    (result is Map && result.isEmpty)
              ? 'empty'
              : 'present',
        if (verb == 'read' && result is Map) 'entry_count': result.length,
        // Only a recognized randomized DB basename can be fingerprinted. No
        // verifier, salt, mnemonic, key or arbitrary value reaches this field.
        if (category == 'db_locator' && result is String)
          'locator_valid': _dbNamePattern.hasMatch(result),
        if (category == 'db_locator' &&
            result is String &&
            _dbNamePattern.hasMatch(result))
          'locator_fingerprint': sha256
              .convert(utf8.encode(result))
              .toString()
              .substring(0, 16),
      });
      return result;
    } catch (error) {
      await _append({
        'event': 'storage_end',
        'operation': id,
        'verb': verb,
        'category': category,
        'outcome': 'error',
        'error_kind': error is PlatformException
            ? 'platform'
            : error is FileSystemException
            ? 'filesystem'
            : error is FormatException
            ? 'format'
            : 'other',
        if (error is PlatformException)
          'storage_error':
              const {
                'KeyringLocked',
                'SecretNotFound',
                'Libsecret error',
                'StorageError',
                'StorageOutcomeUnknown',
                'storage_cancelled',
              }.contains(error.code)
              ? error.code
              : 'other',
      });
      rethrow;
    }
  }

  Future<void> bootstrap(
    StorageBootstrapStage stage, {
    bool? passwordConfigured,
    bool? databaseExists,
    int? storedAccountCount,
  }) => _append({
    'event': 'bootstrap',
    'stage': stage.name,
    'password_configured': ?passwordConfigured,
    'database_exists': ?databaseExists,
    'stored_account_count': ?storedAccountCount,
  });

  Future<void> keyringState(StorageKeyringStage stage) =>
      _append({'event': 'keyring', 'stage': stage.name});

  Future<void> keyringAction(StorageKeyringAction action) =>
      _append({'event': 'keyring_action', 'action': action.name});

  Future<void> _append(Map<String, Object> record) {
    if (!_initialized) return Future<void>.value();
    final line =
        '${jsonEncode({'time': DateTime.now().toUtc().toIso8601String(), 'session': '$_session-$_instanceId', 'pid': pid, ...record})}\n';
    final bytes = utf8.encode(line).length;
    // A logger must never prevent wallet access or replace the original error.
    _tail = _tail.then((_) async {
      try {
        if (_file == null || _fileBytes + bytes > _maxFileBytes) {
          final sequence = '${_fileSequence++}'.padLeft(12, '0');
          _file = File(
            '${_directory!.path}/secure-storage-$_session-$pid-$_instanceId-$sequence.jsonl',
          );
          _fileBytes = 0;
          await _prune();
        }
        await _file!.writeAsString(line, mode: FileMode.append, flush: true);
        _fileBytes += bytes;
      } catch (_) {
        _reportFailure();
      }
    });
    return _tail;
  }

  Future<void> _prune() async {
    final files = <File>[];
    await for (final entity in _directory!.list(followLinks: false)) {
      if (entity is File &&
          _filePattern.hasMatch(entity.uri.pathSegments.last) &&
          entity.path != _file!.path) {
        files.add(entity);
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    final removeCount = files.length - (_maxFiles - 1);
    for (final file in files.take(removeCount > 0 ? removeCount : 0)) {
      await file.delete();
    }
  }

  void _reportFailure() {
    if (_reportedFailure) return;
    _reportedFailure = true;
    debugPrint('[zcash] Secure-storage diagnostics could not be written.');
  }

  static String _verb(String operation) {
    if (operation.startsWith('read ')) return 'read';
    if (operation.startsWith('write ') || operation.startsWith('restore ')) {
      return 'write';
    }
    if (operation.startsWith('delete all')) return 'delete_all';
    if (operation.startsWith('delete ')) return 'delete';
    return 'other';
  }

  static String _category(String operation) {
    const knownKeys = {
      'zcash_wallet_db_name': 'db_locator',
      'zcash_password_verifier_salt': 'password_verifier_salt',
      'zcash_password_verifier': 'password_verifier',
      'zcash_secure_store_salt': 'secret_salt',
      'zcash_accounts': 'accounts',
      'zcash_active_account': 'active_account',
      'zcash_wallet_network': 'network',
      'zcash_rpc_endpoint_url': 'rpc_endpoint',
      'zcash_rpc_endpoint_preset': 'rpc_endpoint',
      'zcash_rotation_in_progress': 'password_rotation',
    };
    for (final entry in knownKeys.entries) {
      if (operation.contains('"${entry.key}"')) return entry.value;
    }
    if (operation.contains('account mnemonic') ||
        operation.contains('account software wallet secret') ||
        operation.contains('zcash_account_mnemonic_')) {
      return 'software_secret';
    }
    if (operation.contains('voting hotkey') ||
        operation.contains('zcash_account_voting_hotkey_')) {
      return 'voting_secret';
    }
    if (operation == 'delete password verifier salt') {
      return 'password_verifier_salt';
    }
    if (operation == 'delete password verifier') return 'password_verifier';
    if (operation == 'delete password rotation record') {
      return 'password_rotation';
    }
    if (operation.contains('secret')) return 'secret';
    if (operation == 'delete all') return 'all';
    return 'other';
  }
}
