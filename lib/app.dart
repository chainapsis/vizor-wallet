import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'main.dart' show log;
import 'src/core/theme/app_theme.dart';
import 'src/features/home/screens/home_screen.dart';
import 'src/features/onboarding/screens/create_wallet_screen.dart';
import 'src/features/onboarding/screens/import_wallet_screen.dart';
import 'src/features/onboarding/screens/welcome_screen.dart';
import 'src/features/history/screens/history_screen.dart';
import 'src/features/receive/screens/receive_screen.dart';
import 'src/features/accounts/screens/accounts_screen.dart';
import 'src/features/send/screens/send_screen.dart';
import 'src/providers/wallet_provider.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final walletAsync = ref.watch(walletProvider);
  log('router: walletAsync=$walletAsync');

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final wallet = walletAsync.value;
      final hasWallet = wallet?.hasWallet ?? false;
      final isOnboarding = state.matchedLocation == '/welcome' ||
          state.matchedLocation == '/create' ||
          state.matchedLocation == '/import';

      log('router redirect: location=${state.matchedLocation}, hasWallet=$hasWallet, isOnboarding=$isOnboarding');

      if (!hasWallet && !isOnboarding) return '/welcome';
      if (hasWallet && state.matchedLocation == '/welcome') return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (_, _) {
          final wallet = walletAsync.value;
          final hasWallet = wallet?.hasWallet ?? false;
          return hasWallet ? '/home' : '/welcome';
        },
      ),
      GoRoute(
        path: '/welcome',
        builder: (_, _) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/create',
        builder: (_, _) => const CreateWalletScreen(),
      ),
      GoRoute(
        path: '/import',
        builder: (_, _) => const ImportWalletScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) => const HomeScreen(),
      ),
      GoRoute(
        path: '/send',
        builder: (_, _) => const SendScreen(),
      ),
      GoRoute(
        path: '/receive',
        builder: (_, _) => const ReceiveScreen(),
      ),
      GoRoute(
        path: '/history',
        builder: (_, _) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/accounts',
        builder: (_, _) => const AccountsScreen(),
      ),
    ],
  );
});

class ZcashWalletApp extends ConsumerWidget {
  const ZcashWalletApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);

    return MaterialApp.router(
      title: 'Zcash Wallet',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: router,
    );
  }
}
