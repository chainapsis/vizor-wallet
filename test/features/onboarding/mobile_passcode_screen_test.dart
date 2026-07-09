@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_passcode_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

Widget _app() {
  return ProviderScope(
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: const MobilePasscodeScreen(
        args: SetPasswordScreenArgs.create(mnemonic: 'stub mnemonic words'),
      ),
    ),
  );
}

Widget _importApp({required _RecordingAccountNotifier accountNotifier}) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const MobilePasscodeScreen(
          args: SetPasswordScreenArgs.importWallet(
            mnemonic: 'stub mnemonic words',
            birthdayHeight: 2500000,
            selectedAdditionalAccountIndices: [1, 2],
          ),
        ),
      ),
      GoRoute(
        path: '/onboarding/biometrics',
        builder: (_, _) => const Text('biometrics route'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      accountProvider.overrideWith(() => accountNotifier),
      appSecurityProvider.overrideWith(() => _RecordingAppSecurityNotifier()),
      syncProvider.overrideWith(() => _NoopSyncNotifier()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
    ),
  );
}

Future<void> _enter(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $d'));
    await tester.pump();
  }
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

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

  testWidgets('import flow forwards selected additional ZIP32 accounts', (
    tester,
  ) async {
    final accountNotifier = _RecordingAccountNotifier();

    await tester.pumpWidget(_importApp(accountNotifier: accountNotifier));
    await tester.pump();

    await _enter(tester, '123456');
    await _enter(tester, '123456');
    await tester.pumpAndSettle();

    expect(accountNotifier.importedMnemonic, 'stub mnemonic words');
    expect(accountNotifier.importedBirthdayHeight, 2500000);
    expect(accountNotifier.importedAdditionalAccountIndices, [1, 2]);
    expect(find.text('biometrics route'), findsOneWidget);
  });
}

class _RecordingAccountNotifier extends AccountNotifier {
  String? importedMnemonic;
  int? importedBirthdayHeight;
  List<int>? importedAdditionalAccountIndices;

  @override
  FutureOr<AccountState> build() => const AccountState();

  @override
  Future<void> importAccount({
    required String mnemonic,
    int? birthdayHeight,
    String? name,
    List<int> additionalAccountIndices = const [],
  }) async {
    importedMnemonic = mnemonic;
    importedBirthdayHeight = birthdayHeight;
    importedAdditionalAccountIndices = additionalAccountIndices;
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
