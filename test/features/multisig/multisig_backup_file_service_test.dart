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
    expect(saved!.destination, 'file:$path');
    expect(saved.path, 'file:$path');
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

    await expectLater(
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

  test('wraps save panel failures with a user-facing message', () async {
    await expectLater(
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

  test('exports iOS backups through the mobile exporter', () async {
    final dir = await Directory.systemTemp.createTemp('multisig-backup-');
    addTearDown(() => dir.delete(recursive: true));
    String? tempPath;

    final saved = await writeMultisigBackupFile(
      suggestedName: 'backup.vizorbackup',
      artifactJson: '{"backup":true}',
      platform: MultisigBackupFileSavePlatform.ios,
      tempDirectory: dir,
      exportMobileFile:
          ({required suggestedName, required tempFilePath, platform}) async {
            tempPath = tempFilePath;
            expect(suggestedName, 'backup.vizorbackup');
            expect(platform, MultisigBackupFileSavePlatform.ios);
            expect(await File(tempFilePath).readAsString(), '{"backup":true}');
            return const MultisigBackupFileExportResult(
              destination: 'ios-files:backup.vizorbackup',
            );
          },
    );

    expect(saved, isNotNull);
    expect(saved!.destination, 'ios-files:backup.vizorbackup');
    expect(saved.artifactJson, '{"backup":true}');
    expect(tempPath, isNotNull);
    expect(await File(tempPath!).exists(), isFalse);
  });

  test('exports Android backups through the mobile exporter', () async {
    final dir = await Directory.systemTemp.createTemp('multisig-backup-');
    addTearDown(() => dir.delete(recursive: true));
    String? tempPath;

    final saved = await writeMultisigBackupFile(
      suggestedName: 'backup.vizorbackup',
      artifactJson: '{"backup":true}',
      platform: MultisigBackupFileSavePlatform.android,
      tempDirectory: dir,
      exportMobileFile:
          ({required suggestedName, required tempFilePath, platform}) async {
            tempPath = tempFilePath;
            expect(suggestedName, 'backup.vizorbackup');
            expect(platform, MultisigBackupFileSavePlatform.android);
            expect(await File(tempFilePath).readAsString(), '{"backup":true}');
            return const MultisigBackupFileExportResult(
              destination: 'android-documents:backup.vizorbackup',
            );
          },
    );

    expect(saved, isNotNull);
    expect(saved!.destination, 'android-documents:backup.vizorbackup');
    expect(saved.artifactJson, '{"backup":true}');
    expect(tempPath, isNotNull);
    expect(await File(tempPath!).exists(), isFalse);
  });

  test('deletes mobile temp backups when export is cancelled', () async {
    final dir = await Directory.systemTemp.createTemp('multisig-backup-');
    addTearDown(() => dir.delete(recursive: true));
    String? tempPath;

    final saved = await writeMultisigBackupFile(
      suggestedName: 'backup.vizorbackup',
      artifactJson: '{"backup":true}',
      platform: MultisigBackupFileSavePlatform.ios,
      tempDirectory: dir,
      exportMobileFile:
          ({required suggestedName, required tempFilePath, platform}) async {
            tempPath = tempFilePath;
            return null;
          },
    );

    expect(saved, isNull);
    expect(tempPath, isNotNull);
    expect(await File(tempPath!).exists(), isFalse);
  });

  test('deletes mobile temp backups when export fails', () async {
    final dir = await Directory.systemTemp.createTemp('multisig-backup-');
    addTearDown(() => dir.delete(recursive: true));
    String? tempPath;

    await expectLater(
      writeMultisigBackupFile(
        suggestedName: 'backup.vizorbackup',
        artifactJson: '{"backup":true}',
        platform: MultisigBackupFileSavePlatform.android,
        tempDirectory: dir,
        exportMobileFile:
            ({required suggestedName, required tempFilePath, platform}) async {
              tempPath = tempFilePath;
              throw const FileSystemException('Document export failed');
            },
      ),
      throwsA(isA<MultisigBackupFileSaveException>()),
    );
    expect(tempPath, isNotNull);
    expect(await File(tempPath!).exists(), isFalse);
  });

  test('cleanup removes stale temporary backup exports', () async {
    final root = await Directory.systemTemp.createTemp('multisig-backup-');
    addTearDown(() => root.delete(recursive: true));
    final exportDir = Directory('${root.path}/multisig-backup-export');
    await exportDir.create();
    final oldBackup = File('${exportDir.path}/old.vizorbackup');
    final freshBackup = File('${exportDir.path}/fresh.vizorbackup');
    final unrelated = File('${exportDir.path}/old.txt');
    await oldBackup.writeAsString('old');
    await freshBackup.writeAsString('fresh');
    await unrelated.writeAsString('old');
    final now = DateTime(2026, 7, 8, 12);
    await oldBackup.setLastModified(now.subtract(const Duration(days: 2)));
    await freshBackup.setLastModified(now);
    await unrelated.setLastModified(now.subtract(const Duration(days: 2)));

    await cleanupStaleMultisigBackupExportFiles(tempDirectory: root, now: now);

    expect(await oldBackup.exists(), isFalse);
    expect(await freshBackup.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
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
