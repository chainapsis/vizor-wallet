import 'dart:io';

import 'package:file_selector/file_selector.dart';
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

  test('reads the selected backup file', () async {
    final dir = await Directory.systemTemp.createTemp('multisig-backup-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/backup.vizorbackup';
    await File(path).writeAsString('{"backup":true}');

    final selected = await readMultisigBackupFile(
      pickFile: () async => XFile(path),
    );

    expect(selected, isNotNull);
    expect(selected!.path, path);
    expect(selected.artifactJson, '{"backup":true}');
  });

  test('returns null when the open panel is cancelled', () async {
    final selected = await readMultisigBackupFile(pickFile: () async => null);

    expect(selected, isNull);
  });

  test('wraps read failures with a user-facing message', () {
    expect(
      readMultisigBackupFile(
        pickFile: () async => XFile('/missing/backup.vizorbackup'),
      ),
      throwsA(
        isA<MultisigBackupFileReadException>().having(
          (error) => error.toString(),
          'message',
          MultisigBackupFileReadException.message,
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
