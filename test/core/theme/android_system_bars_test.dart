import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/app_theme_host.dart';

void main() {
  test('light theme puts both bars on light window with dark icons', () {
    final style = androidSystemBarsStyleFor(Brightness.light);
    expect(style.statusBarColor, AppColors.light.background.window);
    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.systemStatusBarContrastEnforced, isFalse);
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

  test('dark theme puts both bars on dark window with light icons', () {
    final style = androidSystemBarsStyleFor(Brightness.dark);
    expect(style.statusBarColor, AppColors.dark.background.window);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemStatusBarContrastEnforced, isFalse);
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

  test('statusBarBrightness stays unset — that field is iOS-side', () {
    expect(
      androidSystemBarsStyleFor(Brightness.light).statusBarBrightness,
      isNull,
    );
    expect(
      androidSystemBarsStyleFor(Brightness.dark).statusBarBrightness,
      isNull,
    );
  });

  test('launch theme hexes in styles.xml match the window tokens', () {
    // values/styles.xml and values-night/styles.xml hardcode these —
    // android resources cannot read Dart tokens, so this pins the copies.
    expect(AppColors.light.background.window, const Color(0xFFF7F7F7));
    expect(AppColors.dark.background.window, const Color(0xFF0F0F0F));
  });
}
