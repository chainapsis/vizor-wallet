import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/theme/app_theme_host.dart';

void main() {
  test('light theme puts both bars on light window with dark icons', () {
    final style = appSystemBarsStyleFor(Brightness.light);
    expect(style.statusBarColor, AppColors.light.background.window);
    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.systemStatusBarContrastEnforced, isFalse);
    expect(style.systemNavigationBarColor, AppColors.light.background.window);
    expect(
      style.systemNavigationBarDividerColor,
      AppColors.light.background.window,
    );
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    expect(style.systemNavigationBarContrastEnforced, isFalse);
  });

  test('dark theme puts both bars on dark window with light icons', () {
    final style = appSystemBarsStyleFor(Brightness.dark);
    expect(style.statusBarColor, AppColors.dark.background.window);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemStatusBarContrastEnforced, isFalse);
    expect(style.systemNavigationBarColor, AppColors.dark.background.window);
    expect(
      style.systemNavigationBarDividerColor,
      AppColors.dark.background.window,
    );
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarContrastEnforced, isFalse);
  });

  test('iOS status bar follows the resolved theme', () {
    expect(
      appSystemBarsStyleFor(Brightness.light).statusBarBrightness,
      Brightness.light,
    );
    expect(
      appSystemBarsStyleFor(Brightness.dark).statusBarBrightness,
      Brightness.dark,
    );
  });

  testWidgets('leaving a dark Welcome override restores light system bars', (
    tester,
  ) async {
    Widget app({required bool welcome}) => MaterialApp(
      builder: (_, _) => AppThemeHost(
        themeMode: ThemeMode.light,
        child: welcome
            ? const AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarBrightness: Brightness.dark,
                  statusBarIconBrightness: Brightness.light,
                ),
                child: SizedBox.expand(),
              )
            : const SizedBox.expand(),
      ),
    );
    await tester.pumpWidget(app(welcome: true));
    await tester.pump();
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
    expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.dark);
    await tester.pumpWidget(app(welcome: false));
    await tester.pump();
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
    expect(SystemChrome.latestStyle?.statusBarBrightness, Brightness.light);
  });

  test('launch theme hexes in styles.xml match the window tokens', () {
    // values/styles.xml and values-night/styles.xml hardcode these —
    // android resources cannot read Dart tokens, so this pins the copies.
    expect(AppColors.light.background.window, const Color(0xFFF7F7F7));
    expect(AppColors.dark.background.window, const Color(0xFF0F0F0F));
  });
}
