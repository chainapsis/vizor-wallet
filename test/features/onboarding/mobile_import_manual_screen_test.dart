@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_manual_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _wordList = ['abandon', 'ability', 'able', 'about', 'zebra'];
const _wordCountSubtitle = 'Accept 12, 15, 18, 21 or 24 words';

Widget _app() {
  return ProviderScope(
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: const MobileImportManualScreen(wordListOverride: _wordList),
    ),
  );
}

Widget _routedApp() {
  final router = GoRouter(
    initialLocation: '/import/manual',
    routes: [
      GoRoute(
        path: '/import/manual',
        builder: (_, _) =>
            const MobileImportManualScreen(wordListOverride: _wordList),
      ),
      GoRoute(
        path: '/import/birthday',
        builder: (_, state) {
          final args = state.extra as ImportBirthdayArgs;
          return Scaffold(body: Text('Birthday: ${args.mnemonic}'));
        },
      ),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
    ),
  );
}

Widget _screenshotApp({
  Stream<void>? screenshotStream,
  SensitivePrivacyOverlayController? privacyOverlayController,
}) {
  return ProviderScope(
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: MobileImportManualScreen(
        wordListOverride: _wordList,
        screenshotStream: screenshotStream,
        privacyOverlayController: privacyOverlayController,
      ),
    ),
  );
}

void _muteSystemChannel(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustApiFake());
  });

  tearDownAll(RustLib.dispose);

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

    expect(find.text(_wordCountSubtitle), findsOneWidget);
    expect(find.text('01'), findsOneWidget);

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

    expect(find.text('02'), findsOneWidget);
    expect(find.textContaining('abandon'), findsOneWidget);
  });

  testWidgets(
    'back from birthday edits the last word instead of adding a 25th',
    (tester) async {
      await tester.pumpWidget(_routedApp());
      await tester.pumpAndSettle();

      final field = find.byKey(const ValueKey('mobile_import_manual_field'));
      await tester.enterText(
        field,
        List.filled(kMnemonicMaxWords, 'abandon').join(' '),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Birthday:'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Enter your Secret Passphrase'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, 'abandon');
      expect(find.text('24'), findsOneWidget);

      await tester.enterText(field, 'zebra');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.textContaining('Birthday:'), findsOneWidget);
      expect(find.textContaining('zebra'), findsOneWidget);
      expect(find.textContaining('found 25'), findsNothing);
    },
  );

  testWidgets('keyboard action advances without dropping focus', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    final field = find.byKey(const ValueKey('mobile_import_manual_field'));
    await tester.showKeyboard(field);
    await tester.enterText(field, 'abandon');
    await tester.pump();

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('02'), findsOneWidget);
    expect(find.textContaining('abandon'), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
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
    expect(find.text('01'), findsOneWidget);
  });

  testWidgets('undo steps back to re-edit the previous word', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('mobile_import_manual_field')),
      'zebra ',
    );
    await tester.pump();
    expect(find.text('02'), findsOneWidget);

    await tester.tap(find.text('Undo last word'));
    await tester.pump();

    expect(find.text('01'), findsOneWidget);
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

    expect(find.text('04'), findsOneWidget);
    expect(find.text('abandon · ability · able'), findsOneWidget);
  });

  testWidgets('pasting stops at the first non-word and ignores the rest', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await paste(tester, 'abandon ability notaword able');

    expect(find.text('03'), findsOneWidget);
    expect(find.text('abandon · ability'), findsOneWidget);
    expect(find.textContaining("Stopped at 'notaword'"), findsOneWidget);
  });

  testWidgets('pasting cleans separators like commas and numbering', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await paste(tester, '1. "abandon", 2. "ability"; 3. "able"');

    expect(find.text('04'), findsOneWidget);
    expect(find.text('abandon · ability · able'), findsOneWidget);
  });

  testWidgets('pasting appends from the current position', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await paste(tester, 'zebra ');
    expect(find.text('02'), findsOneWidget);

    await paste(tester, 'abandon ability');

    expect(find.text('04'), findsOneWidget);
    expect(find.text('zebra · abandon · ability'), findsOneWidget);
  });

  testWidgets('pasting a leading non-word fills nothing', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await paste(tester, 'notaword abandon');

    expect(find.text('01'), findsOneWidget);
    expect(find.textContaining("Stopped at 'notaword'"), findsOneWidget);
    expect(find.text('Undo last word'), findsNothing);
  });

  testWidgets('warns on a screenshot once a word is on screen', (tester) async {
    final screenshots = StreamController<void>();
    addTearDown(screenshots.close);
    _muteSystemChannel(tester);

    await tester.pumpWidget(
      _screenshotApp(screenshotStream: screenshots.stream),
    );
    await tester.pump();

    // Empty field — nothing to protect yet.
    screenshots.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSeedScreenshotWarningSheet), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('mobile_import_manual_field')),
      'abandon',
    );
    await tester.pump();

    screenshots.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSeedScreenshotWarningSheet), findsOneWidget);
    expect(find.textContaining('Don’t take screenshots'), findsOneWidget);
  });

  testWidgets(
    'covers the field once a word is on screen when the controller is unsafe',
    (tester) async {
      final privacyController = SensitivePrivacyOverlayController(
        initiallySafe: false,
      );
      addTearDown(privacyController.dispose);

      await tester.pumpWidget(
        _screenshotApp(privacyOverlayController: privacyController),
      );
      await tester.pump();

      // An empty field has nothing to blank, even when unsafe.
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('mobile_import_manual_field')),
        'ab',
      );
      await tester.pump();
      // A typed word turns on protection; the shield covers the field.
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

      privacyController.markSafe();
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
    },
  );
}

class _RustApiFake implements RustLibApi {
  @override
  bool crateApiWalletValidateMnemonic({required String mnemonic}) {
    final count = mnemonic.trim().split(RegExp(r'\s+')).length;
    return count >= 12 && count <= 24 && count % 3 == 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
