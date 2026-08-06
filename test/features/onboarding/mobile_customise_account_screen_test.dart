@Tags(['mobile'])
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_customise_account_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_passcode_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

const _mnemonic = 'stub mnemonic words';

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(393, 852)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('keeps its random persona stable and uses the eighth progress', (
    tester,
  ) async {
    final random = _SequenceRandom([0, 1, 2, 3]);
    String? submittedName;
    String? submittedProfilePictureId;

    await tester.pumpWidget(
      _harness(
        MobileCustomiseAccountScreen(
          args: const CustomiseAccountArgs(
            setupArgs: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
          ),
          random: random,
          onFinish: (name, profilePictureId) async {
            submittedName = name;
            submittedProfilePictureId = profilePictureId;
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Customise Account'), findsOneWidget);
    expect(find.text('Windborne Wardbearer'), findsOneWidget);
    expect(_stepsProgress(tester), closeTo(mobileCreateProgress(8), 0.0001));
    expect(random.nextIntCallCount, 3);
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_customise_account_card')),
      ),
      const Size(361, 123),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_customise_account_edit_badge')),
      ),
      const Size(28, 28),
    );
    expect(
      tester.getTopLeft(
            find.byKey(const ValueKey('mobile_customise_account_edit_badge')),
          ) -
          tester.getTopLeft(
            find.byKey(
              const ValueKey('mobile_customise_account_avatar_button'),
            ),
          ),
      const Offset(34, 34),
    );
    expect(
      tester.getSize(
        find.byKey(const ValueKey('mobile_customise_account_edit_glyph_frame')),
      ),
      const Size(20, 20),
    );
    final editGlyph = tester.widget<AppIcon>(
      find.byKey(const ValueKey('mobile_customise_account_edit_glyph')),
    );
    expect(editGlyph.size, 12);

    await tester.binding.setSurfaceSize(const Size(430, 932));
    await tester.pump();
    expect(find.text('Windborne Wardbearer'), findsOneWidget);
    expect(random.nextIntCallCount, 3);

    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await tester.pump();
    expect(submittedName, 'Windborne Wardbearer');
    expect(submittedProfilePictureId, 'pfp-03');
  });

  testWidgets('uses the shared account name validation', (tester) async {
    var submitCount = 0;
    await tester.pumpWidget(
      _harness(
        MobileCustomiseAccountScreen(
          args: const CustomiseAccountArgs(
            setupArgs: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
          ),
          onFinish: (_, _) async => submitCount += 1,
        ),
      ),
    );

    final field = find.byKey(
      const ValueKey('mobile_customise_account_name_field'),
    );
    await tester.enterText(field, '   ');
    await tester.pump();
    expect(_continueButton(tester).onPressed, isNull);

    await tester.enterText(field, '123456789012345678901');
    await tester.pump();
    expect(find.text('Name can be up to 20 characters.'), findsOneWidget);
    expect(_continueButton(tester).onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await tester.pump();
    expect(submitCount, 0);
  });

  testWidgets('uses the existing mobile profile picture picker', (
    tester,
  ) async {
    String? submittedProfilePictureId;
    await tester.pumpWidget(
      _harness(
        MobileCustomiseAccountScreen(
          args: const CustomiseAccountArgs(
            setupArgs: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
          ),
          onFinish: (_, profilePictureId) async {
            submittedProfilePictureId = profilePictureId;
          },
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_avatar_button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Select profile picture'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('mobile_account_pfp_option_pfp-02')),
    );
    await tester.tap(find.byKey(const ValueKey('mobile_account_pfp_update')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await tester.pump();
    expect(submittedProfilePictureId, 'pfp-02');
  });

  testWidgets('blocks route pops while account creation is in flight', (
    tester,
  ) async {
    final finish = Completer<void>();
    await tester.pumpWidget(
      _harness(
        MobileCustomiseAccountScreen(
          args: const CustomiseAccountArgs(
            setupArgs: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
          ),
          onFinish: (_, _) => finish.future,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await tester.pump();

    final popScope = find.byWidgetPredicate(
      (widget) => widget is PopScope<void>,
    );
    expect(tester.widget<PopScope<void>>(popScope).canPop, isFalse);

    finish.complete();
    await tester.pump();

    expect(tester.widget<PopScope<void>>(popScope).canPop, isTrue);
  });

  testWidgets('back is safe in the router-free Widgetbook preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const MobileCustomiseAccountScreen(
          args: CustomiseAccountArgs(
            setupArgs: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
            pendingPassword: '123456',
          ),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Customise Account'), findsOneWidget);
  });

  testWidgets('returning to passcode does not reopen the phrase back stack', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const MobileCustomiseAccountScreen(
            args: CustomiseAccountArgs(
              setupArgs: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
              pendingPassword: '123456',
            ),
          ),
        ),
        GoRoute(
          path: '/onboarding/set-passcode',
          builder: (_, state) =>
              MobilePasscodeScreen(args: state.extra! as SetPasswordScreenArgs),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, c) => AppTheme(data: AppThemeData.dark, child: c!),
        ),
      ),
    );

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Create Passcode'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsNothing);
  });

  testWidgets('creates the initial account with the selected persona', (
    tester,
  ) async {
    final accountNotifier = _RecordingAccountNotifier();
    final securityNotifier = _RecordingSecurityNotifier();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MobileCustomiseAccountScreen(
            args: const CustomiseAccountArgs(
              setupArgs: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
              pendingPassword: '123456',
            ),
            random: _SequenceRandom([0, 1, 2]),
          ),
        ),
        GoRoute(
          path: '/onboarding/biometrics',
          builder: (_, _) => const Text('biometrics route'),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(() => accountNotifier),
          appSecurityProvider.overrideWith(() => securityNotifier),
          syncProvider.overrideWith(_NoopSyncNotifier.new),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, c) => AppTheme(data: AppThemeData.dark, child: c!),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('mobile_customise_account_name_field')),
      '  Gentle Warden  ',
    );
    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await tester.pumpAndSettle();

    expect(securityNotifier.preparedPassword, '123456');
    expect(securityNotifier.committed, isTrue);
    expect(accountNotifier.createdMnemonic, _mnemonic);
    expect(accountNotifier.createdName, 'Gentle Warden');
    expect(accountNotifier.createdProfilePictureId, 'pfp-03');
    expect(find.text('biometrics route'), findsOneWidget);
  });

  testWidgets('creates an additional account without reconfiguring security', (
    tester,
  ) async {
    final accountNotifier = _RecordingAccountNotifier();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MobileCustomiseAccountScreen(
            args: const CustomiseAccountArgs(
              setupArgs: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
            ),
            random: _SequenceRandom([0, 1, 2]),
          ),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(() => accountNotifier),
          syncProvider.overrideWith(_NoopSyncNotifier.new),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, c) => AppTheme(data: AppThemeData.dark, child: c!),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await tester.pumpAndSettle();

    expect(accountNotifier.createdMnemonic, _mnemonic);
    expect(accountNotifier.createdName, 'Windborne Wardbearer');
    expect(accountNotifier.createdProfilePictureId, 'pfp-03');
    expect(find.text('home route'), findsOneWidget);
  });

  testWidgets('derives an account without passing a mnemonic through the UI', (
    tester,
  ) async {
    final accountNotifier = _RecordingAccountNotifier();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MobileCustomiseAccountScreen(
            args: const CustomiseAccountArgs.derive(
              deriveFromAccountUuid: 'software-account',
            ),
            random: _SequenceRandom([0, 1, 2]),
          ),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(() => accountNotifier),
          syncProvider.overrideWith(_NoopSyncNotifier.new),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.dark, child: child!),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await tester.pumpAndSettle();

    expect(accountNotifier.derivedSourceAccountUuid, 'software-account');
    expect(accountNotifier.createdMnemonic, isNull);
    expect(accountNotifier.createdName, 'Windborne Wardbearer');
    expect(accountNotifier.createdProfilePictureId, 'pfp-03');
    expect(find.text('home route'), findsOneWidget);
  });

  testWidgets('imports a software draft with the selected persona', (
    tester,
  ) async {
    final accountNotifier = _RecordingAccountNotifier();
    const setupArgs = SetPasswordScreenArgs.importWallet(
      mnemonic: _mnemonic,
      bip39Passphrase: 'extra words',
      birthdayHeight: 2500000,
      selectedAdditionalAccountIndices: [2],
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MobileCustomiseAccountScreen(
            args: const CustomiseAccountArgs(setupArgs: setupArgs),
            random: _SequenceRandom([0, 1, 2]),
          ),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(() => accountNotifier),
          syncProvider.overrideWith(_NoopSyncNotifier.new),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, c) => AppTheme(data: AppThemeData.dark, child: c!),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await tester.pumpAndSettle();

    expect(accountNotifier.importedMnemonic, _mnemonic);
    expect(accountNotifier.importedBip39Passphrase, 'extra words');
    expect(accountNotifier.importedBirthdayHeight, 2500000);
    expect(accountNotifier.importedAdditionalAccountIndices, [2]);
    expect(accountNotifier.importedName, 'Windborne Wardbearer');
    expect(accountNotifier.importedProfilePictureId, 'pfp-03');
    expect(find.text('home route'), findsOneWidget);
  });

  testWidgets('imports a Keystone draft with the selected persona', (
    tester,
  ) async {
    final accountNotifier = _RecordingAccountNotifier();
    const setupArgs = SetPasswordScreenArgs.importKeystone(
      name: 'Keystone account',
      ufvk: 'uview-test',
      seedFingerprint: [1, 2, 3, 4],
      zip32Index: 7,
      birthdayHeight: 2500000,
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MobileCustomiseAccountScreen(
            args: const CustomiseAccountArgs(setupArgs: setupArgs),
            random: _SequenceRandom([0, 1, 2]),
          ),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('home route')),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountProvider.overrideWith(() => accountNotifier),
          syncProvider.overrideWith(_NoopSyncNotifier.new),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, c) => AppTheme(data: AppThemeData.dark, child: c!),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('mobile_customise_account_continue')),
    );
    await tester.pumpAndSettle();

    expect(accountNotifier.keystoneName, 'Windborne Wardbearer');
    expect(accountNotifier.keystoneProfilePictureId, 'pfp-03');
    expect(accountNotifier.keystoneUfvk, 'uview-test');
    expect(accountNotifier.keystoneZip32Index, 7);
    expect(find.text('home route'), findsOneWidget);
  });
}

double _stepsProgress(WidgetTester tester) {
  final fill = tester.widget<FractionallySizedBox>(
    find.byType(FractionallySizedBox).first,
  );
  return fill.widthFactor!;
}

AppButton _continueButton(WidgetTester tester) => tester.widget<AppButton>(
  find.byKey(const ValueKey('mobile_customise_account_continue')),
);

Widget _harness(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.dark, child: c!),
      home: child,
    ),
  );
}

class _SequenceRandom implements Random {
  _SequenceRandom(this._values);

  final List<int> _values;
  var _index = 0;

  int get nextIntCallCount => _index;

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1 << 26) / (1 << 26);

  @override
  int nextInt(int max) {
    final value = _values[_index++ % _values.length];
    return value % max;
  }
}

class _RecordingAccountNotifier extends AccountNotifier {
  String? createdMnemonic;
  String? derivedSourceAccountUuid;
  String? createdName;
  String? createdProfilePictureId;
  String? importedMnemonic;
  String? importedBip39Passphrase;
  int? importedBirthdayHeight;
  List<int>? importedAdditionalAccountIndices;
  String? importedName;
  String? importedProfilePictureId;
  String? keystoneName;
  String? keystoneProfilePictureId;
  String? keystoneUfvk;
  int? keystoneZip32Index;

  @override
  FutureOr<AccountState> build() => const AccountState();

  @override
  Future<void> createAccountFromMnemonic({
    required String mnemonic,
    String? name,
    String profilePictureId = 'pfp-01',
  }) async {
    createdMnemonic = mnemonic;
    createdName = name;
    createdProfilePictureId = profilePictureId;
  }

  @override
  Future<void> deriveAccountFromExistingSeed({
    required String sourceAccountUuid,
    String? name,
    String profilePictureId = 'pfp-01',
  }) async {
    derivedSourceAccountUuid = sourceAccountUuid;
    createdName = name;
    createdProfilePictureId = profilePictureId;
  }

  @override
  Future<void> importAccount({
    required String mnemonic,
    String bip39Passphrase = '',
    int? birthdayHeight,
    String? name,
    String profilePictureId = 'pfp-01',
    List<int> additionalAccountIndices = const [],
  }) async {
    importedMnemonic = mnemonic;
    importedBip39Passphrase = bip39Passphrase;
    importedBirthdayHeight = birthdayHeight;
    importedAdditionalAccountIndices = additionalAccountIndices;
    importedName = name;
    importedProfilePictureId = profilePictureId;
  }

  @override
  Future<void> importKeystoneAccount({
    required String name,
    required String ufvk,
    required List<int> seedFingerprint,
    required int zip32Index,
    required int birthdayHeight,
    String profilePictureId = 'pfp-01',
  }) async {
    keystoneName = name;
    keystoneProfilePictureId = profilePictureId;
    keystoneUfvk = ufvk;
    keystoneZip32Index = zip32Index;
  }
}

class _RecordingSecurityNotifier extends AppSecurityNotifier {
  String? preparedPassword;
  var committed = false;

  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: false, isUnlocked: true);

  @override
  Future<void> preparePasswordSetup(String password) async {
    preparedPassword = password;
  }

  @override
  void commitPasswordSetup() {
    committed = true;
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
