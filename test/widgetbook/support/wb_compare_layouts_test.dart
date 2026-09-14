import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/widgetbook/gallery/home_activity_gallery.dart';
import 'package:zcash_wallet/widgetbook/support/wb_compare_layouts.dart';
import 'package:zcash_wallet/widgetbook/support/wb_layout.dart';

import 'wb_gallery_harness.dart';

// Desktop lane by default like the other gallery suites; every assertion is
// on pane structure, not on token metrics, so it holds in either lane.
void main() {
  // The real gallery case at the end needs real fonts: the monospaced fallback
  // overflows the fixed-width home fixtures.
  setUpAll(_loadAppFonts);

  testWidgets('the label constant matches the knob the galleries register', (
    tester,
  ) async {
    final state = await pumpUseCase(tester, (context) {
      wbLayoutKnob(context);
      return const SizedBox.shrink();
    });

    expect(state.knobs.containsKey(kWbLayoutKnobLabel), isTrue);
  });

  group('wbCompareLayoutOf', () {
    test('reads the selected option label', () {
      for (final layout in WbLayout.values) {
        expect(
          wbCompareLayoutOf({kWbLayoutKnobLabel: wbLayoutLabel(layout)}),
          layout,
        );
      }
    });

    test('falls back to the compiled lane like the knob does', () {
      expect(wbCompareLayoutOf(const {}), wbCompiledLaneLayout);
      expect(
        wbCompareLayoutOf(const {kWbLayoutKnobLabel: 'Tablet'}),
        wbCompiledLaneLayout,
      );
    });
  });

  group('WbCompareLayoutsAddon', () {
    testWidgets('off renders the single real pane', (tester) async {
      await _pumpCompare(tester, setting: false, layout: WbLayout.desktop);

      expect(find.byKey(kWbCompareLayoutsKey), findsNothing);
      expect(find.text(WbLayout.desktop.name), findsOneWidget);
      expect(find.text(WbLayout.mobile.name), findsNothing);
      expect(_captionFinder(WbLayout.desktop), findsNothing);
    });

    testWidgets('on with Layout=Desktop shows both panes, desktop left', (
      tester,
    ) async {
      await _pumpCompare(tester, setting: true, layout: WbLayout.desktop);

      _expectBothPanes(tester);
    });

    testWidgets('on with Layout=Mobile shows the same two panes', (
      tester,
    ) async {
      await _pumpCompare(tester, setting: true, layout: WbLayout.mobile);

      _expectBothPanes(tester);
    });

    testWidgets('flipping the real knob does not move a pane', (tester) async {
      await _pumpCompare(tester, setting: true, layout: WbLayout.desktop);
      final onDesktop = _paneCentres(tester);

      await _pumpCompare(tester, setting: true, layout: WbLayout.mobile);
      final onMobile = _paneCentres(tester);

      // The real state drives whichever pane it selects, but the derived pane
      // always takes the other layout, so the canvas is identical either way.
      expect(onMobile, onDesktop);
    });

    testWidgets('a use case without a Layout knob keeps its single pane', (
      tester,
    ) async {
      await _pumpCompare(
        tester,
        setting: true,
        layout: WbLayout.desktop,
        knobs: const {},
        builder: (_) => const Text('no layout knob'),
      );

      expect(find.byKey(kWbCompareLayoutsKey), findsNothing);
      expect(find.text('no layout knob'), findsOneWidget);
      expect(_captionFinder(WbLayout.desktop), findsNothing);
      expect(_captionFinder(WbLayout.mobile), findsNothing);
    });

    testWidgets('the registered knobs outrank a stale Layout in the URL', (
      tester,
    ) async {
      // A deep link can carry a `Layout` entry the current use case does not
      // register; once it has built, the empty registry collapses the panes.
      await _pumpCompare(
        tester,
        setting: true,
        layout: WbLayout.desktop,
        builder: (_) => const Text('no layout knob'),
      );

      expect(find.byKey(kWbCompareLayoutsKey), findsNothing);
      expect(find.text('no layout knob'), findsOneWidget);
    });

    testWidgets('the derived pane does not touch the real state', (
      tester,
    ) async {
      final state = await _pumpCompare(
        tester,
        setting: true,
        layout: WbLayout.mobile,
      );

      // Same knob group the harness encoded: the preview pane rebuilt the use
      // case at the other layout without writing that choice back.
      expect(FieldCodec.decodeQueryGroup(state.queryParams['knobs']), {
        kWbLayoutKnobLabel: wbLayoutLabel(WbLayout.mobile),
      });
      expect(state.uri.queryParameters['knobs'], isNotNull);
      expect(
        wbCompareLayoutOf(
          FieldCodec.decodeQueryGroup(state.queryParams['knobs']),
        ),
        WbLayout.mobile,
      );
    });

    testWidgets('both panes lay a fixed-size frame out at its own size', (
      tester,
    ) async {
      // The workbench loosens the real use case's constraints with a Stack, so
      // a pane that hands its copy tight constraints would stretch a fixed
      // preview frame (a phone box, a desktop window box) to the pane.
      await _pumpCompare(
        tester,
        setting: true,
        layout: WbLayout.desktop,
        builder: _fixedSizeProbe,
      );

      for (final layout in WbLayout.values) {
        expect(
          tester.getSize(find.byKey(_fixedSizeProbeKey(layout))),
          _kFixedProbeSize,
          reason: layout.name,
        );
      }
    });

    testWidgets(
      'opening the second pane reparents the first, not remounts it',
      (tester) async {
        // Frame 1 is the single pane (the knob is not registered yet), frame 2
        // the pair. A remount there re-runs every mount driver in the fixture.
        _mountCount = 0;
        await _pumpCompare(
          tester,
          setting: true,
          layout: WbLayout.desktop,
          knobs: const {},
          builder: _mountCountingProbe,
        );
        await tester.pump();

        expect(find.byKey(kWbCompareLayoutsKey), findsOneWidget);
        expect(
          _mountCount,
          2,
          reason: 'the kept primary plus the new secondary pane',
        );
      },
    );

    testWidgets('a lane-filtered knob says so on the pane that fell back', (
      tester,
    ) async {
      await _pumpCompare(
        tester,
        setting: true,
        layout: WbLayout.mobile,
        knobs: {
          kWbLayoutKnobLabel: wbLayoutLabel(WbLayout.mobile),
          _kStageKnob: _kScanningStage,
        },
        builder: _laneFilteredProbe,
      );
      await tester.pump();

      // Desktop does not offer 'Scanning', so its pane silently shows the
      // first stage; the caption is what keeps the pair from reading as one
      // state in two layouts.
      expect(
        tester.widget<Text>(_captionFinder(WbLayout.desktop)).data,
        _expectedCaption(WbLayout.desktop, '$_kStageKnob: $_kRequestStage'),
      );
      expect(
        tester.widget<Text>(_captionFinder(WbLayout.mobile)).data,
        _expectedCaption(WbLayout.mobile),
      );
    });

    testWidgets('navigating away forgets the Layout knob it remembered', (
      tester,
    ) async {
      final withKnob = WidgetbookUseCase(
        name: 'Playground',
        builder: _layoutProbe,
      );
      final plain = WidgetbookUseCase(
        name: 'Playground',
        builder: (_) => const Text('no layout knob'),
      );
      final state = WidgetbookState(
        root: WidgetbookRoot(
          children: [
            WidgetbookFolder(
              name: 'Screens',
              children: [
                WidgetbookComponent(name: 'Probe', useCases: [withKnob]),
                WidgetbookComponent(name: 'Plain', useCases: [plain]),
              ],
            ),
          ],
        ),
        path: withKnob.path,
        // No panels, so `updatePath` below does not sync a real router.
        panels: const <LayoutPanel>{},
        queryParams: {
          'knobs': FieldCodec.encodeQueryGroup({
            kWbLayoutKnobLabel: wbLayoutLabel(WbLayout.desktop),
          }),
        },
      );
      addTearDown(state.dispose);

      await _pumpPanes(tester, state);
      await tester.pump();
      expect(find.byKey(kWbCompareLayoutsKey), findsOneWidget);

      // What `WidgetbookState.updatePath` does when the navigation panel moves:
      // same state object, new path, knobs dropped. The remembered flag must
      // not survive it.
      state
        ..path = plain.path
        ..queryParams.remove('knobs');
      state.knobs.clear();
      await _pumpPanes(tester, state);

      expect(find.byKey(kWbCompareLayoutsKey), findsNothing);
      expect(find.text('no layout knob'), findsOneWidget);
    });

    testWidgets('a real gallery case compares without throwing', (
      tester,
    ) async {
      await _pumpCompare(
        tester,
        setting: true,
        layout: WbLayout.desktop,
        builder: buildHomeScreenGalleryCase,
        canvasSize: const Size(2400, 1400),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(kWbCompareLayoutsKey), findsOneWidget);
      expect(_captionFinder(WbLayout.desktop), findsOneWidget);
      expect(_captionFinder(WbLayout.mobile), findsOneWidget);
      await disposeTree(tester);
    });

    for (final layout in WbLayout.values) {
      testWidgets('activity state updates both panes with primary $layout', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(2400, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final useCase = WidgetbookUseCase(
          name: 'Playground',
          builder: buildActivityScreenGalleryCase,
        );
        final root = WidgetbookRoot(
          children: [
            WidgetbookComponent(name: 'Activity', useCases: [useCase]),
          ],
        );
        final state = WidgetbookState(
          root: root,
          path: useCase.path,
          queryParams: {
            'knobs': FieldCodec.encodeQueryGroup({
              'Layout': wbLayoutLabel(layout),
              'State': 'Rows',
            }),
          },
        );
        await _pumpPanes(tester, state);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('April 2025'), findsNWidgets(2));

        // Keep the mounted compare tree, as the live workbench does. Only
        // its URI-keyed primary is replaced by a knob change.
        state.queryParams = {
          'knobs': FieldCodec.encodeQueryGroup({
            'Layout': wbLayoutLabel(layout),
            'State': 'Failed to load',
          }),
        };
        await _pumpPanes(tester, state);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        expect(find.text('Activity could not be loaded.'), findsOneWidget);
        expect(
          find.text("Couldn't load activity. Try again in a moment."),
          findsOneWidget,
        );

        state.queryParams = {
          'knobs': FieldCodec.encodeQueryGroup({
            'Layout': wbLayoutLabel(layout),
            'State': 'Rows',
          }),
        };
        await _pumpPanes(tester, state);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        expect(find.text('April 2025'), findsNWidgets(2));
        expect(find.text('Activity could not be loaded.'), findsNothing);
        expect(
          find.text("Couldn't load activity. Try again in a moment."),
          findsNothing,
        );
        await disposeTree(tester);
        state.dispose();
      });
    }
  });
}

/// A use case that renders which layout its own knob resolved to.
///
/// The pane text is the enum name (`desktop`) and the caption is the knob's
/// option label (`Desktop`), so the two never collide in a text finder.
Widget _layoutProbe(BuildContext context) {
  return Center(child: Text(wbLayoutKnob(context).name));
}

const Size _kFixedProbeSize = Size(200, 100);

Key _fixedSizeProbeKey(WbLayout layout) => ValueKey('probe_${layout.name}');

/// A use case that lays out to a fixed size, the way the preview frames do.
Widget _fixedSizeProbe(BuildContext context) {
  final layout = wbLayoutKnob(context);
  return SizedBox.fromSize(
    key: _fixedSizeProbeKey(layout),
    size: _kFixedProbeSize,
    child: Center(child: Text(layout.name)),
  );
}

const String _kStageKnob = 'Stage';
const String _kRequestStage = 'Request QR';
const String _kScanningStage = 'Scanning';

/// A use case whose second knob only offers its last option on mobile — the
/// `payAmountErrorOptions(layout)` shape.
Widget _laneFilteredProbe(BuildContext context) {
  final layout = wbLayoutKnob(context);
  final stage = context.knobs.object.dropdown<String>(
    label: _kStageKnob,
    options: layout == WbLayout.mobile
        ? const [_kRequestStage, _kScanningStage]
        : const [_kRequestStage],
  );
  return Center(child: Text('${layout.name} $stage'));
}

int _mountCount = 0;

Widget _mountCountingProbe(BuildContext context) =>
    _MountCounter(label: wbLayoutKnob(context).name);

class _MountCounter extends StatefulWidget {
  const _MountCounter({required this.label});

  final String label;

  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  @override
  void initState() {
    super.initState();
    _mountCount++;
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(widget.label));
}

/// Pumps the panes directly around [state], so a test can mutate that state —
/// navigate, in particular — without remounting the tree.
Future<void> _pumpPanes(WidgetTester tester, WidgetbookState state) {
  return tester.pumpWidget(
    MaterialApp(
      home: WidgetbookScope(
        state: state,
        child: AppTheme(
          data: AppThemeData.dark,
          child: Material(
            type: MaterialType.transparency,
            child: WbCompareLayoutsPanes(
              state: state,
              primary: _workbenchPrimary(),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The primary child exactly as the workbench hands it to the innermost addon:
/// the use case under the `Stack` that loosens its constraints.
Widget _workbenchPrimary() => Stack(
  children: [
    Builder(
      builder: (context) {
        final state = WidgetbookState.of(context);
        // Match Workbench's UseCaseBuilder(key: ValueKey(state.uri)) without
        // importing Widgetbook's internal widget.
        return KeyedSubtree(
          key: ValueKey(state.uri),
          child: Builder(builder: state.useCase!.build),
        );
      },
    ),
  ],
);

/// Pumps [builder] as a registered use case, wrapped by the addon the way the
/// workbench wraps it: the addon builds above the use case, and its `child`
/// resolves the use case from the ambient state.
Future<WidgetbookState> _pumpCompare(
  WidgetTester tester, {
  required bool setting,
  required WbLayout layout,
  WidgetBuilder builder = _layoutProbe,
  Map<String, String>? knobs,
  Size canvasSize = const Size(1600, 1200),
}) async {
  final useCase = WidgetbookUseCase(name: 'Playground', builder: builder);
  final root = WidgetbookRoot(
    children: [
      WidgetbookFolder(
        name: 'Screens',
        children: [
          WidgetbookComponent(name: 'Probe', useCases: [useCase]),
        ],
      ),
    ],
  );
  final addon = WbCompareLayoutsAddon();

  return pumpUseCase(
    tester,
    (context) => addon.buildUseCase(context, _workbenchPrimary(), setting),
    root: root,
    path: useCase.path,
    knobs: knobs ?? {kWbLayoutKnobLabel: wbLayoutLabel(layout)},
    canvasSize: canvasSize,
  );
}

Finder _captionFinder(WbLayout layout) =>
    find.byKey(wbCompareLayoutsCaptionKey(layout));

/// The caption a pane shows: its layout, the token note when the layout is
/// not the compiled lane, then any knob drift. Lane-agnostic on purpose.
String _expectedCaption(WbLayout layout, [String? drift]) => [
  wbLayoutLabel(layout),
  if (layout != wbCompiledLaneLayout) wbCompareTokenNote(),
  ?drift,
].join(' · ');

void _expectBothPanes(WidgetTester tester) {
  expect(find.byKey(kWbCompareLayoutsKey), findsOneWidget);
  for (final layout in WbLayout.values) {
    expect(find.text(layout.name), findsOneWidget, reason: layout.name);
    expect(_captionFinder(layout), findsOneWidget, reason: layout.name);
    expect(
      tester.widget<Text>(_captionFinder(layout)).data,
      _expectedCaption(layout),
    );
  }

  final centres = _paneCentres(tester);
  expect(
    centres[WbLayout.desktop]!.dx,
    lessThan(centres[WbLayout.mobile]!.dx),
    reason: 'Desktop is always the left pane',
  );
  expect(
    tester.getCenter(_captionFinder(WbLayout.desktop)).dx,
    lessThan(tester.getCenter(_captionFinder(WbLayout.mobile)).dx),
  );
}

Map<WbLayout, Offset> _paneCentres(WidgetTester tester) => {
  for (final layout in WbLayout.values)
    layout: tester.getCenter(find.text(layout.name)),
};

Future<void> _loadAppFonts() async {
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Bold.ttf'));
  final geistMono = FontLoader('Geist Mono')
    ..addFont(rootBundle.load('assets/fonts/GeistMono-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/GeistMono-Medium.ttf'));
  final youngSerif = FontLoader('Young Serif')
    ..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'));

  await Future.wait([geist.load(), geistMono.load(), youngSerif.load()]);
}
