import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/features/onboarding/lost_password_screen.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/forgot_passcode_sheet.dart';
import 'package:zcash_wallet/src/providers/account_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/providers/device_owner_auth_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/services/device_owner_auth.dart';

class _FakeDeviceOwnerAuth extends DeviceOwnerAuth {
  _FakeDeviceOwnerAuth({required this.result});

  final bool result;
  var calls = 0;
  String? lastReason;

  @override
  Future<bool> verify({required String reason}) async {
    calls += 1;
    lastReason = reason;
    return result;
  }
}

class _ThrowingDeviceOwnerAuth extends DeviceOwnerAuth {
  var calls = 0;

  @override
  Future<bool> verify({required String reason}) async {
    calls += 1;
    throw const DeviceOwnerAuthException(
      DeviceOwnerAuthErrorKind.unavailable,
    );
  }
}

class _FakeAccountNotifier extends AccountNotifier {
  var resets = 0;

  @override
  FutureOr<AccountState> build() => const AccountState(
    accounts: [AccountInfo(uuid: 'account-1', name: 'Knight', order: 0)],
    activeAccountUuid: 'account-1',
  );

  @override
  Future<void> resetWallet() async {
    resets += 1;
    state = const AsyncData(AccountState());
  }
}

class _FakeSyncNotifier extends SyncNotifier {
  var sensitiveClears = 0;
  var cachedPathClears = 0;

  @override
  Future<SyncState> build() async => SyncState();

  @override
  Future<void> clearSensitiveStateForLock() async {
    sensitiveClears += 1;
    state = AsyncData(SyncState());
  }

  @override
  void clearCachedWalletDbPath() {
    cachedPathClears += 1;
  }
}

class _FakeBiometricNotifier extends BiometricUnlockNotifier {
  var disables = 0;

  @override
  Future<BiometricUnlockState> build() async => BiometricUnlockState.initial;

  @override
  Future<void> disable() async {
    disables += 1;
  }
}

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('lost-password reset cancel does not show an error', (
    tester,
  ) async {
    final auth = _FakeDeviceOwnerAuth(result: false);

    tester.view.physicalSize = const Size(1080, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [deviceOwnerAuthProvider.overrideWithValue(auth)],
        child: const MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: LostPasswordScreen(
              initialCountdownSeconds: 0,
              countdownEnabled: false,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Reset Vizor'));
    await tester.pump();

    expect(auth.calls, 1);
    expect(find.text(kWalletResetDeviceAuthRequiredMessage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lost-password reset auth error does not overflow the card', (
    tester,
  ) async {
    final auth = _ThrowingDeviceOwnerAuth();

    tester.view.physicalSize = const Size(1080, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [deviceOwnerAuthProvider.overrideWithValue(auth)],
        child: const MaterialApp(
          home: AppTheme(
            data: AppThemeData.light,
            child: LostPasswordScreen(
              initialCountdownSeconds: 0,
              countdownEnabled: false,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Reset Vizor'));
    await tester.pump();

    expect(auth.calls, 1);
    expect(find.text(kWalletResetDeviceAuthRequiredMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot-passcode helper does not wipe when auth is cancelled', (
    tester,
  ) async {
    final auth = _FakeDeviceOwnerAuth(result: false);
    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [deviceOwnerAuthProvider.overrideWithValue(auth)],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox();
          },
        ),
      ),
    );

    final didReset = await resetWalletForForgottenPasscode(capturedRef);

    expect(didReset, isFalse);
    expect(auth.calls, 1);
  });

  testWidgets('forgot-passcode helper wipes after auth succeeds', (
    tester,
  ) async {
    final auth = _FakeDeviceOwnerAuth(result: true);
    late WidgetRef capturedRef;
    late _FakeAccountNotifier accountNotifier;
    late _FakeSyncNotifier syncNotifier;
    late _FakeBiometricNotifier biometricNotifier;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceOwnerAuthProvider.overrideWithValue(auth),
          accountProvider.overrideWith(() {
            accountNotifier = _FakeAccountNotifier();
            return accountNotifier;
          }),
          syncProvider.overrideWith(() {
            syncNotifier = _FakeSyncNotifier();
            return syncNotifier;
          }),
          biometricUnlockProvider.overrideWith(() {
            biometricNotifier = _FakeBiometricNotifier();
            return biometricNotifier;
          }),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox();
          },
        ),
      ),
    );

    final didReset = await resetWalletForForgottenPasscode(capturedRef);

    expect(didReset, isTrue);
    expect(auth.calls, 1);
    expect(syncNotifier.sensitiveClears, 1);
    expect(accountNotifier.resets, 1);
    expect(syncNotifier.cachedPathClears, 1);
    expect(biometricNotifier.disables, 1);
  });
}

Future<void> _loadAppFonts() async {
  final geist = FontLoader('Geist')
    ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'));
  final youngSerif = FontLoader('Young Serif')
    ..addFont(rootBundle.load('assets/fonts/YoungSerif-Regular.ttf'));

  await Future.wait([geist.load(), youngSerif.load()]);
}
