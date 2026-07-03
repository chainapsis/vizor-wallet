@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_import_screens.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

const _validMnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';

Widget _app(String initialLocation) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: mobileOnboardingRoutes(),
  );
  return ProviderScope(
    child: MaterialApp.router(
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
      localizationsDelegates:
          AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
