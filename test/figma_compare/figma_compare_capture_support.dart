import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_app.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_configuration.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';

const _windowAppearanceChannel = MethodChannel(
  'com.zcash.wallet/window_appearance',
);

void runFigmaCompareCaptureTest({
  required AppFormFactor expectedFormFactor,
  required Size defaultLogicalSize,
  required double defaultPixelRatio,
}) {
  testWidgets('captures the configured Figma comparison scenario', (
    tester,
  ) async {
    expect(
      kAppFormFactor,
      expectedFormFactor,
      reason:
          'The capture test was compiled with the wrong form factor. Use '
          'scripts/figma-compare.sh so the required define is always passed.',
    );

    if (expectedFormFactor == AppFormFactor.mobile) {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    }

    final configuration = FigmaCompareConfiguration.fromEnvironment(
      defaultLogicalSize: defaultLogicalSize,
      defaultPixelRatio: defaultPixelRatio,
    );
    final scenario = configuration.resolveScenario(expectedFormFactor);
    final output = File(
      configuration.outputPath.isEmpty
          ? '${Directory.systemTemp.path}/vizor-figma-compare/'
                '${scenario.id}/content.widget.png'
          : configuration.outputPath,
    ).absolute;
    output.parent.createSync(recursive: true);

    tester.view.devicePixelRatio = configuration.pixelRatio;
    tester.view.physicalSize = Size(
      configuration.logicalSize.width * configuration.pixelRatio,
      configuration.logicalSize.height * configuration.pixelRatio,
    );
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      _windowAppearanceChannel,
      (_) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(_windowAppearanceChannel, null),
    );

    await _loadAppFonts();
    final captureBoundaryKey = GlobalKey();
    await tester.pumpWidget(
      FigmaCompareApp(
        scenario: scenario,
        themeMode: configuration.themeMode,
        captureBoundaryKey: captureBoundaryKey,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await _precacheRenderedImages(tester);
    // Route- and provider-driven modal scenarios are presented after the
    // first frame. Advance the standard Material sheet transition to its
    // resting state without using pumpAndSettle, which would hang on the
    // intentionally looping home-screen illustration motion.
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byKey(captureBoundaryKey),
      matchesGoldenFile(output.uri),
    );
    debugDefaultTargetPlatformOverride = null;
    debugPrint(
      'Figma comparison widget: ${output.path} '
      '(${configuration.logicalSize.width.toInt()}x'
      '${configuration.logicalSize.height.toInt()} logical PNG, simulated '
      'DPR ${configuration.pixelRatio})',
    );
  });
}

Future<void> _precacheRenderedImages(WidgetTester tester) async {
  final cachedProviders = <ImageProvider<Object>>{};
  final images = [
    for (final element in find.byType(Image).evaluate())
      (image: element.widget as Image, context: element),
  ];
  await tester.runAsync(() async {
    for (final entry in images) {
      if (!cachedProviders.add(entry.image.image)) continue;
      await precacheImage(entry.image.image, entry.context);
    }
  });
}

Future<void> _loadAppFonts() async {
  const fonts = <String, List<String>>{
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
  };

  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final asset in entry.value) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }
}
