import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/app.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/welcome.dart';
import 'package:zcash_wallet/src/features/swap/providers/swap_activity_store.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

const _validPassword = 'Correct123!';

void main() {
  testWidgets(
    'uninstall reset stays on the data removed screen instead of welcome',
    (tester) async {
      await _runUninstallFlow(tester, initialLocation: '/settings/uninstall');
    },
  );

  testWidgets(
    'settings uninstall entry stays on the data removed screen after reset',
    (tester) async {
      await _runUninstallFlow(
        tester,
        initialLocation: '/settings',
        openFromSettings: true,
      );
    },
  );
}

Future<void> _runUninstallFlow(
  WidgetTester tester, {
  required String initialLocation,
  bool openFromSettings = false,
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final accountNotifier = _ResettingAccountNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap(initialLocation)),
          accountProvider.overrideWith(() => accountNotifier),
          appSecurityProvider.overrideWith(_TestAppSecurityNotifier.new),
          syncProvider.overrideWith(_TestSyncNotifier.new),
          swapPendingIntentCountProvider.overrideWith(
            (ref, accountUuid) async => 0,
          ),
        ],
        child: const ZcashWalletApp(),
      ),
    );
    await tester.pumpAndSettle();

    if (openFromSettings) {
      await tester.tap(find.text('Uninstall Vizor'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.widgetWithText(AppButton, 'Uninstall Vizor'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm access'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), _validPassword);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Confirm password'));

    await _pumpUntilPresent(tester, find.text('Removing data...'));
    final removingBadgeCenter = tester.getCenter(
      find.byKey(const ValueKey('settings_uninstall_badge')),
    );
    expect(_helmetOpacity(tester), 1);

    await _pumpUntilPresent(tester, find.text('Your data has been removed'));
    final doneBadgeCenter = tester.getCenter(
      find.byKey(const ValueKey('settings_uninstall_badge')),
    );
    expect(doneBadgeCenter.dx, closeTo(removingBadgeCenter.dx, 0.01));
    expect(doneBadgeCenter.dy, closeTo(removingBadgeCenter.dy, 0.01));
    expect(_helmetOpacity(tester), 1);

    await tester.pump(const Duration(milliseconds: 1600));
    expect(_helmetOpacity(tester), 0);

    expect(accountNotifier.resetWalletCalled, isTrue);
    expect(find.text('Your data has been removed'), findsOneWidget);
    expect(find.text('Close Vizor'), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> _pumpUntilPresent(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }
}

double _helmetOpacity(WidgetTester tester) {
  final fade = tester.widget<FadeTransition>(
    find.byKey(const ValueKey('settings_uninstall_badge_helmet')),
  );
  return fade.opacity.value;
}

AppBootstrapState _bootstrap(String initialLocation) {
  return AppBootstrapState(
    initialLocation: initialLocation,
    initialAccountState: const AccountState(
      accounts: [
        AccountInfo(
          uuid: 'account-1',
          name: 'Primary vault',
          order: 0,
          isSeedAnchor: true,
        ),
      ],
      activeAccountUuid: 'account-1',
      activeAddress: 'u1uninstalladdress',
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
}

class _ResettingAccountNotifier extends AccountNotifier {
  bool resetWalletCalled = false;

  @override
  FutureOr<AccountState> build() => _bootstrap('/settings').initialAccountState;

  @override
  Future<void> resetWallet() async {
    resetWalletCalled = true;
    state = const AsyncData(AccountState());
    ref.read(appSecurityProvider.notifier).reset();
  }
}

class _TestAppSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() {
    return const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  }

  @override
  Future<bool> confirmPassword(String password) async {
    return password == _validPassword;
  }

  @override
  void reset() {
    state = const AppSecurityState(
      isPasswordConfigured: false,
      isUnlocked: false,
    );
  }
}

class _TestSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async =>
      SyncState(accountUuid: 'account-1', hasAccountScopedData: true);

  @override
  bool needsPauseForWalletMutation() => true;

  @override
  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async {
    return const WalletMutationSyncPause(
      hadActiveSync: false,
      hadPolling: false,
      hadBackgroundSync: false,
      hadMempoolObserver: false,
    );
  }

  @override
  void resumeAfterWalletMutation(WalletMutationSyncPause pause) {}

  @override
  void clearCachedWalletDbPath() {}
}
