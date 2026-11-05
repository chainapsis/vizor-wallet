// ignore_for_file: depend_on_referenced_packages
// Figma comparison tooling is dev-only and may reuse Widgetbook fixtures.

import 'package:flutter/material.dart';

import '../src/core/l10n/app_language.dart';
import '../src/core/l10n/locale_typography.dart';
import '../src/core/theme/app_theme.dart';
import '../src/core/theme/app_theme_host.dart';
import '../src/core/theme/legacy_material_theme.dart';
import 'figma_compare_scenarios.dart';

class FigmaCompareApp extends StatelessWidget {
  const FigmaCompareApp({
    required this.scenario,
    required this.themeMode,
    required this.captureBoundaryKey,
    this.locale,
    super.key,
  });

  final FigmaCompareScenario scenario;
  final ThemeMode themeMode;
  final GlobalKey captureBoundaryKey;

  /// Forces a UI language, including preview-only ones; `null` follows the
  /// device.
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    final appTheme = themeMode == ThemeMode.light
        ? AppThemeData.light
        : AppThemeData.dark;

    final capture = RepaintBoundary(
      key: captureBoundaryKey,
      child: Focus(
        canRequestFocus: false,
        descendantsAreFocusable: scenario.allowFocus,
        child: IgnorePointer(
          ignoring: !scenario.allowPointer,
          child: Builder(builder: scenario.builder),
        ),
      ),
    );

    return MaterialApp(
      title: 'Vizor Figma comparison',
      debugShowCheckedModeBanner: false,
      theme: buildLegacyLightTheme(),
      darkTheme: buildLegacyDarkTheme(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: locale == null
          ? appSupportedLocales()
          : appSupportedLocales(preview: true),
      localizationsDelegates: appLocalizationsDelegates,
      home: scenario.outsideScaffold
          ? const SizedBox.shrink()
          : Scaffold(body: capture),
      builder: (context, child) {
        final themed = LocaleTypography(
          child: AppThemeHost(
            themeMode: themeMode,
            child: ColoredBox(
              color: appTheme.colors.background.window,
              child: scenario.outsideScaffold ? capture : child!,
            ),
          ),
        );
        final mediaQuery = MediaQuery.maybeOf(context);
        if (mediaQuery == null) return themed;
        return MediaQuery(
          data: mediaQuery.copyWith(disableAnimations: true),
          child: themed,
        );
      },
    );
  }
}
