import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_layout.dart';
import 'package:zcash_wallet/src/core/profile_pictures.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/migration/providers/orchard_migration_status_provider.dart';
import 'package:zcash_wallet/src/features/migration/screens/migration_scan_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/services/qr_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('completion from direct route returns to migration', (
    tester,
  ) async {
    await tester.pumpWidget(_scanHarness(initialLocation: '/migration/scan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Complete scan'));
    await tester.pumpAndSettle();

    expect(find.text('migration route'), findsOneWidget);
  });

  testWidgets('completion from pushed route returns scanned signed QR', (
    tester,
  ) async {
    await tester.pumpWidget(_scanHarness(initialLocation: '/migration'));
    await tester.tap(find.text('Open scan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Complete scan'));
    await tester.pumpAndSettle();

    expect(find.text('scan result: zcash-sign-result 1,2,3'), findsOneWidget);
  });
}

Widget _scanHarness({required String initialLocation}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/migration', builder: (_, _) => const _MigrationRoute()),
      GoRoute(
        path: '/migration/scan',
        builder: (_, _) => MigrationScanScreen(
          scannerBuilder:
              ({
                required decoding,
                required error,
                required onDecodeError,
                required onComplete,
              }) => _TestScanner(onComplete: onComplete),
        ),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      GoRoute(path: '/accounts', builder: (_, _) => const Text('accounts')),
      GoRoute(path: '/send', builder: (_, _) => const Text('send')),
      GoRoute(path: '/swap', builder: (_, _) => const Text('swap')),
      GoRoute(path: '/voting', builder: (_, _) => const Text('voting')),
      GoRoute(path: '/receive', builder: (_, _) => const Text('receive')),
      GoRoute(
        path: '/address-book',
        builder: (_, _) => const Text('address book'),
      ),
      GoRoute(path: '/activity', builder: (_, _) => const Text('activity')),
      GoRoute(path: '/settings', builder: (_, _) => const Text('settings')),
      GoRoute(path: '/about', builder: (_, _) => const Text('about')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      appLayoutProvider.overrideWith(_FakeAppLayoutNotifier.new),
      activeOrchardMigrationStatusProvider.overrideWith((_) async => null),
      syncProvider.overrideWith(() => _FakeSyncNotifier(SyncState())),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

class _MigrationRoute extends StatefulWidget {
  const _MigrationRoute();

  @override
  State<_MigrationRoute> createState() => _MigrationRouteState();
}

class _MigrationRouteState extends State<_MigrationRoute> {
  MigrationSignedQrResult? _result;

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('migration route'),
            TextButton(
              onPressed: () async {
                final signedQr = await context.push<MigrationSignedQrResult>(
                  '/migration/scan',
                );
                if (!mounted) return;
                setState(() => _result = signedQr);
              },
              child: const Text('Open scan'),
            ),
            if (result != null)
              Text('scan result: ${result.urType} ${result.cbor.join(',')}'),
          ],
        ),
      ),
    );
  }
}

class _TestScanner extends StatelessWidget {
  const _TestScanner({required this.onComplete});

  final ValueChanged<ScanResult> onComplete;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => onComplete(
        const ScanResult(urType: 'zcash-sign-result', data: [1, 2, 3]),
      ),
      child: const Text('Complete scan'),
    );
  }
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/migration',
  initialAccountState: const AccountState(
    accounts: [
      AccountInfo(
        uuid: 'account-1',
        name: 'Primary Vault',
        order: 0,
        profilePictureId: kDefaultProfilePictureId,
      ),
    ],
    activeAccountUuid: 'account-1',
    activeAddress: 'u1migrationaddress',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeAppLayoutNotifier extends AppLayoutNotifier {
  @override
  AppLayoutState build() => const AppLayoutState(AppLayoutMode.large);

  @override
  Future<void> setMode(AppLayoutMode mode) async {
    state = AppLayoutState(mode);
  }
}

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this.initialState);

  final SyncState initialState;

  @override
  Future<SyncState> build() async => initialState;
}
