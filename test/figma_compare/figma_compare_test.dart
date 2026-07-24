import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_app.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_capture.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_scenarios.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

void main() {
  test('comparison scenarios have stable unique IDs', () {
    final ids = figmaCompareScenarios.map((scenario) => scenario.id).toList();

    expect(ids.toSet(), hasLength(ids.length));
    expect(
      ids,
      containsAll(<String>[
        'pay-recipient',
        'pay-recipient-new-address',
        'pay-in-progress',
        'pay-completed',
        'mobile-home-default',
        'ironwood-migration-announcement-modal',
      ]),
    );
  });

  test('window capture path stays beside the Flutter content capture', () {
    expect(
      figmaCompareWindowCapturePath('/tmp/pay-recipient/content.png'),
      '/tmp/pay-recipient/content.window.png',
    );
    expect(
      figmaCompareWindowCapturePath('/tmp/pay-recipient/content'),
      '/tmp/pay-recipient/content.window.png',
    );
  });

  test('capture configuration accepts a form-factor-specific default', () {
    final configuration = FigmaCompareConfiguration.fromEnvironment(
      defaultScenarioId: 'mobile-home-default',
    );

    expect(configuration.scenarioId, 'mobile-home-default');
  });

  test(
    'configuration resolves only scenarios supported by its form factor',
    () {
      const desktopConfiguration = FigmaCompareConfiguration(
        scenarioId: 'pay-recipient',
        themeMode: ThemeMode.dark,
        outputPath: '/tmp/content.png',
        logicalSize: Size(1080, 720),
        pixelRatio: 1,
      );

      expect(
        desktopConfiguration.resolveScenario(AppFormFactor.desktop).id,
        'pay-recipient',
      );
      expect(
        () => desktopConfiguration.resolveScenario(AppFormFactor.mobile),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('does not support mobile'),
          ),
        ),
      );

      const mobileConfiguration = FigmaCompareConfiguration(
        scenarioId: 'mobile-home-default',
        themeMode: ThemeMode.dark,
        outputPath: '/tmp/content.png',
        logicalSize: Size(393, 852),
        pixelRatio: 3,
      );
      expect(
        mobileConfiguration.resolveScenario(AppFormFactor.mobile).id,
        'mobile-home-default',
      );
      expect(
        () => mobileConfiguration.resolveScenario(AppFormFactor.desktop),
        throwsStateError,
      );
    },
  );

  for (final scenario in figmaCompareScenarios.where(
    (scenario) => scenario.desktop,
  )) {
    testWidgets('${scenario.id} renders at the desktop comparison viewport', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1080, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        FigmaCompareApp(
          scenario: scenario,
          themeMode: ThemeMode.dark,
          captureBoundaryKey: boundaryKey,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(boundaryKey.currentContext, isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}
