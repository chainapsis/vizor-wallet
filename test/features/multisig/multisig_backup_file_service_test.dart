import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/multisig/services/multisig_backup_file_service.dart';

void main() {
  test('writes and reads the selected backup file', () async {
    final dir = await Directory.systemTemp.createTemp('multisig-backup-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/backup.vizorbackup';

    final saved = await writeMultisigBackupFile(
      suggestedName: 'backup.vizorbackup',
      artifactJson: '{"backup":true}',
      pickSavePath: ({required suggestedName}) async => path,
    );

    expect(saved, isNotNull);
    expect(saved!.path, path);
    expect(saved.artifactJson, '{"backup":true}');
    expect(await File(path).readAsString(), '{"backup":true}');
  });

  test('returns null when the save panel is cancelled', () async {
    final saved = await writeMultisigBackupFile(
      suggestedName: 'backup.vizorbackup',
      artifactJson: '{"backup":true}',
      pickSavePath: ({required suggestedName}) async => null,
    );

    expect(saved, isNull);
  });

  test('wraps write failures with a user-facing message', () async {
    final dir = await Directory.systemTemp.createTemp('multisig-backup-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/missing/backup.vizorbackup';

    expect(
      writeMultisigBackupFile(
        suggestedName: 'backup.vizorbackup',
        artifactJson: '{"backup":true}',
        pickSavePath: ({required suggestedName}) async => path,
      ),
      throwsA(
        isA<MultisigBackupFileSaveException>().having(
          (error) => error.toString(),
          'message',
          MultisigBackupFileSaveException.message,
        ),
      ),
    );
  });

  test('wraps save panel failures with a user-facing message', () {
    expect(
      writeMultisigBackupFile(
        suggestedName: 'backup.vizorbackup',
        artifactJson: '{"backup":true}',
        pickSavePath: ({required suggestedName}) async {
          throw const FileSystemException('Save panel unavailable');
        },
      ),
      throwsA(
        isA<MultisigBackupFileSaveException>().having(
          (error) => error.toString(),
          'message',
          MultisigBackupFileSaveException.message,
        ),
      ),
    );
  });

  test('builds a safe default backup file name', () {
    expect(
      defaultMultisigBackupFileName(
        backupHash: 'abc/123+456',
        now: DateTime(2026, 6, 29, 16, 27),
      ),
      'vizor-multisig-backup-20260629-1627-abc123.vizorbackup',
    );
  });
}
