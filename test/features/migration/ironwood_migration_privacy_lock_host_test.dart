import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    as frb;
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/app_bootstrap.dart';
import 'package:zcash_wallet/src/core/config/rpc_endpoint_config.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_coordinator_provider.dart';
import 'package:zcash_wallet/src/features/migration/providers/ironwood_migration_privacy_lock_provider.dart';
import 'package:zcash_wallet/src/features/migration/widgets/ironwood_migration_privacy_lock_host.dart';
import 'package:zcash_wallet/src/providers/account_models.dart';
import 'package:zcash_wallet/src/providers/app_security_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

class _FakeSecurityNotifier extends AppSecurityNotifier {
  _FakeSecurityNotifier({this.confirmResult = true});

  final bool confirmResult;
  final confirmedPasswords = <String>[];
  var unlockCalls = 0;

  bool get isUnlocked => state.isUnlocked;

  @override
  Future<bool> confirmPassword(String password) async {
    confirmedPasswords.add(password);
    return confirmResult;
  }

  @override
  Future<bool> unlock(String password) async {
    unlockCalls += 1;
    return true;
  }
}

class _EligibilityNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void setEligible(bool eligible) => state = eligible;
}

final _eligibilityProvider = NotifierProvider<_EligibilityNotifier, bool>(
  _EligibilityNotifier.new,
);

class _FakeMigrationCoordinator extends IronwoodMigrationCoordinator {
  _FakeMigrationCoordinator(this.initialState);

  final IronwoodMigrationCoordinatorState initialState;

  @override
  IronwoodMigrationCoordinatorState build() => initialState;
}

void main() {
  test('eligibility includes a migration running on another account', () {
    final security = _FakeSecurityNotifier();
    final container = ProviderContainer(
      overrides: [
        appBootstrapProvider.overrideWithValue(_bootstrap()),
        appSecurityProvider.overrideWith(() => security),
        ironwoodMigrationPrivacyLockFeatureEnabledProvider.overrideWithValue(
          true,
        ),
        ironwoodMigrationCoordinatorProvider.overrideWith(
          () => _FakeMigrationCoordinator(
            IronwoodMigrationCoordinatorState(
              statuses: {
                'active-account': _migrationStatus(
                  'ready_to_prepare',
                  activeRunId: null,
                ),
                'other-account': _migrationStatus(
                  'waiting_denom_confirmations',
                ),
              },
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(ironwoodMigrationPrivacyLockEligibleProvider),
      isTrue,
    );
  });

  testWidgets('disabled feature leaves the child unwrapped and idle', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ironwoodMigrationPrivacyLockFeatureEnabledProvider.overrideWithValue(
            false,
          ),
        ],
        child: const MaterialApp(
          home: IronwoodMigrationPrivacyLockHost(
            idleTimeout: Duration(milliseconds: 1),
            child: Text('Unwrapped child'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(minutes: 1));

    expect(find.text('Unwrapped child'), findsOneWidget);
    expect(find.text('Migration in progress'), findsNothing);
  });

  testWidgets('locks after one idle interval without showing forgot password', (
    tester,
  ) async {
    final clock = _TestClock();
    await tester.pumpWidget(_app(clock: clock));
    await tester.pump();

    clock.elapse(const Duration(milliseconds: 49));
    await tester.pump(const Duration(milliseconds: 49));
    expect(find.text('Migration in progress'), findsNothing);

    clock.elapse(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(find.text('Migration in progress'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Unlock Vizor'), findsOneWidget);
    expect(find.text('Forgot password?'), findsNothing);
    expect(find.byKey(ironwoodMigrationVirtualUnlockScreenKey), findsOneWidget);
    expect(find.byKey(ironwoodMigrationInProgressBadgeKey), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.name == AppIcons.ironwoodMigrationLoader,
      ),
      findsOneWidget,
    );
    await _focusVirtualUnlockPassword(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pointer interaction restarts the idle interval', (tester) async {
    final clock = _TestClock();
    await tester.pumpWidget(_app(clock: clock));
    await tester.pump();

    clock.elapse(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.byKey(const ValueKey('protected_content')));
    await tester.pump();

    clock.elapse(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('Migration in progress'), findsNothing);

    clock.elapse(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(find.text('Migration in progress'), findsOneWidget);
  });

  testWidgets('keyboard interaction restarts the idle interval', (
    tester,
  ) async {
    final clock = _TestClock();
    await tester.pumpWidget(_app(clock: clock));
    await tester.pump();

    clock.elapse(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();

    clock.elapse(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text('Migration in progress'), findsNothing);

    clock.elapse(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    expect(find.text('Migration in progress'), findsOneWidget);
  });

  testWidgets('background idle time locks immediately on resume', (
    tester,
  ) async {
    final clock = _TestClock();
    await tester.pumpWidget(_app(clock: clock));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    clock.elapse(const Duration(minutes: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('Migration in progress'), findsOneWidget);
  });

  testWidgets('confirmation only clears the virtual lock', (tester) async {
    final clock = _TestClock();
    final security = _FakeSecurityNotifier();
    await tester.pumpWidget(_app(clock: clock, security: security));
    await tester.pump();
    await _elapseIdleInterval(tester, clock);

    await tester.enterText(
      find.byKey(const ValueKey('unlock_password_field')),
      'password1',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('unlock_submit_button')));
    await tester.pump();

    expect(security.confirmedPasswords, ['password1']);
    expect(security.unlockCalls, 0);
    expect(find.text('Migration in progress'), findsNothing);
    expect(security.isUnlocked, isTrue);
  });

  testWidgets('failed confirmation keeps the overlay visible', (tester) async {
    final clock = _TestClock();
    final security = _FakeSecurityNotifier(confirmResult: false);
    await tester.pumpWidget(_app(clock: clock, security: security));
    await tester.pump();
    await _elapseIdleInterval(tester, clock);

    await tester.enterText(
      find.byKey(const ValueKey('unlock_password_field')),
      'password1',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('unlock_submit_button')));
    await tester.pump();

    expect(find.text('Incorrect password. Try again.'), findsOneWidget);
    expect(find.text('Migration in progress'), findsOneWidget);
  });

  testWidgets(
    'migration completion hides progress but keeps the privacy lock',
    (tester) async {
      final clock = _TestClock();
      final container = ProviderContainer(
        overrides: _overrides(_FakeSecurityNotifier()),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _themedHost(clock),
        ),
      );
      await tester.pump();
      await _elapseIdleInterval(tester, clock);

      container.read(_eligibilityProvider.notifier).setEligible(false);
      await tester.pump();

      expect(find.text('Migration in progress'), findsNothing);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Unlock Vizor'), findsOneWidget);
      expect(
        find.byKey(ironwoodMigrationVirtualUnlockScreenKey),
        findsOneWidget,
      );
      expect(find.byKey(ironwoodMigrationInProgressBadgeKey), findsNothing);
    },
  );

  testWidgets('locked overlay blocks interaction with protected content', (
    tester,
  ) async {
    final clock = _TestClock();
    var protectedTaps = 0;
    await tester.pumpWidget(
      _app(clock: clock, protectedTap: () => protectedTaps += 1),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('protected_content')));
    await tester.pump();
    expect(protectedTaps, 1);
    await _elapseIdleInterval(tester, clock);

    await tester.tapAt(const Offset(20, 300));
    await tester.pump();
    expect(protectedTaps, 1);
  });
}

Widget _app({
  required _TestClock clock,
  _FakeSecurityNotifier? security,
  VoidCallback? protectedTap,
}) {
  return ProviderScope(
    overrides: _overrides(security ?? _FakeSecurityNotifier()),
    child: _themedHost(clock, protectedTap: protectedTap),
  );
}

List<Override> _overrides(_FakeSecurityNotifier security) {
  return [
    appBootstrapProvider.overrideWithValue(_bootstrap()),
    appSecurityProvider.overrideWith(() => security),
    ironwoodMigrationPrivacyLockFeatureEnabledProvider.overrideWithValue(true),
    ironwoodMigrationPrivacyLockEligibleProvider.overrideWith(
      (ref) => ref.watch(_eligibilityProvider),
    ),
  ];
}

Widget _themedHost(_TestClock clock, {VoidCallback? protectedTap}) {
  return MaterialApp(
    builder: (_, child) => AppTheme(
      data: AppThemeData.dark,
      child: IronwoodMigrationPrivacyLockHost(
        idleTimeout: const Duration(milliseconds: 50),
        now: clock.now,
        child: child!,
      ),
    ),
    home: Scaffold(
      body: GestureDetector(
        key: const ValueKey('protected_content'),
        behavior: HitTestBehavior.opaque,
        onTap: protectedTap,
        child: const Center(child: Text('Protected content')),
      ),
    ),
  );
}

Future<void> _focusVirtualUnlockPassword(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey('unlock_password_field')),
      matching: find.byType(EditableText),
    ),
  );
  await tester.pump();
}

Future<void> _elapseIdleInterval(WidgetTester tester, _TestClock clock) async {
  clock.elapse(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump();
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
    isPasswordConfigured: true,
    isUnlocked: true,
    passwordRotationRecoveryFailed: false,
  );
}

class _TestClock {
  DateTime _now = DateTime(2026, 7, 28, 12);

  DateTime now() => _now;

  void elapse(Duration duration) {
    _now = _now.add(duration);
  }
}

rust_sync.MigrationStatus _migrationStatus(
  String phase, {
  String? activeRunId = 'run-1',
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    activeRunId: activeRunId,
    targetValuesZatoshi: frb.Uint64List.fromList(const []),
    preparedNoteCount: 0,
    denominationConfirmationCount: 0,
    denominationConfirmationTarget: 0,
    denominationSplitCompletedCount: 0,
    denominationSplitTotalCount: 0,
    pendingTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 0,
    signedChildPcztCount: 0,
    pendingSplitStageCount: 0,
    canAbandon: false,
    signingBatchLimit: 0,
    scheduleMeanDelayBlocks: 0,
    scheduleMaxDelayBlocks: 0,
    scheduledBroadcasts: const [],
    parts: const [],
  );
}
