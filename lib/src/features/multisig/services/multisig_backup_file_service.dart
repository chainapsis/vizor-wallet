import 'dart:io';

import 'package:path_provider/path_provider.dart';

class MultisigBackupFileSaveResult {
  const MultisigBackupFileSaveResult({
    required this.path,
    required this.artifactJson,
  });

  final String path;
  final String artifactJson;
}

String defaultMultisigBackupFileName({
  required String backupHash,
  DateTime? now,
}) {
  final timestamp = _backupFileTimestamp(now ?? DateTime.now());
  final suffix = _backupHashSuffix(backupHash);
  return 'vizor-multisig-backup-$timestamp-$suffix.vizorbackup';
}

Future<MultisigBackupFileSaveResult> writeMultisigBackupFile({
  required String suggestedName,
  required String artifactJson,
}) async {
  final dir =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$suggestedName');
  await file.writeAsString(artifactJson);
  final readBack = await file.readAsString();
  return MultisigBackupFileSaveResult(path: file.path, artifactJson: readBack);
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
