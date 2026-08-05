import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/features/onboarding/unlock_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/linux_update_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import 'fakes/fake_sync_notifier.dart';

void main() {
  testWidgets('shows the detected Linux release without blocking the app', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_lockedBootstrap),
          syncProvider.overrideWith(FakeSyncNotifier.new),
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

    expect(find.byType(UnlockScreen), findsOneWidget);
    expect(find.text('Vizor 1.2.3 is available.'), findsOneWidget);
    expect(find.text('View release'), findsOneWidget);
  });
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
