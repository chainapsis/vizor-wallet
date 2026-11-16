import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import 'package:zcash_wallet/src/core/layout/app_form_factor.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/create/secret_passphrase_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress_scope.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_secret_passphrase_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

import '../../fakes/fake_sync_notifier.dart';

const _mnemonic =
    'abandon ability able about above absent absorb abstract '
    'absurd abuse access accident account accuse achieve acid acoustic acquire '
    'across act action actor actress actual';
const _mobile = kAppFormFactor == AppFormFactor.mobile;
final _primary = find.byKey(
  ValueKey(
    _mobile
        ? 'mobile_secret_passphrase_primary'
        : 'create_secret_phrase_primary_button',
  ),
);

void main() {
  Future<GoRouter> pump(WidgetTester tester, _Accounts accounts) async {
    await tester.binding.setSurfaceSize(
      _mobile ? const Size(520, 1100) : const Size(1280, 900),
    );
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/phrase',
      routes: [
        GoRoute(
          path: '/phrase',
          builder: (_, _) => _mobile
              ? const MobileSecretPassphraseScreen(
                  args: CreateSecretPassphraseArgs(mnemonic: _mnemonic),
                  screenshotStream: Stream.empty(),
                )
              : const SecretPassphraseScreen(
                  args: CreateSecretPassphraseArgs(mnemonic: _mnemonic),
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
    final submit = tester.widget<AppButton>(_primary).onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(accounts.names, hasLength(1));
    expect(tester.widget<AppButton>(_primary).onPressed, isNull);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(router.state.uri.path, '/phrase');
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Created Home'), findsOneWidget);
    expect(accounts.names.single, isNotEmpty);
    expect(accounts.pictures.single, isNotEmpty);
    expect(accounts.mnemonics, [_mnemonic]);
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
        expect(router.state.uri.path, '/phrase');
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
  final mnemonics = <String>[];
  Object? failure;
  Completer<void>? gate;
  @override
  AccountState build() => const AccountState(
    accounts: [AccountInfo(uuid: 'original', name: 'Original', order: 0)],
    activeAccountUuid: 'original',
  );
  @override
  Future<void> createAccountFromMnemonic({
    required String mnemonic,
    String? name,
    String profilePictureId = 'pfp-01',
  }) async {
    names.add(name!);
    pictures.add(profilePictureId);
    mnemonics.add(mnemonic);
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
