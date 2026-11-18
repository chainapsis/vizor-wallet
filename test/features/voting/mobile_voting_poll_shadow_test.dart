@Tags(['mobile'])
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/voting_use_cases.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

void main() {
  setUpAll(loadFigmaCompareFonts);

  for (final width in [320.0, 393.0]) {
    testWidgets('poll shadows extend beyond the card at width $width', (
      tester,
    ) async {
      final shadowsWereDisabled = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = shadowsWereDisabled);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 852);
      addTearDown(tester.view.reset);
      final boundaryKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          home: RepaintBoundary(
            key: boundaryKey,
            child: AppTheme(
              data: AppThemeData.light,
              child: Builder(builder: buildMobileVotingPollsUseCase),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _expectOuterShadow(tester, boundaryKey, 'snack-governance-active');
      // Exercise a different item after the list has scrolled, too.
      final voted = find.byKey(
        const ValueKey('voting_poll_card_snack-governance-voted'),
      );
      await tester.ensureVisible(voted);
      await tester.pumpAndSettle();
      await _expectOuterShadow(tester, boundaryKey, 'snack-governance-voted');
      expect(tester.takeException(), isNull);
      debugDisableShadows = shadowsWereDisabled;
    });
  }
}

Future<void> _expectOuterShadow(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String roundId,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(boundaryKey),
  );
  final rect = tester
      .getRect(find.byKey(ValueKey('voting_poll_card_$roundId')))
      .shift(-boundary.localToGlobal(Offset.zero));
  final samples = {
    'left': Offset(rect.left - 3, rect.center.dy),
    'right': Offset(rect.right + 3, rect.center.dy),
    'bottom': Offset(rect.center.dx, rect.bottom + 4),
  };
  final background = AppThemeData.light.colors.background.window.toARGB32();
  final backgroundRgb =
      ((background >> 16) & 0xff) +
      ((background >> 8) & 0xff) +
      (background & 0xff);

  for (final sample in samples.values) {
    expect(boundary.size.contains(sample), isTrue);
  }
  final sampleRgb = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      int readRgb(Offset point) {
        final x = point.dx.round();
        final y = point.dy.round();
        final offset = (y * image.width + x) * 4;
        return pixels.getUint8(offset) +
            pixels.getUint8(offset + 1) +
            pixels.getUint8(offset + 2);
      }

      return {
        for (final sample in samples.entries) sample.key: readRgb(sample.value),
      };
    } finally {
      image.dispose();
    }
  });
  for (final sample in sampleRgb!.entries) {
    expect(
      sample.value,
      lessThan(backgroundRgb),
      reason: '$roundId shadow must reach beyond its ${sample.key} edge',
    );
  }
}
