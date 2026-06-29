import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef MultisigBackupFileWriter =
    Future<MultisigBackupFileSaveResult?> Function({
      required String suggestedName,
      required String artifactJson,
    });

typedef MultisigBackupSavePathPicker =
    Future<String?> Function({required String suggestedName});

final multisigBackupFileWriterProvider = Provider<MultisigBackupFileWriter>(
  (ref) => writeMultisigBackupFile,
);

class MultisigBackupFileSaveResult {
  const MultisigBackupFileSaveResult({
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
}) async {
  final picker = pickSavePath ?? pickMultisigBackupSavePath;

  try {
    final path = await picker(suggestedName: suggestedName);
    if (path == null) return null;

    final file = File(path);
    await file.writeAsString(artifactJson);
    final readBack = await file.readAsString();
    return MultisigBackupFileSaveResult(
      path: file.path,
      artifactJson: readBack,
    );
  } catch (e) {
    throw MultisigBackupFileSaveException(e);
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

String _pad2(int value) => value.toString().padLeft(2, '0');

String _pad4(int value) => value.toString().padLeft(4, '0');
