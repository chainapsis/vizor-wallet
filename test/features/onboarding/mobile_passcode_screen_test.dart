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
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_onboarding_routes.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_customise_account_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/account_persona_draft.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_passcode_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

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
      home: const MobilePasscodeScreen(
        args: SetPasswordScreenArgs.create(mnemonic: 'stub mnemonic words'),
      ),
    ),
  );
}

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
}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const MobileCustomiseAccountScreen(
          args: CustomiseAccountArgs(
            setupArgs: SetPasswordScreenArgs.create(
              mnemonic: 'stub mnemonic words',
            ),
          ),
        ),
      ),
      ...mobileOnboardingRoutes().whereType<GoRoute>().where(
        (route) => route.path == '/onboarding/set-passcode',
      ),
      GoRoute(
        path: '/onboarding/biometrics',
        builder: (_, _) => const Text('biometrics route'),
      ),
    ],
  );
  onRouter?.call(router);
  return _routerHarness(router, accountNotifier);
}

Widget _routerHarness(
  GoRouter router,
  _RecordingAccountNotifier accountNotifier,
) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    accountProvider.overrideWith(() => accountNotifier),
    appSecurityProvider.overrideWith(_RecordingAppSecurityNotifier.new),
    syncProvider.overrideWith(_NoopSyncNotifier.new),
  ],
  child: MaterialApp.router(
    routerConfig: router,
    builder: (_, c) => AppTheme(
      data: AppThemeData.light,
      child: MobileOnboardingProgressFrame(child: c!),
    ),
  ),
);

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
    await tester.pumpWidget(_importApp(accountNotifier: accounts));
    await tester.pump();
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
}

class _RecordingAccountNotifier extends AccountNotifier {
  String? createdMnemonic;
  String? accountName;
  String? pictureId;
  String? importedMnemonic;
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
    accountName = name;
    pictureId = profilePictureId;
    importedMnemonic = mnemonic;
    importedBirthdayHeight = birthdayHeight;
    importedAdditionalAccountIndices = additionalAccountIndices;
  }

  @override
  Future<void> createAccountFromMnemonic({
    required String mnemonic,
    String? name,
    String profilePictureId = 'pfp-01',
  }) async {
    accountName = name;
    pictureId = profilePictureId;
    createdMnemonic = mnemonic;
  }
}

class _RecordingAppSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() {
    return const AppSecurityState(
      isPasswordConfigured: false,
      isUnlocked: true,
    );
  }

  @override
  Future<void> preparePasswordSetup(String password) async {}

  @override
  Future<void> completePasswordSetup() async => commitPasswordSetup();

  @override
  void commitPasswordSetup() {
    state = const AppSecurityState(
      isPasswordConfigured: true,
      isUnlocked: true,
    );
  }

  @override
  Future<void> rollbackPasswordSetup() async {}
}

class _NoopSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();

  @override
  bool needsPauseForWalletMutation() => false;
}
