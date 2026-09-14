import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';

import 'wb_gallery_harness.dart';

// Lane-agnostic on purpose: assertions compare against [wbCompiledLaneLayout]
// so the file passes in both the desktop and the mobile token lane. The
// mobile-lane specifics live in `wb_layout_mobile_test.dart`.
const _desktopBoxChildKey = ValueKey('wb_desktop_window_box_child');

void main() {
  const childKey = ValueKey('wb_layout_test_child');

  testWidgets('layout knob starts on the compiled lane', (tester) async {
    WbLayout? captured;

    final state = await pumpUseCase(tester, (context) {
      captured = wbLayoutKnob(context);
      return const SizedBox.shrink();
    });

    expect(captured, wbCompiledLaneLayout);
    expect(state.knobs['Layout']!.fields.single.type, FieldType.objectDropdown);
  });

  testWidgets('layout knob reads the selected option from the query group', (
    tester,
  ) async {
    for (final layout in WbLayout.values) {
      WbLayout? captured;

      await pumpUseCase(tester, (context) {
        captured = wbLayoutKnob(context);
        return const SizedBox.shrink();
      }, knobs: {'Layout': wbLayoutLabel(layout)});

      expect(captured, layout);
    }
  });

  testWidgets('WbFrame desktop gives the child the real pane box', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      (_) => const WbFrame(
        layout: WbLayout.desktop,
        child: SizedBox.expand(key: childKey),
      ),
    );

    final paneInset = appDesktopPaneLeftInset(kAppDesktopSidebarWidth);
    expect(
      tester.getSize(find.byKey(childKey)),
      Size(
        kWbDesktopWindowWidth - paneInset - kAppDesktopShellMargin,
        kWbDesktopWindowHeight - kAppDesktopShellMargin * 2,
      ),
    );
  });

  testWidgets('WbFrame mobile gives the child the phone box and insets', (
    tester,
  ) async {
    late MediaQueryData media;

    await pumpUseCase(
      tester,
      (_) => WbFrame(
        layout: WbLayout.mobile,
        child: Builder(
          builder: (context) {
            media = MediaQuery.of(context);
            return const SizedBox.expand(key: childKey);
          },
        ),
      ),
    );

    expect(tester.getSize(find.byKey(childKey)), kWbPhoneSize);
    expect(media.size, kWbPhoneSize);
    expect(media.viewPadding.top, kWbPhoneStatusBarInset);
    // The fixtures hand their screens a const MediaQueryData, so no host
    // padding or keyboard inset may leak into the preview.
    expect(media.padding, EdgeInsets.zero);
    expect(media.viewInsets, EdgeInsets.zero);
  });

  testWidgets('WbDesktopWindowBox keeps the 1080x720 window on a big canvas', (
    tester,
  ) async {
    late MediaQueryData media;

    await pumpUseCase(
      tester,
      (_) => Align(
        child: WbDesktopWindowBox(
          child: Builder(
            builder: (context) {
              media = MediaQuery.of(context);
              return const SizedBox.expand(key: _desktopBoxChildKey);
            },
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    // The default harness canvas is 1600x1200, so the window never scales up.
    expect(
      tester.getRect(find.byKey(_desktopBoxChildKey)).size,
      const Size(kWbDesktopWindowWidth, kWbDesktopWindowHeight),
    );
    expect(
      media.size,
      const Size(kWbDesktopWindowWidth, kWbDesktopWindowHeight),
    );
    expect(media.padding, EdgeInsets.zero);
    expect(media.viewInsets, EdgeInsets.zero);
  });

  testWidgets('WbDesktopWindowBox scales down into a shorter canvas', (
    tester,
  ) async {
    late MediaQueryData media;

    await pumpUseCase(
      tester,
      (_) => Align(
        child: SizedBox(
          width: 900,
          height: 600,
          // Loose constraints, the way the canvas centres a use case.
          child: Align(
            child: WbDesktopWindowBox(
              child: Builder(
                builder: (context) {
                  media = MediaQuery.of(context);
                  return const SizedBox.expand(key: _desktopBoxChildKey);
                },
              ),
            ),
          ),
        ),
      ),
    );

    // Nothing overflows: the window still lays out against the full 1080x720,
    // and the screen inside it still reads the window's own metrics.
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(_desktopBoxChildKey)),
      const Size(kWbDesktopWindowWidth, kWbDesktopWindowHeight),
    );
    expect(
      media.size,
      const Size(kWbDesktopWindowWidth, kWbDesktopWindowHeight),
    );

    // Only the painted box shrinks, and it shrinks to fit the 900x600 canvas.
    final painted = tester.getRect(find.byKey(_desktopBoxChildKey));
    final scale = 600 / kWbDesktopWindowHeight;
    expect(painted.height, moreOrLessEquals(600, epsilon: 0.01));
    expect(
      painted.width,
      moreOrLessEquals(kWbDesktopWindowWidth * scale, epsilon: 0.01),
    );
  });

  testWidgets('WbPhoneBox keeps the phone box whole on a taller canvas', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      (_) => const Align(child: WbPhoneBox(child: _PhoneFillColumn())),
    );

    expect(tester.takeException(), isNull);
    // The default harness canvas is 1600x1200, so nothing has to shrink.
    expect(tester.getRect(find.byKey(_phoneBoxChildKey)).size, kWbPhoneSize);
  });

  testWidgets('WbPhoneBox scales down into a canvas shorter than the phone', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      (_) => const Align(
        child: SizedBox(
          width: 900,
          height: 600,
          // Loose constraints, the way the canvas centres a use case.
          child: Align(child: WbPhoneBox(child: _PhoneFillColumn())),
        ),
      ),
    );

    // Nothing overflows: the column still lays out against the full 852.
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(_phoneBoxChildKey)), kWbPhoneSize);

    // Only the painted box shrinks, and it shrinks to the canvas height.
    final painted = tester.getRect(find.byKey(_phoneBoxChildKey));
    final scale = 600 / kWbPhoneSize.height;
    expect(painted.height, moreOrLessEquals(600, epsilon: 0.01));
    expect(
      painted.width,
      moreOrLessEquals(kWbPhoneSize.width * scale, epsilon: 0.01),
    );
  });

  testWidgets('WbPhoneBox still fills tight constraints larger than the phone', (
    tester,
  ) async {
    // No Align, so the box inherits the harness's TIGHT canvas constraints —
    // what a gallery use case gets. A bare FittedBox would centre the frame at
    // 393x852 here and collapse the fingerprints of knob options that differ
    // only outside the phone box (see send_gallery_test.dart).
    await pumpUseCase(
      tester,
      (_) => const WbPhoneBox(child: _PhoneFillColumn()),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(_phoneBoxChildKey)),
      const Size(1600, 1200),
    );
  });

  testWidgets('WbScaleDownBox keeps the child mounted across the threshold', (
    tester,
  ) async {
    final canvasHeight = ValueNotifier<double>(1200);
    addTearDown(canvasHeight.dispose);
    _MountCountingChild.mounts = 0;

    await pumpUseCase(
      tester,
      (_) => ValueListenableBuilder<double>(
        valueListenable: canvasHeight,
        builder: (context, height, _) => Align(
          child: SizedBox(
            width: 900,
            height: height,
            child: Align(
              child: WbScaleDownBox(
                size: kWbPhoneSize,
                child: SizedBox.fromSize(
                  size: kWbPhoneSize,
                  child: const _MountCountingChild(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(_MountCountingChild.mounts, 1);
    expect(tester.getRect(find.byType(_MountCountingChild)).size, kWbPhoneSize);

    // Crossing the fits / does-not-fit threshold swaps the tree shape, so the
    // subtree is reparented through a GlobalKey rather than remounted — a
    // preview mid-interaction would otherwise reset on every canvas resize.
    canvasHeight.value = 600;
    await tester.pump();

    expect(_MountCountingChild.mounts, 1);
    expect(
      tester.getRect(find.byType(_MountCountingChild)).height,
      moreOrLessEquals(600, epsilon: 0.01),
    );
  });

  testWidgets('WbLaneOnly renders the child for the compiled lane', (
    tester,
  ) async {
    await pumpUseCase(
      tester,
      (_) => const WbLaneOnly(
        layout: wbCompiledLaneLayout,
        child: SizedBox.expand(key: childKey),
      ),
    );

    expect(find.byKey(childKey), findsOneWidget);
    expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsNothing);
  });

  testWidgets('WbLaneOnly shows the other lane run command instead', (
    tester,
  ) async {
    final other = wbCompiledLaneLayout == WbLayout.desktop
        ? WbLayout.mobile
        : WbLayout.desktop;

    await pumpUseCase(
      tester,
      (_) => WbLaneOnly(
        layout: other,
        child: const SizedBox.expand(key: childKey),
      ),
    );

    expect(find.byKey(childKey), findsNothing);
    expect(find.byKey(const ValueKey('wb_lane_only_notice')), findsOneWidget);
    expect(
      find.text('Compiled for ${wbCompiledLaneLayout.name}'),
      findsOneWidget,
    );
    expect(
      find.text('Run the ${other.name} lane to preview this layout.'),
      findsOneWidget,
    );
    expect(find.text(wbLaneRunCommand(other)), findsOneWidget);
    expect(
      wbLaneRunCommand(other),
      'fvm flutter run -t lib/widgetbook.dart '
      '--dart-define=VIZOR_FORM_FACTOR=${other.name}',
    );
  });

  test('wbLayoutMatchesLane only matches the compiled lane', () {
    expect(wbLayoutMatchesLane(wbCompiledLaneLayout), isTrue);
    for (final layout in WbLayout.values) {
      expect(wbLayoutMatchesLane(layout), layout == wbCompiledLaneLayout);
    }
  });
}

const _phoneBoxChildKey = ValueKey('wb_phone_box_test_child');

/// Counts how many times it is mounted, so a remount across the scale-down
/// threshold is visible to a test.
class _MountCountingChild extends StatefulWidget {
  const _MountCountingChild();

  static int mounts = 0;

  @override
  State<_MountCountingChild> createState() => _MountCountingChildState();
}

class _MountCountingChildState extends State<_MountCountingChild> {
  @override
  void initState() {
    super.initState();
    _MountCountingChild.mounts++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// A column that exactly fills the phone box, so squeezing the box instead of
/// scaling it would raise a RenderFlex overflow the test can see.
class _PhoneFillColumn extends StatelessWidget {
  const _PhoneFillColumn();

  @override
  Widget build(BuildContext context) {
    final half = kWbPhoneSize.height / 2;
    return Column(
      key: _phoneBoxChildKey,
      children: [
        SizedBox(height: half, width: double.infinity),
        SizedBox(height: half, width: double.infinity),
      ],
    );
  }
}
