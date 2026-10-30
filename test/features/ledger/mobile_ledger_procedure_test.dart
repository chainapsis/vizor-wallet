@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/ledger_procedure.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile/mobile_ledger_sheet_content.dart';
import 'package:zcash_wallet/src/features/ledger/widgets/mobile_ledger_signing_surface.dart';

import '../../figma_compare/figma_compare_font_loader.dart';

const _steps = [
  LedgerStep('Prepare transaction'),
  LedgerStep(
    'Review on Ledger',
    message: 'When prompted, check the amount and recipient on Ledger.',
    detail: 'Transaction 1 of 2',
    note: 'You will approve the next transaction separately.',
  ),
  LedgerStep('Finish transaction'),
];
const _boundaryKey = ValueKey('procedure_capture');
const _output = String.fromEnvironment('LEDGER_CAPTURE_DIR');
const _preparing = 'Keep Ledger connected while Vizor checks the Zcash app.';
const _reviewing = 'When prompted, check the amount and recipient on Ledger.';
const _saving = 'Keep Vizor open while it saves the signed transaction.';

Widget _motionHarness(
  int current, {
  bool reducedMotion = false,
  bool showNote = true,
}) => MaterialApp(
  home: AppTheme(
    data: AppThemeData.light,
    child: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: LedgerProcedure(
              currentStep: current,
              steps: [
                LedgerStep(
                  'Prepare transaction',
                  message: current == 0 ? _preparing : null,
                  busy: current == 0,
                ),
                LedgerStep(
                  'Review on Ledger',
                  message: current == 1 ? _reviewing : null,
                  note: current == 1 && showNote
                      ? 'You will approve the next transaction separately.'
                      : null,
                  requiresDeviceAction: true,
                  busy: current == 1,
                ),
                LedgerStep(
                  'Finish transaction',
                  message: current == 2 ? _saving : null,
                  busy: current == 2,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

double _visibleBodyHeight(WidgetTester tester, String message) => tester
    .getSize(
      find.ancestor(of: find.text(message), matching: find.byType(ClipRect)),
    )
    .height;

Widget _harness({
  double scale = 1,
  bool busy = false,
  bool failed = false,
  int currentStep = 1,
  ThemeMode theme = ThemeMode.light,
}) => RepaintBoundary(
  key: _boundaryKey,
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AppTheme(
      data: theme == ThemeMode.light ? AppThemeData.light : AppThemeData.dark,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: MobileLedgerSigningSurface(
            onBack: () {},
            canLeave: true,
            child: MobileLedgerSheetContent(
              title: failed ? 'Request declined' : 'Sign transaction',
              onClose: () {},
              action: failed
                  ? MobileLedgerAction('Try again', onPressed: () {})
                  : null,
              children: [
                const MobileLedgerIdentity('Ledger Flex', topPadding: 0),
                LedgerProcedure(
                  currentStep: currentStep,
                  steps: [
                    LedgerStep(
                      _steps[0].label,
                      message: currentStep == 0 ? _preparing : null,
                    ),
                    LedgerStep(
                      _steps[1].label,
                      message: _steps[1].message,
                      detail: _steps[1].detail,
                      note: _steps[1].note,
                      busy: busy || !failed,
                      requiresDeviceAction: !failed,
                    ),
                    _steps[2],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  setUpAll(loadFigmaCompareFonts);
  testWidgets('step guidance folds and unfolds without moving its baseline', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_motionHarness(0));
      final initialHeight = _visibleBodyHeight(tester, _preparing);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_visibleBodyHeight(tester, _preparing), initialHeight);

      await tester.pumpWidget(_motionHarness(1));
      expect(_visibleBodyHeight(tester, _preparing), initialHeight);
      await tester.pump(const Duration(milliseconds: 60));
      final incomingHeight = _visibleBodyHeight(tester, _reviewing);
      expect(
        _visibleBodyHeight(tester, _preparing),
        inExclusiveRange(0, initialHeight),
      );
      expect(incomingHeight, greaterThan(0));
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(_preparing))),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(_reviewing))),
        findsWidgets,
      );
      double baseline(String text) {
        final finder = find.text(text);
        final box = tester.renderObject<RenderBox>(finder);
        return tester.getTopLeft(finder).dy +
            box.getDryBaseline(box.constraints, TextBaseline.alphabetic)!;
      }

      expect(baseline('2'), closeTo(baseline('Review on Ledger'), 0.1));
      expect(
        find.byWidgetPredicate(
          (w) => w is AppIcon && w.name == AppIcons.loader,
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(_preparing), findsNothing);
      expect(
        _visibleBodyHeight(tester, _reviewing),
        greaterThan(incomingHeight),
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('rapid step reversal continues from the current visible layout', (
    tester,
  ) async {
    await tester.pumpWidget(_motionHarness(0));
    await tester.pumpWidget(_motionHarness(1));
    await tester.pump(const Duration(milliseconds: 80));
    final before = tester.getTopLeft(find.text('Finish transaction'));
    await tester.pumpWidget(_motionHarness(0));
    expect(
      tester.getTopLeft(find.text('Finish transaction')).dy,
      closeTo(before.dy, 0.1),
    );
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(_motionHarness(2));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(_motionHarness(1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(_reviewing), findsOneWidget);
    expect(find.text(_preparing), findsNothing);
    expect(find.text(_saving), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guidance changes within a step resize without a height jump', (
    tester,
  ) async {
    await tester.pumpWidget(_motionHarness(1));
    final originalHeight = _visibleBodyHeight(tester, _reviewing);
    await tester.pumpWidget(_motionHarness(1, showNote: false));
    expect(_visibleBodyHeight(tester, _reviewing), originalHeight);
    await tester.pump(const Duration(milliseconds: 80));
    final intermediateHeight = _visibleBodyHeight(tester, _reviewing);
    expect(intermediateHeight, inExclusiveRange(0, originalHeight));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      _visibleBodyHeight(tester, _reviewing),
      lessThan(intermediateHeight),
    );
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Review on Ledger'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion changes steps without a folding transition', (
    tester,
  ) async {
    await tester.pumpWidget(_motionHarness(0, reducedMotion: true));
    await tester.pumpWidget(_motionHarness(1, reducedMotion: true));
    await tester.pump();
    expect(find.text(_preparing), findsNothing);
    final height = _visibleBodyHeight(tester, _reviewing);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_visibleBodyHeight(tester, _reviewing), height);

    await tester.pumpWidget(
      _motionHarness(1, reducedMotion: true, showNote: false),
    );
    expect(_visibleBodyHeight(tester, _reviewing), lessThan(height));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(_motionHarness(1, showNote: false));
    await tester.pumpWidget(_motionHarness(2));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text(_reviewing), findsOneWidget);
    await tester.pumpWidget(_motionHarness(2, reducedMotion: true));
    await tester.pump();
    expect(find.text(_reviewing), findsNothing);
    expect(find.text(_saving), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'step motion keeps active guidance reachable at 320px and 2x text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_harness(scale: 2, currentStep: 0));
      await tester.pump();
      await tester.pumpWidget(_harness(scale: 2));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 200));
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final heading = tester.getTopLeft(find.text('Review on Ledger'));
      expect(heading.dy, greaterThanOrEqualTo(viewport.top - 1));
      expect(heading.dy, lessThan(viewport.bottom));
      await tester.ensureVisible(
        find.text('You will approve the next transaction separately.'),
      );
      await tester.pump();
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      scroll.position.jumpTo(0);
      await tester.pumpWidget(_harness(scale: 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scroll.position.pixels, 0);
      expect(tester.takeException(), isNull);
    },
  );
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'ordinal and first label baseline stay aligned at ${scale}x while busy',
      (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(_harness(scale: scale, busy: true));
        await tester.pump();
        final number = find.text('2');
        final label = find.text('Review on Ledger');
        double baseline(Finder finder) {
          final box = tester.renderObject<RenderBox>(finder);
          return tester.getTopLeft(finder).dy +
              box.getDryBaseline(box.constraints, TextBaseline.alphabetic)!;
        }

        expect(baseline(number), closeTo(baseline(label), 0.1));
        expect(
          number,
          findsOneWidget,
          reason: 'The loader must not replace the current ordinal.',
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is AppIcon && w.name == AppIcons.loader,
          ),
          findsOneWidget,
        );
        expect(find.text('Transaction 1 of 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final failed in [false, true]) {
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        '320px with 2x text reveals current guidance and retains footer (failed: $failed, ${theme.name})',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            _harness(scale: 2, failed: failed, theme: theme),
          );
          await tester.pump();
          final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
          final viewport = tester.getRect(find.byType(SingleChildScrollView));
          expect(scroll.position.pixels, greaterThan(0));
          expect(
            tester.getTopLeft(find.text('Review on Ledger')).dy,
            greaterThanOrEqualTo(viewport.top - 1),
          );
          expect(
            tester.getTopLeft(find.text('Review on Ledger')).dy,
            lessThan(viewport.bottom),
          );
          if (failed) {
            expect(find.text('Try again').hitTestable(), findsOneWidget);
          }
          if (_output.isNotEmpty) {
            await expectLater(
              find.byKey(_boundaryKey),
              matchesGoldenFile(
                '$_output/sign-${failed ? 'declined' : 'reviewing'}-320-2x-${theme.name}.png',
              ),
            );
          }
          // Manual scrolling remains possible and an unrelated parent rebuild
          // must not send the reader back to the active step.
          scroll.position.jumpTo(0);
          await tester.pump();
          await tester.pumpWidget(
            _harness(scale: 2, failed: failed, theme: theme),
          );
          await tester.pump();
          expect(scroll.position.pixels, 0);
          await tester.ensureVisible(
            find.text('You will approve the next transaction separately.'),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
