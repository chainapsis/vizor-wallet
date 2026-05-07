import 'dart:ui' show Size;

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/create/intro_zcash_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/create/onboarding_split_view.dart';
import 'package:zcash_wallet/src/features/onboarding/create/secret_passphrase_screen.dart';

void main() {
  testWidgets('reuses pending create mnemonic when returning to passphrase', (
    tester,
  ) async {
    await _setDesktopViewport(tester);
    final container = _providerContainer();
    addTearDown(container.dispose);
    container
        .read(createOnboardingMnemonicProvider.notifier)
        .setMnemonic(_mnemonic);
    container
        .read(onboardingSecretPassphraseRevealedProvider.notifier)
        .setRevealed(true);

    await tester.pumpWidget(
      _harness(container, const SecretPassphraseScreen()),
    );
    await tester.pump();

    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('xray'), findsOneWidget);
    expect(container.read(createOnboardingMnemonicProvider), _mnemonic);
  });

  testWidgets('intro clears pending create mnemonic', (tester) async {
    await _setDesktopViewport(tester);
    final container = _providerContainer();
    addTearDown(container.dispose);
    container
        .read(createOnboardingMnemonicProvider.notifier)
        .setMnemonic(_mnemonic);
    container
        .read(onboardingSecretPassphraseRevealedProvider.notifier)
        .setRevealed(true);

    await tester.pumpWidget(_harness(container, const IntroZcashScreen()));
    await tester.pump();

    expect(container.read(createOnboardingMnemonicProvider), isNull);
    expect(container.read(onboardingSecretPassphraseRevealedProvider), isFalse);
  });
}

Future<void> _setDesktopViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

ProviderContainer _providerContainer() {
  return ProviderContainer(
    overrides: [
      appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    ],
  );
}

Widget _harness(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: AppTheme(data: AppThemeData.light, child: child),
    ),
  );
}

const _mnemonic =
    'alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima '
    'mike november oscar papa quebec romeo sierra tango uniform victor whiskey '
    'xray';
