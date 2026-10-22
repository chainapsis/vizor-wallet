@Tags(['mobile'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_app.dart';
import 'package:zcash_wallet/figma_compare/figma_compare_scenarios.dart';
import 'package:zcash_wallet/figma_compare/mobile_passcode_capture.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';

import '../../figma_compare/figma_compare_font_loader.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';

Widget _app(
  PasscodeCaptureScreen screen, {
  double scale = 1,
  double bottomInset = 0,
  EdgeInsets? safeInsets,
  GlobalKey? captureKey,
  BiometricUnlockState biometric = BiometricUnlockState.initial,
}) => FigmaCompareApp(
  scenario: FigmaCompareScenario(
    id: 'passcode-layout',
    description: 'Passcode layout regression',
    allowPointer: true,
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        padding: safeInsets ?? EdgeInsets.only(bottom: bottomInset),
        viewPadding: safeInsets ?? EdgeInsets.only(bottom: bottomInset),
      ),
      child: MobilePasscodeCapture(screen: screen, biometric: biometric),
    ),
  ),
  themeMode: ThemeMode.light,
  captureBoundaryKey: captureKey ?? GlobalKey(),
);

void main() {
  setUpAll(loadFigmaCompareFonts);
  for (final screen in PasscodeCaptureScreen.values) {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final viewport in [
        (size: const Size(951, 669), insets: const EdgeInsets.only(bottom: 24)),
        (size: const Size(951, 560), insets: const EdgeInsets.only(bottom: 24)),
        (size: const Size(568, 320), insets: const EdgeInsets.only(bottom: 24)),
        // The Duo's folded display remains portrait, with side system chrome.
        (
          size: const Size(466, 678),
          insets: const EdgeInsets.only(right: 84, bottom: 34),
        ),
        (size: const Size(320, 568), insets: const EdgeInsets.only(bottom: 24)),
      ]) {
        final size = viewport.size;
        testWidgets('${screen.name} fits $size at text scale $scale', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            _app(screen, scale: scale, safeInsets: viewport.insets),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final keypad = tester.widget<PasscodeNumpad>(
            find.byType(PasscodeNumpad),
          );
          expect(keypad.keySize, lessThan(80));
          expect(
            find.bySemanticsLabel('Passcode help'),
            screen == PasscodeCaptureScreen.unlock
                ? findsOneWidget
                : findsNothing,
          );
          // Scrolling must make the last row reachable even at the shortest height.
          await tester.ensureVisible(find.bySemanticsLabel('Digit 0'));
          await tester.pumpAndSettle();
          final zero = tester.getRect(find.bySemanticsLabel('Digit 0'));
          expect(
            zero.bottom,
            lessThanOrEqualTo(size.height - viewport.insets.bottom),
          );
          await tester.tap(find.bySemanticsLabel('Digit 0'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<PasscodeDots>(find.byType(PasscodeDots)).filled,
            1,
          );
          // All digits stay in the familiar three-column order after shrinking.
          final one = tester.getRect(find.bySemanticsLabel('Digit 1'));
          final two = tester.getRect(find.bySemanticsLabel('Digit 2'));
          final three = tester.getRect(find.bySemanticsLabel('Digit 3'));
          final four = tester.getRect(find.bySemanticsLabel('Digit 4'));
          expect(one.top, two.top);
          expect(two.top, three.top);
          expect(four.left, one.left);
          expect(four.top, greaterThan(one.bottom));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final screen in [
    PasscodeCaptureScreen.unlock,
    PasscodeCaptureScreen.viewingKey,
    PasscodeCaptureScreen.seedPhrase,
  ]) {
    for (final viewport in [
      (size: const Size(951, 560), insets: const EdgeInsets.only(bottom: 24)),
      (
        size: const Size(466, 678),
        insets: const EdgeInsets.only(right: 84, bottom: 34),
      ),
    ]) {
      for (final enabled in [true, false]) {
        testWidgets(
          '${screen.name} biometric footer remains reachable ($enabled) ${viewport.size}',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = viewport.size;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              _app(
                screen,
                scale: 2,
                safeInsets: viewport.insets,
                biometric: BiometricUnlockState(
                  availability: const BiometricAvailability(
                    supported: true,
                    enrolled: true,
                    kind: BiometricKind.face,
                  ),
                  enabled: enabled,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final footer = find.byType(
              enabled ? PasscodeBiometricButton : PasscodeBiometricOptIn,
            );
            if (!enabled && screen != PasscodeCaptureScreen.unlock) {
              expect(find.byType(PasscodeBiometricButton), findsNothing);
              return;
            }
            expect(footer, findsOneWidget);
            await tester.ensureVisible(footer);
            await tester.pumpAndSettle();
            expect(
              tester.getRect(footer).bottom,
              lessThanOrEqualTo(viewport.size.height - viewport.insets.bottom),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('roomy windows retain the original keypad for every screen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final screen in PasscodeCaptureScreen.values) {
      for (final size in [
        const Size(393, 852),
        const Size(669, 951),
        const Size(852, 852),
        const Size(1200, 900),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          _app(
            screen,
            safeInsets: size == const Size(393, 852)
                ? const EdgeInsets.only(top: 62, bottom: 34)
                : EdgeInsets.zero,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('compact_passcode')), findsNothing);
        expect(
          tester.widget<PasscodeNumpad>(find.byType(PasscodeNumpad)).keySize,
          80,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets(
    'folding and rotation preserve entered digits and setup confirmation phase',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        _app(PasscodeCaptureScreen.create, captureKey: captureKey),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.bySemanticsLabel('Digit 1'));
        await tester.pump();
      }
      expect(find.text('Confirm Passcode'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Digit 2'));
      await tester.pump();
      tester.view.physicalSize = const Size(951, 669);
      await tester.pumpAndSettle();
      expect(find.text('Confirm Passcode'), findsOneWidget);
      expect(tester.widget<PasscodeDots>(find.byType(PasscodeDots)).filled, 1);
      tester.view.physicalSize = const Size(466, 678);
      await tester.pumpWidget(
        _app(
          PasscodeCaptureScreen.create,
          captureKey: captureKey,
          safeInsets: const EdgeInsets.only(right: 84, bottom: 34),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Confirm Passcode'), findsOneWidget);
      expect(tester.widget<PasscodeDots>(find.byType(PasscodeDots)).filled, 1);
      expect(
        tester.widget<PasscodeNumpad>(find.byType(PasscodeNumpad)).keySize,
        lessThan(80),
      );
      tester.view.physicalSize = const Size(393, 852);
      await tester.pumpWidget(
        _app(PasscodeCaptureScreen.create, captureKey: captureKey),
      );
      await tester.pumpAndSettle();
      expect(find.text('Confirm Passcode'), findsOneWidget);
      expect(tester.widget<PasscodeDots>(find.byType(PasscodeDots)).filled, 1);
      expect(
        tester.widget<PasscodeNumpad>(find.byType(PasscodeNumpad)).keySize,
        80,
      );
      await tester.tap(find.bySemanticsLabel('Delete digit'));
      await tester.pump();
      expect(tester.widget<PasscodeDots>(find.byType(PasscodeDots)).filled, 0);
    },
  );

  for (final size in [const Size(951, 710), const Size(466, 710)]) {
    testWidgets('error clearance is safe at the legacy fit boundary $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(PasscodeCaptureScreen.change));
      await tester.pumpAndSettle();
      expect(
        tester.widget<PasscodeNumpad>(find.byType(PasscodeNumpad)).keySize,
        80,
      );
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.bySemanticsLabel('Digit 1'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Incorrect Passcode'), findsOneWidget);
      expect(
        tester.getRect(find.text('Incorrect Passcode')).bottom,
        lessThan(tester.getRect(find.bySemanticsLabel('Digit 1')).top),
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final viewport in [
    (size: const Size(951, 669), insets: const EdgeInsets.only(bottom: 24)),
    (
      size: const Size(466, 678),
      insets: const EdgeInsets.only(right: 84, bottom: 34),
    ),
  ]) {
    testWidgets('error text remains above the first key row ${viewport.size}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport.size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _app(
          PasscodeCaptureScreen.change,
          scale: 1.5,
          safeInsets: viewport.insets,
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await tester.ensureVisible(find.bySemanticsLabel('Digit 1'));
        await tester.tap(find.bySemanticsLabel('Digit 1'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Incorrect Passcode'), findsOneWidget);
      expect(
        tester.getRect(find.text('Incorrect Passcode')).bottom,
        lessThan(tester.getRect(find.bySemanticsLabel('Digit 1')).top),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
