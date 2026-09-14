import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/storage/wallet_recovery.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/wallet_recovery_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/welcome.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';

final _routerProvider = Provider.autoDispose.family<GoRouter, String>((
  ref,
  location,
) {
  final bootstrap = ref.watch(appBootstrapProvider);
  final router = GoRouter(
    initialLocation: location,
    redirect: (_, state) =>
        appRedirect(ref: ref, bootstrap: bootstrap, state: state),
    routes: [
      ...appAuthRoutes(
        ref,
        bootstrap,
        unlockScreen: const Text('Ordinary unlock'),
      ),
      ...appDesktopOnboardingRoutes(ref),
      GoRoute(path: '/home', builder: (_, _) => const Text('Wallet home')),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final location in [
    '/',
    '/welcome',
    '/home',
    '/unlock',
    '/wallet-recovery',
  ]) {
    testWidgets('recovery blocks ordinary wallet routes from $location', (
      tester,
    ) async {
      final bootstrap = AppBootstrapState.recovery(
        const WalletRecoveryState(
          candidates: [],
          network: 'main',
          isPasswordConfigured: true,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
          child: Consumer(
            builder: (context, ref, _) => MaterialApp.router(
              routerConfig: ref.watch(_routerProvider(location)),
              builder: (_, child) =>
                  AppTheme(data: AppThemeData.dark, child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WalletRecoveryScreen), findsOneWidget);
      expect(find.text('Create wallet'), findsNothing);
      expect(find.text('Wallet home'), findsNothing);
      expect(find.text('Ordinary unlock'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WalletRecoveryScreen)),
      );
      expect(container.exists(walletProvider), isFalse);
      expect(container.exists(appSecurityProvider), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  group('interrupted setup startup boundary', () {
    late Directory support;
    const dbName = 'zcash_wallet_interrupted.db';
    final store = AppSecureStore.instance;
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final prepared = <String, String>{
      kWalletRecoveryPendingKey: kWalletSetupPendingValue,
      kWalletDbNameKey: dbName,
      'zcash_password_verifier': 'persisted-verifier',
      'zcash_password_verifier_salt': 'persisted-salt',
    };

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      support = await Directory.systemTemp.createTemp('vizor-empty-setup-');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (call) async => support.path);
      SharedPreferences.setMockInitialValues({});
      store.clearSessionPassword();
    });
    tearDown(() async {
      store.clearSessionPassword();
      FlutterSecureStorage.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
      debugDefaultTargetPlatformOverride = null;
      await support.delete(recursive: true);
    });

    for (final scenario
        in <({String name, Map<String, String> values, bool resume})>[
          (
            name: 'allocated locator before DB creation',
            values: prepared,
            resume: true,
          ),
          (
            name: 'marker before credential writes',
            values: {kWalletRecoveryPendingKey: kWalletSetupPendingValue},
            resume: true,
          ),
          (
            name: 'partial credential write',
            values: {...prepared}..remove('zcash_password_verifier'),
            resume: true,
          ),
          (
            name: 'unmarked missing DB',
            values: {...prepared}..remove(kWalletRecoveryPendingKey),
            resume: false,
          ),
          (
            name: 'reconnection marker',
            values: {...prepared, kWalletRecoveryPendingKey: dbName},
            resume: false,
          ),
          (
            name: 'invalid DB locator',
            values: {...prepared, kWalletDbNameKey: '../wallet.db'},
            resume: false,
          ),
          (
            name: 'persisted active account',
            values: {...prepared, 'zcash_active_account': 'existing-account'},
            resume: false,
          ),
          (
            name: 'persisted account list',
            values: {
              ...prepared,
              'zcash_accounts': jsonEncode([
                {'uuid': 'existing-account', 'name': 'Existing', 'order': 0},
              ]),
            },
            resume: false,
          ),
          (
            name: 'damaged account metadata',
            values: {...prepared, 'zcash_accounts': '{damaged'},
            resume: false,
          ),
        ]) {
      test(scenario.name, () async {
        final values = Map<String, String>.of(scenario.values);
        FlutterSecureStorage.setMockInitialValues(values);
        final bootstrap = await loadAppBootstrap();
        expect(
          bootstrap.initialLocation,
          scenario.resume ? '/welcome' : '/wallet-recovery',
        );
        expect(bootstrap.isUnlocked, isFalse);
        if (scenario.resume) expect(bootstrap.isPasswordConfigured, isFalse);
        expect(values, scenario.values);
        expect(await support.list().toList(), isEmpty);
      });
    }

    for (final remnant in ['wal', 'symlink']) {
      test('$remnant evidence prevents empty setup resumption', () async {
        FlutterSecureStorage.setMockInitialValues(Map.of(prepared));
        if (remnant == 'wal') {
          await File(
            '${support.path}/$dbName-wal',
          ).writeAsString('preserved WAL');
        } else {
          await Link(
            '${support.path}/$dbName',
          ).create('${support.path}/missing.db');
        }
        final bootstrap = await loadAppBootstrap();
        expect(bootstrap.initialLocation, '/wallet-recovery');
        expect(bootstrap.walletRecovery!.candidates.single.canInspect, isFalse);
        expect(await support.list(followLinks: false).toList(), hasLength(1));
      });
    }

    testWidgets('an unused locator returns to the actual welcome screen', (
      tester,
    ) async {
      try {
        FlutterSecureStorage.setMockInitialValues(Map.of(prepared));
        final bootstrap = (await tester.runAsync(loadAppBootstrap))!;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appBootstrapProvider.overrideWithValue(bootstrap)],
            child: Consumer(
              builder: (context, ref, _) => MaterialApp.router(
                routerConfig: ref.watch(_routerProvider('/')),
                builder: (_, child) =>
                    AppTheme(data: AppThemeData.dark, child: child!),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(WelcomeScreen), findsOneWidget);
        expect(find.byType(WalletRecoveryScreen), findsNothing);
        expect(find.text('Create a wallet'), findsOneWidget);
        expect(find.text('Import a wallet'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
