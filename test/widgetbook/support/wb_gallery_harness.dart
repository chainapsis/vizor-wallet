// Shared pump harness for gallery and support tests, so the ten Phase 2
// gallery suites do not each copy a WidgetbookScope setup.

import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

/// Repaint boundary [useCaseFingerprint] captures.
const Key kWbCaptureKey = ValueKey('wb_use_case_capture');

/// Pumps [builder] inside a Widgetbook scope so `context.knobs` reads [knobs],
/// and returns the state so a test can assert on the registered fields.
///
/// [knobs] maps a knob label to the *option label* the knob's `labelBuilder`
/// produces, which is what the shareable URL encodes.
Future<WidgetbookState> pumpUseCase(
  WidgetTester tester,
  WidgetBuilder builder, {
  Map<String, String> knobs = const {},
  WidgetbookRoot? root,
  String? path,
  AppThemeData theme = AppThemeData.dark,
  Size canvasSize = const Size(1600, 1200),
}) async {
  tester.view.physicalSize = canvasSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // Fresh mount per pump: reusing the element tree keeps the previous pump's
  // State, so a fixture seeded in `initState` would still show the old option.
  await tester.pumpWidget(const SizedBox.shrink());

  final state = WidgetbookState(
    root: root ?? WidgetbookRoot(children: []),
    path: path,
    queryParams: knobs.isEmpty
        ? const {}
        : {'knobs': FieldCodec.encodeQueryGroup(knobs)},
  );

  await tester.pumpWidget(
    MaterialApp(
      home: WidgetbookScope(
        state: state,
        child: AppTheme(
          data: theme,
          // `Widgetbook.material` puts a Material above every use case; the
          // composer's text fields require one.
          child: Material(
            type: MaterialType.transparency,
            child: RepaintBoundary(
              key: kWbCaptureKey,
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return state;
}

/// Unmounts the tree so fixture timers (the deposit countdown) are cancelled
/// before the test ends.
Future<void> disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

/// A render signature of the pumped use case: the sha1 of its raw pixels.
///
/// Two knob options with the same fingerprint render the same thing, which is
/// how a dispatcher that ignores its knob is caught. Pixels rather than the
/// widget tree because some states differ only in colour — an active amount
/// card, a focused border — and never in text or widget type.
Future<String> useCaseFingerprint(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(kWbCaptureKey),
  );
  // `runAsync`: rasterising and reading back pixels are real engine calls and
  // deadlock on the fake async of a widget test.
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
  });
  return sha1.convert(bytes!.buffer.asUint8List()).toString();
}

/// Sweeps one knob and asserts every option renders something distinguishable.
///
/// [labels] maps each option label to the knob value it selects; the knob's
/// other axes stay at their defaults via [otherKnobs].
Future<void> expectKnobOptionsRenderDistinctly(
  WidgetTester tester,
  WidgetBuilder builder, {
  required String label,
  required List<String> optionLabels,
  Map<String, String> otherKnobs = const {},
}) async {
  final seen = <String, String>{};
  for (final option in optionLabels) {
    await pumpUseCase(tester, builder, knobs: {...otherKnobs, label: option});
    expect(tester.takeException(), isNull, reason: '$label / $option');

    final fingerprint = await useCaseFingerprint(tester);
    final duplicate = seen[fingerprint];
    expect(
      duplicate,
      isNull,
      reason:
          "'$label' options '$duplicate' and '$option' render identically — "
          'the knob has a dead option or a duplicated dispatch.',
    );
    seen[fingerprint] = option;
  }
  await disposeTree(tester);
}
