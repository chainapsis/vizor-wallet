@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';

import 'wb_gallery_harness.dart';

// The desktop lane can only ever compile `WbLaneOnly`'s notice branch for a
// mobile request; this file pins the mirror image in the mobile lane.
// Run with:
//   fvm flutter test --tags mobile --run-skipped \
//     --dart-define=VIZOR_FORM_FACTOR=mobile \
//     test/widgetbook/support/wb_layout_mobile_test.dart
void main() {
  test('the mobile lane compiles the mobile token set', () {
    expect(wbCompiledLaneLayout, WbLayout.mobile);
  });

  testWidgets('a desktop request renders the desktop lane command', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      (_) =>
          const WbLaneOnly(layout: WbLayout.desktop, child: SizedBox.expand()),
    );

    expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsOneWidget);
    expect(find.text('Compiled for mobile'), findsOneWidget);
    expect(find.text(wbLaneRunCommand(WbLayout.desktop)), findsOneWidget);
  });

  testWidgets('the layout knob opens on mobile in this lane', (tester) async {
    WbLayout? captured;

    await pumpUseCase(tester, (context) {
      captured = wbLayoutKnob(context);
      return const SizedBox.shrink();
    });

    expect(captured, WbLayout.mobile);
  });
}
