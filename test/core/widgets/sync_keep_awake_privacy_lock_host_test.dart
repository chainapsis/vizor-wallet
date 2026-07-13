@Tags(['mobile'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/sync_keep_awake_interaction_listener.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/sync_keep_awake_privacy_lock_host.dart';
import 'package:zcash_wallet/src/features/onboarding/mobile/passcode_widgets.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/providers/biometric_unlock_provider.dart';
import 'package:zcash_wallet/src/providers/sync_keep_awake_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/services/biometric_unlock.dart';

import '../../fakes/fake_sync_notifier.dart';

class _FakeSecurityNotifier extends AppSecurityNotifier {
  _FakeSecurityNotifier({this.confirmResult = true});

  final bool confirmResult;
  final confirmedWith = <String>[];

  @override
  Future<bool> confirmPassword(String password) async {
    confirmedWith.add(password);
    return confirmResult;
  }
}

class _FakeBiometricUnlockNotifier extends BiometricUnlockNotifier {
  _FakeBiometricUnlockNotifier(
    this.initialState, {
    this.passcode,
    this.stateAfterRead,
    this.buildCompleter,
  });

  final BiometricUnlockState initialState;
  final String? passcode;
  final BiometricUnlockState? stateAfterRead;
  final Completer<BiometricUnlockState>? buildCompleter;
  var reads = 0;

  @override
  Future<BiometricUnlockState> build() async =>
      buildCompleter?.future ?? initialState;

  @override
  Future<String?> readPasscode({required String reason}) async {
    reads += 1;
    final nextState = stateAfterRead;
    if (nextState != null) state = AsyncData(nextState);
    return passcode;
  }
}

const _disabledBiometricState = BiometricUnlockState(
  availability: BiometricAvailability.unavailable,
  enabled: false,
);

const _faceBiometricState = BiometricUnlockState(
  availability: BiometricAvailability(
    supported: true,
    enrolled: true,
    kind: BiometricKind.face,
  ),
  enabled: true,
);

const _fingerprintBiometricState = BiometricUnlockState(
  availability: BiometricAvailability(
    supported: true,
    enrolled: true,
    kind: BiometricKind.fingerprint,
  ),
  enabled: true,
);

void main() {
  testWidgets('shows the privacy screen after keep-awake idle timeout', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        syncNotifier: FakeSyncNotifier(
          _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
        ),
      ),
    );
    await _settleInitialSync(tester);

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('Unlock Vizor'), findsOneWidget);
  });

  testWidgets('does not show the privacy screen for near-tip catch-up', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        syncNotifier: FakeSyncNotifier(
          _sync(
            scannedHeight: 100,
            chainTipHeight: 102,
            lastSyncStartedAt: DateTime(2026, 7, 9, 12),
          ),
        ),
      ),
    );
    await _settleInitialSync(tester);

    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsNothing);
  });

  testWidgets('recent interaction delays the privacy screen', (tester) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        syncNotifier: FakeSyncNotifier(
          _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
        ),
      ),
    );
    await _settleInitialSync(tester);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.byKey(const ValueKey('home_surface')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsNothing);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsOneWidget);
  });

  testWidgets(
    'background time does not trigger an immediate privacy lock on resume',
    (tester) async {
      _setMobileViewport(tester);
      await tester.pumpWidget(
        _app(
          syncNotifier: FakeSyncNotifier(
            _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
          ),
        ),
      );
      await _settleInitialSync(tester);

      await tester.tap(find.byKey(const ValueKey('home_surface')));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.pump(const Duration(minutes: 5));

      expect(find.text('Vizor is syncing,\nstick around ...'), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text('Vizor is syncing,\nstick around ...'), findsNothing);

      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(find.text('Vizor is syncing,\nstick around ...'), findsOneWidget);
    },
  );

  testWidgets('an existing privacy lock remains latched across background', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        syncNotifier: FakeSyncNotifier(
          _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
        ),
      ),
    );
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(minutes: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsOneWidget);
  });

  testWidgets('passcode confirmation clears the virtual privacy lock', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final security = _FakeSecurityNotifier();
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        appSecurityProvider.overrideWith(() => security),
        biometricUnlockProvider.overrideWith(
          () => _FakeBiometricUnlockNotifier(_disabledBiometricState),
        ),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _themedApp()),
    );
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);

    await tester.tap(find.text('Unlock Vizor'));
    await tester.pump();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('25% Syncing...'), findsOneWidget);
    expect(find.text('Vizor is syncing, stick around ...'), findsOneWidget);
    expect(find.byType(PasscodeNumpad), findsOneWidget);
    expect(find.bySemanticsLabel('Passcode help'), findsNothing);
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);

    await _enterPasscode(tester, '123456');

    expect(security.confirmedWith, ['123456']);
    expect(find.text('Welcome Back'), findsNothing);
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isFalse);
  });

  testWidgets(
    'biometric confirmation clears the virtual lock without passcode UI',
    (tester) async {
      _setMobileViewport(tester);
      final security = _FakeSecurityNotifier();
      final biometric = _FakeBiometricUnlockNotifier(
        _faceBiometricState,
        passcode: '123456',
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          appSecurityProvider.overrideWith(() => security),
          biometricUnlockProvider.overrideWith(() => biometric),
          syncProvider.overrideWith(
            () => FakeSyncNotifier(
              _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _themedApp()),
      );
      await _settleInitialSync(tester);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);
      expect(_findAppIcon(AppIcons.faceId), findsOneWidget);

      await tester.tap(find.text('Unlock Vizor'));
      await tester.pump();
      await tester.pump();

      expect(biometric.reads, 1);
      expect(security.confirmedWith, ['123456']);
      expect(find.text('Welcome Back'), findsNothing);
      expect(find.byType(PasscodeNumpad), findsNothing);
      expect(
        container.read(syncKeepAwakePrivacyLockProvider).isLocked,
        isFalse,
      );
    },
  );

  testWidgets(
    'unlock attempt suppresses duplicate taps before probe resolves',
    (tester) async {
      _setMobileViewport(tester);
      final security = _FakeSecurityNotifier();
      final buildCompleter = Completer<BiometricUnlockState>();
      final biometric = _FakeBiometricUnlockNotifier(
        _faceBiometricState,
        passcode: '123456',
        buildCompleter: buildCompleter,
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          appSecurityProvider.overrideWith(() => security),
          biometricUnlockProvider.overrideWith(() => biometric),
          syncProvider.overrideWith(
            () => FakeSyncNotifier(
              _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _themedApp()),
      );
      await _settleInitialSync(tester);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      await tester.tap(find.text('Unlock Vizor'));
      await tester.tap(find.text('Unlock Vizor'));

      buildCompleter.complete(_faceBiometricState);
      await tester.pump();
      await tester.pump();

      expect(biometric.reads, 1);
      expect(security.confirmedWith, ['123456']);
      expect(
        container.read(syncKeepAwakePrivacyLockProvider).isLocked,
        isFalse,
      );
    },
  );

  testWidgets('biometric cancellation falls back to passcode confirmation', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final security = _FakeSecurityNotifier();
    final biometric = _FakeBiometricUnlockNotifier(_faceBiometricState);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        appSecurityProvider.overrideWith(() => security),
        biometricUnlockProvider.overrideWith(() => biometric),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _themedApp()),
    );
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    await tester.tap(find.text('Unlock Vizor'));
    await tester.pump();
    await tester.pump();

    expect(biometric.reads, 1);
    expect(security.confirmedWith, isEmpty);
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.byType(PasscodeNumpad), findsOneWidget);
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);

    await _enterPasscode(tester, '123456');

    expect(security.confirmedWith, ['123456']);
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isFalse);
  });

  testWidgets('biometric invalidation explains the passcode fallback', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final biometric = _FakeBiometricUnlockNotifier(
      _faceBiometricState,
      stateAfterRead: _faceBiometricState.copyWith(enabled: false),
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
        biometricUnlockProvider.overrideWith(() => biometric),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _themedApp()),
    );
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    await tester.tap(find.text('Unlock Vizor'));
    await tester.pump();
    await tester.pump();

    expect(biometric.reads, 1);
    expect(find.text('Face ID changed. Enter your passcode.'), findsOneWidget);
    expect(find.byType(PasscodeNumpad), findsOneWidget);
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);
  });

  testWidgets('wrong passcode keeps the virtual privacy lock visible', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final security = _FakeSecurityNotifier(confirmResult: false);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        appSecurityProvider.overrideWith(() => security),
        biometricUnlockProvider.overrideWith(
          () => _FakeBiometricUnlockNotifier(_disabledBiometricState),
        ),
        syncProvider.overrideWith(
          () => FakeSyncNotifier(
            _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _themedApp()),
    );
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    await tester.tap(find.text('Unlock Vizor'));
    await tester.pump();
    await _enterPasscode(tester, '999999');

    expect(security.confirmedWith, ['999999']);
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);
    expect(find.text('Incorrect Passcode'), findsOneWidget);
    expect(find.text('Welcome Back'), findsOneWidget);
  });

  testWidgets('keeps the privacy screen and shows done after sync completes', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        biometricUnlockProvider.overrideWith(
          () => _FakeBiometricUnlockNotifier(_disabledBiometricState),
        ),
        syncProvider.overrideWith(() => syncNotifier),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _themedApp()),
    );
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();

    expect(find.text('Vizor is syncing,\nstick around ...'), findsOneWidget);

    syncNotifier.emit(
      _sync(
        isSyncing: false,
        percentage: 1,
        displayPercentage: 1,
        scannedHeight: 200,
        chainTipHeight: 200,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );
    await tester.pump();

    expect(container.read(syncKeepAwakeActiveProvider), isFalse);
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.done,
    );
    expect(find.text('Vizor is syncing,\nstick around ...'), findsNothing);
    expect(find.text('Synced'), findsOneWidget);
    expect(
      find.text('Synced successfully.\nYou can unlock Vizor.'),
      findsOneWidget,
    );
    expect(find.text('Unlock Vizor'), findsOneWidget);
  });

  testWidgets('keeps the privacy screen across near-tip follow-up syncs', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final syncNotifier = FakeSyncNotifier(
      _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
    );
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        biometricUnlockProvider.overrideWith(
          () => _FakeBiometricUnlockNotifier(_disabledBiometricState),
        ),
        syncProvider.overrideWith(() => syncNotifier),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: _themedApp()),
    );
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    syncNotifier.emit(
      _sync(
        isSyncing: false,
        percentage: 1,
        displayPercentage: 1,
        scannedHeight: 200,
        chainTipHeight: 200,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );
    await tester.pump();

    expect(find.text('Synced'), findsOneWidget);

    syncNotifier.emit(
      _sync(
        percentage: 0,
        displayPercentage: 0,
        scannedHeight: 200,
        chainTipHeight: 202,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12, 2),
      ),
    );
    await tester.pump();

    expect(container.read(syncKeepAwakeActiveProvider), isFalse);
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.syncing,
    );
    expect(find.text('Synced'), findsNothing);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Vizor is syncing,\nstick around ...'), findsOneWidget);

    syncNotifier.emit(
      _sync(
        isSyncing: false,
        percentage: 1,
        displayPercentage: 1,
        scannedHeight: 202,
        chainTipHeight: 202,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12, 2),
      ),
    );
    await tester.pump();

    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.done,
    );
    expect(find.text('Synced'), findsOneWidget);
    expect(find.text('Unlock Vizor'), findsOneWidget);
  });

  testWidgets(
    'keeps the privacy screen with paused copy when sync stops early',
    (tester) async {
      _setMobileViewport(tester);
      final syncNotifier = FakeSyncNotifier(
        _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
      );
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          biometricUnlockProvider.overrideWith(
            () => _FakeBiometricUnlockNotifier(_disabledBiometricState),
          ),
          syncProvider.overrideWith(() => syncNotifier),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _themedApp()),
      );
      await _settleInitialSync(tester);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      syncNotifier.emit(
        _sync(
          isSyncing: false,
          percentage: 0.5,
          displayPercentage: 0.5,
          scannedHeight: 150,
          chainTipHeight: 200,
          lastSyncStartedAt: DateTime(2026, 7, 9, 12),
        ),
      );
      await tester.pump();

      expect(container.read(syncKeepAwakeActiveProvider), isFalse);
      expect(
        container.read(syncKeepAwakePrivacyLockModeProvider),
        SyncKeepAwakePrivacyLockMode.interrupted,
      );
      expect(find.text('Synced'), findsNothing);
      expect(
        find.text('Synced successfully.\nYou can unlock Vizor.'),
        findsNothing,
      );
      expect(find.text('Sync paused'), findsOneWidget);
      expect(find.text('Unlock Vizor to continue.'), findsOneWidget);
      expect(find.text('Unlock Vizor'), findsOneWidget);
    },
  );

  testWidgets('keeps the Figma vertical position on the reference viewport', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(_privacyScreenApp());
    await _settleInitialSync(tester);

    final logoRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_logo')),
    );

    expect(logoRect.top, closeTo(110, 0.1));
  });

  testWidgets('keeps the done state Figma vertical positions', (tester) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _privacyScreenApp(mode: SyncKeepAwakePrivacyLockMode.done),
    );
    await _settleInitialSync(tester);

    final checkRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_done_check')),
    );
    final titleRect = tester.getRect(find.text('Synced'));
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_unlock_button')),
    );

    expect(checkRect.top, closeTo(306, 0.1));
    expect(titleRect.top, closeTo(406, 0.1));
    expect(buttonRect.top, closeTo(653, 0.1));
  });

  testWidgets('uses the status layout for the interrupted state', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _privacyScreenApp(mode: SyncKeepAwakePrivacyLockMode.interrupted),
    );
    await _settleInitialSync(tester);

    final warningRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_interrupted_warning')),
    );
    final titleRect = tester.getRect(find.text('Sync paused'));
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_unlock_button')),
    );

    expect(warningRect.top, closeTo(306, 0.1));
    expect(titleRect.top, closeTo(406, 0.1));
    expect(buttonRect.top, closeTo(653, 0.1));
  });

  testWidgets('renders the current display sync percentage', (tester) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(_privacyScreenApp());
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 420));

    expect(find.text('63%'), findsOneWidget);
  });

  testWidgets('animates display sync percentage changes', (tester) async {
    _setMobileViewport(tester);
    final syncNotifier = FakeSyncNotifier(
      _sync(
        percentage: 0.05,
        displayPercentage: 0.05,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          biometricUnlockProvider.overrideWith(
            () => _FakeBiometricUnlockNotifier(_disabledBiometricState),
          ),
          syncProvider.overrideWith(() => syncNotifier),
        ],
        child: MaterialApp(
          builder: (_, child) =>
              AppTheme(data: AppThemeData.light, child: child!),
          home: const SyncKeepAwakePrivacyLockScreen(),
        ),
      ),
    );
    await _settleInitialSync(tester);
    await tester.pump(const Duration(milliseconds: 420));

    expect(find.text('5%'), findsOneWidget);

    syncNotifier.emit(
      _sync(
        percentage: 0.10,
        displayPercentage: 0.10,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );
    await tester.pump();

    expect(find.text('10%'), findsNothing);

    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text('10%'), findsNothing);

    await tester.pump(const Duration(milliseconds: 420));

    expect(find.text('10%'), findsOneWidget);
  });

  testWidgets('centers the privacy stack on a shorter phone viewport', (
    tester,
  ) async {
    _setMobileViewport(tester, size: const Size(375, 667));
    await tester.pumpWidget(_privacyScreenApp());
    await _settleInitialSync(tester);

    final logoRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_logo')),
    );
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_unlock_button')),
    );
    final bottomGap =
        tester.view.physicalSize.height / tester.view.devicePixelRatio -
        buttonRect.bottom;

    expect(logoRect.top, greaterThanOrEqualTo(0));
    expect(buttonRect.bottom, lessThanOrEqualTo(667));
    expect((logoRect.top - bottomGap).abs(), lessThanOrEqualTo(1));
  });

  testWidgets('keeps logo and unlock button visible on compact short phones', (
    tester,
  ) async {
    _setMobileViewport(tester, size: const Size(320, 568));
    await tester.pumpWidget(_privacyScreenApp());
    await _settleInitialSync(tester);

    final logoRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_logo')),
    );
    final buttonRect = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_unlock_button')),
    );

    expect(logoRect.top, greaterThanOrEqualTo(0));
    expect(buttonRect.bottom, lessThanOrEqualTo(568));
  });

  testWidgets('uses the unlock icon when biometric unlock is unavailable', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(_privacyScreenApp());
    await _settleInitialSync(tester);

    expect(_findAppIcon(AppIcons.unlock), findsOneWidget);
    expect(_findAppIcon(AppIcons.faceId), findsNothing);
    expect(find.byIcon(Icons.fingerprint), findsNothing);
  });

  testWidgets('uses the Face ID icon when biometric unlock is usable', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _privacyScreenApp(
        biometricNotifier: () =>
            _FakeBiometricUnlockNotifier(_faceBiometricState),
      ),
    );
    await _settleInitialSync(tester);
    await tester.pump();

    expect(_findAppIcon(AppIcons.faceId), findsOneWidget);
    expect(_findAppIcon(AppIcons.unlock), findsNothing);
    expect(find.byIcon(Icons.fingerprint), findsNothing);
  });

  testWidgets('uses the fingerprint icon when fingerprint unlock is usable', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _privacyScreenApp(
        biometricNotifier: () =>
            _FakeBiometricUnlockNotifier(_fingerprintBiometricState),
      ),
    );
    await _settleInitialSync(tester);
    await tester.pump();

    expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    expect(_findAppIcon(AppIcons.unlock), findsNothing);
    expect(_findAppIcon(AppIcons.faceId), findsNothing);
  });
}

void _setMobileViewport(
  WidgetTester tester, {
  Size size = const Size(393, 852),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app({required FakeSyncNotifier syncNotifier}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
      biometricUnlockProvider.overrideWith(
        () => _FakeBiometricUnlockNotifier(_disabledBiometricState),
      ),
      syncProvider.overrideWith(() => syncNotifier),
    ],
    child: _themedApp(),
  );
}

Widget _privacyScreenApp({
  SyncKeepAwakePrivacyLockMode mode = SyncKeepAwakePrivacyLockMode.syncing,
  BiometricUnlockNotifier Function()? biometricNotifier,
}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
      biometricUnlockProvider.overrideWith(
        biometricNotifier ??
            () => _FakeBiometricUnlockNotifier(_disabledBiometricState),
      ),
      syncProvider.overrideWith(
        () => FakeSyncNotifier(
          _sync(percentage: 0.63, lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
        ),
      ),
    ],
    child: MaterialApp(
      builder: (_, child) => AppTheme(data: AppThemeData.light, child: child!),
      home: SyncKeepAwakePrivacyLockScreen(mode: mode),
    ),
  );
}

Widget _themedApp() {
  return MaterialApp(
    builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
    home: SyncKeepAwakePrivacyLockHost(
      idleTimeout: const Duration(milliseconds: 50),
      child: SyncKeepAwakeInteractionListener(
        child: Scaffold(
          body: GestureDetector(
            key: const ValueKey('home_surface'),
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: const Center(child: Text('Home')),
          ),
        ),
      ),
    ),
  );
}

Future<void> _settleInitialSync(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _enterPasscode(WidgetTester tester, String digits) async {
  for (final digit in digits.split('')) {
    await tester.tap(find.bySemanticsLabel('Digit $digit'));
    await tester.pump();
  }
  await tester.pump();
  await tester.pump();
}

Finder _findAppIcon(String iconName) {
  return find.byWidgetPredicate(
    (widget) => widget is AppIcon && widget.name == iconName,
    description: 'AppIcon($iconName)',
  );
}

AppBootstrapState _bootstrap() {
  return AppBootstrapState(
    initialLocation: '/home',
    initialAccountState: const AccountState(),
    initialSyncSnapshot: AppSyncSnapshot.empty,
    network: kZcashDefaultNetworkName,
    rpcEndpointConfig: defaultRpcEndpointConfig(kZcashDefaultNetworkName),
    themeMode: ThemeMode.dark,
    privacyModeEnabled: false,
    syncKeepAwakeEnabled: true,
    syncKeepAwakePromptSeen: true,
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

SyncState _sync({
  bool isSyncing = true,
  bool isBackgroundMode = false,
  double percentage = 0.25,
  double? displayPercentage,
  int scannedHeight = 100,
  int chainTipHeight = 200,
  DateTime? lastSyncStartedAt,
}) {
  return SyncState(
    isSyncing: isSyncing,
    isBackgroundMode: isBackgroundMode,
    percentage: percentage,
    displayPercentage: displayPercentage,
    scannedHeight: scannedHeight,
    chainTipHeight: chainTipHeight,
    lastSyncStartedAt: lastSyncStartedAt,
  );
}
