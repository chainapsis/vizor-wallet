@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_screens.dart';

const _wordList = ['abandon', 'ability', 'able', 'about', 'zebra'];
const _pasteCardKey = ValueKey('mobile_import_paste_card');

Widget _app(String initialLocation) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: mobileOnboardingRoutes(),
  );
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

Widget _pasteApp({
  List<String>? mnemonicWordListOverride = _wordList,
  bool Function(String mnemonic)? validateMnemonicOverride,
}) {
  return ProviderScope(
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
      home: MobileImportScreen(
        mnemonicWordListOverride: mnemonicWordListOverride,
        validateMnemonicOverride: validateMnemonicOverride ?? (_) => false,
      ),
    ),
  );
}

void _mockClipboard(
  WidgetTester tester,
  String? text, {
  Completer<void>? gate,
}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.getData') {
        if (gate != null) await gate.future;
        return {'text': text};
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void _mockClipboardFailure(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.getData') {
        throw PlatformException(code: 'clipboard_unavailable');
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void main() {
  void setViewport(Size size) {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
  }

  setUp(() {
    setViewport(const Size(520, 1300));
  });

  test('normalises pasted mnemonic-like text', () {
    expect(parseMnemonicWords('1. Abandon, 2) ability\n3: able; 4/about'), [
      'abandon',
      'ability',
      'able',
      'about',
    ]);
  });

  testWidgets('the entry offers paste and the manual wizard link', (
    tester,
  ) async {
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    expect(find.text('Import Wallet'), findsOneWidget);
    expect(find.byType(MobileImportScreen), findsOneWidget);
    expect(find.text('Paste from clipboard'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Enter Secret Passphrase manually'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_enter_manually')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter your Secret Passphrase'), findsOneWidget);
  });

  testWidgets('keeps the Figma card height on the baseline viewport', (
    tester,
  ) async {
    await tester.pumpWidget(_pasteApp());
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(_pasteCardKey)).height, 370);
  });

  testWidgets('shrinks the paste card before the manual link leaves view', (
    tester,
  ) async {
    setViewport(const Size(520, 820));
    await tester.pumpWidget(_pasteApp());
    await tester.pumpAndSettle();

    final cardHeight = tester.getSize(find.byKey(_pasteCardKey)).height;
    final manualBottom = tester
        .getBottomLeft(
          find.byKey(const ValueKey('mobile_import_enter_manually')),
        )
        .dy;

    expect(cardHeight, lessThan(370));
    expect(cardHeight, greaterThanOrEqualTo(320));
    expect(manualBottom, lessThanOrEqualTo(820 - 80));
  });

  testWidgets('uses scrolling instead of shrinking the paste card too far', (
    tester,
  ) async {
    setViewport(const Size(520, 560));
    await tester.pumpWidget(_pasteApp());
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(_pasteCardKey)).height, 320);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('paste shows a reading state while clipboard data resolves', (
    tester,
  ) async {
    final gate = Completer<void>();
    _mockClipboard(tester, '   ', gate: gate);
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pump();

    expect(find.text('Reading...'), findsOneWidget);
    expect(find.text('Paste from clipboard'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('word-count validation shows the inline error card', (
    tester,
  ) async {
    _mockClipboard(tester, 'one two three');
    await tester.pumpWidget(_pasteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(
      find.text('Secret Passphrase must be 12, 15, 18, 21, or 24 words'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('one'), findsNothing);
  });

  testWidgets('an empty clipboard shows the inline error card', (tester) async {
    _mockClipboard(tester, '   ');
    await tester.pumpWidget(_pasteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(
      find.text("Clipboard doesn’t contain a Secret Passphrase"),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('clipboard read failures keep the clipboard error message', (
    tester,
  ) async {
    _mockClipboardFailure(tester);
    await tester.pumpWidget(_pasteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(find.text("Can’t read clipboard data"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('paste rejects words outside the mnemonic word list', (
    tester,
  ) async {
    _mockClipboard(
      tester,
      'abandon ability able about zebra abandon ability able about zebra '
      'abandon notaword',
    );
    await tester.pumpWidget(_pasteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(
      find.text("Some words aren’t in the passphrase word list"),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('paste separates invalid mnemonic checksum from read failures', (
    tester,
  ) async {
    _mockClipboard(
      tester,
      '1. abandon, 2. ability, 3. able, 4. about, 5. zebra, 6. abandon, '
      '7. ability, 8. able, 9. about, 10. zebra, 11. abandon, 12. ability',
    );
    await tester.pumpWidget(_pasteApp(validateMnemonicOverride: (_) => false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(find.text("That Secret Passphrase isn’t valid"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
