import 'package:flutter/material.dart' show MaterialApp, Scaffold, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_secret_passphrase_screen.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });

  tearDownAll(RustLib.dispose);

  testWidgets('shows BIP39 prefix suggestions for the focused word', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen());
    await tester.enterText(_wordField(0), 'ca');
    await tester.pump();

    expect(find.text('cabbage'), findsOneWidget);
    expect(find.text('cabin'), findsOneWidget);
    expect(find.text('cable'), findsOneWidget);
    expect(find.text('cactus'), findsOneWidget);
  });

  testWidgets(
    'tapping a suggestion fills the word and focuses the next field',
    (tester) async {
      await _setDesktopViewport(tester);
      await tester.pumpWidget(_importPassphraseScreen());
      await tester.enterText(_wordField(0), 'cab');
      await tester.pump();

      await tester.tap(find.text('cabbage'));
      await tester.pump();

      expect(_textField(tester, 0).controller!.text, 'cabbage');
      expect(_textField(tester, 1).focusNode!.hasFocus, isTrue);
    },
  );

  testWidgets('Enter accepts the highlighted suggestion and moves next', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen());
    await tester.enterText(_wordField(0), 'cab');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(_textField(tester, 0).controller!.text, 'cabbage');
    expect(_textField(tester, 1).focusNode!.hasFocus, isTrue);
  });

  testWidgets('Tab keeps the typed text and moves focus to the next field', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen());
    await tester.enterText(_wordField(0), 'cab');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(_textField(tester, 0).controller!.text, 'cab');
    expect(_textField(tester, 1).focusNode!.hasFocus, isTrue);
  });

  testWidgets('keeps existing paste-to-fill behavior', (tester) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(_importPassphraseScreen());
    await tester.enterText(_wordField(0), 'abandon ability able');
    await tester.pump();

    expect(_textField(tester, 0).controller!.text, 'abandon');
    expect(_textField(tester, 1).controller!.text, 'ability');
    expect(_textField(tester, 2).controller!.text, 'able');
    expect(_textField(tester, 3).focusNode!.hasFocus, isTrue);
  });
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Widget _importPassphraseScreen() {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    ],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.light,
        child: const Scaffold(body: ImportSecretPassphraseScreen()),
      ),
    ),
  );
}

Finder _wordField(int index) => find.byType(TextField).at(index);

TextField _textField(WidgetTester tester, int index) {
  return tester.widget<TextField>(_wordField(index));
}

class _RustApiFake implements RustLibApi {
  @override
  List<String> crateApiWalletMnemonicWordList() => _wordList;

  @override
  bool crateApiWalletValidateMnemonic({required String mnemonic}) {
    return mnemonic.trim().split(RegExp(r'\s+')).length == 24;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

const _wordList = <String>[
  'abandon',
  'ability',
  'able',
  'about',
  'above',
  'cabbage',
  'cabin',
  'cable',
  'cactus',
  'cage',
  'cake',
  'call',
  'calm',
  'camera',
  'camp',
];
