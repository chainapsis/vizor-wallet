@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _validMnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

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

Widget _entryAppWithBirthdayProbe({
  SensitivePrivacyOverlayController? privacyOverlayController,
  Stream<void>? screenshotStream,
}) {
  final router = GoRouter(
    initialLocation: '/import',
    routes: [
      GoRoute(
        path: '/import',
        builder: (_, _) => MobileImportScreen(
          privacyOverlayController: privacyOverlayController,
          screenshotStream: screenshotStream,
        ),
      ),
      GoRoute(
        path: '/import/birthday',
        builder: (context, state) {
          final args = state.extra as ImportBirthdayArgs;
          return Scaffold(
            body: Column(
              children: [
                Text('Birthday: ${args.mnemonic}'),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('back-probe'),
                ),
              ],
            ),
          );
        },
      ),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

void _mockClipboard(WidgetTester tester, String? text) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.getData') return {'text': text};
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

Widget _screenshotApp({
  Stream<void>? screenshotStream,
  SensitivePrivacyOverlayController? privacyOverlayController,
}) {
  return ProviderScope(
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
      home: MobileImportScreen(
        screenshotStream: screenshotStream,
        privacyOverlayController: privacyOverlayController,
      ),
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
      ..physicalSize = const Size(520, 1300)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('the entry offers paste and the manual wizard link', (
    tester,
  ) async {
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    expect(find.text('Import Wallet'), findsOneWidget);
    expect(find.byType(MobileImportScreen), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_enter_manually')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter your Secret Passphrase'), findsOneWidget);
  });

  testWidgets('tapping the slot grid opens the manual wizard', (tester) async {
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_slots')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your Secret Passphrase'), findsOneWidget);
  });

  testWidgets('the slot grid stays tappable after a rejected paste', (
    tester,
  ) async {
    _mockClipboard(tester, 'one two three');
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_slots')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your Secret Passphrase'), findsOneWidget);
  });

  testWidgets('word-count validation rejects a short paste', (tester) async {
    _mockClipboard(tester, 'one two three');
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(find.textContaining('found 3'), findsOneWidget);
    // The pasted words still render into the slot card for inspection.
    expect(find.text('one'), findsOneWidget);
  });

  testWidgets('paste normalizes quoted and numbered mnemonic text', (
    tester,
  ) async {
    _mockClipboard(tester, '1. "one", 2. "two"; 3. "three"');
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(find.textContaining('found 3'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.text('three'), findsOneWidget);
    expect(find.textContaining('"one"'), findsNothing);
  });

  testWidgets('confirming a valid paste opens birthday directly', (
    tester,
  ) async {
    _mockClipboard(tester, _validMnemonic);
    await tester.pumpWidget(_entryAppWithBirthdayProbe());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile_import_confirm')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mobile_import_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Review Import'), findsNothing);
    expect(find.text('Birthday: $_validMnemonic'), findsOneWidget);
  });

  testWidgets('an empty clipboard surfaces a toast', (tester) async {
    _mockClipboard(tester, '   ');
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pump();

    expect(find.text('Clipboard is empty'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Clipboard is empty'), findsNothing);
  });

  testWidgets('warns on a screenshot once pasted words are on screen', (
    tester,
  ) async {
    final screenshots = StreamController<void>();
    addTearDown(screenshots.close);
    // A short paste is invalid but still renders the words into the slot card.
    _mockClipboard(tester, 'one two three');

    await tester.pumpWidget(
      _screenshotApp(screenshotStream: screenshots.stream),
    );
    await tester.pumpAndSettle();

    // Nothing to protect before a paste — no warning.
    screenshots.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSeedScreenshotWarningSheet), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();
    expect(find.text('one'), findsOneWidget);

    screenshots.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(MobileSeedScreenshotWarningSheet), findsOneWidget);
    expect(find.textContaining('Don’t take screenshots'), findsOneWidget);
  });

  testWidgets(
    'covers the entry once words are pasted when the controller is unsafe',
    (tester) async {
      final privacyController = SensitivePrivacyOverlayController(
        initiallySafe: false,
      );
      addTearDown(privacyController.dispose);
      _mockClipboard(tester, 'one two three');

      await tester.pumpWidget(
        _screenshotApp(privacyOverlayController: privacyController),
      );
      await tester.pumpAndSettle();

      // Nothing on screen to blank before a paste, even when unsafe.
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);

      await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
      await tester.pumpAndSettle();
      expect(find.text('one'), findsOneWidget);
      // Pasted words turn on protection; the shield covers the filled card.
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

      privacyController.markSafe();
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
    },
  );

  testWidgets(
    'keeps the shield through the push slide, drops it once covered, and '
    'restores it on back',
    (tester) async {
      final privacyController = SensitivePrivacyOverlayController(
        initiallySafe: false,
      );
      addTearDown(privacyController.dispose);
      _mockClipboard(tester, _validMnemonic);

      await tester.pumpWidget(
        _entryAppWithBirthdayProbe(privacyOverlayController: privacyController),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
      await tester.pumpAndSettle();
      // Pasted words + unsafe controller: the shield covers the import entry.
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

      // Start the push: the seed screen is still sliding out — the shield must
      // stay up so a screenshot mid-transition does not capture the mnemonic.
      await tester.tap(find.byKey(const ValueKey('mobile_import_confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

      // Transition finished: the import screen is fully covered, so the shield
      // drops and the global native token no longer blanks the birthday screen.
      await tester.pumpAndSettle();
      expect(find.text('Birthday: $_validMnemonic'), findsOneWidget);
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);

      // Back: the secret screen slides in and is protected again.
      await tester.tap(find.text('back-probe'));
      await tester.pumpAndSettle();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);
    },
  );

  testWidgets(
    'keeps the shield up while the screenshot warning sheet is open over the '
    'seed (real go_router routing)',
    (tester) async {
      final screenshots = StreamController<void>();
      addTearDown(screenshots.close);
      final privacyController = SensitivePrivacyOverlayController(
        initiallySafe: false,
      );
      addTearDown(privacyController.dispose);
      _mockClipboard(tester, 'one two three');

      await tester.pumpWidget(
        _entryAppWithBirthdayProbe(
          privacyOverlayController: privacyController,
          screenshotStream: screenshots.stream,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
      await tester.pumpAndSettle();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

      // A screenshot opens the warning bottom sheet — a non-opaque popup route
      // (showModalBottomSheet). A page route does not drive its
      // secondaryAnimation for a popup pushed above it, so RouteCoverageAware
      // must NOT treat the screen as covered: the mnemonic is still behind the
      // sheet, and the shield must stay up so a second screenshot or an
      // app-switcher snapshot is still blanked.
      screenshots.add(null);
      await tester.pumpAndSettle();
      expect(find.byType(MobileSeedScreenshotWarningSheet), findsOneWidget);
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

      // The route's secondaryAnimation must have stayed dismissed (the popup
      // never counted as coverage).
      final route = ModalRoute.of(
        tester.element(find.byType(MobileImportScreen)),
      );
      expect(route?.secondaryAnimation?.status, AnimationStatus.dismissed);
    },
  );
}

class _RustApiFake implements RustLibApi {
  @override
  List<String> crateApiWalletMnemonicWordList() => _validMnemonic.split(' ');

  @override
  bool crateApiWalletValidateMnemonic({required String mnemonic}) {
    final count = mnemonic.trim().split(RegExp(r'\s+')).length;
    return kMnemonicWordCounts.contains(count);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
