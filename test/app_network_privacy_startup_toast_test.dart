import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'fakes/fake_sync_notifier.dart';

void main() {
  testWidgets('startup Tor failure stays fail-closed and shows one notice', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(_appHarness());
    await tester.pump();

    expect(find.text(kTorStartupFailureNotice), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ZcashWalletApp)),
    );
    final privacy = container.read(networkPrivacyProvider);
    expect(privacy.torEnabled, isTrue);
    expect(privacy.status, NetworkPrivacyConnectionStatus.failed);
    expect(privacy.startupNotice, isNull);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text(kTorStartupFailureNotice), findsNothing);
  });
}

Widget _appHarness() {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_lockedBootstrap),
      syncProvider.overrideWith(FakeSyncNotifier.new),
      networkPrivacyProvider.overrideWith(_StartupTorFailureNotifier.new),
    ],
    child: const ZcashWalletApp(),
  );
}

final _lockedBootstrap = AppBootstrapState(
  initialLocation: '/unlock',
  initialAccountState: const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Account 1', order: 0)],
    activeAccountUuid: 'account-1',
  ),
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.system,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: false,
  passwordRotationRecoveryFailed: false,
);

class _StartupTorFailureNotifier extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState(
    torEnabled: true,
    status: NetworkPrivacyConnectionStatus.failed,
    error: 'Bootstrap Tor: unavailable',
    startupNotice: kTorStartupFailureNotice,
  );
}
