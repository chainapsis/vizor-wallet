import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/router_refresh_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/create/customise_account_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/create/onboarding_split_view.dart';
import 'package:zcash_wallet/src/features/onboarding/ledger/ledger_connect_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/set_password_screen.dart';

void main() {
  testWidgets('Ledger duplicate error preserves branding and permits retry', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    var attempts = 0;
    Future<void> failImport(String name, String profilePictureId) async {
      attempts++;
      throw Exception('This Ledger account is already in your wallet.');
    }

    await tester.pumpWidget(
      _screenHarness(
        CustomiseAccountScreen.ledger(
          onFinish: failImport,
          ledgerBackTarget: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final submit = find.byKey(
      const ValueKey('customise_account_finish_button'),
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(
      find.text('This Ledger account is already in your wallet.'),
      findsOneWidget,
    );
    expect(
      find.text('This Keystone account is already in your wallet.'),
      findsNothing,
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  for (final ledger in [false, true]) {
    for (final uncertain in [false, true]) {
      testWidgets(
        'interrupted setup retries bootstrap, ledger=$ledger uncertain=$uncertain',
        (tester) async {
          await _setDesktopViewport(tester);
          var imports = 0;
          var reloads = 0;
          final security = _RecoverySecurity();
          Future<void> fail(String _, String _) async {
            imports++;
            if (uncertain) {
              throw WalletAccountStateUncertainException(
                StateError('DB unavailable'),
              );
            }
            throw WalletAccountSetupInterruptedException(
              null,
              StateError('save failed'),
            );
          }

          await tester.pumpWidget(
            _screenHarness(
              ledger
                  ? CustomiseAccountScreen.ledger(
                      onFinish: fail,
                      ledgerBackTarget: const OnboardingBackTarget.route(
                        label: 'Set Password',
                        routePath: '/onboarding/ledger/set-password',
                      ),
                    )
                  : CustomiseAccountScreen(
                      args: const CustomiseAccountArgs(
                        setupArgs: SetPasswordScreenArgs.create(
                          mnemonic: _mnemonic,
                        ),
                        pendingPassword: 'Password1!',
                      ),
                      onFinish: fail,
                    ),
              overrides: [
                appSecurityProvider.overrideWith(() => security),
                appBootstrapRetryProvider.overrideWithValue(() async {
                  reloads++;
                  expect(security.state.requiresUnlock, isTrue);
                  if (reloads == 1) {
                    throw StateError('temporary reload failure');
                  }
                }),
              ],
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('customise_account_finish_button')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Retry setup'), findsOneWidget);
          expect(
            find.text('Setup interrupted. Retry to recover your wallet.'),
            findsOneWidget,
          );
          expect(
            tester
                .renderObject<RenderParagraph>(
                  find.text('Setup interrupted. Retry to recover your wallet.'),
                )
                .didExceedMaxLines,
            isFalse,
          );
          if (!ledger) {
            expect(
              tester
                  .widget<OnboardingTrailingPane>(
                    find.byType(OnboardingTrailingPane),
                  )
                  .backTarget,
              isNull,
            );
          } else {
            expect(
              tester
                  .widget<LedgerOnboardingShell>(
                    find.byType(LedgerOnboardingShell),
                  )
                  .backTarget,
              isNull,
            );
          }

          expect(
            tester.widget<TextField>(find.byType(TextField)).enabled,
            isFalse,
          );
          await tester.tap(find.text('Retry setup'));
          await tester.pumpAndSettle();
          expect(
            find.text("Couldn't resume setup. Please try again."),
            findsOneWidget,
          );
          await tester.tap(find.text('Retry setup'));
          await tester.pumpAndSettle();
          expect(imports, 1);
          expect(reloads, 2);
          expect(find.text('Recovering wallet...'), findsOneWidget);
          expect(_finishButton(tester).onPressed, isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'lock during setup reloads before router refresh exposes unlock',
    (tester) async {
      await _setDesktopViewport(tester);
      final security = _RecoverySecurity();
      final refresh = RouterRefreshController();
      addTearDown(refresh.dispose);
      final reload = Completer<void>();
      var reloads = 0;
      var refreshes = 0;
      refresh.addListener(() => refreshes++);
      await tester.pumpWidget(
        _screenHarness(
          CustomiseAccountScreen(
            args: const CustomiseAccountArgs(
              setupArgs: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
              pendingPassword: 'Password1!',
            ),
            onFinish: (_, _) async {
              security.lock();
              refresh.requestRefresh();
              throw WalletAccountSetupInterruptedException(
                null,
                StateError('locked'),
              );
            },
          ),
          overrides: [
            appSecurityProvider.overrideWith(() => security),
            routerRefreshProvider.overrideWithValue(refresh),
            appBootstrapRetryProvider.overrideWithValue(() async {
              reloads++;
              await reload.future;
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      ProviderScope.containerOf(
        tester.element(find.byType(CustomiseAccountScreen)),
      ).read(appSecurityProvider);
      await tester.tap(
        find.byKey(const ValueKey('customise_account_finish_button')),
      );
      await tester.pump();
      expect(reloads, 1);
      expect(refreshes, 0);
      expect(find.text('Recovering wallet...'), findsOneWidget);
      reload.complete();
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  setUpAll(_loadAppFonts);

  test('customise account is the final create-onboarding step', () {
    expect(OnboardingStep.customiseAccount.label, 'Customise wallet');
    expect(
      OnboardingStep.customiseAccount.routePath,
      '/onboarding/customise-account',
    );
    expect(
      onboardingStepFromLocation('/onboarding/customise-account'),
      OnboardingStep.customiseAccount,
    );
  });

  for (final setupArgs in _setupArgsByFlow) {
    testWidgets('autofocuses the account name for ${setupArgs.flow.name}', (
      tester,
    ) async {
      await _setDesktopViewport(tester);
      await tester.pumpWidget(
        _screenHarness(
          CustomiseAccountScreen(
            args: CustomiseAccountArgs(setupArgs: setupArgs),
            random: _SequenceRandom([0, 1, 2]),
            onFinish: (_, _) async {},
          ),
        ),
      );
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('customise_account_name_field')),
      );
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('customise_account_name_field')),
          matching: find.byType(EditableText),
        ),
      );

      expect(field.autofocus, isTrue);
      expect(editable.focusNode.hasFocus, isTrue);
      expect(
        field.controller!.selection,
        TextSelection.collapsed(offset: field.controller!.text.length),
      );
    });
  }

  testWidgets('set password continues to customise without creating a wallet', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    CustomiseAccountArgs? routedArgs;
    final router = GoRouter(
      initialLocation: '/onboarding/set-password',
      routes: [
        GoRoute(
          path: '/onboarding/set-password',
          builder: (_, _) => const SetPasswordScreen(
            args: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
          ),
        ),
        GoRoute(
          path: '/onboarding/customise-account',
          builder: (_, state) {
            routedArgs = state.extra! as CustomiseAccountArgs;
            return const Text('Customise destination');
          },
        ),
      ],
    );

    await tester.pumpWidget(_routerHarness(router));
    expect(
      tester
          .widget<OnboardingTrailingPane>(find.byType(OnboardingTrailingPane))
          .backTarget,
      isNull,
    );
    await tester.enterText(find.byType(TextField).at(0), 'Password1!');
    await tester.enterText(find.byType(TextField).at(1), 'Password1!');
    await tester.pump();

    expect(find.text('Set password & continue'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('set_password_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Customise destination'), findsOneWidget);
    expect(routedArgs?.mnemonic, _mnemonic);
    expect(routedArgs?.pendingPassword, 'Password1!');
  });

  testWidgets('import password forwards its complete draft to customise', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    CustomiseAccountArgs? routedArgs;
    const setupArgs = SetPasswordScreenArgs.importWallet(
      mnemonic: _mnemonic,
      bip39Passphrase: 'hidden words',
      birthdayHeight: 2500000,
      selectedAdditionalAccountIndices: [1, 2],
    );
    final router = GoRouter(
      initialLocation: '/import/set-password',
      routes: [
        GoRoute(
          path: '/import/set-password',
          builder: (_, _) => const SetPasswordScreen(args: setupArgs),
        ),
        GoRoute(
          path: '/import/customise-account',
          builder: (_, state) {
            routedArgs = state.extra! as CustomiseAccountArgs;
            return const Text('Import customise destination');
          },
        ),
      ],
    );

    await tester.pumpWidget(_routerHarness(router));
    await tester.enterText(find.byType(TextField).at(0), 'Password1!');
    await tester.enterText(find.byType(TextField).at(1), 'Password1!');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('set_password_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Import customise destination'), findsOneWidget);
    expect(routedArgs?.flow, SetPasswordFlow.importWallet);
    expect(routedArgs?.pendingPassword, 'Password1!');
    expect(routedArgs?.setupArgs.bip39Passphrase, 'hidden words');
    expect(routedArgs?.setupArgs.selectedAdditionalAccountIndices, [1, 2]);
  });

  testWidgets('generates its draft once and keeps it across rebuilds', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    String? submittedName;
    String? submittedProfilePictureId;
    final random = _SequenceRandom([0, 1, 2, 3, 4, 5]);

    await tester.pumpWidget(
      _screenHarness(
        CustomiseAccountScreen(
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
    expect(find.text('Finish setup'), findsOneWidget);
    expect(random.nextIntCallCount, 3);
    expect(
      tester.getSize(find.byKey(const ValueKey('customise_account_card'))),
      const Size(396, 140),
    );

    await tester.binding.setSurfaceSize(const Size(1279, 900));
    await tester.pump();
    expect(find.text('Windborne Wardbearer'), findsOneWidget);
    expect(random.nextIntCallCount, 3);

    await tester.tap(
      find.byKey(const ValueKey('customise_account_finish_button')),
    );
    await tester.pump();

    expect(submittedName, 'Windborne Wardbearer');
    expect(submittedProfilePictureId, 'pfp-03');
    expect(
      tester
          .widget<OnboardingTrailingPane>(find.byType(OnboardingTrailingPane))
          .backTarget,
      isNotNull,
    );
  });

  testWidgets('submits the trimmed edited account name', (tester) async {
    await _setDesktopViewport(tester);
    String? submittedName;
    await tester.pumpWidget(
      _screenHarness(
        CustomiseAccountScreen(
          args: const CustomiseAccountArgs(
            setupArgs: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
          ),
          onFinish: (name, _) async => submittedName = name,
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('customise_account_name_field')),
      '  My spending account  ',
    );
    await tester.tap(
      find.byKey(const ValueKey('customise_account_finish_button')),
    );
    await tester.pump();

    expect(submittedName, 'My spending account');
  });

  testWidgets('blocks empty and overlong names with the shared policy', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    var submitCount = 0;
    await tester.pumpWidget(
      _screenHarness(
        CustomiseAccountScreen(
          args: const CustomiseAccountArgs(
            setupArgs: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
          ),
          onFinish: (_, _) async => submitCount += 1,
        ),
      ),
    );

    final field = find.byKey(const ValueKey('customise_account_name_field'));
    await tester.enterText(field, '   ');
    await tester.pump();
    expect(_finishButton(tester).onPressed, isNull);

    await tester.enterText(field, '123456789012345678901');
    await tester.pump();
    expect(find.text('Name can be up to 20 characters.'), findsOneWidget);
    expect(_finishButton(tester).onPressed, isNull);

    await tester.tap(
      find.byKey(const ValueKey('customise_account_finish_button')),
    );
    await tester.pump();
    expect(submitCount, 0);
  });

  testWidgets('picks a profile picture before finishing setup', (tester) async {
    await _setDesktopViewport(tester);
    String? submittedProfilePictureId;
    await tester.pumpWidget(
      _screenHarness(
        CustomiseAccountScreen(
          random: _SequenceRandom([0, 0, 0]),
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
      find.byKey(const ValueKey('customise_account_avatar_button')),
    );
    await tester.pump();
    expect(find.text('Select profile picture'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('customise_account_pfp_option_pfp-02')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('customise_account_pfp_update')),
    );
    await tester.pump();
    expect(find.text('Select profile picture'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('customise_account_finish_button')),
    );
    await tester.pump();
    expect(submittedProfilePictureId, 'pfp-02');
  });

  testWidgets('disables the back target while wallet creation is in flight', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final finish = Completer<void>();
    await tester.pumpWidget(
      _screenHarness(
        CustomiseAccountScreen(
          args: const CustomiseAccountArgs(
            setupArgs: SetPasswordScreenArgs.create(mnemonic: _mnemonic),
            pendingPassword: 'Password1!',
          ),
          onFinish: (_, _) => finish.future,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('customise_account_finish_button')),
    );
    await tester.pump();

    expect(
      tester
          .widget<OnboardingTrailingPane>(find.byType(OnboardingTrailingPane))
          .backTarget,
      isNull,
    );

    finish.complete();
    await tester.pump();

    expect(
      tester
          .widget<OnboardingTrailingPane>(find.byType(OnboardingTrailingPane))
          .backTarget,
      isNotNull,
    );
  });
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

AppButton _finishButton(WidgetTester tester) => tester.widget<AppButton>(
  find.byKey(const ValueKey('customise_account_finish_button')),
);

Future<void> _loadAppFonts() async {
  final youngSerif = FontLoader('Young Serif')
    ..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'));
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));
  await Future.wait([youngSerif.load(), geist.load()]);
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async => tester.binding.setSurfaceSize(null));
}

Widget _screenHarness(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
      ...overrides,
    ],
    child: MaterialApp(
      home: AppTheme(
        data: AppThemeData.dark,
        child: Material(color: Colors.transparent, child: child),
      ),
    ),
  );
}

Widget _routerHarness(GoRouter router) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(
        data: AppThemeData.dark,
        child: Material(color: Colors.transparent, child: child!),
      ),
    ),
  );
}

const _mnemonic =
    'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima '
    'mike november oscar papa quebec romeo sierra tango uniform victor whiskey '
    'xray';

const _setupArgsByFlow = <SetPasswordScreenArgs>[
  SetPasswordScreenArgs.create(mnemonic: _mnemonic),
  SetPasswordScreenArgs.importWallet(
    mnemonic: _mnemonic,
    birthdayHeight: 2500000,
  ),
  SetPasswordScreenArgs.importKeystone(
    name: 'Keystone account',
    ufvk: 'uview-test',
    seedFingerprint: [1, 2, 3, 4],
    zip32Index: 0,
    birthdayHeight: 2500000,
  ),
];

class _RecoverySecurity extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: true);

  @override
  void lock() => state = state.copyWith(isUnlocked: false);
}
