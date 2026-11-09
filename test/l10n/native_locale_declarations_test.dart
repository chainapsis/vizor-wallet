import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

/// Each non-English language as Apple and Android resources name it.
const _nativeTags = {
  AppLanguage.ko: (apple: 'ko', android: 'ko'),
  AppLanguage.zh: (apple: 'zh-Hans', android: 'zh-CN'),
};

const _appleRunners = ['ios', 'macos'];

Set<String> _knownRegions(String platform) {
  final project = File(
    '$platform/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();
  final match = RegExp(r'knownRegions = \(([^)]*)\);').firstMatch(project);
  expect(match, isNotNull, reason: '$platform has no knownRegions');
  return match!
      .group(1)!
      .split(',')
      .map((region) => region.trim().replaceAll('"', ''))
      .where((region) => region.isNotEmpty)
      .toSet();
}

Set<String> _androidLocales() {
  final config = File('android/app/src/main/res/xml/locales_config.xml');
  if (!config.existsSync()) return {};
  return RegExp(r'android:name="([^"]+)"')
      .allMatches(config.readAsStringSync())
      .map((match) => match.group(1)!)
      .toSet();
}

void main() {
  test('English is the Apple development region', () {
    for (final platform in _appleRunners) {
      expect(_knownRegions(platform), contains('en'), reason: platform);
    }
  });

  // The OS and the stores read these before the app runs, so they list a
  // language exactly when it is released (docs/i18n/adding-a-language.md).
  test('native resources declare exactly the released languages', () {
    final androidLocales = _androidLocales();
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    var anyReleased = false;
    for (final language in AppLanguage.values) {
      if (language == AppLanguage.en) continue;
      final tags = _nativeTags[language];
      expect(
        tags,
        isNotNull,
        reason: 'Add the Apple and Android tags of ${language.tag}.',
      );
      final released = language.released;
      anyReleased |= released;
      final fix = released ? 'add' : 'remove';
      for (final platform in _appleRunners) {
        expect(
          _knownRegions(platform).contains(tags!.apple),
          released,
          reason: '$fix ${tags.apple} in $platform knownRegions',
        );
        expect(
          File(
            '$platform/Runner/${tags.apple}.lproj/InfoPlist.strings',
          ).existsSync(),
          released,
          reason: '$fix $platform/Runner/${tags.apple}.lproj/InfoPlist.strings',
        );
      }
      expect(
        androidLocales.contains(tags!.android),
        released,
        reason: '$fix ${tags.android} in res/xml/locales_config.xml',
      );
    }
    expect(
      manifest.contains('android:localeConfig='),
      anyReleased,
      reason: 'android:localeConfig is set only once a language ships',
    );
  });
}
