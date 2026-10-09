@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress_scope.dart';

import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/layout/mobile/mobile_top_nav.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_customise_account_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/account_persona_draft.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_passcode_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/providers/router_refresh_provider.dart';

Widget _app() {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    ],
    child: MaterialApp(
      builder: (_, c) => AppTheme(
        data: AppThemeData.light,
        child: MobileOnboardingProgressFrame(child: c!),
      ),
      home: MobilePasscodeScreen(
        args: const SetPasswordScreenArgs.create(
          mnemonic: 'stub mnemonic words',
        ).withPersona(_persona),
      ),
    ),
  );
}

const _createArgs = SetPasswordScreenArgs.create(
  mnemonic: 'stub mnemonic words',
);
const _importArgs = SetPasswordScreenArgs.importWallet(
  mnemonic: 'stub mnemonic words',
  bip39Passphrase: 'extra words',
  birthdayHeight: 2500000,
  selectedAdditionalAccountIndices: [1, 2],
);

const _persona = AccountPersona(name: 'My savings', profilePictureId: 'pfp-03');

Widget _importApp({required _RecordingAccountNotifier accountNotifier}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => MobilePasscodeScreen(
          args: const SetPasswordScreenArgs.importWallet(
            mnemonic: 'stub mnemonic words',
            birthdayHeight: 2500000,
            selectedAdditionalAccountIndices: [1, 2],
          ).withPersona(_persona),
        ),
      ),
      GoRoute(
        path: '/onboarding/biometrics',
        builder: (_, _) => const Text('biometrics route'),
      ),
    ],
  );
  return _routerHarness(router, accountNotifier);
}

Widget _createRouterApp({
  required _RecordingAccountNotifier accountNotifier,
  ValueChanged<GoRouter>? onRouter,
}) => _personaRouterApp(
  args: _createArgs,
  accountNotifier: accountNotifier,
  onRouter: onRouter,
);

Widget _personaRouterApp({
  required SetPasswordScreenArgs args,
  required _RecordingAccountNotifier accountNotifier,
  _RecordingAppSecurityNotifier? security,
  AppBootstrapRetry? reload,
  RouterRefreshController? refresh,
  ValueChanged<GoRouter>? onRouter,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => MobileCustomiseAccountScreen(
          args: CustomiseAccountArgs(setupArgs: args),
          initialPersona: _persona,
        ),
      ),
      ...mobileOnboardingRoutes().whereType<GoRoute>().where(
        (route) => route.path == '/onboarding/set-passcode',
      ),
      GoRoute(
        path: '/onboarding/biometrics',
        builder: (_, _) => const Text('biometrics route'),
      ),
      GoRoute(path: '/unlock', builder: (_, _) => const Text('unlock route')),
    ],
  );
  addTearDown(router.dispose);
  onRouter?.call(router);
  return _routerHarness(
    router,
    accountNotifier,
    security: security,
    reload: reload,
    refresh: refresh,
  );
}

Widget _routerHarness(
  GoRouter router,
  _RecordingAccountNotifier accountNotifier, {
  _RecordingAppSecurityNotifier? security,
  AppBootstrapRetry? reload,
  RouterRefreshController? refresh,
}) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    accountProvider.overrideWith(() => accountNotifier),
    appSecurityProvider.overrideWith(
      () => security ?? _RecordingAppSecurityNotifier(),
    ),
    syncProvider.overrideWith(_NoopSyncNotifier.new),
    if (reload != null) appBootstrapRetryProvider.overrideWithValue(reload),
    if (refresh != null) routerRefreshProvider.overrideWithValue(refresh),
  ],
  child: MaterialApp.router(
    routerConfig: router,
    builder: (_, c) => AppTheme(
      data: AppThemeData.light,
      child: MobileOnboardingProgressFrame(child: c!),
    ),
  ),
);

Future<void> _continuePersona(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('mobile_customise_account_name_field')),
    '  My savings  ',
  );
  await tester.tap(
    find.byKey(const ValueKey('mobile_customise_account_continue')),
  );
  await tester.pumpAndSettle();
}

void _expectSavedPersona(
  _RecordingAccountNotifier accounts,
  SetPasswordScreenArgs args,
) {
  expect(accounts.accountName, _persona.name);
  expect(accounts.pictureId, _persona.profilePictureId);
  if (args.flow == SetPasswordFlow.create) {
    expect(accounts.createdMnemonic, args.mnemonic);
  } else {
    expect(accounts.importedMnemonic, args.mnemonic);
    expect(accounts.importedBip39Passphrase, args.bip39Passphrase);
    expect(accounts.importedBirthdayHeight, args.birthdayHeight);
    expect(
      accounts.importedAdditionalAccountIndices,
      args.selectedAdditionalAccountIndices,
    );
  }
}

Future<void> _enter(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $d'));
    await tester.pump();
  }
}

double _stepsProgress(WidgetTester tester) {
  final fill = tester.widget<FractionallySizedBox>(
    find.byType(FractionallySizedBox).first,
  );
  return fill.widthFactor!;
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('repeated persona Continue opens only one credential screen', (
    tester,
  ) async {
    GoRouter? router;
    final accounts = _RecordingAccountNotifier();
    await tester.pumpWidget(
      _createRouterApp(
        accountNotifier: accounts,
        onRouter: (value) => router = value,
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<AppButton>(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Create Passcode').hitTestable(), findsOneWidget);
    router!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Customise Account').hitTestable(), findsOneWidget);
    expect(find.text('Create Passcode').hitTestable(), findsNothing);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const ValueKey('mobile_customise_account_continue')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'dismissed birthday keyboard does not compress the passcode title',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
      tester.view.viewInsets = const FakeViewPadding(bottom: 95);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Create Passcode'), findsOneWidget);
      await _enter(tester, '123456');
      expect(find.text('Confirm Passcode'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('six digits advance to the confirm phase', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Create Passcode'), findsOneWidget);
    final createTitle = tester.widget<Text>(find.text('Create Passcode'));
    expect(createTitle.style?.fontSize, AppTypography.displayLarge.fontSize);
    await _enter(tester, '12345');
    // Backspace removes a digit before completion.
    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.pump();
    await _enter(tester, '56');

    expect(find.text('Confirm Passcode'), findsOneWidget);
    final confirmTitle = tester.widget<Text>(find.text('Confirm Passcode'));
    expect(confirmTitle.style?.fontSize, AppTypography.displayLarge.fontSize);
    expect(find.text('Re-enter your passcode.'), findsOneWidget);
  });

  testWidgets('create passcode progress follows the create flow', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(_stepsProgress(tester), closeTo(0.88435374150, 0.0001));
  });

  testWidgets('import passcode progress follows the review import flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _importApp(accountNotifier: _RecordingAccountNotifier()),
    );
    await tester.pump();
    expect(_stepsProgress(tester), closeTo(0.88435374150, 0.0001));
  });

  testWidgets('a mismatched confirmation restarts with an error', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await _enter(tester, '123456');
    expect(find.text('Confirm Passcode'), findsOneWidget);

    await _enter(tester, '654321');
    expect(find.text('Create Passcode'), findsOneWidget);
    expect(find.text("Passcodes didn't match. Try again."), findsOneWidget);
  });

  testWidgets('create saves the persona only after matching confirmation', (
    tester,
  ) async {
    final accounts = _RecordingAccountNotifier();
    await tester.pumpWidget(_createRouterApp(accountNotifier: accounts));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('mobile_customise_account_name_field')),
      'My savings',
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await tester.pumpAndSettle();
    expect(accounts.createdMnemonic, isNull);
    await _enter(tester, '123456');
    expect(accounts.createdMnemonic, isNull);
    await _enter(tester, '123456');
    await tester.pumpAndSettle();
    expect(find.text('biometrics route'), findsOneWidget);
    expect(accounts.createdMnemonic, 'stub mnemonic words');
    expect(accounts.accountName, 'My savings');
  });

  testWidgets(
    'back from passcode preserves the edited persona and resets passcode',
    (tester) async {
      late GoRouter router;
      final accounts = _RecordingAccountNotifier();
      await tester.pumpWidget(
        _createRouterApp(
          accountNotifier: accounts,
          onRouter: (value) => router = value,
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('mobile_customise_account_name_field')),
        'My savings',
      );
      await tester.tap(
        find.byKey(const ValueKey('mobile_customise_account_continue')),
      );
      await tester.pumpAndSettle();
      await _enter(tester, '123456');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('My savings'), findsOneWidget);
      expect(accounts.createdMnemonic, isNull);
      expect(router.canPop(), isFalse);
      await tester.tap(
        find.byKey(const ValueKey('mobile_customise_account_continue')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create Passcode'), findsOneWidget);
    },
  );

  testWidgets('import keeps selected additional ZIP32 accounts and persona', (
    tester,
  ) async {
    final accounts = _RecordingAccountNotifier();
    await tester.pumpWidget(
      _personaRouterApp(args: _importArgs, accountNotifier: accounts),
    );
    await _continuePersona(tester);
    await _enter(tester, '123456');
    expect(accounts.importedMnemonic, isNull);
    await _enter(tester, '123456');
    await tester.pumpAndSettle();
    expect(find.text('biometrics route'), findsOneWidget);
    expect(accounts.importedMnemonic, 'stub mnemonic words');
    expect(accounts.importedBirthdayHeight, 2500000);
    expect(accounts.importedAdditionalAccountIndices, [1, 2]);
    expect(accounts.accountName, _persona.name);
    expect(accounts.pictureId, _persona.profilePictureId);
  });
  for (final args in [_createArgs, _importArgs]) {
    testWidgets(
      '${args.flow.name}: failure before saving rolls back and permits retry',
      (tester) async {
        final security = _RecordingAppSecurityNotifier();
        final accounts = _RecordingAccountNotifier(
          beforeMutation: (attempt) async {
            if (attempt == 1) throw Exception('Account save failed');
          },
        );
        await tester.pumpWidget(
          _personaRouterApp(
            args: args,
            accountNotifier: accounts,
            security: security,
          ),
        );
        await _continuePersona(tester);
        expect(security.prepareCalls, 0);
        expect(accounts.mutationCalls, 0);
        await _enter(tester, '123456');
        await _enter(tester, '123456');
        await tester.pumpAndSettle();
        expect(find.text('Create Passcode'), findsOneWidget);
        expect(find.text('Account save failed'), findsOneWidget);
        expect(security.rollbackCalls, 1);
        expect(security.commitCalls, 0);
        expect(security.preparedPassword, isNull);
        expect(accounts.createdMnemonic, isNull);
        expect(accounts.importedMnemonic, isNull);
        await _enter(tester, '654321');
        await _enter(tester, '654321');
        await tester.pumpAndSettle();
        expect(find.text('biometrics route'), findsOneWidget);
        expect(security.preparedPassword, '654321');
        expect(security.prepareCalls, 2);
        expect(security.commitCalls, 1);
        expect(accounts.mutationCalls, 2);
        _expectSavedPersona(accounts, args);
      },
    );

    testWidgets(
      '${args.flow.name}: saving blocks back and repeated confirmation',
      (tester) async {
        final saving = Completer<void>();
        final security = _RecordingAppSecurityNotifier();
        final accounts = _RecordingAccountNotifier(
          beforeMutation: (_) => saving.future,
        );
        await tester.pumpWidget(
          _personaRouterApp(
            args: args,
            accountNotifier: accounts,
            security: security,
          ),
        );
        await _continuePersona(tester);
        await _enter(tester, '123456');
        await _enter(tester, '123456');
        expect(accounts.mutationCalls, 1);
        expect(security.commitCalls, 0);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('Customise Account').hitTestable(), findsNothing);
        expect(
          tester
              .widget<MobileTopNav>(find.byType(MobileTopNav).hitTestable())
              .onBack,
          isNull,
        );
        await tester.tap(find.bySemanticsLabel('Back').hitTestable());
        await tester.pump();
        expect(find.text('Customise Account').hitTestable(), findsNothing);
        await _enter(tester, '123456');
        expect(accounts.mutationCalls, 1);
        saving.complete();
        await tester.pumpAndSettle();
        expect(find.text('biometrics route'), findsOneWidget);
        expect(security.prepareCalls, 1);
        expect(security.commitCalls, 1);
        _expectSavedPersona(accounts, args);
      },
    );

    for (final uncertain in [false, true]) {
      testWidgets(
        '${args.flow.name}: ${uncertain ? 'uncertain DB' : 'partial save'} recovers without submitting a second account',
        (tester) async {
          late GoRouter router;
          var reloadCalls = 0;
          final security = _RecordingAppSecurityNotifier();
          final accounts = _RecordingAccountNotifier(
            beforeMutation: (_) async {
              if (uncertain) {
                throw const WalletAccountStateUncertainException(
                  'DB read failed',
                );
              }
              throw const WalletAccountSetupInterruptedException(
                'saved-uuid',
                'storage failed',
              );
            },
          );
          await tester.pumpWidget(
            _personaRouterApp(
              args: args,
              accountNotifier: accounts,
              security: security,
              onRouter: (value) => router = value,
              reload: () async {
                reloadCalls++;
                if (reloadCalls == 1) throw Exception('Bootstrap unavailable');
                router.go('/unlock');
              },
            ),
          );
          await _continuePersona(tester);
          await _enter(tester, '123456');
          await _enter(tester, '123456');
          await tester.pumpAndSettle();
          expect(security.preparedPassword, '123456');
          expect(security.commitCalls, 1);
          expect(security.rollbackCalls, 0);
          expect(find.bySemanticsLabel('Digit 1'), findsNothing);
          expect(find.bySemanticsLabel('Back').hitTestable(), findsNothing);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          final retry = find.byKey(
            const ValueKey('mobile_passcode_retry_setup'),
          );
          expect(retry, findsOneWidget);
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(
            find.text("Couldn't resume setup. Please try again."),
            findsOneWidget,
          );
          expect(retry, findsOneWidget);
          expect(find.bySemanticsLabel('Digit 1'), findsNothing);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(find.text('unlock route'), findsOneWidget);
          expect(reloadCalls, 2);
          expect(accounts.mutationCalls, 1);
          expect(security.prepareCalls, 1);
          expect(security.commitCalls, 1);
          expect(security.rollbackCalls, 0);
        },
      );
    }

    for (final reloadFails in [false, true]) {
      testWidgets(
        '${args.flow.name}: lock recovery ${reloadFails ? 'failure permits retry' : 'finishes before router refresh'}',
        (tester) async {
          late GoRouter router;
          final reloadGate = Completer<void>();
          var reloadCalls = 0;
          var refreshes = 0;
          final refresh = RouterRefreshController()
            ..addListener(() => refreshes++);
          addTearDown(refresh.dispose);
          final security = _RecordingAppSecurityNotifier();
          final accounts = _RecordingAccountNotifier(
            beforeMutation: (_) async {
              security.lock();
              refresh.requestRefresh();
              throw const WalletAccountSetupInterruptedException(
                'saved-uuid',
                'session locked',
              );
            },
          );
          await tester.pumpWidget(
            _personaRouterApp(
              args: args,
              accountNotifier: accounts,
              security: security,
              refresh: refresh,
              onRouter: (value) => router = value,
              reload: () async {
                reloadCalls++;
                await reloadGate.future;
                if (reloadFails && reloadCalls == 1) {
                  throw Exception('Bootstrap unavailable');
                }
                router.go('/unlock');
              },
            ),
          );
          await _continuePersona(tester);
          await _enter(tester, '123456');
          await _enter(tester, '123456');
          expect(reloadCalls, 1);
          expect(refreshes, 0);
          expect(security.state.requiresUnlock, isTrue);
          expect(security.commitCalls, 1);
          expect(security.rollbackCalls, 0);
          await tester.binding.handlePopRoute();
          await tester.pump();
          expect(find.text('Customise Account').hitTestable(), findsNothing);
          reloadGate.complete();
          await tester.pumpAndSettle();
          if (reloadFails) {
            expect(refreshes, 0);
            expect(find.bySemanticsLabel('Digit 1'), findsNothing);
            final retry = find.byKey(
              const ValueKey('mobile_passcode_retry_setup'),
            );
            expect(retry, findsOneWidget);
            await tester.binding.handlePopRoute();
            await tester.pump();
            await tester.tap(retry);
            await tester.pumpAndSettle();
            expect(reloadCalls, 2);
          }
          expect(find.text('unlock route'), findsOneWidget);
          expect(refreshes, reloadFails ? 0 : 1);
          expect(accounts.mutationCalls, 1);
          expect(security.prepareCalls, 1);
        },
      );
    }
  }
}

class _RecordingAccountNotifier extends AccountNotifier {
  _RecordingAccountNotifier({this.beforeMutation});
  final Future<void> Function(int attempt)? beforeMutation;
  int mutationCalls = 0;
  String? createdMnemonic;
  String? accountName;
  String? pictureId;
  String? importedMnemonic;
  String? importedBip39Passphrase;
  int? importedBirthdayHeight;
  List<int>? importedAdditionalAccountIndices;

  @override
  FutureOr<AccountState> build() => const AccountState();

  @override
  Future<void> importAccount({
    required String mnemonic,
    String bip39Passphrase = '',
    int? birthdayHeight,
    String? name,
    String profilePictureId = 'pfp-01',
    List<int> additionalAccountIndices = const [],
  }) async {
    mutationCalls++;
    await beforeMutation?.call(mutationCalls);
    accountName = name;
    pictureId = profilePictureId;
    importedMnemonic = mnemonic;
    importedBip39Passphrase = bip39Passphrase;
    importedBirthdayHeight = birthdayHeight;
    importedAdditionalAccountIndices = additionalAccountIndices;
  }

  @override
  Future<void> createAccountFromMnemonic({
    required String mnemonic,
    String? name,
    String profilePictureId = 'pfp-01',
  }) async {
    mutationCalls++;
    await beforeMutation?.call(mutationCalls);
    accountName = name;
    pictureId = profilePictureId;
    createdMnemonic = mnemonic;
  }
}

class _RecordingAppSecurityNotifier extends AppSecurityNotifier {
  String? preparedPassword;
  int prepareCalls = 0;
  int commitCalls = 0;
  int rollbackCalls = 0;
  bool _locked = false;
  @override
  AppSecurityState build() {
    return const AppSecurityState(
      isPasswordConfigured: false,
      isUnlocked: true,
    );
  }

  @override
  Future<void> preparePasswordSetup(String password) async {
    prepareCalls++;
    preparedPassword = password;
  }

  @override
  Future<void> completePasswordSetup() async => commitPasswordSetup();

  @override
  void commitPasswordSetup() {
    commitCalls++;
    state = AppSecurityState(isPasswordConfigured: true, isUnlocked: !_locked);
  }

  @override
  Future<void> rollbackPasswordSetup() async {
    rollbackCalls++;
    preparedPassword = null;
  }

  @override
  void lock() {
    _locked = true;
    state = state.copyWith(isUnlocked: false);
  }
}

class _NoopSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();

  @override
  bool needsPauseForWalletMutation() => false;
}
