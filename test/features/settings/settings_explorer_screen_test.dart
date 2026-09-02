import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/zcash_explorer.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_explorer_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zcash_explorer_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

const _accountState = AccountState(
  accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1exploreraddress',
);

AppBootstrapState _bootstrap({String explorerUrlTemplate = ''}) =>
    AppBootstrapState(
      initialLocation: '/settings/explorer',
      initialAccountState: _accountState,
      initialSyncSnapshot: AppSyncSnapshot.empty,
      network: 'main',
      rpcEndpointConfig: defaultRpcEndpointConfig('main'),
      explorerUrlTemplate: explorerUrlTemplate,
      themeMode: ThemeMode.light,
      privacyModeEnabled: false,
      isPasswordConfigured: true,
      isUnlocked: true,
      passwordRotationRecoveryFailed: false,
    );

class _FakeExplorerNotifier extends ZcashExplorerNotifier {
  _FakeExplorerNotifier(this.initial);

  final String initial;

  @override
  String build() => initial;

  @override
  Future<void> setCustom(String input) async {
    state = normalizeExplorerUrlTemplate(input);
  }

  @override
  Future<void> resetToDefault() async {
    state = '';
  }
}

Widget _harness({String explorerUrlTemplate = ''}) {
  final router = GoRouter(
    initialLocation: '/settings/explorer',
    routes: [
      GoRoute(
        path: '/settings/explorer',
        builder: (_, _) => const SettingsExplorerScreen(),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(explorerUrlTemplate: explorerUrlTemplate),
      ),
      syncProvider.overrideWith(FakeSyncNotifier.new),
      zcashExplorerProvider.overrideWith(
        () => _FakeExplorerNotifier(explorerUrlTemplate),
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

void main() {
  testWidgets('defaults to CipherScan and saves a custom origin', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('CipherScan'), findsOneWidget);
    expect(find.textContaining('cipherscan.app'), findsWidgets);
    expect(find.text(kZcashExplorerPrivacyCopy), findsOneWidget);
    expect(find.text('Any explorer you prefer'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('explorer_option_custom')));
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('explorer_custom_field')),
      'https://privacy.example',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('explorer_update')));
    await tester.pump();

    expect(find.textContaining('privacy.example'), findsWidgets);
  });

  testWidgets('resetting to CipherScan clears a custom explorer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      _harness(explorerUrlTemplate: 'https://privacy.example/tx/{txid}'),
    );
    await tester.pump();

    expect(find.textContaining('privacy.example'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('explorer_option_cipherscan')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('explorer_update')));
    await tester.pump();

    expect(find.textContaining('(default)'), findsOneWidget);
  });
}
