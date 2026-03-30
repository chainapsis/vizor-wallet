import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'src/features/home/screens/home_screen.dart';
import 'src/features/onboarding/screens/create_wallet_screen.dart';
import 'src/features/onboarding/screens/import_wallet_screen.dart';
import 'src/features/onboarding/screens/welcome_screen.dart';
import 'src/providers/wallet_provider.dart';

final _routerProvider = Provider<GoRouter>((ref) {
  final walletAsync = ref.watch(walletProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final wallet = walletAsync.value;
      final hasWallet = wallet?.hasWallet ?? false;
      final isOnboarding = state.matchedLocation == '/welcome' ||
          state.matchedLocation == '/create' ||
          state.matchedLocation == '/import';

      if (!hasWallet && !isOnboarding) return '/welcome';
      if (hasWallet && state.matchedLocation == '/welcome') return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/welcome'),
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
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFFF4B728), // Zcash yellow
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFFF4B728),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
