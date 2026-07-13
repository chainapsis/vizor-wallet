// ignore_for_file: depend_on_referenced_packages
// Figma comparison tooling is dev-only and may reuse Widgetbook fixtures.

import 'package:flutter/material.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/theme/app_theme_host.dart';
import '../src/core/theme/legacy_material_theme.dart';
import 'figma_compare_scenarios.dart';

class FigmaCompareApp extends StatelessWidget {
  const FigmaCompareApp({
    required this.scenario,
    required this.themeMode,
    required this.captureBoundaryKey,
    super.key,
  });

  final FigmaCompareScenario scenario;
  final ThemeMode themeMode;
  final GlobalKey captureBoundaryKey;

  @override
  Widget build(BuildContext context) {
    final appTheme = themeMode == ThemeMode.light
        ? AppThemeData.light
        : AppThemeData.dark;

    return MaterialApp(
      title: 'Vizor Figma comparison',
      debugShowCheckedModeBanner: false,
      theme: buildLegacyLightTheme(),
      darkTheme: buildLegacyDarkTheme(),
      themeMode: themeMode,
      home: Scaffold(
        body: RepaintBoundary(
          key: captureBoundaryKey,
          child: Focus(
            canRequestFocus: false,
            descendantsAreFocusable: false,
            child: IgnorePointer(child: Builder(builder: scenario.builder)),
          ),
        ),
      ),
      builder: (context, child) => AppThemeHost(
        themeMode: themeMode,
        child: ColoredBox(
          color: appTheme.colors.background.window,
          child: child!,
        ),
      ),
    );
  }
}
