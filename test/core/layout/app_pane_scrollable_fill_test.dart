import 'dart:ui' show Offset, PointerDeviceKind, Size;

import 'package:flutter/material.dart' show MaterialApp, Scrollbar;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';

void main() {
  testWidgets('shows scrollbar while hovered only when content overflows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: AppPaneScrollableFill(child: SizedBox(height: 600)),
        ),
      ),
    );
    await tester.pump();

    Scrollbar scrollbar() => tester.widget<Scrollbar>(find.byType(Scrollbar));

    expect(scrollbar().thumbVisibility, isFalse);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);

    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(AppPaneScrollableFill)));
    await tester.pump();

    expect(scrollbar().thumbVisibility, isTrue);

    await mouse.moveTo(const Offset(500, 500));
    await tester.pump();

    expect(scrollbar().thumbVisibility, isFalse);
  });

  testWidgets('keeps scrollbar hidden while hovered when content fits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(300, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: AppPaneScrollableFill(child: SizedBox(height: 120)),
        ),
      ),
    );
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);

    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(AppPaneScrollableFill)));
    await tester.pump();

    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.thumbVisibility, isFalse);
  });
}
