import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/storage/wallet_recovery.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/wallet_recovery_screen.dart';
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
      GoRoute(path: '/home', builder: (_, _) => const Text('Wallet home')),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

void main() {
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
}
