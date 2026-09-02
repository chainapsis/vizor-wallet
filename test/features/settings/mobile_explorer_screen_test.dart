@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/config/zcash_explorer.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_explorer_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/zcash_explorer_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

const _accountState = AccountState(
  accounts: [AccountInfo(uuid: 'account-1', name: 'John', order: 0)],
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
      themeMode: ThemeMode.dark,
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

Widget _app({String explorerUrlTemplate = ''}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(explorerUrlTemplate: explorerUrlTemplate),
      ),
      syncProvider.overrideWith(() => FakeSyncNotifier(SyncState())),
      zcashExplorerProvider.overrideWith(
        () => _FakeExplorerNotifier(explorerUrlTemplate),
      ),
    ],
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
      home: const MobileExplorerScreen(),
    ),
  );
}

void main() {
  testWidgets('saves a custom explorer URL from the mobile settings screen', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Explorer'), findsOneWidget);
    expect(find.text('CipherScan'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_explorer_option_custom')),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const ValueKey('mobile_explorer_custom_field')),
      'https://privacy.example/tx/{txid}',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mobile_explorer_update')));
    await tester.pump();

    expect(find.textContaining('privacy.example'), findsWidgets);
  });
}
