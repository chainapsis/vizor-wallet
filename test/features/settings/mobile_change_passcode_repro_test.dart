@Tags(['mobile'])
library;

import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_toast.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_change_passcode_screen.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_settings_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/l10n/app_localizations.dart';

class _FakeSecurityNotifier extends AppSecurityNotifier {
  @override
  Future<bool> confirmPassword(String password) async => true;

  @override
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async => true;
}

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/settings',
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

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1200)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('settings → change passcode → back to settings keeps the '
      'Password row reachable for a second round', (tester) async {
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) => NoTransitionPage(
            key: state.pageKey,
            child: const AppToastHost(child: MobileSettingsScreen()),
          ),
        ),
        GoRoute(
          path: '/settings/change-password',
          pageBuilder: (context, state) => CupertinoPage(
            key: state.pageKey,
            child: const MobileChangePasscodeScreen(),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
        ],
        child: MaterialApp.router(
          localizationsDelegates:
              AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
        ),
      ),
    );
    await tester.pump();

    Future<void> enterPasscode(String digits) async {
      for (final digit in digits.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $digit'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> changePasscode(String current, String next) async {
      await tester.tap(find.text('Password'));
      await tester.pumpAndSettle();
      expect(find.text('Enter Passcode'), findsOneWidget);
      await enterPasscode(current);
      expect(find.text('Set New Passcode'), findsOneWidget);
      await enterPasscode(next);
      expect(find.text('Confirm Passcode'), findsOneWidget);
      await enterPasscode(next);
      expect(find.text('Passcode updated'), findsOneWidget);
      // Let the toast time out fully.
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    await changePasscode('111111', '222222');
    await changePasscode('222222', '111111');
  });
}
