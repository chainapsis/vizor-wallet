import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/privacy/sensitive_privacy_overlay.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';

void main() {
  test('platform privacy signals are macOS-only', () {
    expect(supportsPlatformPrivacySignals(isWeb: false, isMacOS: true), isTrue);
    expect(
      supportsPlatformPrivacySignals(isWeb: false, isMacOS: false),
      isFalse,
    );
    expect(supportsPlatformPrivacySignals(isWeb: true, isMacOS: true), isFalse);
  });

  test('native privacy shield supports macOS and Android', () {
    expect(
      supportsNativePrivacyShield(
        isWeb: false,
        isMacOS: true,
        isAndroid: false,
      ),
      isTrue,
    );
    expect(
      supportsNativePrivacyShield(
        isWeb: false,
        isMacOS: false,
        isAndroid: true,
      ),
      isTrue,
    );
    expect(
      supportsNativePrivacyShield(
        isWeb: false,
        isMacOS: false,
        isAndroid: false,
      ),
      isFalse,
    );
    expect(
      supportsNativePrivacyShield(isWeb: true, isMacOS: true, isAndroid: true),
      isFalse,
    );
  });

  test('reuses one native macOS exposure stream instance', () {
    expect(
      MacOSPrivacyExposureEvents.stream,
      same(MacOSPrivacyExposureEvents.stream),
    );
  }, skip: !Platform.isMacOS);

  testWidgets('shows privacy shield only when sensitive content is unsafe', (
    tester,
  ) async {
    final controller = SensitivePrivacyOverlayController(initiallySafe: true);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.light,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SensitivePrivacyOverlay(
            sensitiveContentVisible: true,
            controller: controller,
            child: const SizedBox(
              width: 320,
              height: 240,
              child: Text('Seed phrase pane'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Seed phrase pane'), findsOneWidget);
    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);

    controller.markUnsafe();
    await tester.pump();

    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

    controller.markSafe();
    await tester.pump();

    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
  });

  testWidgets('does not show privacy shield when no sensitive content exists', (
    tester,
  ) async {
    final controller = SensitivePrivacyOverlayController(initiallySafe: false);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.light,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SensitivePrivacyOverlay(
            sensitiveContentVisible: false,
            controller: controller,
            child: const SizedBox(
              width: 320,
              height: 240,
              child: Text('Empty import form'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Empty import form'), findsOneWidget);
    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
  });

  testWidgets('applies configured privacy shield border radius', (
    tester,
  ) async {
    final controller = SensitivePrivacyOverlayController(initiallySafe: false);
    addTearDown(controller.dispose);
    final radius = BorderRadius.circular(20);

    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.light,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SensitivePrivacyOverlay(
            sensitiveContentVisible: true,
            controller: controller,
            borderRadius: radius,
            child: const SizedBox(width: 320, height: 240),
          ),
        ),
      ),
    );

    final clip = tester.widget<ClipRRect>(
      find.descendant(
        of: find.byKey(SensitivePrivacyOverlay.shieldKey),
        matching: find.byType(ClipRRect),
      ),
    );

    expect(clip.borderRadius, radius);
  });

  testWidgets(
    'auth-prompt marker does not override a plain unsafe controller',
    (tester) async {
      final controller = SensitivePrivacyOverlayController(
        initiallySafe: false,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        AppTheme(
          data: AppThemeData.light,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SensitivePrivacyOverlay(
              sensitiveContentVisible: true,
              controller: controller,
              child: const SizedBox(width: 320, height: 240),
            ),
          ),
        ),
      );

      // Unsafe with visible content → shield shows.
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

      // The base controller records the prompt marker but does not decide which
      // unsafe state is safe to suppress.
      controller.beginAuthPrompt();
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

      controller.endAuthPrompt();
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);
    },
  );

  testWidgets(
    'environment controller suppresses the shield across the biometric '
    'inactive→resumed transition',
    (tester) async {
      final controller = SensitivePrivacyEnvironmentController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        AppTheme(
          data: AppThemeData.light,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SensitivePrivacyOverlay(
              sensitiveContentVisible: true,
              controller: controller,
              child: const SizedBox(width: 320, height: 240),
            ),
          ),
        ),
      );

      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);

      // The prompt suppresses the shield, then iOS drives the app inactive.
      controller.beginAuthPrompt();
      controller.setLifecycleInactiveForTesting();
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);

      // A real background transition is not suppressed by the auth marker.
      controller.setLifecycleHiddenForTesting();
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

      controller.endAuthPrompt();
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

      // Return to foreground, then repeat the intended prompt path.
      controller.setLifecycleForegroundForTesting();
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
      controller.beginAuthPrompt();
      controller.setLifecycleInactiveForTesting();
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);

      // Releasing while still inactive defers — no flash before resume.
      controller.endAuthPrompt();
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);

      // Returning to foreground clears suppression in lockstep with safe.
      controller.setLifecycleForegroundForTesting();
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);

      // A genuine background (no prompt) still covers the content.
      controller.setLifecycleInactiveForTesting();
      await tester.pump();
      expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);
    },
  );

  testWidgets('environment controller honors native macOS exposure events', (
    tester,
  ) async {
    final exposureEvents = StreamController<MacOSPrivacyExposureEvent>();
    final controller = SensitivePrivacyEnvironmentController(
      macOSExposureEvents: exposureEvents.stream,
    );
    addTearDown(() async {
      controller.dispose();
      await exposureEvents.close();
    });

    await tester.pumpWidget(
      AppTheme(
        data: AppThemeData.light,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SensitivePrivacyOverlay(
            sensitiveContentVisible: true,
            controller: controller,
            child: const SizedBox(
              width: 320,
              height: 240,
              child: Text('Seed phrase pane'),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);

    exposureEvents.add(
      const MacOSPrivacyExposureEvent(isSafe: false, reason: 'missionControl'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsOneWidget);

    exposureEvents.add(
      const MacOSPrivacyExposureEvent(isSafe: true, reason: 'windowVisible'),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(SensitivePrivacyOverlay.shieldKey), findsNothing);
  });

  testWidgets(
    'syncs sensitive visibility to the native privacy shield bridge',
    (tester) async {
      const channel = MethodChannel('com.zcash.wallet/privacy_shield');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      MacOSSensitiveContentBridge.resetForTesting();
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        MacOSSensitiveContentBridge.resetForTesting();
      });

      await tester.pumpWidget(
        AppTheme(
          data: AppThemeData.light,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: SensitivePrivacyOverlay(
              sensitiveContentVisible: false,
              child: SizedBox(
                width: 320,
                height: 240,
                child: Text('Seed phrase pane'),
              ),
            ),
          ),
        ),
      );

      expect(calls, isEmpty);

      await tester.pumpWidget(
        AppTheme(
          data: AppThemeData.light,
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: SensitivePrivacyOverlay(
              sensitiveContentVisible: true,
              child: SizedBox(
                width: 320,
                height: 240,
                child: Text('Seed phrase pane'),
              ),
            ),
          ),
        ),
      );
      await tester.idle();

      expect(calls.single.method, 'setSensitiveContentVisible');
      expect(calls.single.arguments, {'visible': true});

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.idle();

      expect(calls.last.method, 'setSensitiveContentVisible');
      expect(calls.last.arguments, {'visible': false});
    },
    skip: !Platform.isMacOS,
  );
}
