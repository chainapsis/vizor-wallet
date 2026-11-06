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
}
