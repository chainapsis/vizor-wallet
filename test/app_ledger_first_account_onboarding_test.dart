import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/ledger_capability.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/onboarding/import/import_birthday_estimator.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_setup_args.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/rpc_endpoint_failover_provider.dart';

void main() {
  testWidgets(
    'first Ledger account sets a password before import and reaches Home',
    (tester) async {
      await _setDesktopViewport(tester);
      final security = _RecordingSecurityNotifier(configured: false);
      final import = _RecordingLedgerImport();

      await tester.pumpWidget(
        _harness(security: security, import: import.call),
      );
      await tester.pumpAndSettle();

      await _enterBirthday(tester);

      expect(
        find.byKey(const ValueKey('set_password_password_field')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('set_password_password_field')),
        'Password1!',
      );
      await tester.enterText(
        find.byKey(const ValueKey('set_password_confirm_field')),
        'Password1!',
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('set_password_submit_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('customise_account_name_field')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('customise_account_name_field')),
        'Ledger savings',
      );
      await tester.tap(
        find.byKey(const ValueKey('customise_account_finish_button')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('ledger_first_account_home')), findsOne);
      expect(security.preparedPassword, 'Password1!');
      expect(security.commitCount, 1);
      expect(security.rollbackCount, 0);
      expect(import.calls, 1);
      expect(import.name, 'Ledger savings');
      expect(import.birthdayHeight, 2500000);
    },
  );

  testWidgets('additional Ledger account skips password setup', (tester) async {
    await _setDesktopViewport(tester);
    final security = _RecordingSecurityNotifier(configured: true);
    final import = _RecordingLedgerImport();

    await tester.pumpWidget(_harness(security: security, import: import.call));
    await tester.pumpAndSettle();

    await _enterBirthday(tester);

    expect(
      find.byKey(const ValueKey('set_password_password_field')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('customise_account_name_field')),
      findsOneWidget,
    );
    expect(find.text('Set Password'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('customise_account_finish_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ledger_first_account_home')), findsOne);
    expect(security.preparedPassword, isNull);
    expect(security.commitCount, 0);
    expect(import.calls, 1);
  });
}

const _account = LedgerDeviceAccount(
  ufvk: 'uview-ledger-first-account',
  seedFingerprint: [1, 2, 3, 4],
  accountIndex: 0,
  appVersion: '3.9.2',
);

Widget _harness({
  required _RecordingSecurityNotifier security,
  required LedgerAccountImporter import,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      appSecurityProvider.overrideWith(() => security),
      ledgerTargetPlatformProvider.overrideWithValue(TargetPlatform.macOS),
      ledgerAccountImporterProvider.overrideWithValue(import),
      rpcEndpointFailoverProvider.overrideWith(
        _FakeRpcEndpointFailoverNotifier.new,
      ),
    ],
    child: const _LedgerRouteHarness(),
  );
}

class _LedgerRouteHarness extends ConsumerStatefulWidget {
  const _LedgerRouteHarness();

  @override
  ConsumerState<_LedgerRouteHarness> createState() =>
      _LedgerRouteHarnessState();
}

final _desktopOnboardingRoutesProvider = Provider(appDesktopOnboardingRoutes);

class _LedgerRouteHarnessState extends ConsumerState<_LedgerRouteHarness> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/onboarding/ledger/birthday',
      initialExtra: const LedgerBirthdayArgs(account: _account),
      routes: [
        ...ref.read(_desktopOnboardingRoutesProvider),
        GoRoute(
          path: '/home',
          builder: (_, _) =>
              const SizedBox(key: ValueKey('ledger_first_account_home')),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    );
  }
}

Future<void> _enterBirthday(WidgetTester tester) async {
  await tester.tap(find.text('Enter the block height'));
  await tester.pump();
  await tester.enterText(find.byType(TextField), '2500000');
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('import_birthday_submit_button')));
  await tester.pumpAndSettle();
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

class _RecordingSecurityNotifier extends AppSecurityNotifier {
  _RecordingSecurityNotifier({required this.configured});

  final bool configured;
  String? preparedPassword;
  var commitCount = 0;
  var rollbackCount = 0;

  @override
  AppSecurityState build() => AppSecurityState(
    isPasswordConfigured: configured,
    isUnlocked: configured,
  );

  @override
  Future<void> preparePasswordSetup(String password) async {
    preparedPassword = password;
  }

  @override
  void commitPasswordSetup() {
    commitCount++;
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
  }

  @override
  Future<void> rollbackPasswordSetup() async {
    rollbackCount++;
  }
}

class _RecordingLedgerImport {
  var calls = 0;
  String? name;
  int? birthdayHeight;

  Future<void> call({
    required String name,
    required LedgerDeviceAccount account,
    required int birthdayHeight,
    required String profilePictureId,
  }) async {
    calls++;
    this.name = name;
    this.birthdayHeight = birthdayHeight;
  }
}

class _FakeRpcEndpointFailoverNotifier extends RpcEndpointFailoverNotifier {
  @override
  RpcEndpointFailoverState build() {
    final endpoint = defaultRpcEndpointConfig('main');
    return RpcEndpointFailoverState(
      primary: endpoint,
      current: endpoint,
      fallbackCandidates: const [],
    );
  }

  @override
  Future<T> runWithEndpointFallback<T>({
    required String operation,
    required Future<T> Function(RpcEndpointConfig endpoint) action,
    bool allowFallback = true,
    bool Function(Object error) shouldFallback =
        shouldFallbackFromLightwalletdError,
  }) async {
    if (operation == 'import birthday metadata') {
      return ImportBirthdayMetadata(
            saplingActivationHeight: 419200,
            saplingActivationDate: DateTime(2016, 10, 28),
            tipHeight: 3336000,
            tipDate: DateTime(2026, 5, 11),
          )
          as T;
    }
    return action(state.current);
  }
}
