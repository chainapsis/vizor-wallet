@Tags(['mobile'])
library;

import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/storage/app_secure_store.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/forgot_passcode_sheet.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/mobile_unlock_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
import 'package:zcash_wallet/src/features/payment_links/models/vizor_payment_link.dart';
import 'package:zcash_wallet/src/features/payment_links/providers/payment_link_intake_provider.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/frb_generated.dart';
import 'package:zcash_wallet/src/features/payment_links/services/payment_link_received_store.dart';
import 'package:zcash_wallet/src/providers/device_owner_auth_provider.dart';
import 'package:zcash_wallet/src/services/device_owner_auth.dart';
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
  Completer<BiometricAvailability>? availabilityCompleter;
  Completer<String>? readCompleter;
  var reads = 0;

  @override
  Future<BiometricAvailability> availability() async {
    final completer = availabilityCompleter;
    if (completer != null) return completer.future;
    return avail;
  }

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

const fingerprintAvailability = BiometricAvailability(
  supported: true,
  enrolled: true,
  kind: BiometricKind.fingerprint,
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

class _SuccessfulSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: false);

  @override
  Future<bool> unlock(String password) async {
    state = state.copyWith(isUnlocked: true);
    return true;
  }
}

class _RestoringAccountNotifier extends AccountNotifier {
  @override
  FutureOr<AccountState> build() => const AccountState();

  @override
  Future<void> restoreAfterUnlock() async {}
}

class _UnlockSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();

  @override
  Future<void> refreshAfterUnlock() async {}

  @override
  Future<void> startSyncAnyway() async {}
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
  bool autoPromptBiometric = true,
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      if (bootstrap != null) appBootstrapProvider.overrideWithValue(bootstrap),
      if (biometricNotifier != null)
        biometricUnlockProvider.overrideWith(biometricNotifier)
      else if (biometric != null)
        biometricUnlockServiceProvider.overrideWithValue(biometric),
      ...extraOverrides,
    ],
    child: MaterialApp(
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: MobileUnlockScreen(autoPromptBiometric: autoPromptBiometric),
    ),
  );
}

({Widget app, GoRouter router}) _routedUnlockApp({
  FakeBiometricUnlock? biometric,
  bool autoPromptBiometric = false,
}) {
  final router = GoRouter(
    initialLocation: '/unlock',
    routes: [
      GoRoute(
        path: '/unlock',
        builder: (_, _) =>
            MobileUnlockScreen(autoPromptBiometric: autoPromptBiometric),
      ),
      GoRoute(
        path: '/payment-links',
        builder: (_, _) => const Text(
          'Payment link destination',
          textDirection: TextDirection.ltr,
        ),
      ),
      GoRoute(
        path: '/home',
        builder: (_, _) =>
            const Text('Home destination', textDirection: TextDirection.ltr),
      ),
    ],
  );
  final app = ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        _bootstrap(biometricEnabled: biometric != null),
      ),
      appSecurityProvider.overrideWith(_SuccessfulSecurityNotifier.new),
      accountProvider.overrideWith(_RestoringAccountNotifier.new),
      syncProvider.overrideWith(_UnlockSyncNotifier.new),
      if (biometric != null)
        biometricUnlockServiceProvider.overrideWithValue(biometric),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
    ),
  );
  return (app: app, router: router);
}

final _pendingPaymentLink = VizorPaymentLink(
  network: 'main',
  address: 'u1pendinggiftcardaddress',
  amountZatoshi: BigInt.from(100000000),
  mnemonic: List.filled(24, 'abandon').join(' '),
  birthdayHeight: 3000000,
  label: 'Gift Card',
  createdAt: DateTime.utc(2026, 8, 28),
);

void _queuePendingPaymentLink(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MobileUnlockScreen)),
  );
  final result = container
      .read(paymentLinkIntakeProvider.notifier)
      .receive(_pendingPaymentLink.toUri().toString());
  expect(result, PaymentLinkIntakeResult.accepted);
}

Future<void> _pumpAutoBiometricPromptWait(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _pumpUntilBiometricRead(
  WidgetTester tester,
  FakeBiometricUnlock biometric,
) async {
  for (var i = 0; i < 4 && biometric.reads == 0; i += 1) {
    await _pumpAutoBiometricPromptWait(tester);
  }
}

class _ResetBlockedAccountNotifier extends AccountNotifier {
  var resets = 0;

  @override
  FutureOr<AccountState> build() => const AccountState();

  @override
  Future<void> restoreAfterUnlock() async {}

  @override
  Future<void> resetWallet() async {
    resets += 1;
    throw const WalletResetInFlightGiftCardClaimsException(count: 1);
  }
}

class _ResetSyncNotifier extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState();

  // The real snapshot asks Rust whether a sync is running, which the secret-API
  // fake in this file does not answer.
  @override
  bool needsPauseForWalletMutation() => false;

  @override
  Future<WalletMutationSyncPause> pauseForWalletMutation({
    FutureOr<void> Function()? onStoppingSync,
  }) async {
    return const WalletMutationSyncPause(
      hadActiveSync: false,
      hadPolling: false,
      hadMempoolObserver: false,
    );
  }

  @override
  Future<void> clearSensitiveStateForLock() async {}

  @override
  void clearCachedWalletDbPath() {}
}

class _ResetBiometricNotifier extends BiometricUnlockNotifier {
  @override
  Future<BiometricUnlockState> build() async => BiometricUnlockState.initial;

  @override
  Future<void> disable() async {}
}

class _AlwaysAllowingDeviceOwnerAuth extends DeviceOwnerAuth {
  _AlwaysAllowingDeviceOwnerAuth() : super(hasOsResetGateOverride: true);

  @override
  Future<bool> verify({required String reason}) async => true;
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

  testWidgets('the reset sheet warns about an in-flight Gift Card', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        extraOverrides: [
          paymentLinkClaimsInFlightProvider.overrideWith((ref) async => 1),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Passcode help'));
    await tester.pumpAndSettle();

    // Warned, never blocked: the claim cannot finish while the wallet stays
    // locked, and this reset is the only way back in.
    expect(
      find.text(kWalletResetInFlightGiftCardWarningMessage),
      findsOneWidget,
    );
    expect(find.text('Continue to reset Vizor'), findsOneWidget);
  });

  testWidgets('a refused reset reads as a Gift Card wait, not a failure', (
    tester,
  ) async {
    // `resetWallet` no longer refuses on this locked path, so this pins the
    // backstop: whatever raises the refusal, the screen must say what is
    // happening rather than fall back to "Couldn't reset the app".
    late _ResetBlockedAccountNotifier accountNotifier;
    final router = GoRouter(
      initialLocation: '/unlock',
      routes: [
        GoRoute(
          path: '/unlock',
          builder: (_, _) =>
              const MobileUnlockScreen(autoPromptBiometric: false),
        ),
        GoRoute(
          path: '/welcome',
          builder: (_, _) => const Text(
            'Welcome destination',
            textDirection: TextDirection.ltr,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appBootstrapProvider.overrideWithValue(
            _bootstrap(biometricEnabled: false),
          ),
          deviceOwnerAuthProvider.overrideWithValue(
            _AlwaysAllowingDeviceOwnerAuth(),
          ),
          accountProvider.overrideWith(() {
            accountNotifier = _ResetBlockedAccountNotifier();
            return accountNotifier;
          }),
          syncProvider.overrideWith(_ResetSyncNotifier.new),
          biometricUnlockProvider.overrideWith(_ResetBiometricNotifier.new),
          paymentLinkClaimsInFlightProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Passcode help'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to reset Vizor'));
    await tester.pumpAndSettle();

    // The second sheet arms after a deliberate countdown.
    await tester.pump(kForgotPasscodeLastWarningArmDelay);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset Vizor'));
    await tester.pumpAndSettle();

    expect(accountNotifier.resets, 1);
    expect(
      find.text(kWalletResetInFlightGiftCardClaimsMessage),
      findsOneWidget,
    );
    expect(
      find.text("Couldn't reset the app. Please try again."),
      findsNothing,
    );
    expect(find.text('Welcome destination'), findsNothing);
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

  testWidgets('digits register on pointer down before tap up', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('Digit 1')),
    );
    await tester.pump();

    var dots = tester.widget<PasscodeDots>(find.byType(PasscodeDots));
    expect(dots.filled, 1);

    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    dots = tester.widget<PasscodeDots>(find.byType(PasscodeDots));
    expect(dots.filled, 1);

    await gesture.up();
  });

  group('unlock destination', () {
    testWidgets('passcode unlock without a pending Gift Card opens home', (
      tester,
    ) async {
      final routed = _routedUnlockApp();
      addTearDown(routed.router.dispose);
      await tester.pumpWidget(routed.app);

      for (final digit in '123456'.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $digit'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(routed.router.state.uri.path, '/home');
      expect(find.text('Home destination'), findsOneWidget);
      expect(find.text('Payment link destination'), findsNothing);
    });

    testWidgets('passcode unlock opens the pending Gift Card once', (
      tester,
    ) async {
      final routed = _routedUnlockApp();
      addTearDown(routed.router.dispose);
      await tester.pumpWidget(routed.app);
      _queuePendingPaymentLink(tester);

      for (final digit in '123456'.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $digit'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(routed.router.state.uri.path, '/payment-links');
      expect(find.text('Payment link destination'), findsOneWidget);
      expect(find.text('Home destination'), findsNothing);
    });

    testWidgets('biometric unlock opens the pending Gift Card once', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      await AppSecureStore.instance.writePlain(
        kBiometricUnlockEnabledKey,
        'true',
      );
      final biometric = FakeBiometricUnlock(
        avail: faceAvailability,
        escrow: '123456',
      );
      final routed = _routedUnlockApp(
        biometric: biometric,
        autoPromptBiometric: true,
      );
      addTearDown(routed.router.dispose);
      await tester.pumpWidget(routed.app);
      _queuePendingPaymentLink(tester);

      await _pumpUntilBiometricRead(tester, biometric);
      await tester.pumpAndSettle();

      expect(biometric.reads, 1);
      expect(routed.router.state.uri.path, '/payment-links');
      expect(find.text('Payment link destination'), findsOneWidget);
      expect(find.text('Home destination'), findsNothing);
    });
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
      await tester.pump();

      expect(biometric.reads, 0);

      await _pumpUntilBiometricRead(tester, biometric);
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
      expect(biometric.reads, 0);

      await _pumpUntilBiometricRead(tester, biometric);
      expect(biometric.reads, 1);

      pendingRead.complete('999999');
      await tester.pumpAndSettle();

      expect(find.byType(MobileBiometricSignInView), findsNothing);
      expect(find.text('Incorrect Passcode'), findsOneWidget);
    });

    testWidgets('auto-prompt waits for a painted backdrop frame', (
      tester,
    ) async {
      await AppSecureStore.instance.configurePassword('123456');
      AppSecureStore.instance.clearSessionPassword();
      await AppSecureStore.instance.writePlain(
        kBiometricUnlockEnabledKey,
        'true',
      );
      final availability = Completer<BiometricAvailability>();
      final pendingRead = Completer<String>();
      final biometric =
          FakeBiometricUnlock(avail: faceAvailability, escrow: '999999')
            ..availabilityCompleter = availability
            ..readCompleter = pendingRead;

      await tester.pumpWidget(
        _app(
          bootstrap: _bootstrap(biometricEnabled: true),
          biometric: biometric,
        ),
      );
      await tester.pump();

      expect(find.byType(MobileBiometricSignInView), findsOneWidget);
      expect(biometric.reads, 0);

      availability.complete(faceAvailability);
      await tester.pump();

      expect(find.byType(MobileBiometricSignInView), findsOneWidget);
      expect(biometric.reads, 0);

      await _pumpUntilBiometricRead(tester, biometric);
      expect(biometric.reads, 1);
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
      await _pumpUntilBiometricRead(tester, biometric);
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

    testWidgets('fingerprint devices label the retry action by modality', (
      tester,
    ) async {
      await AppSecureStore.instance.writePlain(
        kBiometricUnlockEnabledKey,
        'true',
      );
      final biometric = FakeBiometricUnlock(
        avail: fingerprintAvailability,
        escrow: '123456',
      );

      await tester.pumpWidget(
        _app(biometric: biometric, autoPromptBiometric: false),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Sign in with fingerprint'), findsOneWidget);
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
      expect(find.bySemanticsLabel('Sign in with Face ID'), findsNothing);
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
      await _pumpUntilBiometricRead(tester, biometric);
      await tester.pumpAndSettle();

      expect(
        find.text('Face ID changed. Enter your passcode.'),
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
