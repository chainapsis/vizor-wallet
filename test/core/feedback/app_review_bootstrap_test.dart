import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/feedback/app_review.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';

AppBootstrapState _existingWallet({bool hardware = false}) {
  final empty = AppBootstrapState.empty;
  return AppBootstrapState(
    initialLocation: '/unlock',
    initialAccountState: AccountState(
      accounts: [
        AccountInfo(
          uuid: 'account-1',
          name: 'Wallet',
          order: 0,
          isHardware: hardware,
        ),
      ],
      activeAccountUuid: 'account-1',
    ),
    initialSyncSnapshot: empty.initialSyncSnapshot,
    network: empty.network,
    rpcEndpointConfig: empty.rpcEndpointConfig,
    themeMode: empty.themeMode,
    privacyModeEnabled: empty.privacyModeEnabled,
    isPasswordConfigured: true,
    isUnlocked: false,
    passwordRotationRecoveryFailed: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (name, bootstrap, expected) in [
    ('new installation', AppBootstrapState.empty, false),
    ('locked software wallet', _existingWallet(), true),
    ('locked hardware wallet', _existingWallet(hardware: true), true),
    for (final failure in AppBootstrapFailureKind.values)
      (
        'blocked startup: $failure',
        AppBootstrapState.blocked(
          failureKind: failure,
          failureMessage: 'Unavailable',
        ),
        null,
      ),
  ]) {
    test('production review startup snapshot: $name', () async {
      final app = await buildProductionZcashWalletApp(
        loadBootstrap: () async => bootstrap,
        applyPrivacyPolicy: (_) async {},
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(app.initialBootstrap),
          ...app.overrides,
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(appReviewStartupWalletProvider), expected);
    });
  }

  test(
    'bootstrap recovery replaces an unknown review startup snapshot',
    () async {
      final blocked = AppBootstrapState.blocked(
        failureKind: AppBootstrapFailureKind.secureStorageUnavailable,
        failureMessage: 'Unavailable',
      );
      final app = await buildProductionZcashWalletApp(
        loadBootstrap: () async => blocked,
        applyPrivacyPolicy: (_) async {},
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(blocked),
          ...app.overrides,
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(appReviewStartupWalletProvider), isNull);
      container.updateOverrides([
        appBootstrapProvider.overrideWithValue(_existingWallet()),
        ...app.overrides,
      ]);
      await container.pump();
      expect(container.read(appReviewStartupWalletProvider), isTrue);
    },
  );
}
