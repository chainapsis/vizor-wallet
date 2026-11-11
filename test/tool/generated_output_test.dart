import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/l10n/generated_output.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('generated_output_test');
    Directory('${root.path}/ios/Runner').createSync(recursive: true);
    File('${root.path}/elsewhere.txt').writeAsStringSync('keep');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('a regular generated file has no link on its path', () {
    File('${root.path}/ios/Runner/Out.swift').writeAsStringSync('');
    expect(symbolicLinkOnPath('ios/Runner/Out.swift', root: root.path), isNull);
    expect(
      symbolicLinkOnPath('ios/Runner/Missing.swift', root: root.path),
      isNull,
    );
  });

  test('finds a generated file that is a symbolic link', () {
    Link(
      '${root.path}/ios/Runner/Out.swift',
    ).createSync('${root.path}/elsewhere.txt');
    expect(
      symbolicLinkOnPath('ios/Runner/Out.swift', root: root.path),
      'ios/Runner/Out.swift',
    );
  });

  test('finds a directory link on the way to a generated file', () {
    Directory('${root.path}/other').createSync();
    Link('${root.path}/android').createSync('${root.path}/other');
    expect(
      symbolicLinkOnPath('android/NativeStrings.kt', root: root.path),
      'android',
    );
  });

  test('identical generated content preserves its modification time', () {
    const path = 'ios/Runner/Out.swift';
    expect(writeGeneratedTextIfChanged(path, 'same', root: root.path), isTrue);
    final file = File('${root.path}/$path');
    final time = DateTime.utc(2000);
    file.setLastModifiedSync(time);
    expect(writeGeneratedTextIfChanged(path, 'same', root: root.path), isFalse);
    expect(file.lastModifiedSync().toUtc(), time);
    expect(
      writeGeneratedTextIfChanged(path, 'changed', root: root.path),
      isTrue,
    );
    expect(file.readAsStringSync(), 'changed');
  });

  test('generated output writes reject a linked destination', () {
    Link(
      '${root.path}/ios/Runner/Out.swift',
    ).createSync('${root.path}/elsewhere.txt');
    expect(
      () => writeGeneratedTextIfChanged(
        'ios/Runner/Out.swift',
        'changed',
        root: root.path,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(File('${root.path}/elsewhere.txt').readAsStringSync(), 'keep');
  });
}
