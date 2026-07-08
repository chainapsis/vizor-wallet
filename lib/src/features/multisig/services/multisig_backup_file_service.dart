import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

typedef MultisigBackupFileWriter =
    Future<MultisigBackupFileSaveResult?> Function({
      required String suggestedName,
      required String artifactJson,
    });

typedef MultisigBackupSavePathPicker =
    Future<String?> Function({required String suggestedName});
typedef MultisigBackupMobileExporter =
    Future<MultisigBackupFileExportResult?> Function({
      required String suggestedName,
      required String tempFilePath,
      MultisigBackupFileSavePlatform? platform,
    });
typedef MultisigBackupFileReader =
    Future<MultisigBackupFileReadResult?> Function();
typedef MultisigBackupOpenFilePicker = Future<XFile?> Function();

const _documentExportChannel = MethodChannel(
  'com.zcash.wallet/document_export',
);
const _backupExportTempDirName = 'multisig-backup-export';

final multisigBackupFileWriterProvider = Provider<MultisigBackupFileWriter>(
  (ref) => writeMultisigBackupFile,
);

final multisigBackupFileReaderProvider = Provider<MultisigBackupFileReader>(
  (ref) => readMultisigBackupFile,
);

class MultisigBackupFileSaveResult {
  const MultisigBackupFileSaveResult({
    required this.destination,
    required this.artifactJson,
  });

  final String destination;
  final String artifactJson;

  String get path => destination;
}

class MultisigBackupFileExportResult {
  const MultisigBackupFileExportResult({required this.destination});

  final String destination;
}

class MultisigBackupFileReadResult {
  const MultisigBackupFileReadResult({
    required this.path,
    required this.artifactJson,
  });

  final String path;
  final String artifactJson;
}

class MultisigBackupFileSaveException implements Exception {
  const MultisigBackupFileSaveException([this.cause]);

  final Object? cause;

  static const message =
      'Could not save the backup file. Choose a writable location and try again.';

  @override
  String toString() => message;
}

class MultisigBackupFileReadException implements Exception {
  const MultisigBackupFileReadException([this.cause]);

  final Object? cause;

  static const message =
      'Could not read the backup file. Choose a valid backup and try again.';

  @override
  String toString() => message;
}

enum MultisigBackupFileSavePlatform { desktop, ios, android }

String defaultMultisigBackupFileName({
  required String backupHash,
  DateTime? now,
}) {
  final timestamp = _backupFileTimestamp(now ?? DateTime.now());
  final suffix = _backupHashSuffix(backupHash);
  return 'vizor-multisig-backup-$timestamp-$suffix.vizorbackup';
}

Future<MultisigBackupFileSaveResult?> writeMultisigBackupFile({
  required String suggestedName,
  required String artifactJson,
  MultisigBackupSavePathPicker? pickSavePath,
  MultisigBackupMobileExporter? exportMobileFile,
  MultisigBackupFileSavePlatform? platform,
  Directory? tempDirectory,
}) async {
  try {
    final savePlatform = platform ?? _currentSavePlatform();
    if (savePlatform == MultisigBackupFileSavePlatform.ios ||
        savePlatform == MultisigBackupFileSavePlatform.android) {
      final exporter = exportMobileFile ?? exportMultisigBackupFileForMobile;
      return await _writeMobileMultisigBackupFile(
        suggestedName: suggestedName,
        artifactJson: artifactJson,
        exportMobileFile: exporter,
        platform: savePlatform,
        tempDirectory: tempDirectory,
      );
    }

    final picker = pickSavePath ?? pickMultisigBackupSavePath;
    final path = await picker(suggestedName: suggestedName);
    if (path == null) return null;

    final file = File(path);
    await file.writeAsString(artifactJson);
    final readBack = await file.readAsString();
    return MultisigBackupFileSaveResult(
      destination: 'file:${file.path}',
      artifactJson: readBack,
    );
  } catch (e) {
    throw MultisigBackupFileSaveException(e);
  }
}

Future<MultisigBackupFileSaveResult?> _writeMobileMultisigBackupFile({
  required String suggestedName,
  required String artifactJson,
  required MultisigBackupMobileExporter exportMobileFile,
  required MultisigBackupFileSavePlatform platform,
  Directory? tempDirectory,
}) async {
  final tempFile = await _writeTemporaryMultisigBackupFile(
    suggestedName: suggestedName,
    artifactJson: artifactJson,
    tempDirectory: tempDirectory,
  );
  try {
    final exported = await exportMobileFile(
      suggestedName: suggestedName,
      tempFilePath: tempFile.path,
      platform: platform,
    );
    if (exported == null) return null;
    return MultisigBackupFileSaveResult(
      destination: exported.destination,
      artifactJson: artifactJson,
    );
  } finally {
    await _deleteFileIfExists(tempFile);
  }
}

Future<MultisigBackupFileExportResult?> exportMultisigBackupFileForMobile({
  required String suggestedName,
  required String tempFilePath,
  MultisigBackupFileSavePlatform? platform,
}) async {
  final savePlatform = platform ?? _currentSavePlatform();
  if (savePlatform != MultisigBackupFileSavePlatform.ios &&
      savePlatform != MultisigBackupFileSavePlatform.android) {
    throw StateError('Mobile backup export is only available on iOS/Android.');
  }

  final response = await _documentExportChannel.invokeMethod<Object?>(
    'exportBackupFile',
    <String, Object?>{
      'fileName': _safeBackupFileName(suggestedName),
      'tempFilePath': tempFilePath,
    },
  );
  if (response == null) return null;
  if (response is! Map) {
    throw StateError('Invalid backup export response.');
  }
  final destination = response['destination'];
  if (destination is! String || destination.isEmpty) {
    throw StateError('Invalid backup export destination.');
  }
  return MultisigBackupFileExportResult(destination: destination);
}

Future<void> cleanupStaleMultisigBackupExportFiles({
  Directory? tempDirectory,
  DateTime? now,
  Duration maxAge = const Duration(hours: 24),
}) async {
  final root = tempDirectory ?? await getTemporaryDirectory();
  final dir = Directory(
    '${root.path}${Platform.pathSeparator}$_backupExportTempDirName',
  );
  if (!await dir.exists()) return;

  final cutoff = (now ?? DateTime.now()).subtract(maxAge);
  await for (final entity in dir.list()) {
    if (entity is! File || !entity.path.endsWith('.vizorbackup')) continue;
    try {
      final modified = await entity.lastModified();
      if (modified.isBefore(cutoff)) {
        await entity.delete();
      }
    } catch (_) {
      // Best-effort startup cleanup only.
    }
  }

  try {
    if (await dir.exists() && await dir.list().isEmpty) {
      await dir.delete();
    }
  } catch (_) {
    // Best-effort startup cleanup only.
  }
}

Future<MultisigBackupFileReadResult?> readMultisigBackupFile({
  MultisigBackupOpenFilePicker? pickFile,
}) async {
  final picker = pickFile ?? pickMultisigBackupOpenFile;

  try {
    final file = await picker();
    if (file == null) return null;
    final artifactJson = await file.readAsString();
    return MultisigBackupFileReadResult(
      path: file.path,
      artifactJson: artifactJson,
    );
  } catch (e) {
    throw MultisigBackupFileReadException(e);
  }
}

Future<String?> pickMultisigBackupSavePath({
  required String suggestedName,
}) async {
  final location = await getSaveLocation(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Vizor backup', extensions: ['vizorbackup']),
    ],
    suggestedName: suggestedName,
    confirmButtonText: 'Save',
    canCreateDirectories: true,
  );
  return location?.path;
}

Future<XFile?> pickMultisigBackupOpenFile() {
  return openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Vizor backup', extensions: ['vizorbackup', 'json']),
    ],
    confirmButtonText: 'Restore',
  );
}

String _backupFileTimestamp(DateTime value) {
  final local = value.toLocal();
  return '${_pad4(local.year)}${_pad2(local.month)}${_pad2(local.day)}-'
      '${_pad2(local.hour)}${_pad2(local.minute)}';
}

String _backupHashSuffix(String value) {
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (safe.isEmpty) return 'backup';
  return safe.length <= 6 ? safe : safe.substring(0, 6);
}

Future<File> _writeTemporaryMultisigBackupFile({
  required String suggestedName,
  required String artifactJson,
  Directory? tempDirectory,
}) async {
  final root = tempDirectory ?? await getTemporaryDirectory();
  final dir = Directory(
    '${root.path}${Platform.pathSeparator}$_backupExportTempDirName',
  );
  await dir.create(recursive: true);
  final file = File(
    '${dir.path}${Platform.pathSeparator}${_safeBackupFileName(suggestedName)}',
  );
  await file.writeAsString(artifactJson, flush: true);
  return file;
}

Future<void> _deleteFileIfExists(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {
    // The export file is encrypted and stored in app temp storage; deletion is
    // best-effort here and startup cleanup catches stale files.
  }
}

MultisigBackupFileSavePlatform _currentSavePlatform() {
  if (kIsWeb) return MultisigBackupFileSavePlatform.desktop;
  if (Platform.isIOS) return MultisigBackupFileSavePlatform.ios;
  if (Platform.isAndroid) return MultisigBackupFileSavePlatform.android;
  return MultisigBackupFileSavePlatform.desktop;
}

String _safeBackupFileName(String value) {
  final safe = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  if (safe.isEmpty) return 'vizor-multisig-backup.vizorbackup';
  return safe.endsWith('.vizorbackup') ? safe : '$safe.vizorbackup';
}

String _pad2(int value) => value.toString().padLeft(2, '0');

String _pad4(int value) => value.toString().padLeft(4, '0');
