import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:zcash_wallet/widgetbook/support/wb_design_status.dart';

import 'wb_gallery_harness.dart';

const _figmaUrl = 'https://www.figma.com/design/abc/Vizor?node-id=1-2';

void main() {
  group('wbNoFigma', () {
    test('bare sentinel when there is no note', () {
      expect(wbNoFigma(), kWbNoFigma);
      expect(wbNoFigma(note: ''), kWbNoFigma);
    });

    test('url-encodes the note', () {
      expect(
        wbNoFigma(note: 'Dev only; not designed'),
        'vizor-design:none?note=Dev%20only%3B%20not%20designed',
      );
    });
  });

  group('wbDesignStatusOf', () {
    test('null, empty and blank are unmarked', () {
      expect(wbDesignStatusOf(null), WbDesignStatus.unmarked);
      expect(wbDesignStatusOf(''), WbDesignStatus.unmarked);
      expect(wbDesignStatusOf('   '), WbDesignStatus.unmarked);
    });

    test('sentinel with or without a note is noFigma', () {
      expect(wbDesignStatusOf(kWbNoFigma), WbDesignStatus.noFigma);
      expect(
        wbDesignStatusOf(wbNoFigma(note: 'Widgetbook-only harness')),
        WbDesignStatus.noFigma,
      );
      expect(wbDesignStatusOf('  $kWbNoFigma  '), WbDesignStatus.noFigma);
    });

    test('anything else is linked', () {
      expect(wbDesignStatusOf(_figmaUrl), WbDesignStatus.linked);
      // A near-miss sentinel is a link, not a sentinel.
      expect(
        wbDesignStatusOf('vizor-design:none-of-the-above'),
        WbDesignStatus.linked,
      );
    });
  });

  group('wbDesignNote', () {
    test('round-trips a note through wbNoFigma', () {
      expect(
        wbDesignNote(wbNoFigma(note: 'Dev only; not designed')),
        'Dev only; not designed',
      );
    });

    test('null for a bare sentinel, a link, or nothing', () {
      expect(wbDesignNote(kWbNoFigma), isNull);
      expect(wbDesignNote('$kWbNoFigma?note='), isNull);
      expect(wbDesignNote(_figmaUrl), isNull);
      expect(wbDesignNote(null), isNull);
    });
  });

  group('wbDesignUri', () {
    test('parses a linked url', () {
      expect(wbDesignUri(' $_figmaUrl '), Uri.parse(_figmaUrl));
    });

    test('null for sentinel and unmarked', () {
      expect(wbDesignUri(kWbNoFigma), isNull);
      expect(wbDesignUri(wbNoFigma(note: 'n')), isNull);
      expect(wbDesignUri(null), isNull);
    });
  });

  group('WbDesignStatusChip', () {
    testWidgets('linked renders the tappable Figma link chip', (tester) async {
      await pumpUseCase(
        tester,
        (_) => const WbDesignStatusChip(designLink: _figmaUrl),
      );
      expect(find.text('Figma ↗'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(WbDesignStatusChip),
          matching: find.byType(IgnorePointer),
        ),
        findsNothing,
      );
      expect(find.byType(GestureDetector), findsOneWidget);
    });

    testWidgets('noFigma renders the badge and its note tooltip', (
      tester,
    ) async {
      await pumpUseCase(
        tester,
        (_) => WbDesignStatusChip(designLink: wbNoFigma(note: 'Dev only')),
      );
      expect(find.text('No Figma'), findsOneWidget);
      expect(tester.widget<Tooltip>(find.byType(Tooltip)).message, 'Dev only');
    });

    testWidgets('a note-less noFigma badge does not take pointer events', (
      tester,
    ) async {
      await pumpUseCase(
        tester,
        (_) => const WbDesignStatusChip(designLink: kWbNoFigma),
      );
      expect(find.text('No Figma'), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
      expect(
        find.descendant(
          of: find.byType(WbDesignStatusChip),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    });

    testWidgets('unmarked renders nothing', (tester) async {
      await pumpUseCase(tester, (_) => const WbDesignStatusChip());
      expect(find.byKey(const ValueKey('wb_design_status_chip')), findsNothing);
      expect(find.text('Unmarked'), findsNothing);
    });
  });

  group('WbDesignStatusOverlay', () {
    testWidgets('an unmarked use case gets no overlay at all', (tester) async {
      await pumpUseCase(
        tester,
        (_) => const WbDesignStatusOverlay(child: SizedBox.expand()),
      );
      expect(find.byType(WbDesignStatusChip), findsNothing);
    });

    testWidgets('a marked use case gets the chip over its top-right', (
      tester,
    ) async {
      await pumpUseCase(
        tester,
        (_) => const WbDesignStatusOverlay(
          designLink: _figmaUrl,
          child: SizedBox.expand(),
        ),
      );
      expect(
        find.byKey(const ValueKey('wb_design_status_chip')),
        findsOneWidget,
      );
    });
  });

  group('WbDesignStatusAddon', () {
    testWidgets('reads designLink from the selected use case', (tester) async {
      final root = WidgetbookRoot(
        children: [
          WidgetbookFolder(
            name: 'Screens',
            children: [
              WidgetbookComponent(
                name: 'Home',
                useCases: [
                  WidgetbookUseCase(
                    name: 'Linked',
                    designLink: _figmaUrl,
                    builder: (_) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

      await _pumpAddon(
        tester,
        root: root,
        path: 'screens/home/linked',
        setting: true,
      );
      expect(find.text('Figma ↗'), findsOneWidget);
    });

    testWidgets('renders nothing extra when the field is off', (tester) async {
      await _pumpAddon(
        tester,
        root: WidgetbookRoot(children: const []),
        path: null,
        setting: false,
      );
      expect(find.byKey(const ValueKey('wb_design_status_chip')), findsNothing);
    });
  });
}

Future<void> _pumpAddon(
  WidgetTester tester, {
  required WidgetbookRoot root,
  required String? path,
  required bool setting,
}) async {
  final addon = WbDesignStatusAddon();
  await pumpUseCase(
    tester,
    (context) => addon.buildUseCase(context, const SizedBox.expand(), setting),
    root: root,
    path: path,
  );
}
