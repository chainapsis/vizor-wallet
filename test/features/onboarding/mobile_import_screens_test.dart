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

void main() {
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
    expect(find.text('Paste from clipboard'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Enter Secret Passphrase manually'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_import_enter_manually')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enter your Secret Passphrase'), findsOneWidget);
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
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(find.text("Can’t read clipboard data"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('one'), findsNothing);
  });

  testWidgets('an empty clipboard shows the inline error card', (tester) async {
    _mockClipboard(tester, '   ');
    await tester.pumpWidget(_app('/import'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mobile_import_paste')));
    await tester.pumpAndSettle();

    expect(find.text("Can’t read clipboard data"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
