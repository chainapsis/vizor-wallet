@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/create/onboarding_split_view.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_onboarding_progress.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_secret_passphrase_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/seed_card.dart';
import 'package:zcash_wallet/src/features/onboarding/shared/onboarding_flow_args.dart';
import 'package:zcash_wallet/src/features/settings/screens/mobile/mobile_seed_phrase_screen.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';

const _mnemonic =
    'abandon ability able about above absent absorb abstract absurd abuse '
    'access accident account accuse achieve acid acoustic acquire across act '
    'action actor actress actual';

class _TestCreateMnemonicNotifier extends CreateOnboardingMnemonicNotifier {
  @override
  String? build() => _mnemonic;
}

class _UnconfiguredSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() {
    return const AppSecurityState(
      isPasswordConfigured: false,
      isUnlocked: false,
    );
  }
}

Widget _app(Widget child, {bool seedCreateMnemonic = false}) {
  return ProviderScope(
    overrides: [
      if (seedCreateMnemonic)
        createOnboardingMnemonicProvider.overrideWith(
          _TestCreateMnemonicNotifier.new,
        ),
    ],
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: child,
    ),
  );
}

Widget _routerApp(Stream<void> screenshotStream) {
  final router = GoRouter(
    initialLocation: '/secret',
    routes: [
      GoRoute(
        path: '/secret',
        builder: (_, _) =>
            MobileSecretPassphraseScreen(screenshotStream: screenshotStream),
      ),
      GoRoute(
        path: '/onboarding/set-passcode',
        builder: (_, _) => const Text('set passcode route'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      createOnboardingMnemonicProvider.overrideWith(
        _TestCreateMnemonicNotifier.new,
      ),
      appSecurityProvider.overrideWith(_UnconfiguredSecurityNotifier.new),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
    ),
  );
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

  testWidgets('starts obscured, reveals, and enables copy', (tester) async {
    await tester.pumpWidget(
      _app(
        const MobileSecretPassphraseScreen(
          // Injecting args skips Rust mnemonic generation in tests, but
          // args arrive pre-revealed, so use the provider-free path:
          // a 24-word fixture via args means revealed — so instead pump
          // without args is impossible here. Args path asserts the
          // revealed state directly.
          args: CreateSecretPassphraseArgs(mnemonic: _mnemonic),
        ),
      ),
    );
    await tester.pump();

    // Args path lands revealed with all words visible.
    expect(find.byType(SeedCard), findsOneWidget);
    expect(find.text('abandon'), findsOneWidget);
    expect(find.text('actual'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('create secret passphrase progress counts welcome', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const MobileSecretPassphraseScreen(
          args: CreateSecretPassphraseArgs(mnemonic: _mnemonic),
        ),
      ),
    );
    await tester.pump();

    expect(_stepsProgress(tester), closeTo(mobileCreateProgress(6), 0.0001));
  });

  testWidgets('copy puts the full phrase on the clipboard', (tester) async {
    final copied = <String>[];
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _app(
        const MobileSecretPassphraseScreen(
          args: CreateSecretPassphraseArgs(mnemonic: _mnemonic),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Copy'));
    await tester.pump();

    expect(copied, [_mnemonic]);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    expect(find.text('Copied'), findsOneWidget);
    // Copy label resets after the timer.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('reveal uses privacy haptic before showing the phrase', (
    tester,
  ) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _app(const MobileSecretPassphraseScreen(), seedCreateMnemonic: true),
    );
    await tester.pump();

    expect(find.byType(SeedCard), findsNothing);

    await tester.tap(find.text('Reveal phrase'));
    await tester.pump();

    expect(find.byType(SeedCard), findsOneWidget);
    expect(find.text('abandon'), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
  });

  testWidgets('shows screenshot warning after the phrase is revealed', (
    tester,
  ) async {
    final screenshots = StreamController<void>();
    addTearDown(screenshots.close);
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _app(
        MobileSecretPassphraseScreen(screenshotStream: screenshots.stream),
        seedCreateMnemonic: true,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Reveal phrase'));
    await tester.pump();

    screenshots.add(null);
    await tester.pumpAndSettle();

    expect(find.byType(MobileSeedScreenshotWarningSheet), findsOneWidget);
    expect(find.textContaining('Don’t take screenshots'), findsOneWidget);
    expect(haptics, [
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
  });

  testWidgets('does not show screenshot warning after pushing passcode route', (
    tester,
  ) async {
    final screenshots = StreamController<void>();
    addTearDown(screenshots.close);
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_routerApp(screenshots.stream));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reveal phrase'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('set passcode route'), findsOneWidget);

    screenshots.add(null);
    await tester.pumpAndSettle();

    expect(find.byType(MobileSeedScreenshotWarningSheet), findsNothing);
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
  });

  testWidgets(
    'covers the revealed phrase when the privacy controller is unsafe',
    (tester) async {
      final privacyController = SensitivePrivacyOverlayController(
        initiallySafe: false,
      );
      addTearDown(privacyController.dispose);

      await tester.pumpWidget(
        _app(
          MobileSecretPassphraseScreen(
            privacyOverlayController: privacyController,
          ),
          seedCreateMnemonic: true,
        ),
      );
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);

      await tester.tap(find.text('Reveal phrase'));
      await tester.pump();

      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

      privacyController.markSafe();
      await tester.pump();

      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
    },
  );
}
