import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/security/software_wallet_secret.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/settings/screens/settings_seed_phrase_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

const _mnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse access accident';
const _bip39Passphrase = 'correct horse battery staple with extra words';

const _accountState = AccountState(
  accounts: [
    AccountInfo(uuid: 'account-1', name: 'Current', order: 0),
    AccountInfo(uuid: 'account-2', name: 'Other', order: 1),
  ],
  activeAccountUuid: 'account-1',
  activeAddress: 'u1currentaddress',
);

void main() {
  testWidgets('reveals the requested account without making it active', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    final privacyController = SensitivePrivacyOverlayController(
      initiallySafe: true,
    );
    addTearDown(privacyController.dispose);
    late _FakeAccountNotifier accountNotifier;

    await tester.pumpWidget(
      _harness(
        privacyController: privacyController,
        accountNotifier: () => accountNotifier = _FakeAccountNotifier(),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'Correct123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pump();

    expect(accountNotifier.requestedMnemonicUuids, ['account-2']);
    expect(accountNotifier.state.requireValue.activeAccountUuid, 'account-1');
    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('BIP39 Passphrase'), findsOneWidget);
    expect(find.text('correct ho ... xtra words'), findsOneWidget);
  });

  testWidgets('hides the BIP39 section when the account has no passphrase', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final privacyController = SensitivePrivacyOverlayController(
      initiallySafe: true,
    );
    addTearDown(privacyController.dispose);

    await tester.pumpWidget(
      _harness(
        privacyController: privacyController,
        accountNotifier: () => _FakeAccountNotifier(bip39Passphrase: ''),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(EditableText), 'Correct123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pump();

    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('BIP39 Passphrase'), findsNothing);
    expect(find.bySemanticsLabel('Copy BIP39 passphrase'), findsNothing);
  });

  testWidgets('describes removal of the requested account accurately', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    final privacyController = SensitivePrivacyOverlayController(
      initiallySafe: true,
    );
    addTearDown(privacyController.dispose);
    late _FakeAccountNotifier accountNotifier;

    await tester.pumpWidget(
      _harness(
        privacyController: privacyController,
        accountNotifier: () => accountNotifier = _FakeAccountNotifier(),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(EditableText), 'Correct123!');
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));
    await tester.pump();
    accountNotifier.removeRequestedAccount();
    await tester.pump();

    expect(
      find.text('Selected account changed. Enter your password again.'),
      findsOneWidget,
    );
    expect(find.textContaining('Active account changed'), findsNothing);
  });
}

Widget _harness({
  required SensitivePrivacyOverlayController privacyController,
  required AccountNotifier Function() accountNotifier,
}) {
  final router = GoRouter(
    initialLocation: '/settings/secret-passphrase',
    routes: [
      GoRoute(
        path: '/settings/secret-passphrase',
        builder: (_, _) => SettingsSeedPhraseScreen(
          accountUuid: 'account-2',
          privacyOverlayController: privacyController,
        ),
      ),
      GoRoute(path: '/accounts', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/settings', builder: (_, _) => const SizedBox()),
      GoRoute(path: '/home', builder: (_, _) => const SizedBox()),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      accountProvider.overrideWith(accountNotifier),
      appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
      syncProvider.overrideWith(_FakeSyncNotifier.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

AppBootstrapState _bootstrap() => AppBootstrapState(
  initialLocation: '/settings/secret-passphrase',
  initialAccountState: _accountState,
  initialSyncSnapshot: AppSyncSnapshot.empty,
  network: 'main',
  rpcEndpointConfig: defaultRpcEndpointConfig('main'),
  themeMode: ThemeMode.light,
  privacyModeEnabled: false,
  isPasswordConfigured: true,
  isUnlocked: true,
  passwordRotationRecoveryFailed: false,
);

class _FakeAccountNotifier extends AccountNotifier {
  _FakeAccountNotifier({this.bip39Passphrase = _bip39Passphrase});

  final String bip39Passphrase;
  final requestedMnemonicUuids = <String>[];

  @override
  FutureOr<AccountState> build() => _accountState;

  @override
  Future<SoftwareWalletSecret?> getSoftwareWalletSecretForAccount(
    String uuid,
  ) async {
    requestedMnemonicUuids.add(uuid);
    return SoftwareWalletSecret(
      mnemonic: _mnemonic,
      bip39Passphrase: bip39Passphrase,
    );
  }

  void removeRequestedAccount() {
    state = AsyncData(
      state.requireValue.copyWith(
        accounts: state.requireValue.accounts
            .where((account) => account.uuid != 'account-2')
            .toList(),
      ),
    );
  }
}

class _FakeSecurityNotifier extends AppSecurityNotifier {
  @override
  Future<bool> confirmPassword(String password) async => true;
}

class _FakeSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();
}
