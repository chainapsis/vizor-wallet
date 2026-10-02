import 'dart:ui' show SemanticsAction, Size;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart' show Text, ValueKey, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/onboarding/import/desktop_hardware_selection_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/import/desktop_import_method_selection_screen.dart';

void main() {
  for (final screen in [
    (
      location: '/import/method',
      labels: {
        'desktop_import_secret_passphrase_card':
            'Import secret passphrase\nVizor or any other Zcash wallet',
        'desktop_import_hardware_card':
            'Connect hardware wallet\nLedger or Keystone wallet',
      },
    ),
    (
      location: '/import/hardware',
      labels: {
        'desktop_hardware_keystone_card':
            'Connect Keystone\nImport from Keystone wallet',
        'desktop_hardware_ledger_card':
            'Connect Ledger\nImport from Ledger wallet',
      },
    ),
  ]) {
    testWidgets('${screen.location} announces each card label once', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        await _setDesktopViewport(tester);
        await tester.pumpWidget(
          _harness(
            initialLocation: screen.location,
            capability: const LedgerCapability.supported(),
          ),
        );
        for (final card in screen.labels.entries) {
          final node = tester.getSemantics(find.byKey(ValueKey(card.key)));
          final data = node.getSemanticsData();
          expect(data.label, card.value);
          expect(node.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
        }
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('desktop import picker renders the two supported methods', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        initialLocation: '/import/method',
        capability: const LedgerCapability.supported(),
      ),
    );
    await tester.pump();

    expect(find.text('Import Account\nto Vizor'), findsOneWidget);
    expect(find.text('Select the method you want.'), findsOneWidget);
    expect(find.text('Import secret passphrase'), findsOneWidget);
    expect(find.text('Vizor or any other Zcash wallet'), findsOneWidget);
    expect(find.text('Connect hardware wallet'), findsOneWidget);
    expect(find.text('Ledger or Keystone wallet'), findsOneWidget);
    expect(find.text('Link Vizor Desktop'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);

    final background = find.byKey(
      const ValueKey('desktop_method_selection_background'),
    );
    expect(tester.getTopLeft(background), const Offset(-264, 0));
    expect(tester.getSize(background), const Size(1344, 520));

    expect(
      tester.getSize(
        find.byKey(const ValueKey('desktop_import_secret_passphrase_card')),
      ),
      const Size(396, 80),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('desktop_import_hardware_card')),
      ),
      const Size(396, 80),
    );
  });

  testWidgets('desktop import picker routes each supported action', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        initialLocation: '/import/method',
        capability: const LedgerCapability.supported(),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('desktop_import_secret_passphrase_card')),
    );
    await tester.pumpAndSettle();
    expect(find.text('secret phrase destination'), findsOneWidget);

    final router = GoRouter.of(
      tester.element(find.text('secret phrase destination')),
    );
    router.go('/import/method');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('desktop_import_hardware_card')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connect\nHardware Wallet'), findsOneWidget);
  });

  testWidgets('desktop import picker honors its cancel destination', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        initialLocation: '/import/method?from=add-account',
        capability: const LedgerCapability.supported(),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('desktop_import_hardware_card')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Connect\nHardware Wallet'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Import Account\nto Vizor'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('add account destination'), findsOneWidget);
  });

  testWidgets('desktop hardware picker routes supported devices', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        initialLocation: '/import/hardware',
        capability: const LedgerCapability.supported(),
      ),
    );

    expect(find.text('Connect\nHardware Wallet'), findsOneWidget);
    expect(find.text('Select your hardware wallet.'), findsOneWidget);
    expect(find.text('Connect Keystone'), findsOneWidget);
    expect(find.text('Import from Keystone wallet'), findsOneWidget);
    expect(find.text('Connect Ledger'), findsOneWidget);
    expect(find.text('Import from Ledger wallet'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('desktop_hardware_keystone_card')),
    );
    await tester.pumpAndSettle();
    expect(find.text('keystone destination'), findsOneWidget);

    final router = GoRouter.of(
      tester.element(find.text('keystone destination')),
    );
    router.go('/import/hardware');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('desktop_hardware_ledger_card')),
    );
    await tester.pumpAndSettle();
    expect(find.text('ledger destination'), findsOneWidget);
  });

  testWidgets('desktop hardware picker hides unsupported Ledger', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    await tester.pumpWidget(
      _harness(
        initialLocation: '/import/hardware',
        capability: const LedgerCapability.unsupported('test'),
      ),
    );

    expect(find.text('Connect Keystone'), findsOneWidget);
    expect(find.text('Connect Ledger'), findsNothing);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Import Account\nto Vizor'), findsOneWidget);
  });
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1080, 720));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _harness({
  required String initialLocation,
  required LedgerCapability capability,
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const Text('welcome')),
      GoRoute(
        path: '/add-account',
        builder: (_, _) => const Text('add account destination'),
      ),
      GoRoute(
        path: '/import/method',
        builder: (_, state) {
          final fromAddAccount =
              state.uri.queryParameters['from'] == 'add-account';
          return DesktopImportMethodSelectionScreen(
            cancelRoute: fromAddAccount ? '/add-account' : '/welcome',
            hardwareRoute: fromAddAccount
                ? '/import/hardware?from=add-account'
                : '/import/hardware',
          );
        },
      ),
      GoRoute(
        path: '/import',
        builder: (_, _) => const Text('secret phrase destination'),
      ),
      GoRoute(
        path: '/import/hardware',
        builder: (_, state) => DesktopHardwareSelectionScreen(
          backRoute: state.uri.queryParameters['from'] == 'add-account'
              ? '/import/method?from=add-account'
              : '/import/method',
        ),
      ),
      GoRoute(
        path: '/onboarding/keystone',
        builder: (_, _) => const Text('keystone destination'),
      ),
      GoRoute(
        path: '/onboarding/ledger',
        builder: (_, _) => const Text('ledger destination'),
      ),
    ],
  );
  addTearDown(router.dispose);

  return ProviderScope(
    overrides: [ledgerStaticCapabilityProvider.overrideWithValue(capability)],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}
