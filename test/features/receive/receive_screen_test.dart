import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/layout/app_desktop_shell.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/receive/screens/receive_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/receive_address_provider.dart';

void main() {
  testWidgets('receive info modal does not block sidebar navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_receiveHarness());
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is AppIcon && widget.name == AppIcons.help,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Shielded Address'), findsOneWidget);

    await tester.tap(
      find.ancestor(
        of: find.text('Send'),
        matching: find.byType(AppSidebarItem),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('send route'), findsOneWidget);
  });
}

Widget _receiveHarness() {
  final router = GoRouter(
    initialLocation: '/receive',
    routes: [
      GoRoute(path: '/receive', builder: (_, _) => const ReceiveScreen()),
      GoRoute(path: '/send', builder: (_, _) => const Text('send route')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap),
      receiveAddressServiceProvider.overrideWith(
        _FakeReceiveAddressService.new,
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

final _bootstrap = AppBootstrapState(
  initialLocation: '/receive',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
    activeAddress: _shieldedAddress,
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

const _shieldedAddress =
    'u1testshieldedaddress000000000000000000000000000000000000000000000000000';

class _FakeReceiveAddressService extends ReceiveAddressService {
  _FakeReceiveAddressService(super.ref);

  @override
  Future<String> loadShieldedAddress({
    required String accountUuid,
    String? currentShieldedAddress,
  }) async {
    return currentShieldedAddress ?? _shieldedAddress;
  }

  @override
  String? getCachedTransparentAddress(String accountUuid) {
    return 't1testtransparentaddress';
  }

  @override
  Future<String> loadTransparentAddress({required String accountUuid}) async {
    return 't1testtransparentaddress';
  }

  @override
  Future<String> renewShieldedAddress({required String accountUuid}) async {
    return _shieldedAddress;
  }
}
