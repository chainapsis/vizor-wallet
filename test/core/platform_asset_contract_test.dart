import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/platform_asset_contract.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final assets = Directory('assets')
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .map((file) => file.path.replaceAll('\\', '/'))
      .where((path) => !path.split('/').any((part) => part.startsWith('.')))
      .toList();
  const desktopEntry = '''    - path: assets/illustrations/desktop/
      platforms:
        - linux
        - macos
        - web
        - windows''';

  test('pubspec exposes runtime assets on their intended platforms', () {
    expect(platformAssetContractErrors(pubspec, assets), isEmpty);
  });

  test('an unrestricted desktop declaration fails the contract', () {
    expect(pubspec, contains(desktopEntry));
    final changed = pubspec.replaceFirst(
      desktopEntry,
      '    - assets/illustrations/desktop/',
    );
    expect(
      platformAssetContractErrors(changed, assets),
      contains(contains('unexpected [android, ios]')),
    );
  });

  test('a shared profile directory restricted to desktop fails', () {
    const profileEntry = '    - assets/profile_pictures/';
    expect(pubspec, contains(profileEntry));
    final changed = pubspec.replaceFirst(
      profileEntry,
      '''    - path: assets/profile_pictures/
      platforms:
        - macos''',
    );
    expect(
      platformAssetContractErrors(changed, assets),
      contains(allOf(contains('profile_picture_01.png'), contains('android'))),
    );
  });

  test('an undeclared nested directory fails even with a declared parent', () {
    const nested = 'assets/illustrations/new_scene/hero.webp';
    expect(
      platformAssetContractErrors(pubspec, [...assets, nested]),
      contains(startsWith('$nested: missing')),
    );
  });

  test('an unrestricted duplicate cannot override desktop exclusion', () {
    final changed = pubspec.replaceFirst(
      '  assets:',
      '  assets:\n    - assets/icons/desktop/network_zec.png',
    );
    expect(
      platformAssetContractErrors(changed, assets),
      contains(allOf(contains('network_zec.png'), contains('android, ios'))),
    );
  });

  test('declared assets retain resolution variants and fonts', () {
    expect(
      platformAssetContractErrors(
        '''
flutter:
  assets:
    - assets/icons/
    - assets/images/hero.webp
  fonts:
    - family: Test
      fonts:
        - asset: assets/fonts/test.ttf
''',
        [
          'assets/icons/book.svg',
          'assets/icons/2.0x/book.svg',
          'assets/images/hero.webp',
          'assets/images/3.0x/hero.webp',
          'assets/images/2.x/hero.webp',
          'assets/fonts/test.ttf',
        ],
      ),
      isEmpty,
    );
  });

  test('a directory declaration rejects variants without a matching base', () {
    const orphan = 'assets/icons/2.0x/new.webp';
    expect(
      platformAssetContractErrors(
        '''
flutter:
  assets:
    - assets/icons/
''',
        [
          'assets/icons/book.svg',
          'assets/icons/2.0x/book.svg',
          orphan,
          'assets/icons/3.0x/new.webp',
        ],
      ),
      unorderedEquals([
        '$orphan: missing [android, ios, linux, macos, web, windows]; unexpected []',
        'assets/icons/3.0x/new.webp: missing [android, ios, linux, macos, web, windows]; unexpected []',
      ]),
    );
  });

  test('an explicit logical asset permits variants without a base file', () {
    expect(
      platformAssetContractErrors(
        '''
flutter:
  assets:
    - assets/icons/
    - assets/icons/new.webp
''',
        ['assets/icons/2.0x/new.webp', 'assets/icons/2.x/new.webp'],
      ),
      isEmpty,
    );
  });

  for (final entry in ['assets/icons/2.0x/', 'assets/icons/2.0x/new.webp']) {
    test('an explicit variant declaration permits $entry without a base', () {
      expect(
        platformAssetContractErrors(
          '''
flutter:
  assets:
    - $entry
''',
          ['assets/icons/2.0x/new.webp'],
        ),
        isEmpty,
      );
    });
  }

  test('directory variants inherit their matching base platform restriction', () {
    const declaration = '''
flutter:
  assets:
    - path: assets/icons/desktop/
      platforms: [linux, macos, web, windows]
''';
    const variants = [
      'assets/icons/desktop/icon.webp',
      'assets/icons/desktop/2.0x/icon.webp',
    ];
    expect(platformAssetContractErrors(declaration, variants), isEmpty);
    expect(
      platformAssetContractErrors(
        '$declaration    - assets/icons/desktop/2.0x/\n',
        variants,
      ),
      contains(
        'assets/icons/desktop/2.0x/icon.webp: missing []; unexpected [android, ios]',
      ),
    );
  });
}
