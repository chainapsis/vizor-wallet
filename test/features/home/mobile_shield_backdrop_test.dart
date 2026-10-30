@Tags(['mobile'])
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/mobile_shield_backdrop.dart';
import 'package:zcash_wallet/src/features/home/widgets/mobile/shield/mobile_shield_scene.dart';

void main() {
  testWidgets('captures the last full shell even with a pending repaint', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    late BuildContext homeContext;
    await tester.pumpWidget(
      MaterialApp(
        home: MobileShieldBackdropHost(
          child: Builder(
            builder: (context) {
              homeContext = context;
              return const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ColoredBox(color: Colors.green)),
                  SizedBox(height: 80, child: ColoredBox(color: Colors.red)),
                ],
              );
            },
          ),
        ),
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.descendant(
        of: find.byType(MobileShieldBackdropHost),
        matching: find.byWidgetPredicate((widget) => widget is RepaintBoundary),
      ),
    );
    // Live balance/animation invalidation may occur between paint and the tap.
    boundary.markNeedsPaint();
    final backdrop = MobileShieldBackdropHost.capture(homeContext);
    expect(backdrop, isNotNull);
    final still = backdrop!;
    addTearDown(still.dispose);
    expect(still.image.width, 320);
    expect(still.image.height, 640);
    // The original render tree can disappear; the captured pixels remain.
    await tester.pumpWidget(const SizedBox.shrink());
    final bytes = await tester.runAsync(
      () => still.image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(bytes, isNotNull);
    final top = (100 * 320 + 100) * 4;
    final bottom = (600 * 320 + 100) * 4;
    expect(bytes!.getUint8(top + 1), greaterThan(bytes.getUint8(top)));
    expect(bytes.getUint8(bottom), greaterThan(bytes.getUint8(bottom + 1)));
  });

  testWidgets('scene retains its image after navigation owner releases it', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 320, 640),
      Paint()..color = Colors.green,
    );
    final picture = recorder.endRecording();
    final backdrop = MobileShieldBackdrop(picture.toImageSync(320, 640));
    picture.dispose();
    await tester.pumpWidget(
      MaterialApp(
        home: MobileShieldScene(
          phase: MobileShieldPhase.review,
          amount: '14.12',
          title: 'Transparent Balance',
          backdrop: backdrop,
        ),
      ),
    );
    final image = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(identical(image, backdrop.image), isFalse);
    backdrop.dispose();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(bytes, isNotNull);
    final filter = tester.widget<ImageFiltered>(find.byType(ImageFiltered));
    expect(filter.enabled, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
