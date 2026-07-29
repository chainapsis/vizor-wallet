import 'package:flutter/material.dart';

import '../src/core/layout/app_form_factor.dart';
import 'figma_compare_scenarios.dart';

class FigmaCompareConfiguration {
  const FigmaCompareConfiguration({
    required this.scenarioId,
    required this.themeMode,
    required this.outputPath,
    required this.logicalSize,
    required this.pixelRatio,
  });

  factory FigmaCompareConfiguration.fromEnvironment({
    Size defaultLogicalSize = const Size(1080, 720),
    double defaultPixelRatio = 1,
    String defaultScenarioId = 'pay-recipient',
  }) {
    const scenarioId = String.fromEnvironment(
      'FIGMA_COMPARE_SCENARIO',
      defaultValue: '',
    );
    const themeName = String.fromEnvironment(
      'FIGMA_COMPARE_THEME',
      defaultValue: 'dark',
    );
    const outputPath = String.fromEnvironment('FIGMA_COMPARE_OUTPUT');
    const widthText = String.fromEnvironment('FIGMA_COMPARE_WIDTH');
    const heightText = String.fromEnvironment('FIGMA_COMPARE_HEIGHT');
    const pixelRatioText = String.fromEnvironment('FIGMA_COMPARE_PIXEL_RATIO');

    final themeMode = switch (themeName) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => throw ArgumentError.value(
        themeName,
        'FIGMA_COMPARE_THEME',
        'Expected dark or light.',
      ),
    };
    final width = widthText.isEmpty
        ? defaultLogicalSize.width
        : _positiveDouble(widthText, 'FIGMA_COMPARE_WIDTH');
    final height = heightText.isEmpty
        ? defaultLogicalSize.height
        : _positiveDouble(heightText, 'FIGMA_COMPARE_HEIGHT');
    final pixelRatio = pixelRatioText.isEmpty
        ? defaultPixelRatio
        : _positiveDouble(pixelRatioText, 'FIGMA_COMPARE_PIXEL_RATIO');

    return FigmaCompareConfiguration(
      scenarioId: scenarioId.isEmpty ? defaultScenarioId : scenarioId,
      themeMode: themeMode,
      outputPath: outputPath,
      logicalSize: Size(width, height),
      pixelRatio: pixelRatio,
    );
  }

  final String scenarioId;
  final ThemeMode themeMode;
  final String outputPath;
  final Size logicalSize;
  final double pixelRatio;

  FigmaCompareScenario resolveScenario(AppFormFactor formFactor) {
    final scenario = findFigmaCompareScenario(scenarioId);
    if (scenario == null) {
      final available = figmaCompareScenarios.map((item) => item.id).join(', ');
      throw ArgumentError.value(
        scenarioId,
        'FIGMA_COMPARE_SCENARIO',
        'Unknown scenario. Available: $available',
      );
    }

    final supported = switch (formFactor) {
      AppFormFactor.desktop => scenario.desktop,
      AppFormFactor.mobile => scenario.mobile,
    };
    if (!supported) {
      throw StateError(
        'Scenario ${scenario.id} does not support ${formFactor.name}.',
      );
    }
    return scenario;
  }

  static double _positiveDouble(String value, String name) {
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) {
      throw ArgumentError.value(value, name, 'Expected a positive number.');
    }
    return parsed;
  }
}
