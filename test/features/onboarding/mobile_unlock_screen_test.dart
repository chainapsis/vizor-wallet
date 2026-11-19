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
import 'package:zcash_wallet/src/core/storage/account_visibility_store.dart';
import 'package:zcash_wallet/src/providers/mobile_account_visibility_provider.dart';
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
import 'package:zcash_wallet/src/core/l10n/app_language.dart';
import '../../support/test_l10n.dart';

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
  Completer<void>? enableCompleter;
  BiometricUnlockErrorKind? enableError;
  var enables = 0;
  var reads = 0;

  @override
  Future<BiometricAvailability> availability() async {
    final completer = availabilityCompleter;
    if (completer != null) return completer.future;
    return avail;
  }

  @override
  Future<void> enable(String passcode) async {
    enables += 1;
    if (enableCompleter != null) await enableCompleter!.future;
    if (enableError != null) throw BiometricUnlockException(enableError!);
    escrow = passcode;
  }

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

class _SuccessfulSecurityNotifier extends AppSecurityNotifier {
  @override
  AppSecurityState build() =>
      const AppSecurityState(isPasswordConfigured: true, isUnlocked: false);

  @override
  Future<bool> confirmPassword(String password) async => password == '123456';

  @override
  Future<bool> unlock(String password) async {
    state = state.copyWith(isUnlocked: true);
    return true;
  }
}

class _RestoringAccountNotifier extends AccountNotifier {
  _RestoringAccountNotifier([this.initial = const AccountState()]);

  final AccountState initial;

  @override
  FutureOr<AccountState> build() => initial;

  @override
  Future<void> restoreAfterUnlock() async {}
}

class _FailingRestoringAccountNotifier extends _RestoringAccountNotifier {
  @override
  Future<void> restoreAfterUnlock() async =>
      throw StateError('recovery failed');
}

Future<void> _enterPasscode(WidgetTester tester, String passcode) async {
  for (final digit in passcode.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $digit'));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

class _UnlockSyncNotifier extends SyncNotifier {
  _UnlockSyncNotifier([this.syncStart]);

  /// Holds the sync start open when set, as one waiting out a cancelled
  /// sync does.
  final Completer<void>? syncStart;
  int syncStarts = 0;

  @override
  Future<SyncState> build() async => SyncState();

  @override
  Future<void> refreshAfterUnlock() async {}

  @override
  Future<void> clearSensitiveStateForLock() async {}

  @override
  Future<void> startSyncAnyway({int? latestTipHeight}) async {
    syncStarts++;
    await syncStart?.future;
  }
}

AppBootstrapState _bootstrap({
  required bool biometricEnabled,
  MobileAccountVisibilityConfig visibility =
      const MobileAccountVisibilityConfig(),
}) => AppBootstrapState(
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
  mobileAccountVisibility: visibility,
);

Widget _app({
  FakeBiometricUnlock? biometric,
  BiometricUnlockNotifier Function()? biometricNotifier,
  AppBootstrapState? bootstrap,

  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(
        bootstrap ?? _bootstrap(biometricEnabled: false),
      ),
      if (biometricNotifier != null)
        biometricUnlockProvider.overrideWith(biometricNotifier)
      else if (biometric != null)
        biometricUnlockServiceProvider.overrideWithValue(biometric),
      ...extraOverrides,
    ],
    child: MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      builder: (_, c) => AppTheme(data: AppThemeData.light, child: c!),
      home: MobileUnlockScreen(),
    ),
  );
}

({Widget app, GoRouter router}) _routedUnlockApp({
  FakeBiometricUnlock? biometric,

  bool useRealSecurity = false,
  MobileAccountVisibilityConfig visibility =
      const MobileAccountVisibilityConfig(),
  AccountNotifier Function()? accountNotifier,
  _UnlockSyncNotifier Function()? syncNotifier,
}) {
  final router = GoRouter(
    initialLocation: '/unlock',
    routes: [
      GoRoute(path: '/unlock', builder: (_, _) => MobileUnlockScreen()),
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
        _bootstrap(biometricEnabled: biometric != null, visibility: visibility),
      ),
      if (useRealSecurity)
        appSecurityProvider.overrideWith(
          () => AppSecurityNotifier.testing(
            store: AppSecureStore.testing(
              storage: const FlutterSecureStorage(),
            ),
          ),
        )
      else
        appSecurityProvider.overrideWith(_SuccessfulSecurityNotifier.new),
      accountProvider.overrideWith(
        accountNotifier ?? _RestoringAccountNotifier.new,
      ),
      syncProvider.overrideWith(syncNotifier ?? _UnlockSyncNotifier.new),
      if (biometric != null)
        biometricUnlockServiceProvider.overrideWithValue(biometric),
    ],
    child: MaterialApp.router(
      localizationsDelegates: appLocalizationsDelegates,
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

class _ResetBlockedAccountNotifier extends AccountNotifier {
  var resets = 0;

  @override
  FutureOr<AccountState> build() => const AccountState();

  @override
  Future<void> restoreAfterUnlock() async {}

  @override
  Future<void> resetWallet({int? confirmedUnsharedGiftCardCount}) async {
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
    FlutterSecureStorage.setMockInitialValues({});
    AppSecureStore.instance.clearSessionPassword();
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
    expect(
      find.text(
        'If you haven’t backed up an account’s secret passphrase, '
        'you can’t recover its funds after resetting Vizor.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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
    expect(find.text(testL10n.walletResetGiftCardWarning), findsOneWidget);
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
        GoRoute(path: '/unlock', builder: (_, _) => const MobileUnlockScreen()),
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
          localizationsDelegates: appLocalizationsDelegates,
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
    expect(find.text(testL10n.walletResetGiftCardInFlight), findsOneWidget);
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
      const channel = MethodChannel('com.zcash.wallet/haptics');
      final confirmations = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        confirmations.add(call.method);
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
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
      expect(confirmations, ['success']);
      expect(find.text('Payment link destination'), findsNothing);
    });

    testWidgets('a slow sync start does not hold the unlock off Home', (
      tester,
    ) async {
      final syncStart = Completer<void>();
      final sync = _UnlockSyncNotifier(syncStart);
      final routed = _routedUnlockApp(syncNotifier: () => sync);
      addTearDown(routed.router.dispose);
      await tester.pumpWidget(routed.app);

      for (final digit in '123456'.split('')) {
        await tester.tap(find.bySemanticsLabel('Digit $digit'));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(sync.syncStarts, 1);
      expect(routed.router.state.uri.path, '/home');
      expect(find.text('Home destination'), findsOneWidget);
      syncStart.complete();
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
      final routed = _routedUnlockApp(biometric: biometric);
      addTearDown(routed.router.dispose);
      await tester.pumpWidget(routed.app);
      _queuePendingPaymentLink(tester);

      expect(biometric.reads, 0);
      await _enterPasscode(tester, '123456');
      await tester.pumpAndSettle();

      expect(biometric.reads, 1);
      expect(routed.router.state.uri.path, '/payment-links');
      expect(find.text('Payment link destination'), findsOneWidget);
      expect(find.text('Home destination'), findsNothing);
    });
  });

  group('biometric opt-in', () {
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      await AppSecureStore.instance.configurePassword('123456');
      AppSecureStore.instance.clearSessionPassword();
    });

    tearDown(AppSecureStore.instance.clearSessionPassword);

    for (final kind in [
      BiometricKind.face,
      BiometricKind.touchId,
      BiometricKind.fingerprint,
    ]) {
      testWidgets('offers ${kind.name} only as an unchecked option', (
        tester,
      ) async {
        final biometric = FakeBiometricUnlock(
          avail: BiometricAvailability(
            supported: true,
            enrolled: true,
            kind: kind,
          ),
        );
        await tester.pumpWidget(_app(biometric: biometric));
        await tester.pumpAndSettle();

        final option = find.byType(PasscodeBiometricOptIn);
        expect(option, findsOneWidget);
        expect(tester.widget<PasscodeBiometricOptIn>(option).selected, isFalse);
        expect(
          find.bySemanticsLabel(kind.useNextTimeLabel(testL10n)),
          findsOneWidget,
        );
        expect(find.byType(PasscodeBiometricButton), findsNothing);
        expect(biometric.enables, 0);
        expect(biometric.reads, 0);
      });
    }

    for (final availability in [
      BiometricAvailability.unavailable,
      const BiometricAvailability(
        supported: true,
        enrolled: false,
        kind: BiometricKind.face,
      ),
    ]) {
      testWidgets('hides opt-in when enrollment is ${availability.enrolled}', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(biometric: FakeBiometricUnlock(avail: availability)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PasscodeBiometricOptIn), findsNothing);
      });
    }

    testWidgets('does not offer opt-in before availability resolves', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          bootstrap: _bootstrap(biometricEnabled: false),
          biometricNotifier: _PendingBiometricNotifier.new,
        ),
      );
      await tester.pump();
      expect(find.byType(PasscodeBiometricOptIn), findsNothing);
    });

    testWidgets('unchecked unlock does not enable biometrics', (tester) async {
      final biometric = FakeBiometricUnlock(avail: faceAvailability);
      final routed = _routedUnlockApp(
        biometric: biometric,
        useRealSecurity: true,
      );
      addTearDown(routed.router.dispose);
      await tester.pumpWidget(routed.app);
      await tester.pumpAndSettle();
      await _enterPasscode(tester, '123456');
      expect(routed.router.state.uri.path, '/home');
      expect(biometric.enables, 0);
      expect(
        await AppSecureStore.instance.readPlain(kBiometricUnlockEnabledKey),
        isNot('true'),
      );
    });

    testWidgets('keeps opt-in after a wrong passcode and enables on success', (
      tester,
    ) async {
      final biometric = FakeBiometricUnlock(avail: faceAvailability);
      final routed = _routedUnlockApp(
        biometric: biometric,
        useRealSecurity: true,
      );
      addTearDown(routed.router.dispose);
      await tester.pumpWidget(routed.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PasscodeBiometricOptIn));
      await tester.pump();
      expect(biometric.enables, 0);

      await _enterPasscode(tester, '999999');
      expect(routed.router.state.uri.path, '/unlock');
      expect(find.text('Incorrect Passcode'), findsOneWidget);
      expect(
        tester
            .widget<PasscodeBiometricOptIn>(find.byType(PasscodeBiometricOptIn))
            .selected,
        isTrue,
      );
      expect(biometric.enables, 0);

      await _enterPasscode(tester, '123456');
      expect(routed.router.state.uri.path, '/home');
      expect(biometric.enables, 1);
      expect(biometric.escrow, '123456');
      expect(biometric.reads, 0);
      expect(
        await AppSecureStore.instance.readPlain(kBiometricUnlockEnabledKey),
        'true',
      );

      // Re-entering unlock asks for both the wallet passcode and biometrics.
      await tester.pumpWidget(const SizedBox.shrink());
      AppSecureStore.instance.clearSessionPassword();
      final reopened = _routedUnlockApp(
        biometric: biometric,
        useRealSecurity: true,
      );
      addTearDown(reopened.router.dispose);
      await tester.pumpWidget(reopened.app);
      await tester.pumpAndSettle();
      expect(biometric.reads, 0);
      await _enterPasscode(tester, '123456');
      await tester.pumpAndSettle();
      expect(biometric.reads, 1);
      expect(reopened.router.state.uri.path, '/home');
    });

    testWidgets('does not enable when wallet recovery fails', (tester) async {
      final biometric = FakeBiometricUnlock(avail: faceAvailability);
      final routed = _routedUnlockApp(
        biometric: biometric,
        useRealSecurity: true,
        accountNotifier: _FailingRestoringAccountNotifier.new,
      );
      addTearDown(routed.router.dispose);
      await tester.pumpWidget(routed.app);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PasscodeBiometricOptIn));
      await _enterPasscode(tester, '123456');
      expect(routed.router.state.uri.path, '/unlock');
      expect(biometric.enables, 0);
      expect(
        find.text("Couldn't open your wallet. Please try again."),
        findsOneWidget,
      );
    });

    for (final error in [
      BiometricUnlockErrorKind.cancelled,
      BiometricUnlockErrorKind.failed,
      BiometricUnlockErrorKind.unavailable,
    ]) {
      testWidgets('$error during enable preserves the Gift Card destination', (
        tester,
      ) async {
        final biometric = FakeBiometricUnlock(avail: faceAvailability)
          ..enableError = error;
        final routed = _routedUnlockApp(
          biometric: biometric,
          useRealSecurity: true,
        );
        addTearDown(routed.router.dispose);
        await tester.pumpWidget(routed.app);
        await tester.pumpAndSettle();
        _queuePendingPaymentLink(tester);
        await tester.tap(find.byType(PasscodeBiometricOptIn));
        await _enterPasscode(tester, '123456');
        expect(routed.router.state.uri.path, '/payment-links');
        expect(biometric.enables, 1);
        expect(biometric.escrow, isNull);
        expect(
          await AppSecureStore.instance.readPlain(kBiometricUnlockEnabledKey),
          isNot('true'),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('waits for enable without accepting another input or prompt', (
      tester,
    ) async {
      final biometric = FakeBiometricUnlock(avail: faceAvailability)
        ..enableCompleter = Completer<void>();
      final routed = _routedUnlockApp(
        biometric: biometric,
        useRealSecurity: true,
      );
      addTearDown(routed.router.dispose);
      await tester.pumpWidget(routed.app);
      await tester.pumpAndSettle();
      _queuePendingPaymentLink(tester);
      await tester.tap(find.byType(PasscodeBiometricOptIn));
      await _enterPasscode(tester, '123456');
      expect(biometric.enables, 1);
      expect(routed.router.state.uri.path, '/unlock');
      expect(
        tester
            .widget<PasscodeBiometricOptIn>(find.byType(PasscodeBiometricOptIn))
            .onChanged,
        isNull,
      );
      expect(
        tester.widget<PasscodeNumpad>(find.byType(PasscodeNumpad)).enabled,
        isFalse,
      );
      expect(biometric.reads, 0);
      biometric.enableCompleter!.complete();
      await tester.pumpAndSettle();
      expect(routed.router.state.uri.path, '/payment-links');
      expect(biometric.reads, 0);
    });

    testWidgets('a session locked during enable stays on unlock', (
      tester,
    ) async {
      final biometric = FakeBiometricUnlock(avail: faceAvailability)
        ..enableCompleter = Completer<void>();
      final routed = _routedUnlockApp(
        biometric: biometric,
        useRealSecurity: true,
      );
      addTearDown(routed.router.dispose);
      await tester.pumpWidget(routed.app);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MobileUnlockScreen)),
      );
      await tester.tap(find.byType(PasscodeBiometricOptIn));
      await _enterPasscode(tester, '123456');
      container.read(appSecurityProvider.notifier).lock();
      biometric.enableCompleter!.complete();
      await tester.pumpAndSettle();
      expect(routed.router.state.uri.path, '/unlock');
      expect(container.read(appSecurityProvider).isUnlocked, isFalse);
      expect(
        tester.widget<PasscodeNumpad>(find.byType(PasscodeNumpad)).enabled,
        isTrue,
      );
    });

    testWidgets(
      'small screen keeps a three-column keypad and scrollable opt-in',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          _app(biometric: FakeBiometricUnlock(avail: fingerprintAvailability)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          tester.getTopLeft(find.bySemanticsLabel('Digit 1')).dy,
          tester.getTopLeft(find.bySemanticsLabel('Digit 3')).dy,
        );
        await tester.ensureVisible(find.byType(PasscodeBiometricOptIn));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(PasscodeBiometricOptIn));
        await tester.pump();
        expect(
          tester
              .widget<PasscodeBiometricOptIn>(
                find.byType(PasscodeBiometricOptIn),
              )
              .selected,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
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

      await tester.pumpWidget(
        _app(
          extraOverrides: [
            appSecurityProvider.overrideWith(_SuccessfulSecurityNotifier.new),
            accountProvider.overrideWith(_RestoringAccountNotifier.new),
            syncProvider.overrideWith(_UnlockSyncNotifier.new),
          ],
        ),
      );
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

  group('accounts by passcode', () {
    const ordinary = AccountInfo(uuid: 'ordinary', name: 'Everyday', order: 0);
    const hidden = AccountInfo(uuid: 'hidden', name: 'Reserve', order: 1);
    const initial = AccountState(
      accounts: [ordinary, hidden],
      activeAccountUuid: 'hidden',
    );

    Future<MobileAccountVisibilityConfig> configuration() async {
      final store = MobileAccountVisibilityStore(AppSecureStore.instance);
      const salt = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
      return MobileAccountVisibilityConfig(
        salt: salt,
        rules: [
          MobileAccountVisibilityRule(
            id: 'reserve',
            verifier: await store.verifier('246810', salt),
            accountIds: const {'hidden'},
          ),
        ],
      );
    }

    testWidgets(
      'B requires A without biometrics and A later restores an ordinary account',
      (tester) async {
        final visibility = await configuration();
        final routed = _routedUnlockApp(
          visibility: visibility,
          accountNotifier: () => _RestoringAccountNotifier(initial),
        );
        addTearDown(routed.router.dispose);
        await tester.pumpWidget(routed.app);
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MobileUnlockScreen)),
        );

        await _enterPasscode(tester, '246810');
        expect(routed.router.state.uri.path, '/unlock');
        expect(container.read(appSecurityProvider).isUnlocked, isFalse);
        expect(container.read(visibleAccountsProvider), [ordinary]);
        expect(find.text('Now enter your wallet passcode'), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('mobile_unlock_cancel_separate_passcode')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Now enter your wallet passcode'), findsNothing);
        expect(container.read(appSecurityProvider).isUnlocked, isFalse);
        await _enterPasscode(tester, '246810');
        await _enterPasscode(tester, '123456');
        expect(container.read(visibleAccountsProvider), [hidden]);
        expect(
          container.read(accountProvider).value?.activeAccountUuid,
          hidden.uuid,
        );
        expect(routed.router.state.uri.path, '/home');

        container.read(appSecurityProvider.notifier).lock();
        routed.router.go('/unlock');
        await tester.pumpAndSettle();
        await _enterPasscode(tester, '123456');
        expect(container.read(visibleAccountsProvider), [ordinary]);
        expect(
          container.read(accountProvider).value?.activeAccountUuid,
          ordinary.uuid,
        );
        expect(routed.router.state.uri.path, '/home');
      },
    );

    testWidgets('B and biometrics show linked accounts without another code', (
      tester,
    ) async {
      await AppSecureStore.instance.writePlain(
        kBiometricUnlockEnabledKey,
        'true',
      );
      final biometric = FakeBiometricUnlock(
        avail: faceAvailability,
        escrow: '123456',
      );
      final routed = _routedUnlockApp(
        visibility: await configuration(),
        biometric: biometric,
        accountNotifier: () => _RestoringAccountNotifier(initial),
      );
      addTearDown(routed.router.dispose);
      await tester.pumpWidget(routed.app);
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MobileUnlockScreen)),
      );
      expect(biometric.reads, 0);
      await _enterPasscode(tester, '246810');
      expect(biometric.reads, 1);
      expect(container.read(visibleAccountsProvider), [hidden]);
      expect(routed.router.state.uri.path, '/home');
    });
  });

  group('passcode before biometrics', () {
    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      await AppSecureStore.instance.configurePassword('123456');
      AppSecureStore.instance.clearSessionPassword();
      await AppSecureStore.instance.writePlain(
        kBiometricUnlockEnabledKey,
        'true',
      );
    });

    testWidgets(
      'the first frame is the keypad while biometric availability loads',
      (tester) async {
        await tester.pumpWidget(
          _app(
            bootstrap: _bootstrap(biometricEnabled: true),
            biometricNotifier: _PendingBiometricNotifier.new,
          ),
        );
        await tester.pump();
        expect(find.byType(PasscodeNumpad), findsOneWidget);
        expect(find.byType(MobileBiometricSignInView), findsNothing);
      },
    );

    testWidgets('an incorrect passcode never prompts for biometrics', (
      tester,
    ) async {
      final biometric = FakeBiometricUnlock(
        avail: faceAvailability,
        escrow: '123456',
      );
      final routed = _routedUnlockApp(
        biometric: biometric,
        useRealSecurity: true,
      );
      addTearDown(routed.router.dispose);
      await tester.pumpWidget(routed.app);
      await tester.pumpAndSettle();
      expect(biometric.reads, 0);
      await _enterPasscode(tester, '999999');
      expect(biometric.reads, 0);
      expect(routed.router.state.uri.path, '/unlock');
      expect(find.text('Incorrect Passcode'), findsOneWidget);
    });

    for (final failure in [
      BiometricUnlockErrorKind.cancelled,
      BiometricUnlockErrorKind.invalidated,
      BiometricUnlockErrorKind.unavailable,
    ]) {
      testWidgets('$failure keeps the second factor enabled across retries', (
        tester,
      ) async {
        final biometric = FakeBiometricUnlock(
          avail: faceAvailability,
          escrow: '123456',
        )..readError = failure;
        final routed = _routedUnlockApp(
          biometric: biometric,
          useRealSecurity: true,
        );
        addTearDown(routed.router.dispose);
        await tester.pumpWidget(routed.app);
        await tester.pumpAndSettle();

        await _enterPasscode(tester, '123456');
        expect(biometric.reads, 1);
        expect(routed.router.state.uri.path, '/unlock');
        expect(
          find.text('Biometric verification is required. Try again.'),
          findsOneWidget,
        );
        expect(
          await AppSecureStore.instance.readPlain(kBiometricUnlockEnabledKey),
          'true',
        );

        biometric.readError = null;
        await _enterPasscode(tester, '123456');
        expect(biometric.reads, 2);
        expect(routed.router.state.uri.path, '/home');
      });
    }
  });
}
