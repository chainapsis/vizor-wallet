import 'dart:io';

import 'package:flutter/services.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

/// Where `scripts/fetch-capture-fonts.sh` stores the CJK capture fonts.
String captureFontDirectory() {
  final override = Platform.environment['VIZOR_CAPTURE_FONT_DIR'];
  if (override != null && override.isNotEmpty) return override;
  return '${Platform.environment['HOME']}/.cache/vizor/capture-fonts';
}

// Family names match the fallbacks in `fontFamilyFallbackFor`.
const _captureFonts = <AppLanguage, (String, String)>{
  AppLanguage.ko: ('Noto Sans KR', 'NotoSansKR-VF.ttf'),
  AppLanguage.zh: ('Noto Sans SC', 'NotoSansSC-VF.ttf'),
};

/// Loads the CJK fonts a [language] capture needs. Flutter tests cannot read
/// system fonts, so ko/zh text would otherwise render as boxes with the
/// wrong widths. Both fonts load when present because a Korean screen can
/// still show Chinese (the language picker), and the other way round.
Future<void> loadCaptureLocaleFonts(AppLanguage language) async {
  if (!_captureFonts.containsKey(language)) return;

  final directory = captureFontDirectory();
  for (final MapEntry(key: fontLanguage, value: (family, fileName))
      in _captureFonts.entries) {
    // Registered fonts outlive a test; scans render hundreds of scenarios.
    if (_loadedFamilies.contains(family)) continue;
    final file = File('$directory/$fileName');
    if (!file.existsSync()) {
      if (fontLanguage != language) continue;
      throw StateError(
        'Missing ${file.path}. Run scripts/fetch-capture-fonts.sh to capture '
        '${language.tag} screens.',
      );
    }
    final bytes = file.readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
    _loadedFamilies.add(family);
  }
}

final _loadedFamilies = <String>{};
