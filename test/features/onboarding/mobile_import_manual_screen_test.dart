@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_manual_screen.dart';

const _wordList = ['abandon', 'ability', 'able', 'about', 'zebra'];

Widget _app() {
  return ProviderScope(
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: const MobileImportManualScreen(wordListOverride: _wordList),
    ),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('typing a prefix offers suggestions and accepts a word', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Word 1/24'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('mobile_import_manual_field')),
      'ab',
    );
    await tester.pump();

    // Suggestions for the prefix appear above the keyboard area.
    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('ability'), findsOneWidget);
    expect(find.text('zebra'), findsNothing);

    await tester.tap(find.text('abandon'));
    await tester.pump();

    expect(find.text('Word 2/24'), findsOneWidget);
    expect(find.textContaining('abandon'), findsOneWidget);
  });

  testWidgets('an unknown word is rejected with an error', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('mobile_import_manual_field')),
      'notaword ',
    );
    await tester.pump();

    expect(
      find.text("'notaword' isn't in the passphrase word list."),
      findsOneWidget,
    );
    expect(find.text('Word 1/24'), findsOneWidget);
  });

  testWidgets('undo steps back to re-edit the previous word', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('mobile_import_manual_field')),
      'zebra ',
    );
    await tester.pump();
    expect(find.text('Word 2/24'), findsOneWidget);

    await tester.tap(find.text('Undo last word'));
    await tester.pump();

    expect(find.text('Word 1/24'), findsOneWidget);
  });

  Future<void> paste(WidgetTester tester, String text) async {
    await tester.enterText(
      find.byKey(const ValueKey('mobile_import_manual_field')),
      text,
    );
    await tester.pump();
  }

  testWidgets('pasting multiple valid words fills consecutive slots', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await paste(tester, 'abandon ability able');

    expect(find.text('Word 4/24'), findsOneWidget);
    expect(find.text('abandon · ability · able'), findsOneWidget);
  });

  testWidgets('pasting stops at the first non-word and ignores the rest', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await paste(tester, 'abandon ability notaword able');

    expect(find.text('Word 3/24'), findsOneWidget);
    expect(find.text('abandon · ability'), findsOneWidget);
    expect(find.textContaining("Stopped at 'notaword'"), findsOneWidget);
  });

  testWidgets('pasting cleans separators like commas and numbering', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await paste(tester, '1. abandon, 2. ability; 3. able');

    expect(find.text('Word 4/24'), findsOneWidget);
    expect(find.text('abandon · ability · able'), findsOneWidget);
  });

  testWidgets('pasting appends from the current position', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await paste(tester, 'zebra ');
    expect(find.text('Word 2/24'), findsOneWidget);

    await paste(tester, 'abandon ability');

    expect(find.text('Word 4/24'), findsOneWidget);
    expect(find.text('zebra · abandon · ability'), findsOneWidget);
  });

  testWidgets('pasting a leading non-word fills nothing', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await paste(tester, 'notaword abandon');

    expect(find.text('Word 1/24'), findsOneWidget);
    expect(find.textContaining("Stopped at 'notaword'"), findsOneWidget);
    expect(find.text('Undo last word'), findsNothing);
  });
}
