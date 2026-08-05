import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/onboarding/unlock_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/linux_update_provider.dart';
import 'package:zcash_wallet/src/providers/network_privacy_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'fakes/fake_sync_notifier.dart';

void main() {
  testWidgets('shows the standard Linux release notice while Tor is off', (
    tester,
  ) async {
    await _pumpUpdateNotice(tester, torEnabled: false);

    expect(find.byType(UnlockScreen), findsOneWidget);
    expect(find.text('Vizor 1.2.3 is available.'), findsOneWidget);
    expect(find.text('View release'), findsOneWidget);
    expect(find.textContaining('outside Vizor’s Tor connection'), findsNothing);
  });

  testWidgets('warns about the external browser while Tor is on', (
    tester,
  ) async {
    await _pumpUpdateNotice(tester, torEnabled: true);

    expect(
      find.text(
        'Vizor 1.2.3 is available. The release page opens in your browser, '
        'outside Vizor’s Tor connection.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open in browser'), findsOneWidget);
  });
}

Future<void> _pumpUpdateNotice(
  WidgetTester tester, {
  required bool torEnabled,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appBootstrapProvider.overrideWithValue(_lockedBootstrap),
        syncProvider.overrideWith(FakeSyncNotifier.new),
        networkPrivacyProvider.overrideWith(
          () => _TestNetworkPrivacyNotifier(torEnabled),
        ),
        linuxUpdateProvider.overrideWith(
          (ref) async => const LinuxUpdateInfo(
            version: '1.2.3',
            assetVersion: '1.2.3',
            buildNumber: 123,
            releaseTag: 'release/v1.2.3',
            releaseUrl:
                'https://github.com/chainapsis/vizor-wallet/releases/tag/release/v1.2.3',
            appImageUrl: 'https://updates.example/Vizor.AppImage',
            sha256Url: 'https://updates.example/Vizor.AppImage.sha256',
            signatureUrl: 'https://updates.example/Vizor.AppImage.asc',
            zsyncUrl: null,
          ),
        ),
      ],
      child: const ZcashWalletApp(),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _TestNetworkPrivacyNotifier extends NetworkPrivacyNotifier {
  _TestNetworkPrivacyNotifier(this.torEnabled);

  final bool torEnabled;

  @override
  NetworkPrivacyState build() => torEnabled
      ? const NetworkPrivacyState(
          torEnabled: true,
          status: NetworkPrivacyConnectionStatus.connected,
        )
      : const NetworkPrivacyState.off();
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
