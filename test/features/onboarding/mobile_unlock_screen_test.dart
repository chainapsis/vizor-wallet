@Tags(['mobile'])
library;

import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_unlock_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
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
  Completer<String>? readCompleter;
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
    final completer = readCompleter;
    if (completer != null) return completer.future;
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

/// Never resolves, so the screen stays in the biometric provider's loading
/// state — isolating the bootstrap "enabled" hint as the only signal that can
/// paint the backdrop on the first frame.
class _PendingBiometricNotifier extends BiometricUnlockNotifier {
  final _completer = Completer<BiometricUnlockState>();

  @override
  Future<BiometricUnlockState> build() => _completer.future;
}

class _FailingBiometricNotifier extends BiometricUnlockNotifier {
  @override
  Future<BiometricUnlockState> build() async {
    throw StateError('biometric probe failed');
  }
}

AppBootstrapState _bootstrap({required bool biometricEnabled}) =>
    AppBootstrapState(
      initialLocation: '/unlock',
      initialAccountState: AccountState(),
      initialSyncSnapshot: AppSyncSnapshot.empty,
      network: 'main',
      rpcEndpointConfig: defaultRpcEndpointConfig('main'),
      themeMode: ThemeMode.light,
      privacyModeEnabled: false,
      isPasswordConfigured: true,
      isUnlocked: false,
      passwordRotationRecoveryFailed: false,
      biometricUnlockEnabled: biometricEnabled,
    );

Widget _app({
  FakeBiometricUnlock? biometric,
  BiometricUnlockNotifier Function()? biometricNotifier,
  AppBootstrapState? bootstrap,
}) {
  return ProviderScope(
    overrides: [
      if (bootstrap != null) appBootstrapProvider.overrideWithValue(bootstrap),
      if (biometricNotifier != null)
        biometricUnlockProvider.overrideWith(biometricNotifier)
      else if (biometric != null)
        biometricUnlockServiceProvider.overrideWithValue(biometric),
    ],
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: const MobileUnlockScreen(),
    ),
  );
}

void main() {
  setUpAll(() {
    RustLib.initMock(api: _RustSecretApiFake());
  });

  tearDownAll(RustLib.dispose);

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
    expect(
      tester.getSize(find.byKey(const ValueKey('passcode_backspace_slot'))),
      const Size(30, 32),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('passcode_backspace_glyph'))),
      const Size(26.25, 23.15),
    );
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

  group('haptics', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      AppSecureStore.instance.clearSessionPassword();
    });

    testWidgets('digits tap light and a wrong passcode buzzes the error', (
      tester,
    ) async {
      await AppSecureStore.instance.configurePassword('123456');
      AppSecureStore.instance.clearSessionPassword();

      final impactTypes = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            impactTypes.add(call.arguments);
          }
          return null;
        },
      );
      final errorHaptics = <MethodCall>[];
      const hapticsChannel = MethodChannel('com.zcash.wallet/haptics');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        hapticsChannel,
        (call) async {
          errorHaptics.add(call);
          return true;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          hapticsChannel,
          null,
        );
      });

      await tester.pumpWidget(_app());
      await tester.pump();

      await tester.tap(find.bySemanticsLabel('Digit 1'));
      await tester.pump();
      expect(impactTypes, ['HapticFeedbackType.lightImpact']);

      await tester.tap(find.bySemanticsLabel('Delete digit'));
      await tester.pump();
      expect(impactTypes.last, 'HapticFeedbackType.selectionClick');

      // A full wrong passcode lands the error haptic exactly once.
      for (final d in '999999'.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $d'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Incorrect Passcode'), findsOneWidget);
      expect(errorHaptics, hasLength(1));
      expect(errorHaptics.single.method, 'error');
    });
  });

  group('biometric unlock', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      AppSecureStore.instance.clearSessionPassword();
    });

    testWidgets(
      'bootstrap hint paints the backdrop before the probe resolves',
      (tester) async {
        await tester.pumpWidget(
          _app(
            bootstrap: _bootstrap(biometricEnabled: true),
            biometricNotifier: _PendingBiometricNotifier.new,
          ),
        );
        // Provider is still loading (never resolves); only the hint can show
        // the backdrop here.
        await tester.pump();

        expect(find.byType(MobileBiometricSignInView), findsOneWidget);
        expect(find.byType(PasscodeNumpad), findsNothing);
      },
    );

    testWidgets('no backdrop while loading when the hint is disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          bootstrap: _bootstrap(biometricEnabled: false),
          biometricNotifier: _PendingBiometricNotifier.new,
        ),
      );
      await tester.pump();

      expect(find.byType(MobileBiometricSignInView), findsNothing);
      expect(find.byType(PasscodeNumpad), findsOneWidget);
    });

    testWidgets('probe errors fall back to the numpad even with the hint', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          bootstrap: _bootstrap(biometricEnabled: true),
          biometricNotifier: _FailingBiometricNotifier.new,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(MobileBiometricSignInView), findsNothing);
      expect(find.byType(PasscodeNumpad), findsOneWidget);
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

    testWidgets('auto-prompt shows the biometric sign-in screen first', (
      tester,
    ) async {
      await AppSecureStore.instance.configurePassword('123456');
      AppSecureStore.instance.clearSessionPassword();
      await AppSecureStore.instance.writePlain(
        kBiometricUnlockEnabledKey,
        'true',
      );
      final pendingRead = Completer<String>();
      final biometric = FakeBiometricUnlock(
        avail: faceAvailability,
        escrow: '999999',
      )..readCompleter = pendingRead;

      await tester.pumpWidget(_app(biometric: biometric));
      await tester.pump();
      await tester.pump();

      expect(find.byType(MobileBiometricSignInView), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mobile_biometric_sign_in_background')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mobile_biometric_sign_in_badge')),
        findsOneWidget,
      );
      expect(find.byType(PasscodeNumpad), findsNothing);
      expect(biometric.reads, 1);

      pendingRead.complete('999999');
      await tester.pumpAndSettle();

      expect(find.byType(MobileBiometricSignInView), findsNothing);
      expect(find.text('Incorrect Passcode'), findsOneWidget);
    });

    testWidgets('cancel falls back to the numpad with a retry key', (
      tester,
    ) async {
      await AppSecureStore.instance.writePlain(
        kBiometricUnlockEnabledKey,
        'true',
      );
      final biometric = FakeBiometricUnlock(
        avail: faceAvailability,
        escrow: '123456',
      )..readError = BiometricUnlockErrorKind.cancelled;

      await tester.pumpWidget(_app(biometric: biometric));
      await tester.pumpAndSettle();

      expect(biometric.reads, 1);
      expect(find.text('Incorrect Passcode'), findsNothing);
      expect(find.bySemanticsLabel('Sign in with Face ID'), findsOneWidget);

      // Manual retry triggers another prompt.
      biometric.readError = BiometricUnlockErrorKind.cancelled;
      await tester.tap(find.bySemanticsLabel('Sign in with Face ID'));
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
      final biometric = FakeBiometricUnlock(avail: faceAvailability)
        ..readError = BiometricUnlockErrorKind.invalidated;

      await tester.pumpWidget(_app(biometric: biometric));
      await tester.pumpAndSettle();

      expect(
        find.text('Biometrics changed. Enter your passcode.'),
        findsOneWidget,
      );
      // The retry key disappears with the flag.
      expect(find.bySemanticsLabel('Sign in with Face ID'), findsNothing);
      expect(
        await AppSecureStore.instance.readPlain(kBiometricUnlockEnabledKey),
        'false',
      );
    });
  });
}
