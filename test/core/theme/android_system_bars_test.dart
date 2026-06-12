import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/app_theme_host.dart';

void main() {
  test('light theme puts the nav bar on light window with dark buttons', () {
    final style = androidSystemBarsStyleFor(Brightness.light);
    expect(
      style.systemNavigationBarColor,
      AppColors.light.background.window,
    );
    expect(
      style.systemNavigationBarDividerColor,
      AppColors.light.background.window,
    );
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    expect(style.systemNavigationBarContrastEnforced, isFalse);
  });

  test('dark theme puts the nav bar on dark window with light buttons', () {
    final style = androidSystemBarsStyleFor(Brightness.dark);
    expect(
      style.systemNavigationBarColor,
      AppColors.dark.background.window,
    );
    expect(
      style.systemNavigationBarDividerColor,
      AppColors.dark.background.window,
    );
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarContrastEnforced, isFalse);
  });

  test('status bar fields stay unset so current behavior is untouched', () {
    final style = androidSystemBarsStyleFor(Brightness.light);
    expect(style.statusBarColor, isNull);
    expect(style.statusBarIconBrightness, isNull);
    expect(style.statusBarBrightness, isNull);
  });

  test('launch theme hexes in styles.xml match the window tokens', () {
    // values/styles.xml and values-night/styles.xml hardcode these —
    // android resources cannot read Dart tokens, so this pins the copies.
    expect(AppColors.light.background.window, const Color(0xFFF7F7F7));
    expect(AppColors.dark.background.window, const Color(0xFF0F0F0F));
  });
}
