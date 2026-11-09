import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool _fontsLoaded = false;

Future<void> loadAppTestFonts() async {
  // Cache completion, not a Future from another widget test's FakeAsync zone.
  if (_fontsLoaded) return;
  const fonts = <String, List<String>>{
    // Load the actual shipped subsets, never alias a system family to a
    // different test font: capture metrics must match the app's UI fonts.
    'Vizor Korean UI': ['assets/fonts/VizorKoreanUI-VF.ttf'],
    'Vizor Chinese UI': ['assets/fonts/VizorChineseUI-VF.ttf'],
    'Inter': [
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-Medium.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
      'assets/fonts/Inter-Bold.ttf',
    ],
    'Geist': [
      'assets/fonts/Geist-Regular.ttf',
      'assets/fonts/Geist-Medium.ttf',
      'assets/fonts/Geist-SemiBold.ttf',
      'assets/fonts/Geist-Bold.ttf',
    ],
    'Geist Mono': [
      'assets/fonts/GeistMono-Regular.ttf',
      'assets/fonts/GeistMono-Medium.ttf',
    ],
    'Young Serif': ['assets/fonts/YoungSerif-Regular.ttf'],
    'Shielding Serif': [
      'assets/fonts/ShieldingSerif-Medium.ttf',
      'assets/fonts/ShieldingSerif-Bold.ttf',
    ],
    'MaterialIcons': ['fonts/MaterialIcons-Regular.otf'],
  };

  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final asset in entry.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
  _fontsLoaded = true;
}
