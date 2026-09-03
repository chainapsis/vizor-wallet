import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/migration/screens/ironwood_migration_flow_screen.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

import '../../fakes/fake_sync_notifier.dart';
import '../../support/payment_uri_busy_surface_expectations.dart';

/// Every migration signing step — desktop or mobile — is an animated migration
/// QR the Keystone is reading, or the scan of the signed result coming back.
/// The screen holds the latch across both halves so no card lands between
/// them.
void main() {
  testWidgets('the desktop migration signing screen holds the payment-URI '
      'busy latch', (tester) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: IronwoodMigrationKeystoneCombinedSignScreen(
        approvedSchedule: const [],
        previewRequest: _previewRequest,
        previewUrParts: _previewUrParts,
      ),
      drainExceptions: true,
    );
  });

  testWidgets('the mobile migration signing screen holds the payment-URI '
      'busy latch', (tester) async {
    final container = _container();
    await expectPaymentUriBusySurfaceHeldWhileMounted(
      tester,
      container: container,
      host: _host(container),
      surface: MobileIronwoodMigrationKeystoneBatchSignScreen(
        previewRequest: _previewRequest,
        previewUrParts: _previewUrParts,
      ),
      drainExceptions: true,
    );
  });
}

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      syncProvider.overrideWith(FakeSyncNotifier.new),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget Function(Widget) _host(ProviderContainer container) =>
    (child) => UncontrolledProviderScope(
      container: container,
      child: AppTheme(
        data: AppThemeData.dark,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );

final _previewRequest = rust_sync.KeystoneMigrationSigningRequest(
  requestId: 'busy-surface-preview',
  messages: [
    rust_sync.KeystoneMigrationMessage(
      id: 'busy-surface-preview-1',
      redactedPczt: Uint8List.fromList(const [1, 2, 3]),
      expectedSignatureCount: 0,
    ),
  ],
  signingBatchLimit: 1,
);

const _previewUrParts = ['ur:zcash-sign-request/busy-surface-preview-1'];

const _accountState = AccountState(
  accounts: [
    AccountInfo(
      uuid: 'account-1',
      name: 'Account1',
      order: 0,
      isHardware: true,
    ),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1migrationsign',
);

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/migration',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.dark,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);
