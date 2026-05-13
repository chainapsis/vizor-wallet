import 'dart:async';

import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/set_password_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

void main() {
  testWidgets('rolls back first wallet state when password commit fails', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final accountNotifier = _FakeAccountNotifier();
    final securityNotifier = _FailingCommitSecurityNotifier();

    await tester.pumpWidget(
      _setPasswordScreen(
        accountNotifier: () => accountNotifier,
        securityNotifier: () => securityNotifier,
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('set_password_password_field')),
      'ValidPass123!',
    );
    await tester.enterText(
      find.byKey(const ValueKey('set_password_confirm_field')),
      'ValidPass123!',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('set_password_submit_button')));
    await tester.pumpAndSettle();

    expect(accountNotifier.createdFromMnemonic, isTrue);
    expect(accountNotifier.rollbackFirstWalletOnboardingCalled, isTrue);
    expect(securityNotifier.rollbackPasswordSetupCalled, isTrue);
    expect(accountNotifier.state.value, const AccountState());
  });
}

Widget _setPasswordScreen({
  required AccountNotifier Function() accountNotifier,
  required AppSecurityNotifier Function() securityNotifier,
}) {
  final router = GoRouter(
    initialLocation: '/set-password',
    routes: [
      GoRoute(
        path: '/set-password',
        builder: (_, _) => const Scaffold(
          body: SetPasswordScreen(
            args: SetPasswordScreenArgs.create(mnemonic: 'test mnemonic'),
          ),
        ),
      ),
      GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
    ],
  );

  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      accountProvider.overrideWith(accountNotifier),
      appSecurityProvider.overrideWith(securityNotifier),
      syncProvider.overrideWith(_IdleSyncNotifier.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
}

class _FakeAccountNotifier extends AccountNotifier {
  bool createdFromMnemonic = false;
  bool rollbackFirstWalletOnboardingCalled = false;

  @override
  FutureOr<AccountState> build() => const AccountState();

  @override
  Future<void> createAccountFromMnemonic({
    required String mnemonic,
    String? name,
  }) async {
    createdFromMnemonic = true;
    state = const AsyncData(
      AccountState(
        accounts: [
          AccountInfo(
            uuid: 'account-1',
            name: 'Account 1',
            order: 0,
            isSeedAnchor: true,
          ),
        ],
        activeAccountUuid: 'account-1',
        activeAddress: 'u-test-address',
      ),
    );
  }

  @override
  Future<void> rollbackFirstWalletOnboarding() async {
    rollbackFirstWalletOnboardingCalled = true;
    state = const AsyncData(AccountState());
  }
}

class _FailingCommitSecurityNotifier extends AppSecurityNotifier {
  bool rollbackPasswordSetupCalled = false;

  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: false);

  @override
  Future<void> preparePasswordSetup(String password) async {}

  @override
  void commitPasswordSetup() {
    throw StateError('commit failed');
  }

  @override
  Future<void> rollbackPasswordSetup() async {
    rollbackPasswordSetupCalled = true;
  }
}

class _IdleSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();

  @override
  bool needsPauseForWalletMutation() => false;
}
