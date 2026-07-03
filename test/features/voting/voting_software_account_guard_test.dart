import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/voting/screens/voting_software_account_guard.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

void main() {
  testWidgets('hardware accounts can load voting child routes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountProvider.overrideWith(_HardwareAccountNotifier.new)],
        child: _guardHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('polls child'), findsOneWidget);
    expect(find.text('Hardware Accounts Coming Soon'), findsNothing);
  });

  testWidgets('software accounts can load voting child routes', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [accountProvider.overrideWith(_SoftwareAccountNotifier.new)],
        child: _guardHarness(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('polls child'), findsOneWidget);
    expect(find.text('Hardware Accounts Coming Soon'), findsNothing);
  });
}

Widget _guardHarness() {
  final router = GoRouter(
    initialLocation: '/voting',
    routes: [
      GoRoute(
        path: '/voting',
        builder: (_, _) =>
            const VotingSoftwareAccountGuard(child: Text('polls child')),
      ),
      GoRoute(
        path: '/accounts',
        builder: (_, _) => const Text('accounts route'),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
    ],
  );

  return MaterialApp.router(
    localizationsDelegates:
        AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: router,
    builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
  );
}

class _HardwareAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'hardware-1',
        name: 'Keystone',
        order: 0,
        isHardware: true,
      ),
    ],
    activeAccountUuid: 'hardware-1',
    activeAddress: 'u1hardwareaddress',
  );
}

class _SoftwareAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1softwareaddress',
  );
}
