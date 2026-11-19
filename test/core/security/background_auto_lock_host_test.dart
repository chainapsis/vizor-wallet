@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/security/background_auto_lock_host.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/mobile_account_visibility_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/voting/voting_submission_guard_provider.dart';
import 'package:zcash_wallet/src/providers/wallet_provider.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';

import '../../fakes/fake_sync_notifier.dart';

class _FakeSecurityNotifier extends AppSecurityNotifier {
  var locks = 0;

  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  @override
  void lock() {
    locks++;
    state = state.copyWith(isUnlocked: false);
  }
}

class _FakeAccountNotifier extends AccountNotifier {
  var clears = 0;

  @override
  FutureOr<AccountState> build() => const AccountState();

  @override
  void clearSensitiveStateForLock() => clears++;
}

class _FakeSyncNotifier extends FakeSyncNotifier {
  var clears = 0;

  @override
  Future<void> clearSensitiveStateForLock() async => clears++;
}

class _FakeWalletNotifier extends WalletNotifier {
  @override
  FutureOr<WalletState> build() => const WalletState(hasWallet: true);
}

Future<void> _sendToBackgroundAndBack(
  WidgetTester tester, {
  void Function()? whileAway,
}) async {
  for (final state in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  whileAway?.call();
  for (final state in const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

void main() {
  late _FakeSecurityNotifier security;
  late _FakeAccountNotifier account;
  late _FakeSyncNotifier sync;
  late GoRouter router;
  late ProviderContainer container;

  Future<void> pumpHost(
    WidgetTester tester, {
    required Duration timeout,
    DateTime Function()? now,
  }) async {
    security = _FakeSecurityNotifier();
    account = _FakeAccountNotifier();
    sync = _FakeSyncNotifier();
    router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Text('home')),
        GoRoute(path: '/unlock', builder: (_, _) => const Text('unlock')),
      ],
    );
    addTearDown(router.dispose);
    container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
        appSecurityProvider.overrideWith(() => security),
        accountProvider.overrideWith(() => account),
        syncProvider.overrideWith(() => sync),
        walletProvider.overrideWith(_FakeWalletNotifier.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(walletProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          localizationsDelegates: appLocalizationsDelegates,
          routerConfig: router,
          builder: (_, child) => AppTheme(
            data: AppThemeData.light,
            child: BackgroundAutoLockHost(
              router: router,
              timeout: timeout,
              now: now,
              child: child!,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('locks and opens unlock after the timeout in background', (
    tester,
  ) async {
    await pumpHost(tester, timeout: Duration.zero);

    await _sendToBackgroundAndBack(tester);

    expect(security.locks, 1);
    expect(account.clears, 1);
    expect(sync.clears, 1);
    expect(find.text('unlock'), findsOneWidget);
  });

  testWidgets('stays unlocked when the app returns within the timeout', (
    tester,
  ) async {
    await pumpHost(tester, timeout: const Duration(hours: 1));

    await _sendToBackgroundAndBack(tester);

    expect(security.locks, 0);
    expect(find.text('home'), findsOneWidget);
  });

  for (final manage in [false, true]) {
    testWidgets(
      'brief background relocks a private view (management: $manage)',
      (tester) async {
        const channel = MethodChannel('com.zcash.wallet/privacy_shield');
        final visible = <bool>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'setPrivateAccountViewVisible');
          visible.add(call.arguments['visible'] as bool);
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await pumpHost(tester, timeout: const Duration(hours: 1));
        if (manage) {
          container
              .read(mobileAccountManagementOpenProvider.notifier)
              .setOpen(Object(), true);
        } else {
          container.read(mobileAccountScopeProvider.notifier).select('private');
        }
        await tester.pump();
        expect(visible, [true]);

        await _sendToBackgroundAndBack(
          tester,
          whileAway: () {
            expect(security.locks, 1);
            expect(visible, [true]);
          },
        );
        expect(find.text('unlock'), findsOneWidget);
        expect(container.read(mobileAccountScopeProvider), isNull);
        expect(container.read(mobileAccountManagementOpenProvider), isFalse);
        expect(visible, [true, false]);
      },
    );
  }

  testWidgets('locks when the clock moved backwards while away', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 30, 12);
    await pumpHost(tester, timeout: const Duration(hours: 1), now: () => now);

    await _sendToBackgroundAndBack(
      tester,
      whileAway: () => now = now.subtract(const Duration(days: 1)),
    );

    expect(security.locks, 1);
    expect(find.text('unlock'), findsOneWidget);
  });

  testWidgets(
    'keeps the entire child covered while waiting to relock a private view',
    (tester) async {
      await pumpHost(tester, timeout: const Duration(hours: 1));
      final guards = container.read(votingSubmissionGuardProvider.notifier);
      final guard = guards.acquire(accountUuid: 'private', roundId: 'round-1');
      container.read(mobileAccountScopeProvider.notifier).select('private');
      await tester.pump();

      await _sendToBackgroundAndBack(tester);
      expect(security.locks, 0);
      expect(router.state.uri.path, '/home');
      expect(find.text('home'), findsNothing);

      guards.release(guard);
      await tester.pumpAndSettle();
      expect(security.locks, 1);
      expect(find.text('unlock'), findsOneWidget);
    },
  );

  testWidgets('waits for a voting submission, then locks', (tester) async {
    await pumpHost(tester, timeout: Duration.zero);
    final guards = container.read(votingSubmissionGuardProvider.notifier);
    final guard = guards.acquire(accountUuid: 'account-1', roundId: 'round-1');

    await _sendToBackgroundAndBack(tester);

    expect(security.locks, 0);
    expect(find.text('home'), findsOneWidget);

    guards.release(guard);
    await tester.pumpAndSettle();

    expect(security.locks, 1);
    expect(find.text('unlock'), findsOneWidget);
  });
}
