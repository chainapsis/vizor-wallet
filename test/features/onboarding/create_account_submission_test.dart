import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/navigation/external_action_guard_provider.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/welcome.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress_scope.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_welcome_screen.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';
import '../../figma_compare/figma_compare_font_loader.dart';

const _mobile = kAppFormFactor == AppFormFactor.mobile;
final _primaryKey = find.byKey(
  ValueKey(
    _mobile ? 'mobile_welcome_get_started' : 'welcome_create_wallet_button',
  ),
);
final _primary = find.descendant(
  of: _primaryKey,
  matching: find.byType(AppButton),
);

void main() {
  setUpAll(loadFigmaCompareFonts);
  Future<GoRouter> pump(WidgetTester tester, _Accounts accounts) async {
    await tester.binding.setSurfaceSize(
      _mobile ? const Size(520, 1100) : const Size(1280, 900),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/add-account',
      routes: [
        GoRoute(
          path: '/add-account',
          builder: (_, _) => _mobile
              ? const MobileWelcomeScreen(
                  showBackButton: true,
                  animateBackground: false,
                )
              : const WelcomeScreen(
                  showBackButton: true,
                  animateBackground: false,
                ),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('Created Home')),
        GoRoute(
          path: '/unlock',
          builder: (_, _) => const Text('Recovery Unlock'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
          accountProvider.overrideWith(() => accounts),
          appSecurityProvider.overrideWith(_Security.new),
          syncProvider.overrideWith(_IdleSync.new),
          appBootstrapRetryProvider.overrideWithValue(
            () async => router.go('/unlock'),
          ),
        ],
        child: MaterialApp.router(
          localizationsDelegates: appLocalizationsDelegates,
          routerConfig: router,
          builder: (_, child) => AppTheme(
            data: AppThemeData.light,
            child: MobileOnboardingProgressFrame(child: child!),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('additional creation blocks repeated taps and Back until Home', (
    tester,
  ) async {
    final gate = Completer<void>();
    final accounts = _Accounts()..gate = gate;
    final router = await pump(tester, accounts);
    final container = ProviderScope.containerOf(tester.element(_primary));
    final submit = tester.widget<AppButton>(_primary).onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(accounts.names, hasLength(1));
    for (final action in ExternalAction.values) {
      expect(
        container.read(externalActionGuardProvider).blocks(action),
        isTrue,
      );
    }
    expect(
      container.read(externalActionGuardProvider.notifier).tryBeginNavigation(),
      isNull,
    );
    expect(tester.widget<AppButton>(_primary).onPressed, isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(router.state.uri.path, '/add-account');
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Created Home'), findsOneWidget);
    expect(container.read(externalActionGuardProvider).activeHoldCount, 0);
    expect(accounts.names.single, isNotEmpty);
    expect(accounts.pictures.single, isNotEmpty);
    expect(accounts.state.requireValue.activeAccount!.setupPending, isTrue);
    expect(
      accounts.state.requireValue.activeAccount!.giftEducationPending,
      isTrue,
    );
    expect(accounts.state.requireValue.accounts, hasLength(2));
  });

  testWidgets('pre-account failure retries with the same generated persona', (
    tester,
  ) async {
    final accounts = _Accounts()..failure = StateError('network unavailable');
    await pump(tester, accounts);
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t finish this step. Try again.'), findsOneWidget);
    expect(accounts.state.requireValue.accounts, hasLength(1));
    accounts.failure = null;
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(find.text('Created Home'), findsOneWidget);
    expect(accounts.names, hasLength(2));
    expect(accounts.names.toSet(), hasLength(1));
    expect(accounts.pictures.toSet(), hasLength(1));
  });

  for (final uncertain in [false, true]) {
    testWidgets(
      'interrupted additional creation recovers without recreating, uncertain=$uncertain',
      (tester) async {
        final accounts = _Accounts()
          ..failure = uncertain
              ? const WalletAccountStateUncertainException('DB unavailable')
              : const WalletAccountSetupInterruptedException(
                  'created',
                  'metadata unavailable',
                );
        final router = await pump(tester, accounts);
        await tester.tap(_primary);
        await tester.pumpAndSettle();
        expect(find.text('Retry setup'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(router.state.uri.path, '/add-account');
        await tester.tap(_primary);
        await tester.pumpAndSettle();
        expect(find.text('Recovery Unlock'), findsOneWidget);
        expect(accounts.names, hasLength(1));
      },
    );
  }
}

class _Security extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);
  @override
  void lock() => state = const AppSecurityState(
    isPasswordConfigured: true,
    isUnlocked: false,
  );
}

class _Accounts extends AccountNotifier {
  final names = <String>[];
  final pictures = <String>[];
  Object? failure;
  Completer<void>? gate;
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: 'original', name: 'Original', order: 0)],
    activeAccountUuid: 'original',
  );
  @override
  Future<void> createAccountForDeferredSetup({
    required String name,
    required String profilePictureId,
  }) async {
    names.add(name);
    pictures.add(profilePictureId);
    await gate?.future;
    if (failure != null) throw failure!;
    state = AsyncData(
      AccountState(
        accounts: [
          ...state.requireValue.accounts,
          AccountInfo(
            uuid: 'created',
            name: name,
            order: 1,
            setupPending: true,
            giftEducationPending: true,
            profilePictureId: profilePictureId,
          ),
        ],
        activeAccountUuid: 'created',
      ),
    );
  }
}

class _IdleSync extends FakeSyncNotifier {
  @override
  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async => const WalletMutationSyncPause(
    hadActiveSync: false,
    hadPolling: false,
    hadMempoolObserver: false,
  );
  @override
  void resumeAfterWalletMutation(
    WalletMutationSyncPause pause, {
    bool forceRestart = false,
  }) {}
}
