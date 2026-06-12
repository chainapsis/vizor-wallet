@Tags(['mobile'])
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_unlock_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';

/// Just enough of the Rust secret API for password verifier checks.
class _RustSecretApiFake implements RustLibApi {
  @override
  Future<String> crateApiSecretDeriveSecretPasswordVerifier({
    required String password,
    required String saltBase64,
  }) async {
    return base64Encode(utf8.encode('$saltBase64:$password'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBiometricUnlock extends BiometricUnlock {
  FakeBiometricUnlock({required this.avail, this.escrow});

  BiometricAvailability avail;
  String? escrow;
  BiometricUnlockErrorKind? readError;
  var reads = 0;

  @override
  Future<BiometricAvailability> availability() async => avail;

  @override
  Future<void> enable(String passcode) async => escrow = passcode;

  @override
  Future<void> disable() async => escrow = null;

  @override
  Future<String> read({required String reason}) async {
    reads += 1;
    final error = readError;
    if (error != null) throw BiometricUnlockException(error);
    final value = escrow;
    if (value == null) {
      throw const BiometricUnlockException(
        BiometricUnlockErrorKind.invalidated,
      );
    }
    return value;
  }
}

const faceAvailability = BiometricAvailability(
  supported: true,
  enrolled: true,
  kind: BiometricKind.face,
);

Widget _app({FakeBiometricUnlock? biometric}) {
  return ProviderScope(
    overrides: [
      if (biometric != null)
        biometricUnlockServiceProvider.overrideWithValue(biometric),
    ],
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: const MobileUnlockScreen(),
    ),
  );
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(520, 1100)
      ..devicePixelRatio = 1.0;
  });

  testWidgets('help opens the forgot-passcode reset sheet', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    await tester.tap(find.bySemanticsLabel('Passcode help'));
    await tester.pumpAndSettle();

    expect(find.text('Forgot Passcode?'), findsOneWidget);
    expect(find.text('Continue to reset Vizor'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Forgot Passcode?'), findsNothing);
  });

  testWidgets('renders the numpad and fills dots while typing', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.bySemanticsLabel('Passcode help'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Digit 1'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Digit 2'));
    await tester.pump();

    final dots = tester.widget<PasscodeDots>(find.byType(PasscodeDots));
    expect(dots.filled, 2);

    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.pump();
    final after = tester.widget<PasscodeDots>(find.byType(PasscodeDots));
    expect(after.filled, 1);

    // Delete hides again once the entry is cleared.
    await tester.tap(find.bySemanticsLabel('Delete digit'));
    await tester.pump();
    expect(find.bySemanticsLabel('Delete digit'), findsNothing);
  });

  group('biometric unlock', () {
    setUpAll(() {
      RustLib.initMock(api: _RustSecretApiFake());
    });

    tearDownAll(RustLib.dispose);

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      AppSecureStore.instance.clearSessionPassword();
    });

    testWidgets('auto-prompt feeds the escrowed passcode to unlock', (
      tester,
    ) async {
      await AppSecureStore.instance.configurePassword('123456');
      AppSecureStore.instance.clearSessionPassword();
      await AppSecureStore.instance.writePlain(
        kBiometricUnlockEnabledKey,
        'true',
      );
      // A mismatching escrow proves the value travelled the whole
      // read → submit → verify pipeline without touching Rust.
      final biometric = FakeBiometricUnlock(
        avail: faceAvailability,
        escrow: '999999',
      );

      await tester.pumpWidget(_app(biometric: biometric));
      await tester.pumpAndSettle();

      expect(biometric.reads, 1);
      expect(find.text('Incorrect Passcode'), findsOneWidget);
    });

    testWidgets('cancel falls back to the numpad with a retry key', (
      tester,
    ) async {
      await AppSecureStore.instance.writePlain(
        kBiometricUnlockEnabledKey,
        'true',
      );
      final biometric =
          FakeBiometricUnlock(avail: faceAvailability, escrow: '123456')
            ..readError = BiometricUnlockErrorKind.cancelled;

      await tester.pumpWidget(_app(biometric: biometric));
      await tester.pumpAndSettle();

      expect(biometric.reads, 1);
      expect(find.text('Incorrect Passcode'), findsNothing);
      expect(find.bySemanticsLabel('Biometric unlock'), findsOneWidget);

      // Manual retry triggers another prompt.
      biometric.readError = BiometricUnlockErrorKind.cancelled;
      await tester.tap(find.bySemanticsLabel('Biometric unlock'));
      await tester.pumpAndSettle();
      expect(biometric.reads, 2);
    });

    testWidgets('invalidation drops the flag and explains the fallback', (
      tester,
    ) async {
      await AppSecureStore.instance.writePlain(
        kBiometricUnlockEnabledKey,
        'true',
      );
      final biometric =
          FakeBiometricUnlock(avail: faceAvailability)
            ..readError = BiometricUnlockErrorKind.invalidated;

      await tester.pumpWidget(_app(biometric: biometric));
      await tester.pumpAndSettle();

      expect(
        find.text('Biometrics changed. Enter your passcode.'),
        findsOneWidget,
      );
      // The retry key disappears with the flag.
      expect(find.bySemanticsLabel('Biometric unlock'), findsNothing);
      expect(
        await AppSecureStore.instance.readPlain(kBiometricUnlockEnabledKey),
        'false',
      );
    });
  });
}
