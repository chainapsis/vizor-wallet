@Tags(['mobile'])
library;

import 'dart:async';
import 'dart:ui' show BoxHeightStyle, SemanticsAction, SemanticsActionEvent;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:go_router/go_router.dart';
import 'package:zcash_wallet/src/core/navigation/mobile_exit_back_guard.dart';
import 'package:flutter/services.dart';
import 'package:zcash_wallet/src/core/widgets/mobile/mobile_numeric_keyboard_toolbar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/platform/device_power.dart';
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
import 'package:zcash_wallet/src/providers/sync_scan_slowdown_provider.dart';
import 'package:zcash_wallet/src/providers/sync_short_catch_up_provider.dart';
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
  testWidgets(
    'accessible actions extend idle time but focus notifications do not',
    (tester) async {
      _setMobileViewport(tester);
      final semantics = tester.ensureSemantics();
      final sendFocus = FocusNode();
      addTearDown(sendFocus.dispose);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
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
        UncontrolledProviderScope(
          container: container,
          child: _coveredApp(sendFocus: sendFocus),
        ),
      );
      await _settleInitialSync(tester);
      final node = tester.getSemantics(find.text('Send'));
      void action(SemanticsAction type) =>
          tester.binding.platformDispatcher.onSemanticsActionEvent!(
            SemanticsActionEvent(
              type: type,
              viewId: tester.view.viewId,
              nodeId: node.id,
            ),
          );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 15));
        action(SemanticsAction.tap);
        await tester.pump();
      }
      expect(find.text('Sent 3'), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      expect(
        container.read(syncKeepAwakePrivacyLockProvider).isLocked,
        isFalse,
      );
      action(SemanticsAction.didGainAccessibilityFocus);
      await tester.pump(const Duration(seconds: 45));
      await tester.pump();
      expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);
      expect(find.semantics.byLabel('Send'), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets('system Back belongs to the lock before cards, routes and exit', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
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
    final navKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: navKey,
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('Home route')),
        ),
        GoRoute(
          path: '/send',
          builder: (_, _) => const Scaffold(body: Text('Send route')),
        ),
      ],
    );
    var cardDismissals = 0;
    var cardVisible = true;
    final dispatcher = MobileExitBackDispatcher(
      exitBackGuard: MobileExitBackGuard(platform: TargetPlatform.android),
      navigatorKey: navKey,
      canPop: router.canPop,
      currentLocation: () =>
          router.routerDelegate.currentConfiguration.uri.path,
      handleBackAboveRouter: () {
        if (container.read(syncKeepAwakePrivacyLockBackProvider).handleBack()) {
          return true;
        }
        if (!cardVisible) return false;
        cardVisible = false;
        cardDismissals++;
        return true;
      },
    );
    addTearDown(router.dispose);
    addTearDown(dispatcher.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routeInformationProvider: router.routeInformationProvider,
          routeInformationParser: router.routeInformationParser,
          routerDelegate: router.routerDelegate,
          backButtonDispatcher: dispatcher,
          onNavigationNotification: dispatcher.handleNavigationNotification,
          builder: (_, child) => AppTheme(
            data: AppThemeData.dark,
            child: SyncKeepAwakePrivacyLockHost(child: child!),
          ),
        ),
      ),
    );
    await _settleInitialSync(tester);
    router.push('/send');
    await tester.pumpAndSettle();
    expect(router.canPop(), isTrue);
    container.read(syncKeepAwakePrivacyLockProvider.notifier).lock();
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.binding.handlePopRoute();
      await tester.pump();
    }
    expect(router.canPop(), isTrue);
    expect(cardDismissals, 0);
    expect(find.text(MobileExitBackGuard.exitHintMessage), findsNothing);
    await tester.tap(find.text('Unlock Vizor'));
    await tester.pump();
    expect(find.text('Welcome Back'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Welcome Back'), findsNothing);
    expect(find.text('Unlock Vizor'), findsOneWidget);
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);
    expect(router.canPop(), isTrue);
    await tester.tap(find.text('Unlock Vizor'));
    await tester.pump();
    await _enterPasscode(tester, '123456');
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(cardDismissals, 1);
    expect(router.canPop(), isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.canPop(), isFalse);
  });

  testWidgets('system Back keeps an in-flight passcode confirmation intact', (
    tester,
  ) async {
    _setMobileViewport(tester);
    final pending = Completer<bool>();
    final security = _PendingSecurityNotifier(pending);
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
    container.read(syncKeepAwakePrivacyLockProvider.notifier).lock();
    await tester.pump();
    await tester.tap(find.text('Unlock Vizor'));
    await tester.pump();
    for (final digit in '123456'.split('')) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    expect(find.text('Checking passcode...'), findsOneWidget);
    expect(
      container.read(syncKeepAwakePrivacyLockBackProvider).handleBack(),
      isTrue,
    );
    await tester.pump();
    expect(find.text('Checking passcode...'), findsOneWidget);
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);
    pending.complete(true);
    await tester.pump();
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isFalse);
  });

  test(
    'late back-handler disposal cannot detach a replacement lock screen',
    () {
      var visible = true;
      final controller = SyncKeepAwakePrivacyLockBackController(() => visible);
      expect(controller.handleBack(), isTrue); // Before the first locked frame.
      var calls = 0;
      final detachOld = controller.attach(() => calls += 100);
      final detachNew = controller.attach(() => calls++);
      detachOld();
      expect(controller.handleBack(), isTrue);
      expect(calls, 1);
      visible = false;
      expect(controller.handleBack(), isFalse);
      expect(calls, 1);
      detachNew();
    },
  );

  setUpAll(() async {
    final loader = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Geist-SemiBold.ttf'));
    await loader.load();
  });

  testWidgets(
    'main scan completion stays done through Checking and unlock confirmation',
    (tester) async {
      _setMobileViewport(tester, size: const Size(320, 852));
      final initial = _sync(
        percentage: 0.99,
        lastSyncStartedAt: DateTime.utc(2026, 10, 12),
      );
      final notifier = FakeSyncNotifier(initial);
      await tester.pumpWidget(_app(syncNotifier: notifier));
      await _settleInitialSync(tester);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.text('Vizor is syncing'), findsOneWidget);

      final mainDrained = initial.copyWith(
        percentage: 1,
        scannedHeight: 200,
        chainTipHeight: 200,
        remainingScanBlocks: 0,
      );
      notifier.emit(mainDrained);
      await tester.pump();
      expect(find.text('Sync Complete'), findsOneWidget);
      expect(find.text('Vizor is syncing'), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SyncKeepAwakePrivacyLockHost)),
      );
      expect(container.read(syncKeepAwakeActiveProvider), isFalse);
      expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);

      final checking = mainDrained.copyWith(
        remainingScanBlocks: 100,
        checking: const SyncCheckingProgress(
          cycle: 1,
          percentage: 0.25,
          displayTargetPercentage: 0.5,
        ),
      );
      notifier.emit(checking);
      await tester.pump();
      expect(find.text('Sync Complete'), findsOneWidget);
      expect(find.text('Vizor is checking'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      await tester.tap(find.text('Unlock Vizor'));
      await tester.pumpAndSettle();
      expect(find.text('Synced'), findsOneWidget);
      expect(tester.takeException(), isNull);

      notifier.emit(
        checking.copyWith(
          checking: const SyncCheckingProgress(
            cycle: 2,
            percentage: 0.05,
            displayTargetPercentage: 0.1,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Synced'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      notifier.emit(checking.withSyncActivityStopped());
      await tester.pump();
      expect(find.text('Synced'), findsOneWidget);
      notifier.emit(
        mainDrained.copyWith(isSyncing: false, isSyncComplete: true),
      );
      await tester.pump();
      expect(find.text('Synced'), findsOneWidget);

      notifier.emit(
        initial.copyWith(
          percentage: 0.25,
          lastSyncStartedAt: DateTime.utc(2026, 10, 12, 0, 1),
        ),
      );
      await tester.pump();
      expect(find.text('25% Syncing…'), findsOneWidget);
      expect(find.text('Synced'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'idle privacy lock dismisses the numeric keyboard and native control',
    (tester) async {
      _setMobileViewport(tester);
      const channel = MethodChannel('com.zcash.wallet/numeric_keyboard');
      final calls = <MethodCall>[];
      addTearDown(() {
        tester.view.resetViewInsets();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      await tester.pumpWidget(
        _app(
          child: MaterialApp(
            builder: (_, child) => AppTheme(
              data: AppThemeData.dark,
              child: SyncKeepAwakePrivacyLockHost(
                idleTimeout: const Duration(minutes: 1),
                child: MobileNumericKeyboardToolbar(child: child!),
              ),
            ),
            home: const Scaffold(
              body: TextField(
                key: ValueKey('numeric-input'),
                keyboardType: TextInputType.number,
              ),
            ),
          ),
          syncNotifier: FakeSyncNotifier(
            _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
          ),
        ),
      );
      await _settleInitialSync(tester);
      await tester.enterText(
        find.byKey(const ValueKey('numeric-input')),
        '123',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump();
      await tester.pump();
      expect(calls.last.arguments['visible'], true);
      await tester.pump(const Duration(seconds: 61));
      await tester.pump();
      expect(find.text('Unlock Vizor'), findsOneWidget);
      expect(tester.testTextInput.isVisible, false);
      expect(calls.last.arguments['visible'], false);
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>()
            ?.widget
            .keyboardType,
        isNull,
      );
      expect(find.text('123'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      tester.view.resetViewInsets();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

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

    expect(find.text('Vizor is syncing'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('Unlock Vizor'), findsOneWidget);
  });

  testWidgets('with animations reduced, the percentage ring jumps to each '
      'value', (tester) async {
    _setMobileViewport(tester);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
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

    expect(find.text('25%'), findsOneWidget);
    expect(
      tester
          .widget<TweenAnimationBuilder<double>>(
            find.byType(TweenAnimationBuilder<double>),
          )
          .duration,
      Duration.zero,
    );
  });

  testWidgets(
    'the body and the slowdown note stack without overlapping at the larger '
    'default text sizes',
    (tester) async {
      _setMobileViewport(tester);
      // iOS xxLarge and Android's largest non-accessibility step.
      tester.platformDispatcher.textScaleFactorTestValue =
          defaultTargetPlatform == TargetPlatform.iOS ? 1.235 : 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(_privacyScreenApp());
      await _settleInitialSync(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SyncKeepAwakePrivacyLockScreen)),
      );
      container.read(syncScanSlowdownProvider.notifier)
        ..updateSyncJob('job', complete: false)
        ..updateDevicePower(SyncScanSlowdown.powerSaving);
      await tester.pump(kSyncScanSlowdownAfter);
      await tester.pump(const Duration(milliseconds: 500));

      final numberRect = tester.getRect(
        find.byKey(const ValueKey('sync_keep_awake_privacy_number')),
      );
      final bodyRect = tester.getRect(find.text('Vizor is syncing'));
      final noteRect = tester.getRect(
        find.byKey(const ValueKey('sync_keep_awake_privacy_slowdown')),
      );
      expect(bodyRect.top, greaterThanOrEqualTo(numberRect.bottom));
      expect(noteRect.top, greaterThanOrEqualTo(bodyRect.bottom));
      _expectLockupTextInsideRingTicks(tester);
      container
          .read(syncScanSlowdownProvider.notifier)
          .updateDevicePower(SyncScanSlowdown.heat);
      await tester.pump();
      _expectLockupTextInsideRingTicks(tester);
      // One line of body copy.
      expect(
        bodyRect.height,
        closeTo(
          tester.platformDispatcher.textScaleFactor *
              AppTypography.bodyMediumStrong.fontSize! *
              AppTypography.bodyMediumStrong.height!,
          0.5,
        ),
      );
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('at iOS xxxLarge the text rises instead of reaching lower', (
    tester,
  ) async {
    _setMobileViewport(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.353;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_privacyScreenApp());
    await _settleInitialSync(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SyncKeepAwakePrivacyLockScreen)),
    );
    container.read(syncScanSlowdownProvider.notifier)
      ..updateSyncJob('job', complete: false)
      ..updateDevicePower(SyncScanSlowdown.powerSaving);
    await tester.pump(kSyncScanSlowdownAfter);
    await tester.pump(const Duration(milliseconds: 500));

    final ring = _ringRect(tester);
    final number = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_number')),
    );
    final note = tester.getRect(
      find.byKey(const ValueKey('sync_keep_awake_privacy_slowdown')),
    );
    expect(number.top - ring.top, lessThan(118));
    expect(note.bottom - ring.top, lessThanOrEqualTo(240));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('the number keeps its Figma position at the default text size', (
    tester,
  ) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(_privacyScreenApp());
    await _settleInitialSync(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SyncKeepAwakePrivacyLockScreen)),
    );
    container.read(syncScanSlowdownProvider.notifier)
      ..updateSyncJob('job', complete: false)
      ..updateDevicePower(SyncScanSlowdown.powerSaving);
    await tester.pump(kSyncScanSlowdownAfter);
    await tester.pump(const Duration(milliseconds: 500));

    final numberTop = tester
        .getRect(find.byKey(const ValueKey('sync_keep_awake_privacy_number')))
        .top;
    expect(numberTop - _ringRect(tester).top, 118);
  });

  group('Sync Complete over a catch-up', () {
    const synced = 3000000;
    SyncState completed() => SyncState(
      isSyncComplete: true,
      percentage: 1,
      scannedHeight: synced,
      chainTipHeight: synced,
      lastSyncStartedAt: DateTime(2026, 7, 9, 12),
    );
    SyncState catchUp(DateTime startedAt, {int scanned = synced}) => SyncState(
      isSyncing: true,
      phase: 'scan',
      scannedHeight: scanned,
      chainTipHeight: synced + 3,
      remainingScanBlocks: synced + 3 - scanned,
      lastSyncStartedAt: startedAt,
      startedFromCompletedSync: true,
    );

    /// A locked screen on "Sync Complete" over a synced wallet.
    Future<(ProviderContainer, FakeSyncNotifier)> lockedComplete(
      WidgetTester tester,
    ) async {
      _setMobileViewport(tester);
      final sync = FakeSyncNotifier(completed());
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
          biometricUnlockProvider.overrideWith(
            () => _FakeBiometricUnlockNotifier(_disabledBiometricState),
          ),
          syncProvider.overrideWith(() => sync),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: _themedApp()),
      );
      await _settleInitialSync(tester);
      container.read(syncKeepAwakePrivacyLockProvider.notifier).lock();
      await tester.pump();
      return (container, sync);
    }

    final body = find.byKey(
      const ValueKey('sync_keep_awake_privacy_status_body'),
    );

    testWidgets('idle Sync Complete still reads Unlock Vizor to continue', (
      tester,
    ) async {
      await lockedComplete(tester);
      expect(find.text('Sync Complete'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sync_keep_awake_privacy_done_check')),
        findsOneWidget,
      );
      expect(tester.widget<Text>(body).data, 'Unlock Vizor to continue');
    });

    testWidgets('the subtitle says new blocks are syncing during a short '
        'catch-up and reverts when it ends', (tester) async {
      final semantics = tester.ensureSemantics();
      final (container, sync) = await lockedComplete(tester);
      final idleRect = tester.getRect(body);

      sync.emit(catchUp(DateTime.now()));
      await tester.pump();
      expect(container.read(syncShortCatchUpProvider), isTrue);
      expect(find.text('Sync Complete'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sync_keep_awake_privacy_done_check')),
        findsOneWidget,
      );
      expect(tester.widget<Text>(body).data, 'Syncing new blocks…');
      expect(find.bySemanticsLabel('Syncing new blocks'), findsOneWidget);
      // The same slot: nothing moves.
      expect(tester.getRect(body).topLeft, idleRect.topLeft);
      expect(tester.getRect(body).height, idleRect.height);

      sync.emit(completed());
      await tester.pump();
      expect(tester.widget<Text>(body).data, 'Unlock Vizor to continue');
      semantics.dispose();
    });

    testWidgets('the subtitle stays on syncing new blocks through the hold '
        'past 10 s', (tester) async {
      final (container, sync) = await lockedComplete(tester);
      // A catch-up just short of its 10 s limit.
      final startedAt = DateTime.now().subtract(
        kSyncShortCatchUpMaxDuration - const Duration(milliseconds: 200),
      );
      sync.emit(catchUp(startedAt));
      await tester.pump();
      expect(container.read(syncShortCatchUpProvider), isTrue);
      expect(tester.widget<Text>(body).data, 'Syncing new blocks…');

      // The limit passes on the wall clock the catch-up reads, then its timer
      // fires: the catch-up is no longer short, and the hold keeps the screen.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      sync.emit(catchUp(startedAt, scanned: synced + 1));
      await tester.pump(const Duration(seconds: 1));
      expect(container.read(syncShortCatchUpProvider), isFalse);
      expect(find.text('Sync Complete'), findsOneWidget);
      expect(tester.widget<Text>(body).data, 'Syncing new blocks…');

      sync.emit(completed());
      await tester.pump();
      expect(tester.widget<Text>(body).data, 'Unlock Vizor to continue');
    });
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
            remainingScanBlocks: 2,
            pendingScanStartHeight: 101,
            lastSyncStartedAt: DateTime(2026, 7, 9, 12),
          ),
        ),
      ),
    );
    await _settleInitialSync(tester);

    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump();

    expect(find.text('Vizor is syncing'), findsNothing);
  });

  testWidgets('recent interaction delays the privacy screen', (tester) async {
    _setMobileViewport(tester);
    await tester.pumpWidget(
      _app(
        child: _themedApp(idleTimeout: const Duration(minutes: 1)),
        syncNotifier: FakeSyncNotifier(
          _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
        ),
      ),
    );
    await _settleInitialSync(tester);

    await tester.pump(const Duration(seconds: 30));
    await tester.tap(find.byKey(const ValueKey('home_surface')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    await tester.pump();

    expect(find.text('Vizor is syncing'), findsNothing);

    await tester.pump(const Duration(seconds: 31));
    await tester.pump();

    expect(find.text('Vizor is syncing'), findsOneWidget);
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

      expect(find.text('Vizor is syncing'), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.text('Vizor is syncing'), findsNothing);

      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();

      expect(find.text('Vizor is syncing'), findsOneWidget);
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

    expect(find.text('Vizor is syncing'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(minutes: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('Vizor is syncing'), findsOneWidget);
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
    expect(find.text('25% Syncing\u2026'), findsOneWidget);
    expect(find.bySemanticsLabel('25% Syncing'), findsOneWidget);
    expect(find.text('Unlock to continue'), findsOneWidget);
    expect(find.byType(PasscodeNumpad), findsOneWidget);
    expect(find.bySemanticsLabel('Passcode help'), findsNothing);
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);

    await _enterPasscode(tester, '123456');

    expect(security.confirmedWith, ['123456']);
    expect(find.text('Welcome Back'), findsNothing);
    expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isFalse);
  });

  testWidgets(
    'the lock hides the covered app from screen readers and focus until unlock',
    (tester) async {
      _setMobileViewport(tester);
      final semantics = tester.ensureSemantics();
      final sendFocus = FocusNode(debugLabel: 'covered send');
      addTearDown(sendFocus.dispose);
      final container = ProviderContainer(
        overrides: [
          appBootstrapProvider.overrideWithValue(_bootstrap()),
          appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
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
        UncontrolledProviderScope(
          container: container,
          child: _coveredApp(sendFocus: sendFocus),
        ),
      );
      await _settleInitialSync(tester);

      tester.semantics.tap(find.semantics.byLabel('Send'));
      await tester.pump();
      expect(find.text('Sent 1'), findsOneWidget);
      expect(_routeLabels(), hasLength(1));

      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(container.read(syncKeepAwakePrivacyLockProvider).isLocked, isTrue);

      // Nothing of the covered app reaches a screen reader, so its focus
      // cannot stay behind the lock, and the lock is the only route left to
      // announce.
      expect(find.semantics.byLabel(_coveredBalance), findsNothing);
      expect(find.semantics.byLabel('Send'), findsNothing);
      expect(find.semantics.byLabel(RegExp('Sent 1')), findsNothing);
      expect(find.semantics.byLabel(RegExp('Unlock Vizor')), findsOneWidget);
      expect(_routeLabels(), ['Vizor is syncing']);
      sendFocus.requestFocus();
      await tester.pump();
      expect(sendFocus.hasFocus, isFalse);
      await tester.tap(find.text('Send'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Sent 1'), findsOneWidget);

      await tester.tap(find.text('Unlock Vizor'));
      await tester.pump();
      expect(_routeLabels(), ['Confirm passcode to unlock Vizor']);
      expect(find.semantics.byLabel(_coveredBalance), findsNothing);
      await _enterPasscode(tester, '123456');
      expect(
        container.read(syncKeepAwakePrivacyLockProvider).isLocked,
        isFalse,
      );

      // The app comes back as it was left: still mounted, so its state
      // survived, and reachable again.
      expect(find.semantics.byLabel(_coveredBalance), findsOneWidget);
      expect(find.text('Sent 1'), findsOneWidget);
      tester.semantics.tap(find.semantics.byLabel('Send'));
      await tester.pump();
      expect(find.text('Sent 2'), findsOneWidget);
      sendFocus.requestFocus();
      await tester.pump();
      expect(sendFocus.hasFocus, isTrue);
      semantics.dispose();
    },
  );

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

  for (final viewport in [
    (size: const Size(951, 669), insets: const EdgeInsets.only(bottom: 24)),
    (
      size: const Size(466, 678),
      insets: const EdgeInsets.only(right: 84, bottom: 34),
    ),
  ]) {
    testWidgets(
      'Duo sync-complete passcode fits with an error and large text ${viewport.size}',
      (tester) async {
        _setMobileViewport(tester, size: viewport.size);
        final security = _FakeSecurityNotifier(confirmResult: false);
        final syncNotifier = FakeSyncNotifier(
          _sync(lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
        );
        final container = ProviderContainer(
          overrides: [
            appBootstrapProvider.overrideWithValue(_bootstrap()),
            appSecurityProvider.overrideWith(() => security),
            biometricUnlockProvider.overrideWith(
              () => _FakeBiometricUnlockNotifier(_disabledBiometricState),
            ),
            syncProvider.overrideWith(() => syncNotifier),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              builder: (context, child) => AppTheme(
                data: AppThemeData.dark,
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(1.5),
                    padding: viewport.insets,
                    viewPadding: viewport.insets,
                  ),
                  child: child!,
                ),
              ),
              home: const SyncKeepAwakePrivacyLockHost(
                idleTimeout: Duration(milliseconds: 50),
                child: Scaffold(body: Text('Home')),
              ),
            ),
          ),
        );
        await _settleInitialSync(tester);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.pump();
        syncNotifier.emit(
          _sync(percentage: 1).copyWith(
            scannedHeight: 200,
            chainTipHeight: 200,
            remainingScanBlocks: 0,
            isSyncComplete: true,
            isSyncing: false,
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Unlock Vizor'));
        await tester.pumpAndSettle();
        expect(find.text('Synced'), findsOneWidget);
        await _enterPasscode(tester, '999999');
        await tester.pumpAndSettle();
        expect(find.text('Incorrect Passcode'), findsOneWidget);
        expect(
          tester.getRect(find.text('Incorrect Passcode')).bottom,
          lessThan(tester.getRect(find.bySemanticsLabel('Digit 1')).top),
        );
        expect(
          tester.widget<PasscodeNumpad>(find.byType(PasscodeNumpad)).keySize,
          lessThan(80),
        );
        await tester.ensureVisible(find.bySemanticsLabel('Digit 0'));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.bySemanticsLabel('Digit 0')).bottom,
          lessThanOrEqualTo(viewport.size.height - viewport.insets.bottom),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

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

    expect(find.text('Vizor is syncing'), findsOneWidget);

    syncNotifier.emit(
      _sync(
        isSyncing: false,
        percentage: 1,
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
    expect(find.text('Vizor is syncing'), findsNothing);
    expect(find.text('Sync Complete'), findsOneWidget);
    expect(find.text('Unlock Vizor to continue'), findsOneWidget);
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
        scannedHeight: 200,
        chainTipHeight: 200,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12),
      ),
    );
    await tester.pump();

    expect(find.text('Sync Complete'), findsOneWidget);

    syncNotifier.emit(
      _sync(
        percentage: 0,
        scannedHeight: 200,
        chainTipHeight: 202,
        remainingScanBlocks: 2,
        pendingScanStartHeight: 201,
        lastSyncStartedAt: DateTime(2026, 7, 9, 12, 2),
      ),
    );
    await tester.pump();

    expect(container.read(syncKeepAwakeActiveProvider), isFalse);
    expect(
      container.read(syncKeepAwakePrivacyLockModeProvider),
      SyncKeepAwakePrivacyLockMode.syncing,
    );
    expect(find.text('Sync Complete'), findsNothing);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('Vizor is syncing'), findsOneWidget);

    syncNotifier.emit(
      _sync(
        isSyncing: false,
        percentage: 1,
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
    expect(find.text('Sync Complete'), findsOneWidget);
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
      expect(find.text('Sync Complete'), findsNothing);
      expect(find.text('Unlock Vizor to continue'), findsNothing);
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
    final titleRect = tester.getRect(find.text('Sync Complete'));
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

  testWidgets(
    'says why sync is slower while scans run on fewer cores',
    (tester) async {
      _setMobileViewport(tester);
      await tester.pumpWidget(_privacyScreenApp());
      await _settleInitialSync(tester);
      final slowdown = find.byKey(
        const ValueKey('sync_keep_awake_privacy_slowdown'),
      );
      expect(slowdown, findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SyncKeepAwakePrivacyLockScreen)),
      );
      final notifier = container.read(syncScanSlowdownProvider.notifier)
        ..updateSyncJob('job', complete: false)
        ..updateDevicePower(SyncScanSlowdown.powerSaving);
      await tester.pump(kSyncScanSlowdownAfter);
      expect(
        find.text(
          defaultTargetPlatform == TargetPlatform.iOS
              ? 'Turn off Low Power Mode to sync faster'
              : 'Turn off power saving to sync faster',
        ),
        findsOneWidget,
      );

      notifier.updateDevicePower(SyncScanSlowdown.heat);
      await tester.pump();
      expect(find.text('Slowed down so your phone can cool'), findsOneWidget);
      expect(find.text('Vizor is syncing'), findsOneWidget);

      notifier.updateDevicePower(null);
      await tester.pump();
      expect(slowdown, findsNothing);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('animates display sync percentage changes', (tester) async {
    _setMobileViewport(tester);
    final syncNotifier = FakeSyncNotifier(
      _sync(percentage: 0.05, lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
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
      _sync(percentage: 0.10, lastSyncStartedAt: DateTime(2026, 7, 9, 12)),
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

Widget _app({required FakeSyncNotifier syncNotifier, Widget? child}) {
  return ProviderScope(
    overrides: [
      appBootstrapProvider.overrideWithValue(_bootstrap()),
      appSecurityProvider.overrideWith(_FakeSecurityNotifier.new),
      biometricUnlockProvider.overrideWith(
        () => _FakeBiometricUnlockNotifier(_disabledBiometricState),
      ),
      syncProvider.overrideWith(() => syncNotifier),
    ],
    child: child ?? _themedApp(),
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

Widget _themedApp({Duration idleTimeout = const Duration(milliseconds: 50)}) {
  return MaterialApp(
    builder: (_, child) => AppTheme(data: AppThemeData.dark, child: child!),
    home: SyncKeepAwakePrivacyLockHost(
      idleTimeout: idleTimeout,
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

const _coveredBalance = 'Shielded 1.25 ZEC';

/// The lock as the app mounts it: in `MaterialApp.builder`, over the
/// navigator, so the covered screen keeps its own route.
Widget _coveredApp({required FocusNode sendFocus}) {
  return MaterialApp(
    builder: (_, child) => AppTheme(
      data: AppThemeData.dark,
      child: SyncKeepAwakePrivacyLockHost(
        idleTimeout: const Duration(minutes: 1),
        child: SyncKeepAwakeInteractionListener(child: child!),
      ),
    ),
    home: Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(_coveredBalance),
            _SendCounter(focusNode: sendFocus),
          ],
        ),
      ),
    ),
  );
}

class _SendCounter extends StatefulWidget {
  const _SendCounter({required this.focusNode});

  final FocusNode focusNode;

  @override
  State<_SendCounter> createState() => _SendCounterState();
}

class _SendCounterState extends State<_SendCounter> {
  var _sent = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          focusNode: widget.focusNode,
          onPressed: () => setState(() => _sent += 1),
          child: const Text('Send'),
        ),
        Text('Sent $_sent'),
      ],
    );
  }
}

/// The labels of the routes a screen reader sees, in tree order. A platform
/// announces the last one that is new and moves its focus into it.
List<String> _routeLabels() {
  return find.semantics
      .byPredicate((node) => node.flagsCollection.scopesRoute)
      .evaluate()
      .map((node) => node.label)
      .toList();
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
  int scannedHeight = 100,
  int chainTipHeight = 200,
  DateTime? lastSyncStartedAt,
  int? remainingScanBlocks,
  int? pendingScanStartHeight,
}) {
  return SyncState(
    isSyncing: isSyncing,
    isBackgroundMode: isBackgroundMode,
    percentage: percentage,
    scannedHeight: scannedHeight,
    chainTipHeight: chainTipHeight,
    remainingScanBlocks: remainingScanBlocks,
    pendingScanStartHeight: pendingScanStartHeight,
    lastSyncStartedAt: lastSyncStartedAt,
  );
}

Rect _ringRect(WidgetTester tester) => tester.getRect(
  find.byWidgetPredicate(
    (widget) =>
        widget is CustomPaint &&
        widget.painter.runtimeType.toString() ==
            '_SyncKeepAwakeSegmentedRingPainter',
  ),
);

/// Every line of the lockup's body and slowdown note lies within the inner
/// ends of the ring's filled ticks (radius 122.5, less half their stroke),
/// [inset] pixels inside them.
void _expectLockupTextInsideRingTicks(WidgetTester tester, {double inset = 2}) {
  final center = _ringRect(tester).center;
  final limit = 122.5 - 1.25 - inset;
  for (final finder in [
    find.text('Vizor is syncing'),
    find.descendant(
      of: find.byKey(const ValueKey('sync_keep_awake_privacy_slowdown')),
      matching: find.byType(RichText),
    ),
  ]) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final length = paragraph.text.toPlainText().length;
    // Tight boxes span the glyphs' ascent and descent, not the line's
    // leading.
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: length),
      boxHeightStyle: BoxHeightStyle.tight,
    );
    for (final box in boxes) {
      for (final corner in [
        Offset(box.left, box.top),
        Offset(box.right, box.top),
        Offset(box.left, box.bottom),
        Offset(box.right, box.bottom),
      ]) {
        final distance = (paragraph.localToGlobal(corner) - center).distance;
        expect(
          distance,
          lessThanOrEqualTo(limit),
          reason: '"${paragraph.text.toPlainText()}" reaches the ring ticks',
        );
      }
    }
  }
}

class _PendingSecurityNotifier extends _FakeSecurityNotifier {
  _PendingSecurityNotifier(this.pending);
  final Completer<bool> pending;
  @override
  Future<bool> confirmPassword(String password) => pending.future;
}
