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
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_review_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';

const _validMnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';
const _invalidOrderedMnemonic =
    'ability abandon able about above absent absorb abstract absurd abuse access accident';

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

Widget _entryAppWithBirthdayProbe() {
  final router = GoRouter(
    initialLocation: '/import',
    routes: [
      GoRoute(path: '/import', builder: (_, _) => const MobileImportScreen()),
      GoRoute(
        path: '/import/review',
        builder:
            (_, state) => MobileImportReviewScreen(
              args: state.extra as ImportSecretPassphraseArgs,
            ),
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
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

Widget _stackedPasteApp() {
  final router = GoRouter(
    initialLocation: '/method',
    routes: [
      GoRoute(
        path: '/method',
        builder:
            (context, _) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const ValueKey('method_import'),
                  onPressed: () => context.push('/import'),
                  child: const Text('Method selection'),
                ),
              ),
            ),
      ),
      GoRoute(path: '/import', builder: (_, _) => const MobileImportScreen()),
      GoRoute(
        path: '/import/review',
        builder:
            (_, state) => MobileImportReviewScreen(
              args: state.extra as ImportSecretPassphraseArgs,
            ),
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

Widget _reviewApp({
  Stream<void>? screenshotStream,
  SensitivePrivacyOverlayController? privacyOverlayController,
}) {
  return MaterialApp(
    home: AppTheme(
      data: AppThemeData.light,
      child: MobileImportReviewScreen(
        args: const ImportSecretPassphraseArgs(mnemonic: _validMnemonic),
        screenshotStream: screenshotStream,
        privacyOverlayController: privacyOverlayController,
      ),
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

void _mockClipboardFailure(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.getData') {
        throw PlatformException(code: 'clipboard-unavailable');
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

  testWidgets('the entry offers manual card and the paste action', (
    tester,
  ) async {
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    expect(find.text('Import Wallet'), findsOneWidget);
    expect(find.byType(MobileImportScreen), findsOneWidget);
    expect(
      find.text('Accept 12, 15, 18, 21, or 24-word\nsecret passphrases'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile_import_manual_card')),
      findsOneWidget,
    );
    expect(find.text('Manually Enter\nSecret Passphrase'), findsOneWidget);
    expect(find.text('Word by word.'), findsOneWidget);
    expect(find.text('Or paste from clipboard'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_enter_manually')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter your Secret Passphrase'), findsOneWidget);
  });

  testWidgets('the manual card stays tappable after a rejected paste', (
    tester,
  ) async {
    _mockClipboard(tester, 'one two three');
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_enter_manually')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter your Secret Passphrase'), findsOneWidget);
  });

  testWidgets('a non-phrase paste shows a toast and keeps the entry state', (
    tester,
  ) async {
    _mockClipboard(tester, 'one two three');
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(find.text('No secret passphrase found'), findsOneWidget);
    expect(find.text('Or paste from clipboard'), findsOneWidget);
    expect(find.textContaining('found 3'), findsNothing);
    expect(find.text('Invalid Secret Passphrase'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_import_manual_card')),
      findsOneWidget,
    );
  });

  testWidgets('an invalid mnemonic candidate shows a toast', (tester) async {
    _mockClipboard(tester, _invalidOrderedMnemonic);
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(find.text('Invalid secret passphrase'), findsOneWidget);
    expect(find.text('Or paste from clipboard'), findsOneWidget);
    expect(find.text("Can't read the clipboard"), findsNothing);
  });

  testWidgets('clipboard read failure shows the Figma toast state', (
    tester,
  ) async {
    _mockClipboardFailure(tester);
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(find.text("Can't read the clipboard"), findsOneWidget);
    expect(find.text('Or paste from clipboard'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile_import_manual_card')),
      findsOneWidget,
    );
  });

  testWidgets('paste read progress only changes the bottom action', (
    tester,
  ) async {
    final pendingClipboard = Completer<Map<String, String>?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) {
        if (call.method == 'Clipboard.getData') return pendingClipboard.future;
        return Future.value(null);
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      if (!pendingClipboard.isCompleted) pendingClipboard.complete(null);
    });

    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pump();

    expect(find.text('Reading clipboard data...'), findsOneWidget);
    expect(find.text('Manually Enter\nSecret Passphrase'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_import_manual_card')),
      findsOneWidget,
    );
  });

  testWidgets('paste normalizes quoted and numbered mnemonic text', (
    tester,
  ) async {
    _mockClipboard(tester, '1. "one", 2. "two"; 3. "three"');
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(find.text('No secret passphrase found'), findsOneWidget);
    expect(find.textContaining('found 3'), findsNothing);
    expect(find.textContaining('"one"'), findsNothing);
  });

  testWidgets('a valid paste opens review before birthday', (tester) async {
    _mockClipboard(tester, _validMnemonic);
    await tester.pumpWidget(_entryAppWithBirthdayProbe());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(find.text('Review Import'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile_import_review_seed_card')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_review_continue')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Birthday: $_validMnemonic'), findsOneWidget);
  });

  testWidgets('clearing a pasted review preserves the import stack', (
    tester,
  ) async {
    _mockClipboard(tester, _validMnemonic);
    await tester.pumpWidget(_stackedPasteApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('method_import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile_import_review_clear')));
    await tester.pumpAndSettle();

    expect(find.text('Import Wallet'), findsOneWidget);
    expect(find.text('Review Import'), findsNothing);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Method selection'), findsOneWidget);
  });

  testWidgets('review phrase is covered when privacy controller is unsafe', (
    tester,
  ) async {
    final privacyController = SensitivePrivacyOverlayController(
      initiallySafe: false,
    );
    addTearDown(privacyController.dispose);

    await tester.pumpWidget(
      _reviewApp(privacyOverlayController: privacyController),
    );
    await tester.pump();

    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

    privacyController.markSafe();
    await tester.pump();

    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
  });

  testWidgets('review phrase shows screenshot warning', (tester) async {
    final screenshots = StreamController<void>();
    addTearDown(screenshots.close);
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
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

    await tester.pumpWidget(_reviewApp(screenshotStream: screenshots.stream));
    await tester.pump();

    screenshots.add(null);
    await tester.pumpAndSettle();

    expect(find.byType(MobileSeedScreenshotWarningSheet), findsOneWidget);
    expect(find.textContaining('Don’t take screenshots'), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
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
}

class _RustApiFake implements RustLibApi {
  @override
  List<String> crateApiWalletMnemonicWordList() => _validMnemonic.split(' ');

  @override
  bool crateApiWalletValidateMnemonic({required String mnemonic}) =>
      mnemonic == _validMnemonic;

  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}
