@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_mobile_ble_service.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_setup_args.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_ledger_birthday_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

const _account = LedgerDeviceAccount(
  ufvk: 'ledger-ufvk',
  seedFingerprint: [1, 2, 3],
  accountIndex: 7,
  appVersion: '3.9.2',
  transport: LedgerConnectionTransport.bluetooth,
  device: LedgerBleDevice(id: 'ledger-id', name: 'My Ledger', model: 'Nano X'),
);

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .first;
    view.physicalSize = const Size(520, 1100);
    view.devicePixelRatio = 1;
  });

  for (final existing in [false, true]) {
    for (final failFirst in [false, true]) {
      testWidgets('Ledger setup existing=$existing failure=$failFirst', (
        tester,
      ) async {
        final events = <String>[];
        final security = _Security(existing, events);
        var imports = 0;
        final router = _router();
        addTearDown(router.dispose);
        await tester.pumpWidget(
          _harness(router, security, ({
            required name,
            required account,
            required birthdayHeight,
            required profilePictureId,
          }) async {
            events.add('import');
            imports++;
            expect(account, same(_account));
            expect(account.device!.id, 'ledger-id');
            expect(account.device!.name, 'My Ledger');
            expect(account.device!.model, 'Nano X');
            expect(account.transport, LedgerConnectionTransport.bluetooth);
            expect(birthdayHeight, 2500000);
            expect(name, isNotEmpty);
            expect(profilePictureId, startsWith('pfp-'));
            expect(security.prepared || existing, isTrue);
            if (failFirst && imports == 1) {
              throw Exception('Ledger import failed. Try again.');
            }
          }),
        );
        await tester.pumpAndSettle();
        await _birthday(tester);
        if (!existing) {
          expect(find.text('Create Passcode'), findsOneWidget);
          await _digits(tester, '123456');
          expect(find.text('Confirm Passcode'), findsOneWidget);
          await _digits(tester, '123456');
        }
        expect(find.text('Customise Account'), findsOneWidget);
        expect(events, isEmpty); // Passcode remains an in-memory draft.
        expect(find.textContaining('Keystone'), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('mobile_customise_account_continue')),
        );
        await tester.pumpAndSettle();
        if (failFirst) {
          expect(find.text('Ledger import failed. Try again.'), findsOneWidget);
          expect(find.textContaining('Keystone'), findsNothing);
          expect(
            events,
            existing ? ['import'] : ['prepare', 'import', 'rollback'],
          );
          expect(security.prepared, isFalse);
          await tester.tap(
            find.byKey(const ValueKey('mobile_customise_account_continue')),
          );
          await tester.pumpAndSettle();
        }
        expect(
          find.text(existing ? 'home route' : 'biometrics route'),
          findsOneWidget,
        );
        expect(events, [
          if (failFirst) ...[
            if (!existing) 'prepare',
            'import',
            if (!existing) 'rollback',
          ],
          if (!existing) 'prepare',
          'import',
          if (!existing) 'commit',
        ]);
      });
    }
  }

  testWidgets('back from passcode does not persist a credential or import', (
    tester,
  ) async {
    final events = <String>[];
    final router = _router();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      _harness(
        router,
        _Security(false, events),
        ({
          required name,
          required account,
          required birthdayHeight,
          required profilePictureId,
        }) async => fail('must not import before confirmation'),
      ),
    );
    await tester.pumpAndSettle();
    await _birthday(tester);
    await _digits(tester, '123456');
    expect(find.text('Confirm Passcode'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(
      find.text('Around when did you create your wallet?'),
      findsOneWidget,
    );
    expect(events, isEmpty);
  });

  testWidgets(
    'valid direct customise extra cannot import without passcode preparation',
    (tester) async {
      final security = _Security(false, []);
      final router = _router();
      addTearDown(router.dispose);
      // Use the real importer and AccountNotifier: this must fail before Rust/storage.
      await tester.pumpWidget(_harness(router, security, null));
      await tester.pumpAndSettle();
      router.go(
        '/onboarding/customise-account',
        extra: const CustomiseAccountArgs(
          setupArgs: SetPasswordScreenArgs.importLedger(
            account: _account,
            birthdayHeight: 2500000,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('mobile_customise_account_continue')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Set up and unlock your wallet'),
        findsOneWidget,
      );
      expect(find.text('home route'), findsNothing);
      expect(find.text('biometrics route'), findsNothing);
    },
  );
}

GoRouter _router() => GoRouter(
  initialLocation: '/onboarding/ledger/birthday',
  routes: [
    GoRoute(
      path: '/onboarding/ledger/birthday',
      builder: (_, _) => const MobileLedgerBirthdayScreen(
        args: LedgerBirthdayArgs(account: _account),
        loadChainMetadata: false,
      ),
    ),
    ...mobileOnboardingRoutes().whereType<GoRoute>().where(
      (route) => [
        '/onboarding/set-passcode',
        '/onboarding/customise-account',
      ].contains(route.path),
    ),
    GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
    GoRoute(
      path: '/onboarding/biometrics',
      builder: (_, _) => const Text('biometrics route'),
    ),
  ],
);

Widget _harness(
  GoRouter router,
  _Security security,
  LedgerAccountImporter? importer,
) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    appSecurityProvider.overrideWith(() => security),
    syncProvider.overrideWith(_Sync.new),
    if (importer != null)
      ledgerAccountImporterProvider.overrideWithValue(importer),
  ],
  child: MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
  ),
);

Future<void> _birthday(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey('mobile_import_birthday_mode_height')),
  );
  await tester.pump();
  await tester.enterText(
    find.byKey(const ValueKey('mobile_import_birthday_height')),
    '2500000',
  );
  await tester.pump();
  await tester.tap(
    find.byKey(const ValueKey('mobile_import_birthday_continue')),
  );
  await tester.pumpAndSettle();
}

Future<void> _digits(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $digit'));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class _Security extends AppSecurityNotifier {
  _Security(this.existing, this.events);
  final bool existing;
  final List<String> events;
  bool prepared = false;
  @override
  AppSecurityState build() =>
      AppSecurityState(isPasswordConfigured: existing, isUnlocked: existing);
  @override
  bool get hasPreparedPasswordSetup => prepared;
  @override
  Future<void> preparePasswordSetup(String password) async {
    expect(password, '123456');
    events.add('prepare');
    prepared = true;
  }

  @override
  void commitPasswordSetup() {
    expect(prepared, isTrue);
    events.add('commit');
    prepared = false;
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
  }

  @override
  Future<void> rollbackPasswordSetup() async {
    events.add('rollback');
    prepared = false;
  }
}

class _Sync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();
  @override
  bool needsPauseForWalletMutation() => false;
}
