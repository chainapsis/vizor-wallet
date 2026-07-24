import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_button.dart';
import 'package:zcash_wallet/src/features/onboarding/create/customise_account_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/create/onboarding_split_view.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/set_password_screen.dart';

void main() {
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
          builder:
              (_, _) => const SetPasswordScreen(
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
          args: const CustomiseAccountArgs(mnemonic: _mnemonic),
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
    expect(find.text('Veiled Wardbearer'), findsOneWidget);
    expect(find.text('Finish setup'), findsOneWidget);
    expect(random.nextIntCallCount, 3);
    expect(
      tester.getSize(find.byKey(const ValueKey('customise_account_card'))),
      const Size(396, 140),
    );

    await tester.binding.setSurfaceSize(const Size(1279, 900));
    await tester.pump();
    expect(find.text('Veiled Wardbearer'), findsOneWidget);
    expect(random.nextIntCallCount, 3);

    await tester.tap(
      find.byKey(const ValueKey('customise_account_finish_button')),
    );
    await tester.pump();

    expect(submittedName, 'Veiled Wardbearer');
    expect(submittedProfilePictureId, 'pfp-03');
  });

  testWidgets('blocks empty and overlong names with the shared policy', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    var submitCount = 0;
    await tester.pumpWidget(
      _screenHarness(
        CustomiseAccountScreen(
          args: const CustomiseAccountArgs(mnemonic: _mnemonic),
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
          args: const CustomiseAccountArgs(mnemonic: _mnemonic),
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
  final geist =
      FontLoader('Geist')
        ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));
  await Future.wait([youngSerif.load(), geist.load()]);
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async => tester.binding.setSurfaceSize(null));
}

Widget _screenHarness(Widget child) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
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
      builder:
          (_, child) => AppTheme(
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
