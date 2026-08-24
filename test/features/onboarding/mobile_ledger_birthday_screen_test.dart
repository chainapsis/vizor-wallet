@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/ledger/services/ledger_account_service.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_setup_args.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_ledger_birthday_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';

const _account = LedgerDeviceAccount(
  ufvk: 'uview-ledger',
  seedFingerprint: [1, 2, 3],
  accountIndex: 7,
  appVersion: '3.9.2',
);

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1;
  });

  testWidgets('confirms a birthday without running mnemonic import', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const MobileLedgerBirthdayScreen(
            args: LedgerBirthdayArgs(account: _account),
            loadChainMetadata: false,
          ),
        ),
        GoRoute(
          path: '/onboarding/ledger/customise-account',
          builder: (_, state) {
            final args = state.extra! as LedgerCustomiseAccountArgs;
            return Text(
              'customise-${args.account.accountIndex}-${args.birthdayHeight}',
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(_harness(router));
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

    expect(find.text('customise-7-2500000'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mobile_import_birthday_continue')),
    );
    await tester.pumpAndSettle();

    expect(find.text('customise-7-2500000'), findsOneWidget);
  });
}

Widget _harness(GoRouter router) => ProviderScope(
  overrides: [appBootstrapProvider.overrideWithValue(_bootstrap())],
  child: MaterialApp.router(
    routerConfig: router,
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
  ),
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/',
  initialAccountState: const AccountState(accounts: []),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
