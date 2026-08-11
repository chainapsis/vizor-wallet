// Storage operations are intentionally asynchronous to avoid blocking Flutter.
// ignore_for_file: avoid_slow_async_io

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

/// An extension on `Map<String, String>` to add support for specific
/// configuration options related to backward compatibility.
@visibleForTesting
extension OptionsExtension on Map<String, String> {
  /// Checks whether the `useBackwardCompatibility` flag is enabled in the map.
  ///
  /// Returns:
  /// - `true` if the value associated with the `useBackwardCompatibility` key
  ///   is not `'false'`.
  /// - `false` otherwise.
  bool get useBackwardCompatibility =>
      this['useBackwardCompatibility'] != 'false';
}

/// Serializes asynchronous critical sections without adding another package.
class _AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;

    return previous.then((_) => action()).whenComplete(completer.complete);
  }
}

/// The `FlutterSecureStorageWindows` class provides a Windows-specific
/// implementation of the `FlutterSecureStoragePlatform` interface.
///
/// This implementation uses a combination of a backward-compatible storage
/// mechanism and a platform-specific storage backend.
class FlutterSecureStorageWindows extends FlutterSecureStoragePlatform {
  /// Creates an instance of `FlutterSecureStorageWindows` with default
  /// configurations for both backward compatibility and platform-specific
  /// storage.
  FlutterSecureStorageWindows()
      : this._(MethodChannelFlutterSecureStorage(), DpapiJsonFileMapStorage());

  /// Internal constructor to initialize `FlutterSecureStorageWindows` with
  /// custom implementations for backward compatibility and platform-specific
  /// storage.
  ///
  /// Parameters:
  /// - [_backwardCompatible]: The storage mechanism used for backward
  ///   compatibility.
  /// - [_storage]: The platform-specific storage backend for Windows.
  FlutterSecureStorageWindows._(this._backwardCompatible, this._storage);

  /// The storage implementation used for backward compatibility.
  final FlutterSecureStoragePlatform _backwardCompatible;

  /// The platform-specific storage implementation for Windows, using DPAPI.
  final MapStorage _storage;

  // FlutterSecureStorage can be instantiated more than once. This must be
  // shared so every instance participates in the same read-modify-write lock.
  static final _processLock = _AsyncLock();

  Future<T> _runStorageTransaction<T>(Future<T> Function() action) {
    return _processLock.run(() {
      final storage = _storage;
      if (storage is TransactionalMapStorage) {
        return storage.runTransaction(action);
      }
      return action();
    });
  }

  /// Registers this plugin.
  static void registerWith() {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWindows();
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) =>
      _runStorageTransaction(() async {
        final map = await _storage.load(options);
        if (map.containsKey(key)) {
          return true;
        }

        if (options.useBackwardCompatibility) {
          return _backwardCompatible.containsKey(key: key, options: options);
        }

        return false;
      });

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) =>
      _runStorageTransaction(() async {
        final map = await _storage.load(options);
        final initialSize = map.length;
        map.remove(key);
        if (map.length != initialSize) {
          await _storage.save(map, options);
        }

        if (options.useBackwardCompatibility) {
          await _backwardCompatible.delete(key: key, options: options);
        }
      });

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      _runStorageTransaction(() async {
        await _storage.clear(options);

        if (options.useBackwardCompatibility) {
          await _backwardCompatible.deleteAll(options: options);
        }
      });

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) =>
      _runStorageTransaction(() async {
        final map = await _storage.load(options);

        var result = map[key];
        if (options.useBackwardCompatibility) {
          if (result == null) {
            final compatible = await _backwardCompatible.read(
              key: key,
              options: options,
            );
            if (compatible != null) {
              // Write back now, so the value should be retrieved from JSON
              // next.
              result = map[key] = compatible;
              await _storage.save(map, options);
            }
          }

          // Clear old entry.
          await _backwardCompatible.delete(key: key, options: options);
        }

        return result;
      });

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      _runStorageTransaction(() async {
        final map = await _storage.load(options);
        if (!options.useBackwardCompatibility) {
          // Just return a map.
          return map;
        }

        final compatible = await _backwardCompatible.readAll(options: options);

        if (compatible.isEmpty) {
          return map;
        }

        for (final entry in compatible.entries) {
          map.putIfAbsent(entry.key, () => entry.value);
        }

        // Write back now, so the value should be retrieved from JSON next.
        await _storage.save(map, options);

        // Clear old entries.
        await _backwardCompatible.deleteAll(options: options);

        return map;
      });

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) =>
      _runStorageTransaction(() async {
        final map = await _storage.load(options);
        map[key] = value;
        await _storage.save(map, options);

        if (options.useBackwardCompatibility) {
          // Clear old entry.
          await _backwardCompatible.delete(key: key, options: options);
        }
      });
}

/// Creates a custom instance of `FlutterSecureStorageWindows` for testing.
///
/// This factory function is annotated with `@visibleForTesting` to indicate
/// its intended use in testing scenarios. It allows specifying custom
/// implementations for backward compatibility and platform-specific storage.
///
/// Parameters:
/// - [backwardCompatible]: A custom implementation of
///   `FlutterSecureStoragePlatform` for backward-compatible storage behavior.
/// - [mapStorage]: A custom implementation of `MapStorage` for Windows secure
///   storage functionality.
///
/// Returns:
/// - An instance of `FlutterSecureStorageWindows` configured with the given
///   `backwardCompatible` and `mapStorage` implementations.
@visibleForTesting
FlutterSecureStorageWindows createFlutterSecureStorageWindows(
  FlutterSecureStoragePlatform backwardCompatible,
  MapStorage mapStorage,
) =>
    FlutterSecureStorageWindows._(backwardCompatible, mapStorage);

@visibleForTesting

/// An abstract class that defines the interface for map-based storage
/// implementations.
abstract class MapStorage {
  /// Loads a map of key-value pairs from the storage medium.
  ///
  /// Parameters:
  /// - [options]: A map of options to customize the load operation.
  FutureOr<Map<String, String>> load(Map<String, String> options);

  /// Saves a map of key-value pairs to the storage medium.
  ///
  /// Parameters:
  /// - [data]: A map containing the data to save.
  /// - [options]: A map of options to customize the save operation.
  FutureOr<void> save(Map<String, String> data, Map<String, String> options);

  /// Clears all key-value pairs from the storage medium.
  ///
  /// Parameters:
  /// - [options]: A map of options to customize the clear operation.
  FutureOr<void> clear(Map<String, String> options);
}

/// A map storage that can guard a complete load-modify-save transaction.
abstract class TransactionalMapStorage implements MapStorage {
  /// Runs [action] while holding the storage's inter-process transaction lock.
  Future<T> runTransaction<T>(Future<T> Function() action);
}

/// The file name used to store encrypted JSON data.
///
/// This constant is exposed for testing purposes.
@visibleForTesting
const String encryptedJsonFileName = 'flutter_secure_storage.dat';

const _backupSuffix = '.bak';
const _invalidBackupSuffix = '.invalid';
const _restorePendingSuffix = '.restore';
const _lockSuffix = '.lock';
const _temporarySuffix = '.tmp';
const _transactionLockTimeout = Duration(seconds: 10);
const _retryDelay = Duration(milliseconds: 25);

// FFI signatures need named native and Dart function types.
// ignore: avoid_private_typedef_functions
typedef _ReplaceFileNative = Int32 Function(
  Pointer<Utf16> replacedFileName,
  Pointer<Utf16> replacementFileName,
  Pointer<Utf16> backupFileName,
  Uint32 replaceFlags,
  Pointer<Void> exclude,
  Pointer<Void> reserved,
);
// FFI signatures need named native and Dart function types.
// ignore: avoid_private_typedef_functions
typedef _ReplaceFileDart = int Function(
  Pointer<Utf16> replacedFileName,
  Pointer<Utf16> replacementFileName,
  Pointer<Utf16> backupFileName,
  int replaceFlags,
  Pointer<Void> exclude,
  Pointer<Void> reserved,
);

final _replaceFile = DynamicLibrary.open(
  'kernel32.dll',
).lookupFunction<_ReplaceFileNative, _ReplaceFileDart>('ReplaceFileW');

class _SecureStorageCorruptionException implements Exception {
  const _SecureStorageCorruptionException(this.cause);

  final Object cause;

  @override
  String toString() => 'Secure storage is corrupt: $cause';
}

/// A `MapStorage` implementation that uses DPAPI (Data Protection API) for
/// encryption and stores data in a JSON file on disk.
///
/// This implementation is specific to Windows platforms.
@visibleForTesting
class DpapiJsonFileMapStorage extends TransactionalMapStorage {
  /// Creates an instance of `DpapiJsonFileMapStorage`.
  DpapiJsonFileMapStorage({
    @visibleForTesting Future<void> Function(File primary)? refreshBackup,
    @visibleForTesting
    Future<void> Function(File temporary, File destination, File? backup)?
        commitTemporaryFile,
  })  : _refreshBackupOverride = refreshBackup,
        _commitTemporaryFileOverride = commitTemporaryFile;

  final Future<void> Function(File primary)? _refreshBackupOverride;
  final Future<void> Function(File temporary, File destination, File? backup)?
      _commitTemporaryFileOverride;

  /// Retrieves the canonical path to the encrypted JSON file used for storage.
  ///
  /// This method constructs the file path based on the application's support
  /// directory.
  ///
  /// Returns:
  /// - A [FutureOr] resolving to the canonical file path as a string.
  FutureOr<String> _getJsonFilePath() async {
    final appDataDirectory = await getApplicationSupportDirectory();

    return path.canonicalize(
      path.join(appDataDirectory.path, encryptedJsonFileName),
    );
  }

  @override
  Future<T> runTransaction<T>(Future<T> Function() action) async {
    final storagePath = await _getJsonFilePath();
    final lockFile = File('$storagePath$_lockSuffix');
    await lockFile.parent.create(recursive: true);

    final handle = await lockFile.open(mode: FileMode.append);
    var locked = false;
    try {
      final deadline = DateTime.now().add(_transactionLockTimeout);
      while (!locked) {
        try {
          await handle.lock(FileLock.exclusive, 0, 1);
          locked = true;
        } on FileSystemException catch (error) {
          final errorCode = error.osError?.errorCode;
          final isContended = errorCode == ERROR_SHARING_VIOLATION ||
              errorCode == ERROR_LOCK_VIOLATION;
          if (!isContended || DateTime.now().isAfter(deadline)) {
            if (isContended) {
              throw FileSystemException(
                'Timed out waiting for the secure-storage transaction lock.',
                lockFile.path,
                error.osError,
              );
            }
            rethrow;
          }
          await Future<void>.delayed(_retryDelay);
        }
      }

      await _deleteStaleTemporaryFiles(File(storagePath));
      return await action();
    } finally {
      if (locked) {
        await handle.unlock(0, 1);
      }
      await handle.close();
    }
  }

  Future<void> _deleteStaleTemporaryFiles(File destination) async {
    if (!await destination.parent.exists()) {
      return;
    }
    await for (final entity in destination.parent.list(followLinks: false)) {
      if (entity is! File ||
          !entity.path.startsWith('${destination.path}.') ||
          !entity.path.endsWith(_temporarySuffix)) {
        continue;
      }
      try {
        await entity.delete();
      } on FileSystemException catch (error) {
        debugPrint(
          'Could not remove stale secure-storage temporary file '
          '${entity.path}: $error',
        );
      }
    }
  }

  @override
  FutureOr<Map<String, String>> load(Map<String, String> options) async {
    final file = File(await _getJsonFilePath());
    final backup = File('${file.path}$_backupSuffix');
    final invalidBackup = File('${backup.path}$_invalidBackupSuffix');
    final restorePending = File('${backup.path}$_restorePendingSuffix');

    if (!await file.exists()) {
      if (!await backup.exists()) {
        return {};
      }
      if (await restorePending.exists()) {
        final recovered = await _loadFile(backup);
        await _restoreBackup(file, backup);
        await _deleteRecoveryMarker(invalidBackup);
        await _deleteRecoveryMarker(restorePending);
        return recovered;
      }
      if (await invalidBackup.exists()) {
        throw FileSystemException(
          'The secure-storage primary is missing and its backup was '
          'invalidated by an interrupted backup refresh.',
          file.path,
        );
      }
      final recovered = await _loadFile(backup);
      await _restoreBackup(file, backup);
      return recovered;
    }

    try {
      final loaded = await _loadFile(file);
      if (await invalidBackup.exists()) {
        await _repairInvalidatedBackup(file, invalidBackup);
      }
      await _deleteRecoveryMarker(restorePending);
      return loaded;
    } on _SecureStorageCorruptionException catch (primaryError, primaryStackTrace) {
      if (!await invalidBackup.exists() && await backup.exists()) {
        try {
          final recovered = await _loadFile(backup);
          await _restoreBackup(file, backup);
          debugPrint(
            'Recovered Windows secure storage from ${backup.path} after '
            'failing to read ${file.path}: $primaryError',
          );
          return recovered;
        } on Exception catch (backupError) {
          debugPrint(
            'Windows secure-storage primary and backup are unreadable. '
            'Primary: $primaryError Backup: $backupError',
          );
        }
      }

      Error.throwWithStackTrace(primaryError, primaryStackTrace);
    }
  }

  Future<Map<String, String>> _loadFile(File file) async {
    final encryptedText = await file.readAsBytes();
    try {
      final plainText = using((alloc) {
        final pEncryptedText = alloc<Uint8>(encryptedText.length);
        pEncryptedText.asTypedList(encryptedText.length).setAll(
              0,
              encryptedText,
            );

        // Specify size of the struct explicitly.
        final encryptedTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(
          sizeOf<CRYPT_INTEGER_BLOB>(),
        );
        encryptedTextBlob.ref.cbData = encryptedText.length;
        encryptedTextBlob.ref.pbData = pEncryptedText;

        // Specify size of the struct explicitly.
        final plainTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(
          sizeOf<CRYPT_INTEGER_BLOB>(),
        );
        if (CryptUnprotectData(
              encryptedTextBlob,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              0,
              plainTextBlob,
            ) ==
            0) {
          throw WindowsException(
            GetLastError(),
            message: 'Failure on CryptUnprotectData()',
          );
        }

        if (plainTextBlob.ref.pbData.address == NULL) {
          throw WindowsException(
            ERROR_OUTOFMEMORY,
            message: 'Failure on CryptUnprotectData()',
          );
        }

        try {
          return utf8.decoder.convert(
            plainTextBlob.ref.pbData.asTypedList(plainTextBlob.ref.cbData),
          );
        } finally {
          if (plainTextBlob.ref.pbData.address != NULL) {
            if (LocalFree(plainTextBlob.ref.pbData).address != NULL) {
              debugPrint(
                'load: Failed to LocalFree with: '
                '0x${GetLastError().toHexString(32)}',
              );
            }
          }
        }
      });

      final decoded = jsonDecode(plainText);

      if (decoded is! Map ||
          decoded.entries.any((entry) {
            return entry.key is! String || entry.value is! String;
          })) {
        throw const FormatException(
          'Secure-storage JSON is not a string-to-string object.',
        );
      }

      return {
        for (final entry in decoded.entries)
          entry.key as String: entry.value as String,
      };
    } on FormatException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        _SecureStorageCorruptionException(error),
        stackTrace,
      );
    } on WindowsException catch (error, stackTrace) {
      if (error.hr == ERROR_OUTOFMEMORY) {
        rethrow;
      }
      Error.throwWithStackTrace(
        _SecureStorageCorruptionException(error),
        stackTrace,
      );
    }
  }

  Future<void> _restoreBackup(File file, File backup) async {
    final temporary = await _createTemporaryFile(file);
    try {
      final handle = await temporary.open(mode: FileMode.write);
      try {
        await handle.writeFrom(await backup.readAsBytes());
        await handle.flush();
      } finally {
        await handle.close();
      }
      await _loadFile(temporary);
      await _commitTemporaryFile(temporary, file, backup: null);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  @override
  FutureOr<void> save(
    Map<String, String> data,
    Map<String, String> options,
  ) async {
    final file = File(await _getJsonFilePath());
    final restorePending = File(
      '${file.path}$_backupSuffix$_restorePendingSuffix',
    );
    // A restore marker authorizes recovery of one previously validated backup.
    // It must not survive into a new commit where that backup can become stale.
    await _deleteRecoveryMarkerStrict(restorePending);
    final json = jsonEncode(data);
    final plainText = utf8.encode(json);

    await using<FutureOr<void>>((alloc) async {
      final pPlainText = alloc<Uint8>(plainText.length);
      pPlainText.asTypedList(plainText.length).setAll(0, plainText);

      // Specify size of the struct explicitly.
      final plainTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(
        sizeOf<CRYPT_INTEGER_BLOB>(),
      );
      plainTextBlob.ref.cbData = plainText.length;
      plainTextBlob.ref.pbData = pPlainText;

      // Specify size of the struct explicitly.
      final encryptedTextBlob = alloc.allocate<CRYPT_INTEGER_BLOB>(
        sizeOf<CRYPT_INTEGER_BLOB>(),
      );
      if (CryptProtectData(
            plainTextBlob,
            nullptr,
            nullptr,
            nullptr,
            nullptr,
            0,
            encryptedTextBlob,
          ) ==
          0) {
        throw WindowsException(
          GetLastError(),
          message: 'Failure on CryptProtectData()',
        );
      }

      if (encryptedTextBlob.ref.pbData.address == NULL) {
        throw WindowsException(
          ERROR_OUTOFMEMORY,
          message: 'Failure on CryptProtectData()',
        );
      }

      try {
        final encryptedText = Uint8List.fromList(
          encryptedTextBlob.ref.pbData.asTypedList(
            encryptedTextBlob.ref.cbData,
          ),
        );
        final temporary = await _createTemporaryFile(file);
        try {
          final handle = await temporary.open(mode: FileMode.write);
          try {
            await handle.writeFrom(encryptedText);
            await handle.flush();
          } finally {
            await handle.close();
          }
          final verified = await _loadFile(temporary);
          final contentsMatch = verified.length == data.length &&
              data.entries.every((entry) => verified[entry.key] == entry.value);
          if (!contentsMatch) {
            throw const FormatException(
              'Secure-storage temporary file failed verification.',
            );
          }
          final invalidBackup = File(
            '${file.path}$_backupSuffix$_invalidBackupSuffix',
          );
          final backup = File('${file.path}$_backupSuffix');
          await invalidBackup.writeAsString('invalid', flush: true);
          try {
            await _commitTemporaryFile(temporary, file, backup: backup);
          } catch (error, stackTrace) {
            await _recoverAfterFailedPrimaryCommit(
              primary: file,
              backup: backup,
              invalidBackup: invalidBackup,
              commitError: error,
              commitStackTrace: stackTrace,
            );
          }
          try {
            await _refreshBackup(file);
            await _deleteRecoveryMarker(invalidBackup);
          } on Exception catch (error) {
            // The primary commit has completed. Keep the invalidation marker
            // and report success so callers never roll back a committed write.
            debugPrint(
              'Could not refresh the Windows secure-storage backup after '
              'committing ${file.path}: $error',
            );
          }
        } finally {
          if (await temporary.exists()) {
            await temporary.delete();
          }
        }
      } finally {
        if (encryptedTextBlob.ref.pbData.address != NULL) {
          if (LocalFree(encryptedTextBlob.ref.pbData).address != NULL) {
            debugPrint(
              'save: Failed to LocalFree with: '
              '0x${GetLastError().toHexString(32)}',
            );
          }
        }
      }
    });
  }

  Future<void> _refreshBackup(File primary) async {
    final override = _refreshBackupOverride;
    if (override != null) {
      await override(primary);
      return;
    }
    final backup = File('${primary.path}$_backupSuffix');
    final temporary = await _createTemporaryFile(backup);
    try {
      final handle = await temporary.open(mode: FileMode.write);
      try {
        await handle.writeFrom(await primary.readAsBytes());
        await handle.flush();
      } finally {
        await handle.close();
      }
      await _loadFile(temporary);
      await _commitTemporaryFile(temporary, backup, backup: null);
    } finally {
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  Future<void> _repairInvalidatedBackup(
    File primary,
    File invalidBackup,
  ) async {
    try {
      await _refreshBackup(primary);
      await _deleteRecoveryMarker(invalidBackup);
    } on Exception catch (error) {
      debugPrint(
        'Could not repair the invalidated Windows secure-storage backup for '
        '${primary.path}: $error',
      );
    }
  }

  Future<Never> _recoverAfterFailedPrimaryCommit({
    required File primary,
    required File backup,
    required File invalidBackup,
    required Object commitError,
    required StackTrace commitStackTrace,
  }) async {
    final restorePending = File('${backup.path}$_restorePendingSuffix');
    try {
      if (!await primary.exists() && await backup.exists()) {
        await _loadFile(backup);
        await restorePending.writeAsString('restore', flush: true);
        await _deleteRecoveryMarker(invalidBackup);
        await _restoreBackup(primary, backup);
      }
      await _deleteRecoveryMarker(invalidBackup);
      await _deleteRecoveryMarker(restorePending);
    } catch (recoveryError, recoveryStackTrace) {
      Error.throwWithStackTrace(
        FileSystemException(
          'Could not restore secure storage after a failed atomic replace. '
          'Commit error: $commitError Recovery error: $recoveryError',
          primary.path,
        ),
        recoveryStackTrace,
      );
    }
    Error.throwWithStackTrace(commitError, commitStackTrace);
  }

  Future<void> _deleteRecoveryMarker(File marker) async {
    try {
      if (await marker.exists()) {
        await marker.delete();
      }
    } on FileSystemException catch (error) {
      debugPrint(
        'Could not remove Windows secure-storage recovery marker '
        '${marker.path}: $error',
      );
    }
  }

  Future<void> _deleteRecoveryMarkerStrict(File marker) async {
    if (await marker.exists()) {
      await marker.delete();
    }
  }

  Future<File> _createTemporaryFile(File destination) async {
    await destination.parent.create(recursive: true);
    for (var attempt = 0; attempt < 100; attempt++) {
      final temporary = File(
        '${destination.path}.$pid.'
        '${DateTime.now().microsecondsSinceEpoch}.$attempt$_temporarySuffix',
      );
      try {
        return await temporary.create(exclusive: true);
      } on PathExistsException {
        // Retry with a distinct attempt suffix.
      }
    }
    throw FileSystemException(
      'Could not allocate a secure-storage temporary file.',
      destination.path,
    );
  }

  Future<void> _commitTemporaryFile(
    File temporary,
    File destination, {
    required File? backup,
  }) async {
    final override = _commitTemporaryFileOverride;
    if (override != null) {
      await override(temporary, destination, backup);
      return;
    }
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (true) {
      final succeeded = using((alloc) {
        final temporaryPath = temporary.path.toNativeUtf16(allocator: alloc);
        final destinationPath = destination.path.toNativeUtf16(
          allocator: alloc,
        );

        if (!destination.existsSync()) {
          return MoveFileEx(
                temporaryPath,
                destinationPath,
                MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH,
              ) !=
              0;
        }

        final backupPath = backup == null
            ? nullptr.cast<Utf16>()
            : backup.path.toNativeUtf16(allocator: alloc);
        return _replaceFile(
              destinationPath,
              temporaryPath,
              backupPath,
              0,
              nullptr,
              nullptr,
            ) !=
            0;
      });
      if (succeeded) {
        return;
      }

      final errorCode = GetLastError();
      final isRetriable = errorCode == ERROR_SHARING_VIOLATION ||
          errorCode == ERROR_LOCK_VIOLATION ||
          errorCode == ERROR_FILE_NOT_FOUND;
      if (!isRetriable || DateTime.now().isAfter(deadline)) {
        throw WindowsException(
          errorCode,
          message: 'Could not atomically replace Windows secure storage.',
        );
      }
      await Future<void>.delayed(_retryDelay);
    }
  }

  @override
  FutureOr<void> clear(Map<String, String> options) async {
    final file = File(await _getJsonFilePath());
    final backup = File('${file.path}$_backupSuffix');
    final invalidBackup = File('${backup.path}$_invalidBackupSuffix');
    final restorePending = File('${backup.path}$_restorePendingSuffix');

    // Delete the backup first so an interrupted clear sees the old primary or
    // an empty store, never a missing primary that resurrects from backup.
    if (await backup.exists()) {
      await backup.delete();
    }
    if (await file.exists()) {
      await file.delete();
    }
    await _deleteRecoveryMarker(invalidBackup);
    await _deleteRecoveryMarker(restorePending);

    await _deleteStaleTemporaryFiles(file);
  }
}
