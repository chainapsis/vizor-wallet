# Migration Two-Step Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the migration tab's per-phase page swapping and modal overlay with two persistent step cards (Prepare denominations / Migrate to Ironwood), and stop the status from flapping during sync.

**Architecture:** Dart-only. A settled-sync gate stops mid-scan status re-queries; a pure mapper turns `MigrationViewState` + local run intent into two card states; a `Notifier`-based run controller owns the stage-advancing Rust call (transplanted from the deleted overlay); a presentational `MigrationStepCard` renders each step; the screen becomes composition. Spec: `docs/superpowers/specs/2026-06-09-migration-two-step-redesign-design.md`.

**Tech Stack:** Flutter, flutter_riverpod 3.3 (classic providers, `Notifier`/`NotifierProvider`), flutter_test. Commands run through `fvm` from the worktree root (`/Users/czar/Documents/vizor-wallet/.claude/worktrees/naughty-wilson-f52179`). Rust/FRB untouched.

**Conventions:** Sentence case copy (AGENTS.md). `MigrationStatus.broadcastWindowSeconds` is `BigInt` (FRB u64); counts are `int`. `SyncState` has a const-friendly constructor with all-default named params.

---

### Task 1: Settled-sync gate + blocks-send hardening

Stops the "Waiting for Orchard funds" flash: re-query Rust only when a sync cycle has settled, and stop treating every reload as "block send".

**Files:**
- Modify: `lib/src/features/migration/providers/orchard_migration_status_provider.dart`
- Test: `test/features/migration/orchard_migration_status_provider_test.dart` (new)

- [ ] **Step 1: Write the failing tests**

Create `test/features/migration/orchard_migration_status_provider_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/providers/orchard_migration_status_provider.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(this._initial);

  final SyncState _initial;

  @override
  Future<SyncState> build() async => _initial;

  void emit(SyncState value) => state = AsyncData(value);
}

SyncState _syncState({
  required bool isSyncing,
  int scannedHeight = 100,
  BigInt? orchard,
  BigInt? orchardPending,
}) {
  return SyncState(
    accountUuid: 'acct-1',
    isSyncing: isSyncing,
    scannedHeight: scannedHeight,
    orchardBalance: orchard ?? BigInt.from(4),
    orchardPendingBalance: orchardPending ?? BigInt.zero,
    ironwoodBalance: BigInt.zero,
    ironwoodPendingBalance: BigInt.zero,
  );
}

rust_sync.MigrationStatus _status(String phase) {
  return rust_sync.MigrationStatus(
    phase: phase,
    targetValuesZatoshi: Uint64List(0),
    preparedNoteCount: 0,
    pendingTxCount: 0,
    broadcastedTxCount: 0,
    confirmedTxCount: 0,
    totalCount: 0,
    canAbandon: false,
    signingBatchLimit: 8,
    broadcastWindowSeconds: BigInt.from(60),
    maxPreparedNotesPerRun: 64,
  );
}

Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  group('settledSyncFingerprint', () {
    test('is null while syncing and for missing state', () {
      expect(settledSyncFingerprint(null), isNull);
      expect(settledSyncFingerprint(_syncState(isSyncing: true)), isNull);
    });

    test('is stable for identical settled inputs', () {
      expect(
        settledSyncFingerprint(_syncState(isSyncing: false)),
        settledSyncFingerprint(_syncState(isSyncing: false)),
      );
    });

    test('changes when scanned height or balances change', () {
      final base = settledSyncFingerprint(_syncState(isSyncing: false));
      expect(
        settledSyncFingerprint(
          _syncState(isSyncing: false, scannedHeight: 101),
        ),
        isNot(base),
      );
      expect(
        settledSyncFingerprint(
          _syncState(isSyncing: false, orchard: BigInt.from(9)),
        ),
        isNot(base),
      );
    });
  });

  group('migrationStatusSyncGateProvider', () {
    test('holds while scanning, updates once on settle', () async {
      final fake = _FakeSyncNotifier(_syncState(isSyncing: false));
      final container = ProviderContainer(
        overrides: [syncProvider.overrideWith(() => fake)],
      );
      addTearDown(container.dispose);
      final gate = container.listen(
        migrationStatusSyncGateProvider,
        (_, __) {},
      );
      await container.read(syncProvider.future);
      await _tick();
      final settled = gate.read();
      expect(settled, isNot(0));

      // Scan starts and balances flap: the gate must not move.
      fake.emit(_syncState(isSyncing: true, orchard: BigInt.zero));
      await _tick();
      expect(gate.read(), settled);
      fake.emit(
        _syncState(isSyncing: true, scannedHeight: 150, orchard: BigInt.two),
      );
      await _tick();
      expect(gate.read(), settled);

      // Sync settles: exactly one new fingerprint.
      fake.emit(_syncState(isSyncing: false, scannedHeight: 150));
      await _tick();
      final after = gate.read();
      expect(after, isNot(settled));

      // Identical settled state again: no change.
      fake.emit(_syncState(isSyncing: false, scannedHeight: 150));
      await _tick();
      expect(gate.read(), after);
    });
  });

  group('migrationBlocksSend', () {
    test('blocks on first load and on error', () {
      expect(
        migrationBlocksSend(const AsyncLoading<rust_sync.MigrationStatus?>()),
        isTrue,
      );
      expect(
        migrationBlocksSend(
          AsyncError<rust_sync.MigrationStatus?>('boom', StackTrace.empty),
        ),
        isTrue,
      );
    });

    test('uses preserved value during reload instead of blocking', () {
      final reloadingIdle = const AsyncLoading<rust_sync.MigrationStatus?>()
          .copyWithPrevious(
            AsyncData<rust_sync.MigrationStatus?>(_status('ready_to_prepare')),
            isRefresh: false,
          );
      expect(migrationBlocksSend(reloadingIdle), isFalse);

      final reloadingActive = const AsyncLoading<rust_sync.MigrationStatus?>()
          .copyWithPrevious(
            AsyncData<rust_sync.MigrationStatus?>(
              _status('waiting_denom_confirmations'),
            ),
            isRefresh: false,
          );
      expect(migrationBlocksSend(reloadingActive), isTrue);
    });

    test('null status (hardware account) does not block once loaded', () {
      expect(
        migrationBlocksSend(const AsyncData<rust_sync.MigrationStatus?>(null)),
        isFalse,
      );
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `fvm flutter test test/features/migration/orchard_migration_status_provider_test.dart`
Expected: FAIL — `settledSyncFingerprint`, `migrationStatusSyncGateProvider`, and `migrationBlocksSend` are undefined.

- [ ] **Step 3: Implement gate + hardening**

Replace the entire contents of `lib/src/features/migration/providers/orchard_migration_status_provider.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/migration_view_state.dart';

/// Fingerprint of the settled sync inputs that can change the no-run
/// migration phase. Null while a scan is running: mid-scan wallet summaries
/// flap between spendable and pending, so they must not drive a status read.
int? settledSyncFingerprint(SyncState? sync) {
  if (sync == null || sync.isSyncing) return null;
  return Object.hash(
    sync.accountUuid,
    sync.scannedHeight,
    sync.orchardBalance,
    sync.orchardPendingBalance,
    sync.ironwoodBalance,
    sync.ironwoodPendingBalance,
  );
}

/// Holds the most recent settled fingerprint. While a scan runs this state
/// never changes, so watchers are not rebuilt at all — not even at scan
/// start. Each settled sync cycle (or idle balance change) updates the
/// fingerprint exactly once.
class MigrationStatusSyncGate extends Notifier<int> {
  @override
  int build() {
    ref.listen(syncProvider, (_, next) {
      final fingerprint = settledSyncFingerprint(next.value);
      if (fingerprint != null && fingerprint != state) state = fingerprint;
    });
    return settledSyncFingerprint(ref.read(syncProvider).value) ?? 0;
  }
}

final migrationStatusSyncGateProvider =
    NotifierProvider<MigrationStatusSyncGate, int>(MigrationStatusSyncGate.new);

final activeOrchardMigrationStatusProvider =
    FutureProvider<rust_sync.MigrationStatus?>((ref) async {
      final accountState = ref.watch(accountProvider).value;
      final account = accountState?.activeAccount;
      final accountUuid = accountState?.activeAccountUuid;
      if (account == null || accountUuid == null || account.isHardware) {
        return null;
      }

      final endpoint = ref.watch(rpcEndpointProvider);

      // Rust is still the source of truth; this watch only chooses when to
      // ask it again. Mid-scan answers flap between waiting and ready, so we
      // only re-ask when a sync cycle has settled (see
      // MigrationStatusSyncGate). Explicit ref.invalidate still works.
      ref.watch(migrationStatusSyncGateProvider);

      final dbPath = await getWalletDbPath();
      return rust_sync.getOrchardMigrationStatus(
        dbPath: dbPath,
        network: endpoint.walletNetworkName,
        accountUuid: accountUuid,
      );
    });

final hasActiveOrchardMigrationRunProvider = Provider<bool>((ref) {
  final status = ref.watch(activeOrchardMigrationStatusProvider).value;
  final viewState = migrationViewStateFromRustPhase(status?.phase);
  return viewState?.hasActiveRun ?? false;
});

/// Pure decision for blocking sends. Uses the preserved previous value
/// during reloads so the send screen does not flicker every time the status
/// provider re-queries.
bool migrationBlocksSend(AsyncValue<rust_sync.MigrationStatus?> statusAsync) {
  if (statusAsync.hasError) return true;
  final status = statusAsync.value;
  if (status == null) return statusAsync.isLoading;
  final viewState = migrationViewStateFromRustPhase(status.phase);
  return viewState?.hasActiveRun ?? false;
}

final migrationBlocksSendProvider = Provider<bool>((ref) {
  return migrationBlocksSend(ref.watch(activeOrchardMigrationStatusProvider));
});
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `fvm flutter test test/features/migration/orchard_migration_status_provider_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Analyze and run the full migration test directory**

Run: `fvm flutter analyze && fvm flutter test test/features/migration/`
Expected: no analyzer issues; all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/migration/providers/orchard_migration_status_provider.dart test/features/migration/orchard_migration_status_provider_test.dart
git commit -m "Gate migration status re-queries on settled sync"
```

---

### Task 2: Step-state mapper

**Files:**
- Create: `lib/src/features/migration/models/migration_step_state.dart`
- Test: `test/features/migration/migration_step_state_test.dart` (new)

- [ ] **Step 1: Write the failing tests**

Create `test/features/migration/migration_step_state_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_step_state.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_view_state.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

rust_sync.MigrationStatus _status({
  String phase = 'ready_to_migrate',
  int pendingTxCount = 0,
  int broadcastedTxCount = 0,
}) {
  return rust_sync.MigrationStatus(
    phase: phase,
    targetValuesZatoshi: Uint64List(0),
    preparedNoteCount: 0,
    pendingTxCount: pendingTxCount,
    broadcastedTxCount: broadcastedTxCount,
    confirmedTxCount: 0,
    totalCount: 0,
    canAbandon: false,
    signingBatchLimit: 8,
    broadcastWindowSeconds: BigInt.from(60),
    maxPreparedNotesPerRun: 64,
  );
}

MigrationStepsModel _map(
  MigrationViewState viewState, {
  rust_sync.MigrationStatus? status,
  bool runInFlight = false,
  MigrationRunIntent intent = MigrationRunIntent.none,
}) {
  return migrationStepsModel(
    viewState: viewState,
    status: status,
    runInFlight: runInFlight,
    intent: intent,
  );
}

void main() {
  test('in-flight intent wins over provider-derived state', () {
    final preparing = _map(
      MigrationViewState.planningDenominations,
      runInFlight: true,
      intent: MigrationRunIntent.preparing,
    );
    expect(preparing.stepOne, MigrationStepOneState.running);
    expect(preparing.stepTwo, MigrationStepTwoState.locked);

    final migrating = _map(
      MigrationViewState.readyToMigrate,
      runInFlight: true,
      intent: MigrationRunIntent.migrating,
    );
    expect(migrating.stepOne, MigrationStepOneState.done);
    expect(migrating.stepTwo, MigrationStepTwoState.running);
  });

  test('balance-derived phases map to step one states', () {
    expect(
      _map(MigrationViewState.noOrchardFunds).stepOne,
      MigrationStepOneState.blocked,
    );
    expect(
      _map(MigrationViewState.waitingForSpendableOrchard).stepOne,
      MigrationStepOneState.blocked,
    );
    expect(
      _map(MigrationViewState.planningDenominations).stepOne,
      MigrationStepOneState.active,
    );
    expect(
      _map(MigrationViewState.preparingDenominations).stepOne,
      MigrationStepOneState.running,
    );
    expect(
      _map(MigrationViewState.waitingDenomConfirmations).stepOne,
      MigrationStepOneState.waiting,
    );
    expect(
      _map(MigrationViewState.planningDenominations).stepTwo,
      MigrationStepTwoState.locked,
    );
  });

  test('run phases map to step two states with step one done', () {
    final ready = _map(MigrationViewState.readyToMigrate);
    expect(ready.stepOne, MigrationStepOneState.done);
    expect(ready.stepTwo, MigrationStepTwoState.ready);

    expect(
      _map(MigrationViewState.paused).stepTwo,
      MigrationStepTwoState.ready,
    );

    for (final running in [
      MigrationViewState.buildingSigningBatch,
      MigrationViewState.signingBatch,
      MigrationViewState.broadcastScheduled,
      MigrationViewState.broadcasting,
    ]) {
      expect(_map(running).stepOne, MigrationStepOneState.done);
      expect(_map(running).stepTwo, MigrationStepTwoState.running);
    }

    expect(
      _map(MigrationViewState.waitingMigrationConfirmations).stepTwo,
      MigrationStepTwoState.confirming,
    );
    expect(
      _map(MigrationViewState.complete).stepTwo,
      MigrationStepTwoState.done,
    );
  });

  test('failedRecoverable routes to the step that actually failed', () {
    final beforeMigrationTxs = _map(
      MigrationViewState.failedRecoverable,
      status: _status(phase: 'failed_recoverable'),
    );
    expect(beforeMigrationTxs.stepOne, MigrationStepOneState.error);
    expect(beforeMigrationTxs.stepTwo, MigrationStepTwoState.locked);

    final withPending = _map(
      MigrationViewState.failedRecoverable,
      status: _status(phase: 'failed_recoverable', pendingTxCount: 3),
    );
    expect(withPending.stepOne, MigrationStepOneState.done);
    expect(withPending.stepTwo, MigrationStepTwoState.error);

    final withBroadcasted = _map(
      MigrationViewState.failedRecoverable,
      status: _status(phase: 'failed_recoverable', broadcastedTxCount: 1),
    );
    expect(withBroadcasted.stepTwo, MigrationStepTwoState.error);
  });

  test('terminal phases are step two errors', () {
    expect(
      _map(MigrationViewState.failedTerminal).stepTwo,
      MigrationStepTwoState.error,
    );
    expect(
      _map(MigrationViewState.abandoned).stepTwo,
      MigrationStepTwoState.error,
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `fvm flutter test test/features/migration/migration_step_state_test.dart`
Expected: FAIL — `migration_step_state.dart` does not exist.

- [ ] **Step 3: Implement the mapper**

Create `lib/src/features/migration/models/migration_step_state.dart`:

```dart
import '../../../rust/api/sync.dart' as rust_sync;
import 'migration_view_state.dart';

/// Which run action the controller is currently (or was last) executing.
enum MigrationRunIntent { none, preparing, migrating }

enum MigrationStepOneState { blocked, active, running, waiting, done, error }

enum MigrationStepTwoState { locked, ready, running, confirming, done, error }

class MigrationStepsModel {
  const MigrationStepsModel({required this.stepOne, required this.stepTwo});

  final MigrationStepOneState stepOne;
  final MigrationStepTwoState stepTwo;
}

/// Pure selector mapping the rust-derived view state (plus the local run
/// intent) onto the two persistent step cards. Kept widget-free so it is
/// trivially testable, like [migrationViewState].
MigrationStepsModel migrationStepsModel({
  required MigrationViewState viewState,
  required rust_sync.MigrationStatus? status,
  required bool runInFlight,
  required MigrationRunIntent intent,
}) {
  // A run call in flight wins over (lagging) provider state.
  if (runInFlight && intent == MigrationRunIntent.preparing) {
    return const MigrationStepsModel(
      stepOne: MigrationStepOneState.running,
      stepTwo: MigrationStepTwoState.locked,
    );
  }
  if (runInFlight && intent == MigrationRunIntent.migrating) {
    return const MigrationStepsModel(
      stepOne: MigrationStepOneState.done,
      stepTwo: MigrationStepTwoState.running,
    );
  }

  final hasMigrationTxs =
      (status?.pendingTxCount ?? 0) > 0 ||
      (status?.broadcastedTxCount ?? 0) > 0;

  return switch (viewState) {
    MigrationViewState.softwareRequired ||
    MigrationViewState.noOrchardFunds ||
    MigrationViewState.waitingForSpendableOrchard => const MigrationStepsModel(
      stepOne: MigrationStepOneState.blocked,
      stepTwo: MigrationStepTwoState.locked,
    ),
    MigrationViewState.planningDenominations => const MigrationStepsModel(
      stepOne: MigrationStepOneState.active,
      stepTwo: MigrationStepTwoState.locked,
    ),
    MigrationViewState.preparingDenominations => const MigrationStepsModel(
      stepOne: MigrationStepOneState.running,
      stepTwo: MigrationStepTwoState.locked,
    ),
    MigrationViewState.waitingDenomConfirmations => const MigrationStepsModel(
      stepOne: MigrationStepOneState.waiting,
      stepTwo: MigrationStepTwoState.locked,
    ),
    MigrationViewState.readyToMigrate ||
    MigrationViewState.paused => const MigrationStepsModel(
      stepOne: MigrationStepOneState.done,
      stepTwo: MigrationStepTwoState.ready,
    ),
    MigrationViewState.buildingSigningBatch ||
    MigrationViewState.signingBatch ||
    MigrationViewState.broadcastScheduled ||
    MigrationViewState.broadcasting => const MigrationStepsModel(
      stepOne: MigrationStepOneState.done,
      stepTwo: MigrationStepTwoState.running,
    ),
    MigrationViewState.waitingMigrationConfirmations =>
      const MigrationStepsModel(
        stepOne: MigrationStepOneState.done,
        stepTwo: MigrationStepTwoState.confirming,
      ),
    MigrationViewState.complete => const MigrationStepsModel(
      stepOne: MigrationStepOneState.done,
      stepTwo: MigrationStepTwoState.done,
    ),
    MigrationViewState.failedRecoverable => hasMigrationTxs
        ? const MigrationStepsModel(
            stepOne: MigrationStepOneState.done,
            stepTwo: MigrationStepTwoState.error,
          )
        : const MigrationStepsModel(
            stepOne: MigrationStepOneState.error,
            stepTwo: MigrationStepTwoState.locked,
          ),
    MigrationViewState.failedTerminal ||
    MigrationViewState.abandoned => const MigrationStepsModel(
      stepOne: MigrationStepOneState.done,
      stepTwo: MigrationStepTwoState.error,
    ),
  };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `fvm flutter test test/features/migration/migration_step_state_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/migration/models/migration_step_state.dart test/features/migration/migration_step_state_test.dart
git commit -m "Add migration step state mapper"
```

---

### Task 3: Two-step copy additions

Add the new strings and the window-text helper. Obsolete strings are removed in Task 6 (the screen and overlay still reference them until then).

**Files:**
- Modify: `lib/src/features/migration/migration_copy.dart`
- Test: `test/features/migration/migration_copy_test.dart` (new)

- [ ] **Step 1: Write the failing tests**

Create `test/features/migration/migration_copy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/migration_copy.dart';

void main() {
  test('migrationWindowText formats seconds and minutes', () {
    expect(MigrationCopy.migrationWindowText(60), 'about one minute');
    expect(MigrationCopy.migrationWindowText(45), 'about 45 seconds');
    expect(MigrationCopy.migrationWindowText(89), 'about 89 seconds');
    expect(MigrationCopy.migrationWindowText(120), 'about 2 minutes');
    expect(MigrationCopy.migrationWindowText(150), 'about 3 minutes');
  });

  test('step copy formatters interpolate counts', () {
    expect(MigrationCopy.stepOneDone(8), '8 prepared notes ready.');
    expect(
      MigrationCopy.stepOnePreparedCounts(3, 8),
      'Prepared notes: 3 of 8',
    );
    expect(
      MigrationCopy.stepTwoReady(8, 'about one minute'),
      'Vizor signs 8 migration transactions and submits them over '
      'about one minute.',
    );
    expect(
      MigrationCopy.stepTwoSubmitting(3, 8),
      'Submitting migration transaction 3 of 8...',
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `fvm flutter test test/features/migration/migration_copy_test.dart`
Expected: FAIL — new members undefined.

- [ ] **Step 3: Add the new copy**

In `lib/src/features/migration/migration_copy.dart`, insert this block immediately after the `startCta` line (keep all existing strings for now):

```dart
  // Two-step layout
  static const stepOneTitle = 'Prepare denominations';
  static const stepOneBody =
      'Split your Orchard funds into standard note amounts in a single '
      'transaction.';
  static const stepOneCta = 'Prepare denominations';
  static const stepOneRunning =
      'Creating and submitting the denomination transaction...';
  static const stepOneWaiting =
      'Denomination transaction submitted. The prepared notes need to '
      'confirm before migration can start.';
  static String stepOneDone(int count) => '$count prepared notes ready.';
  static const stepOneDoneGeneric = 'Prepared notes ready.';
  static String stepOnePreparedCounts(int prepared, int total) =>
      'Prepared notes: $prepared of $total';
  static const stepOneNoFunds = 'No Orchard funds to prepare.';
  static const stepOneUnspendable =
      'Waiting for Orchard funds to become spendable. Keep Vizor syncing.';
  static const stepTwoTitle = 'Migrate to Ironwood';
  static const stepTwoLocked = 'Available once the prepared notes confirm.';
  static String stepTwoReady(int count, String window) =>
      'Vizor signs $count migration transactions and submits them over '
      '$window.';
  static const stepTwoCta = 'Start migration';
  static const stepTwoSigning = 'Signing migration transactions...';
  static String stepTwoSubmitting(int index, int total) =>
      'Submitting migration transaction $index of $total...';
  static const stepTwoPausedNote =
      'Migration paused. Start migration to resume this run.';
  static const stepTwoKeepOpen =
      'Keep Vizor open while the migration transactions are created and '
      'broadcast.';
  static const partialBroadcastError =
      'Migration transactions were created locally but not fully broadcast. '
      'Keep Vizor open and do not start another migration.';

  static String migrationWindowText(int seconds) {
    if (seconds == 60) return 'about one minute';
    if (seconds < 90) return 'about $seconds seconds';
    return 'about ${(seconds / 60).round()} minutes';
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `fvm flutter test test/features/migration/migration_copy_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/migration/migration_copy.dart test/features/migration/migration_copy_test.dart
git commit -m "Add two-step migration copy"
```

---

### Task 4: Migration run controller

Lift the Rust-call orchestration out of `MigrationSigningOverlay` into a `Notifier`. The overlay file itself is deleted in Task 6.

**Files:**
- Create: `lib/src/features/migration/providers/migration_run_controller.dart`
- Test: `test/features/migration/migration_run_controller_test.dart` (new)

- [ ] **Step 1: Write the failing tests**

The controller body touches FFI/secure storage and is exercised manually in Task 7; the testable logic is the success classifier and the state object. Create `test/features/migration/migration_run_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/features/migration/models/migration_step_state.dart';
import 'package:zcash_wallet/src/features/migration/providers/migration_run_controller.dart';
import 'package:zcash_wallet/src/rust/api/sync.dart' as rust_sync;

rust_sync.IronwoodMigrationResult _result(
  String status, {
  int broadcastedCount = 0,
  String? message,
}) {
  return rust_sync.IronwoodMigrationResult(
    txids: '',
    status: status,
    broadcastedCount: broadcastedCount,
    totalCount: 8,
    message: message,
    feeZatoshi: BigInt.zero,
    migratedZatoshi: BigInt.zero,
  );
}

void main() {
  test('stage outcomes that advanced the run count as success', () {
    expect(migrationRunAdvanced(_result('broadcasted')), isTrue);
    expect(
      migrationRunAdvanced(
        _result('waiting_denom_confirmations', message: 'sync more'),
      ),
      isTrue,
    );
    expect(
      migrationRunAdvanced(_result('waiting_migration_confirmations')),
      isTrue,
    );
    expect(
      migrationRunAdvanced(_result('partial_broadcast', broadcastedCount: 2)),
      isTrue,
    );
  });

  test('failures and empty partial broadcasts are not success', () {
    expect(migrationRunAdvanced(_result('failed_recoverable')), isFalse);
    expect(migrationRunAdvanced(_result('pending_broadcast')), isFalse);
    expect(
      migrationRunAdvanced(
        _result('partial_broadcast', broadcastedCount: 2, message: 'lwd down'),
      ),
      isFalse,
    );
    expect(
      migrationRunAdvanced(_result('partial_broadcast', broadcastedCount: 0)),
      isFalse,
    );
  });

  test('run state defaults are inert', () {
    const state = MigrationRunState();
    expect(state.intent, MigrationRunIntent.none);
    expect(state.inFlight, isFalse);
    expect(state.error, isNull);
    expect(state.errorIntent, isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `fvm flutter test test/features/migration/migration_run_controller_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement the controller**

Create `lib/src/features/migration/providers/migration_run_controller.dart`. Behavior is a faithful transplant of `MigrationSigningOverlay._startMigration` / `_migrateWithMnemonicBytes` / `_friendlyError` / `_isActiveMigrationError`, minus widget concerns, plus: a correct success classifier (the overlay mislabeled successful stage outcomes as failures), a 2 s status re-poll while in flight, and intent-scoped errors. The `appLayoutProvider.setMode(large)` call from the overlay is intentionally dropped — no modal anymore.

```dart
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../migration_copy.dart';
import '../models/migration_batch.dart';
import '../models/migration_step_state.dart';
import 'migration_expected_transfer_count_provider.dart';
import 'orchard_migration_status_provider.dart';

class MigrationRunState {
  const MigrationRunState({
    this.intent = MigrationRunIntent.none,
    this.inFlight = false,
    this.error,
    this.errorIntent,
  });

  final MigrationRunIntent intent;
  final bool inFlight;
  final String? error;

  /// Which step card shows [error]. Null when there is no error.
  final MigrationRunIntent? errorIntent;
}

/// True when the Rust call advanced the run. Successful stage outcomes
/// report run-phase strings, not 'broadcasted': stage 1 returns
/// waiting_denom_confirmations, stage 2 returns
/// waiting_migration_confirmations (and its benign "notes not spendable
/// yet" no-op also returns waiting_denom_confirmations).
bool migrationRunAdvanced(rust_sync.IronwoodMigrationResult result) {
  return switch (result.status) {
    'broadcasted' ||
    'waiting_denom_confirmations' ||
    'waiting_migration_confirmations' => true,
    'partial_broadcast' =>
      result.broadcastedCount > 0 && result.message == null,
    _ => false,
  };
}

class MigrationRunController extends Notifier<MigrationRunState> {
  Timer? _progressTimer;

  @override
  MigrationRunState build() {
    ref.onDispose(() {
      _progressTimer?.cancel();
      _progressTimer = null;
    });
    return const MigrationRunState();
  }

  /// Advances the migration run one stage. The Rust entry point is
  /// stage-aware: with no active run it splits notes into denominations;
  /// with an active run it signs and submits the migration transactions
  /// over the broadcast window.
  Future<void> advance(MigrationRunIntent intent) async {
    if (state.inFlight) return;
    state = MigrationRunState(intent: intent, inFlight: true);
    _progressTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      ref.invalidate(activeOrchardMigrationStatusProvider);
    });

    try {
      final accountState = ref.read(accountProvider).value;
      final account = accountState?.activeAccount;
      final accountUuid = accountState?.activeAccountUuid;
      if (account == null || accountUuid == null) {
        throw MigrationBatchError('No active account.');
      }
      if (account.isHardware) {
        throw MigrationBatchError(
          'Switch to a software account before migrating.',
        );
      }

      final endpoint = ref.read(rpcEndpointProvider);
      if (endpoint.network != ZcashNetwork.testnet) {
        throw MigrationBatchError(
          'Select a testnet endpoint before migrating.',
        );
      }

      final dbPath = await getWalletDbPath();
      final migrationNetworkName = endpoint.walletNetworkName;
      final security = ref.read(appSecurityProvider.notifier);
      final password = security.requireSessionPasswordForNativeSecretUse();
      final saltBase64 = await security
          .requireSecretPayloadSaltForNativeSecretUse();
      late final rust_sync.IronwoodMigrationResult result;

      if (Platform.isMacOS && !kDebugMode) {
        try {
          result = await rust_sync
              .migrateOrchardToIronwoodWithMacosStoredMnemonic(
                dbPath: dbPath,
                lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
                network: migrationNetworkName,
                accountUuid: accountUuid,
                password: password,
                saltBase64: saltBase64,
              );
        } catch (e) {
          final message = e.toString().toLowerCase();
          if (!message.contains('secure storage salt not found') &&
              !message.contains('mnemonic not found for account')) {
            rethrow;
          }
          log(
            'MigrationRunController: native macOS mnemonic unavailable, '
            'falling back to Dart mnemonic storage: $e',
          );
          result = await _migrateWithMnemonicBytes(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: migrationNetworkName,
            accountUuid: accountUuid,
            password: password,
            saltBase64: saltBase64,
          );
        }
      } else {
        result = await _migrateWithMnemonicBytes(
          dbPath: dbPath,
          lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
          network: migrationNetworkName,
          accountUuid: accountUuid,
          password: password,
          saltBase64: saltBase64,
        );
      }

      log(
        'MigrationRunController: intent=${intent.name} '
        'txids=${result.txids} status=${result.status} '
        'broadcasted=${result.broadcastedCount}/${result.totalCount} '
        'fee=${result.feeZatoshi} migrated=${result.migratedZatoshi}',
      );

      final firstTxid = _firstTxid(result.txids);
      if (result.broadcastedCount > 0 &&
          result.totalCount > 0 &&
          firstTxid != null) {
        ref
            .read(migrationExpectedTransferCountProvider.notifier)
            .setCount(accountUuid, result.totalCount, firstTxid: firstTxid);
      }

      if (migrationRunAdvanced(result)) {
        state = const MigrationRunState();
      } else {
        state = MigrationRunState(
          intent: intent,
          error: result.message ?? MigrationCopy.partialBroadcastError,
          errorIntent: intent,
        );
      }

      unawaited(
        _refreshIfAccountStillActive(accountUuid).catchError((Object e) {
          log('MigrationRunController: refreshAfterSend failed: $e');
        }),
      );
    } catch (e, st) {
      if (_isActiveMigrationError(e)) {
        log(
          'MigrationRunController.advance: migration already active; '
          'reconciling from status',
        );
        state = const MigrationRunState();
      } else {
        log('MigrationRunController.advance: ERROR: $e\n$st');
        state = MigrationRunState(
          intent: intent,
          error: _friendlyError(e),
          errorIntent: intent,
        );
      }
    } finally {
      _progressTimer?.cancel();
      _progressTimer = null;
      ref.invalidate(activeOrchardMigrationStatusProvider);
    }
  }

  Future<rust_sync.IronwoodMigrationResult> _migrateWithMnemonicBytes({
    required String dbPath,
    required String lightwalletdUrl,
    required String network,
    required String accountUuid,
    required String password,
    required String saltBase64,
  }) async {
    final mnemonicBytes = await ref
        .read(accountProvider.notifier)
        .getMnemonicBytesForAccount(accountUuid);
    if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
      throw MigrationBatchError('Mnemonic not found for the active account.');
    }

    try {
      return await rust_sync.migrateOrchardToIronwood(
        dbPath: dbPath,
        lightwalletdUrl: lightwalletdUrl,
        network: network,
        accountUuid: accountUuid,
        mnemonicBytes: mnemonicBytes,
        password: password,
        saltBase64: saltBase64,
      );
    } finally {
      mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
    }
  }

  Future<void> _refreshIfAccountStillActive(String accountUuid) async {
    final activeAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    if (activeAccountUuid != accountUuid) return;
    await ref
        .read(syncProvider.notifier)
        .refreshAfterSend(
          transactionHistoryLimit: migrationProgressTransactionHistoryLimit,
        );
  }

  String? _firstTxid(String txids) {
    for (final txid in txids.split(',')) {
      final trimmed = txid.trim();
      if (trimmed.isNotEmpty) return trimmed.toLowerCase();
    }
    return null;
  }

  String _friendlyError(Object error) {
    if (error is MigrationBatchError) return error.message;
    final lower = error.toString().toLowerCase();
    if (lower.contains('insufficient') || lower.contains('spendable')) {
      return 'Receive enough Orchard funds, let Vizor sync, then try again.';
    }
    if (lower.contains('sync') || lower.contains('scan required')) {
      return 'Sync the wallet before migrating.';
    }
    return '${error.runtimeType}: $error';
  }

  bool _isActiveMigrationError(Object error) {
    return error.toString().toLowerCase().contains(
      'ironwood migration is already running',
    );
  }
}

final migrationRunControllerProvider =
    NotifierProvider<MigrationRunController, MigrationRunState>(
      MigrationRunController.new,
    );
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `fvm flutter test test/features/migration/migration_run_controller_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Analyze**

Run: `fvm flutter analyze`
Expected: no issues (the overlay still exists and compiles; both coexist until Task 6).

- [ ] **Step 6: Commit**

```bash
git add lib/src/features/migration/providers/migration_run_controller.dart test/features/migration/migration_run_controller_test.dart
git commit -m "Add migration run controller"
```

---

### Task 5: Step card widget

**Files:**
- Create: `lib/src/features/migration/widgets/migration_step_card.dart`
- Test: `test/features/migration/migration_step_card_test.dart` (new)

- [ ] **Step 1: Write the failing tests**

Create `test/features/migration/migration_step_card_test.dart` (harness pattern copied from `test/activity_table_row_test.dart`):

```dart
import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcash_wallet/src/core/theme/app_theme.dart';
import 'package:zcash_wallet/src/core/widgets/app_icon.dart';
import 'package:zcash_wallet/src/features/migration/widgets/migration_step_card.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: AppTheme(
      data: AppThemeData.light,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('renders number badge, title, status and enabled CTA', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        MigrationStepCard(
          stepNumber: 1,
          title: 'Prepare denominations',
          statusLine: 'Ready.',
          ctaLabel: 'Prepare denominations',
          onCta: () => taps += 1,
        ),
      ),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('Prepare denominations'), findsNWidgets(2));
    expect(find.text('Ready.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('migration_step1_cta')));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('disabled CTA does not fire and dimmed card is wrapped in '
      'reduced opacity', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        MigrationStepCard(
          stepNumber: 2,
          title: 'Migrate to Ironwood',
          isDimmed: true,
          statusLine: 'Available once the prepared notes confirm.',
          ctaLabel: 'Start migration',
          onCta: null,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('migration_step2_cta')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(taps, 0);

    final opacity = tester.widget<Opacity>(
      find.ancestor(
        of: find.text('Migrate to Ironwood'),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, lessThan(1));
  });

  testWidgets('done shows check icon instead of number; spinner and '
      'progress render when requested', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MigrationStepCard(
          stepNumber: 1,
          title: 'Prepare denominations',
          isDone: true,
        ),
      ),
    );
    expect(find.text('1'), findsNothing);
    expect(find.byType(AppIcon), findsOneWidget);

    await tester.pumpWidget(
      _wrap(
        const MigrationStepCard(
          stepNumber: 2,
          title: 'Migrate to Ironwood',
          showSpinner: true,
          progress: 0.5,
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('error banner renders', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MigrationStepCard(
          stepNumber: 2,
          title: 'Migrate to Ironwood',
          errorBanner: 'Migration broadcast failed.',
        ),
      ),
    );
    expect(find.text('Migration broadcast failed.'), findsOneWidget);
  });
}
```

Note: `CircularProgressIndicator`/`LinearProgressIndicator` come from
`package:flutter/material.dart`; add `CircularProgressIndicator, LinearProgressIndicator` to the material `show` clause in the test if the analyzer complains.

- [ ] **Step 2: Run tests to verify they fail**

Run: `fvm flutter test test/features/migration/migration_step_card_test.dart`
Expected: FAIL — widget file does not exist.

- [ ] **Step 3: Implement the card**

Create `lib/src/features/migration/widgets/migration_step_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';

/// Presentational shell for one migration step. State semantics live in the
/// screen; this widget only renders what it is given.
class MigrationStepCard extends StatelessWidget {
  const MigrationStepCard({
    required this.stepNumber,
    required this.title,
    this.isDone = false,
    this.isDimmed = false,
    this.showSpinner = false,
    this.statusLine,
    this.statusIsError = false,
    this.errorBanner,
    this.progress,
    this.body = const <Widget>[],
    this.ctaLabel,
    this.onCta,
    super.key,
  });

  final int stepNumber;
  final String title;
  final bool isDone;
  final bool isDimmed;
  final bool showSpinner;
  final String? statusLine;
  final bool statusIsError;
  final String? errorBanner;

  /// 0..1 bar shown when non-null.
  final double? progress;
  final List<Widget> body;
  final String? ctaLabel;

  /// Null with a non-null [ctaLabel] renders the disabled button state.
  final VoidCallback? onCta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: isDimmed ? 0.5 : 1,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.background.neutralSubtleOpacity,
          borderRadius: BorderRadius.circular(AppRadii.xSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isDone)
                  AppIcon(
                    AppIcons.checkCircle,
                    size: AppIconSize.medium,
                    color: colors.icon.success,
                  )
                else
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.border.subtle),
                    ),
                    child: Text(
                      '$stepNumber',
                      style: AppTypography.bodyExtraSmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                if (showSpinner)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.icon.success,
                    ),
                  ),
              ],
            ),
            if (statusLine != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                statusLine!,
                style: AppTypography.bodyMedium.copyWith(
                  color: statusIsError
                      ? colors.text.destructive
                      : colors.text.secondary,
                ),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: AppSpacing.s),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.full),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: colors.background.neutralSubtleOpacity,
                  color: colors.icon.success,
                ),
              ),
            ],
            ...body.map(
              (child) => Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s),
                child: child,
              ),
            ),
            if (errorBanner != null) ...[
              const SizedBox(height: AppSpacing.s),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppIcon(
                    AppIcons.warning,
                    size: AppIconSize.medium,
                    color: colors.icon.destructive,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      errorBanner!,
                      style: AppTypography.bodyExtraSmall.copyWith(
                        color: colors.text.destructive,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (ctaLabel != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppButton(
                key: ValueKey('migration_step${stepNumber}_cta'),
                onPressed: onCta,
                leading: const AppIcon(AppIcons.doubleArrowVertical),
                child: Text(ctaLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `fvm flutter test test/features/migration/migration_step_card_test.dart`
Expected: PASS (4 tests). If `colors.text.destructive` does not resolve, the field is defined in `lib/src/core/theme/colors/app_text_colors.dart` — check the getter name there (it exists with light/dark values).

- [ ] **Step 5: Commit**

```bash
git add lib/src/features/migration/widgets/migration_step_card.dart test/features/migration/migration_step_card_test.dart
git commit -m "Add migration step card widget"
```

---

### Task 6: Recompose the screen, delete the overlay, prune copy

**Files:**
- Modify: `lib/src/features/migration/screens/migration_screen.dart`
- Modify: `lib/src/features/migration/migration_copy.dart`
- Delete: `lib/src/features/migration/widgets/migration_signing_overlay.dart`
- Delete: `lib/src/features/migration/widgets/migration_completion_dialog.dart` (verified unreferenced)

- [ ] **Step 1: Rewrite the screen**

Replace the entire contents of `lib/src/features/migration/screens/migration_screen.dart` with:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../migration_copy.dart';
import '../models/migration_step_state.dart';
import '../models/migration_view_state.dart';
import '../providers/migration_expected_transfer_count_provider.dart';
import '../providers/migration_run_controller.dart';
import '../providers/orchard_migration_status_provider.dart';
import '../widgets/migration_step_card.dart';

class MigrationScreen extends ConsumerStatefulWidget {
  const MigrationScreen({super.key});

  @override
  ConsumerState<MigrationScreen> createState() => _MigrationScreenState();
}

class _MigrationScreenState extends ConsumerState<MigrationScreen> {
  Timer? _progressRefreshTimer;

  @override
  void dispose() {
    _progressRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accountState = ref.watch(accountProvider).value;
    final account = accountState?.activeAccount;
    final accountUuid = accountState?.activeAccountUuid;
    final isHardware = account?.isHardware ?? false;
    final sync = (ref.watch(syncProvider).value ?? SyncState()).scopedToAccount(
      accountUuid,
    );
    final migrationTransactions = _migrationTransactions(
      sync.recentTransactions,
    );
    final expectedTransferCount = ref.watch(
      migrationExpectedTransferCountProvider,
    );
    final scopedExpectedTransferCount = accountUuid == null
        ? null
        : expectedTransferCount[accountUuid];
    final now = DateTime.now();
    final hasUnconfirmedMigration = migrationTransactions.any(
      _isPendingMigration,
    );
    final expectedTransferCountIsFresh =
        scopedExpectedTransferCount != null &&
        (!scopedExpectedTransferCount.isExpired(now) ||
            hasUnconfirmedMigration);
    final freshExpectedTransferCount = expectedTransferCountIsFresh
        ? scopedExpectedTransferCount
        : null;
    final scopedExpectedCount = freshExpectedTransferCount?.count;
    final currentRunMigrationTransactions = _currentRunMigrationTransactions(
      migrationTransactions,
      freshExpectedTransferCount,
    );
    final currentRunCompletedCount = currentRunMigrationTransactions
        .where(_isCompletedMigration)
        .length;
    final expectedMigrationInProgress =
        scopedExpectedCount != null &&
        currentRunCompletedCount < scopedExpectedCount;
    final hasPendingMigration =
        hasUnconfirmedMigration || expectedMigrationInProgress;
    final hasCompletedMigration = migrationTransactions.any(
      _isCompletedMigration,
    );
    final migrationStatusAsync = ref.watch(
      activeOrchardMigrationStatusProvider,
    );
    final migrationStatus = migrationStatusAsync.value;
    final runState = ref.watch(migrationRunControllerProvider);
    final statusIsLoading =
        !isHardware &&
        accountUuid != null &&
        migrationStatus == null &&
        migrationStatusAsync.isLoading;
    final statusError = migrationStatusAsync.error;

    late final Widget body;
    MigrationViewState? viewState;
    if (statusIsLoading) {
      body = const _StatusNote(
        title: MigrationCopy.checkingTitle,
        body: MigrationCopy.checkingBody,
      );
    } else if (!isHardware &&
        accountUuid != null &&
        statusError != null &&
        migrationStatus == null) {
      body = _StatusNote(
        title: MigrationCopy.failedRecoverableTitle,
        body: MigrationCopy.failedRecoverableBody,
        details: statusError.toString(),
        onRetry: () => ref.invalidate(activeOrchardMigrationStatusProvider),
      );
      viewState = MigrationViewState.failedRecoverable;
    } else {
      viewState = migrationViewState(
        isHardware: isHardware,
        rustPhase: migrationStatus?.phase,
        hasPendingMigration: hasPendingMigration,
        hasCompletedMigration: hasCompletedMigration,
        orchardBalance: sync.orchardBalance,
        ironwoodBalance: sync.ironwoodBalance,
      );

      if (viewState == MigrationViewState.softwareRequired) {
        body = const _SoftwareRequiredView();
      } else {
        final steps = migrationStepsModel(
          viewState: viewState,
          status: migrationStatus,
          runInFlight: runState.inFlight,
          intent: runState.intent,
        );
        final effectiveExpectedCount =
            migrationStatus != null && migrationStatus.totalCount > 0
            ? migrationStatus.totalCount
            : scopedExpectedCount;

        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              MigrationCopy.idleTitle,
              style: AppTypography.displaySmall.copyWith(
                color: context.colors.text.accent,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              MigrationCopy.idleBody,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const _PoolTransition(),
            const SizedBox(height: AppSpacing.md),
            _stepOneCard(steps, viewState, migrationStatus, runState, sync),
            const SizedBox(height: AppSpacing.s),
            _stepTwoCard(
              steps,
              viewState,
              migrationStatus,
              runState,
              sync,
              currentRunMigrationTransactions,
              effectiveExpectedCount,
            ),
            if (migrationStatus != null && migrationStatus.totalCount > 0) ...[
              const SizedBox(height: AppSpacing.s),
              _RunDetails(status: migrationStatus),
            ],
          ],
        );
      }
    }

    _syncMigrationProgressPolling(
      hasPendingMigration || (viewState?.shouldPollProgress ?? false),
    );
    _clearExpiredExpectedTransferCount(
      accountUuid: accountUuid,
      expectedTransferCount: scopedExpectedTransferCount,
      hasPendingMigration:
          hasUnconfirmedMigration || (viewState?.hasActiveRun ?? false),
    );

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: body,
        ),
      ),
    );
  }

  Widget _stepOneCard(
    MigrationStepsModel steps,
    MigrationViewState viewState,
    rust_sync.MigrationStatus? status,
    MigrationRunState runState,
    SyncState sync,
  ) {
    final errorBanner = runState.errorIntent == MigrationRunIntent.preparing
        ? runState.error
        : null;

    return switch (steps.stepOne) {
      MigrationStepOneState.blocked => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        isDimmed: true,
        statusLine: viewState == MigrationViewState.noOrchardFunds
            ? MigrationCopy.stepOneNoFunds
            : MigrationCopy.stepOneUnspendable,
        errorBanner: errorBanner,
        ctaLabel: MigrationCopy.stepOneCta,
        onCta: null,
      ),
      MigrationStepOneState.active => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        statusLine: MigrationCopy.stepOneBody,
        errorBanner: errorBanner,
        body: [_readyAmount(sync)],
        ctaLabel: MigrationCopy.stepOneCta,
        onCta: () => ref
            .read(migrationRunControllerProvider.notifier)
            .advance(MigrationRunIntent.preparing),
      ),
      MigrationStepOneState.running => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        showSpinner: true,
        statusLine: MigrationCopy.stepOneRunning,
      ),
      MigrationStepOneState.waiting => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        statusLine: MigrationCopy.stepOneWaiting,
        errorBanner: errorBanner,
        body: [
          if (status != null && status.totalCount > 0)
            Text(
              MigrationCopy.stepOnePreparedCounts(
                status.preparedNoteCount,
                status.totalCount,
              ),
              style: AppTypography.bodyExtraSmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
        ],
      ),
      MigrationStepOneState.done => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        isDone: true,
        statusLine: status != null && status.totalCount > 0
            ? MigrationCopy.stepOneDone(status.totalCount)
            : MigrationCopy.stepOneDoneGeneric,
      ),
      MigrationStepOneState.error => MigrationStepCard(
        stepNumber: 1,
        title: MigrationCopy.stepOneTitle,
        statusLine: status?.message ?? MigrationCopy.failedRecoverableBody,
        statusIsError: true,
        errorBanner: errorBanner,
        ctaLabel: MigrationCopy.retryCta,
        onCta: () => ref
            .read(migrationRunControllerProvider.notifier)
            .advance(MigrationRunIntent.preparing),
      ),
    };
  }

  Widget _stepTwoCard(
    MigrationStepsModel steps,
    MigrationViewState viewState,
    rust_sync.MigrationStatus? status,
    MigrationRunState runState,
    SyncState sync,
    List<rust_sync.TransactionInfo> currentRunMigrationTransactions,
    int? effectiveExpectedCount,
  ) {
    final errorBanner = runState.errorIntent == MigrationRunIntent.migrating
        ? runState.error
        : null;
    final total = status?.totalCount ?? 0;
    void startMigration() => ref
        .read(migrationRunControllerProvider.notifier)
        .advance(MigrationRunIntent.migrating);

    return switch (steps.stepTwo) {
      MigrationStepTwoState.locked => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        isDimmed: true,
        statusLine: MigrationCopy.stepTwoLocked,
        errorBanner: errorBanner,
        ctaLabel: MigrationCopy.stepTwoCta,
        onCta: null,
      ),
      MigrationStepTwoState.ready => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        statusLine: MigrationCopy.stepTwoReady(
          total,
          MigrationCopy.migrationWindowText(
            (status?.broadcastWindowSeconds ?? BigInt.from(60)).toInt(),
          ),
        ),
        errorBanner: errorBanner,
        body: [
          if (viewState == MigrationViewState.paused)
            Text(
              MigrationCopy.stepTwoPausedNote,
              style: AppTypography.bodyExtraSmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
        ],
        ctaLabel: MigrationCopy.stepTwoCta,
        onCta: startMigration,
      ),
      MigrationStepTwoState.running => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        showSpinner: true,
        statusLine: _stepTwoRunningLine(status),
        progress: total > 0
            ? (status?.broadcastedTxCount ?? 0).clamp(0, total) / total
            : null,
        body: [_warningRow(MigrationCopy.stepTwoKeepOpen)],
      ),
      MigrationStepTwoState.confirming => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        statusLine: MigrationCopy.inProgressBody,
        body: [
          _MigrationTransfersList(
            migrationTransactions: currentRunMigrationTransactions,
            expectedTransferCount: effectiveExpectedCount,
            amountZatoshi: _migrationDisplayAmount(
              sync,
              currentRunMigrationTransactions,
            ),
          ),
          _warningRow(MigrationCopy.keepOpenWarning),
        ],
      ),
      MigrationStepTwoState.done => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        isDone: true,
        statusLine: MigrationCopy.doneBody,
      ),
      MigrationStepTwoState.error => MigrationStepCard(
        stepNumber: 2,
        title: MigrationCopy.stepTwoTitle,
        statusLine: switch (viewState) {
          MigrationViewState.failedTerminal =>
            status?.message ?? MigrationCopy.failedTerminalBody,
          MigrationViewState.abandoned => MigrationCopy.abandonedBody,
          _ => status?.message ?? MigrationCopy.failedRecoverableBody,
        },
        statusIsError: true,
        errorBanner: errorBanner,
        ctaLabel: viewState == MigrationViewState.failedRecoverable
            ? MigrationCopy.retryCta
            : null,
        onCta: viewState == MigrationViewState.failedRecoverable
            ? startMigration
            : null,
      ),
    };
  }

  String _stepTwoRunningLine(rust_sync.MigrationStatus? status) {
    final total = status?.totalCount ?? 0;
    final isSubmitting =
        status?.phase == 'broadcasting' || status?.phase == 'broadcast_scheduled';
    if (isSubmitting && total > 0) {
      final next = ((status?.broadcastedTxCount ?? 0) + 1).clamp(1, total);
      return MigrationCopy.stepTwoSubmitting(next, total);
    }
    return MigrationCopy.stepTwoSigning;
  }

  Widget _readyAmount(SyncState sync) {
    final amount = ZecAmount.fromZatoshi(
      sync.orchardBalance,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.readyToMigrateLabel,
          style: AppTypography.labelLarge.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          amount,
          key: const ValueKey('migration_ready_amount'),
          style: AppTypography.displaySmall.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          MigrationCopy.poolFlow,
          style: AppTypography.bodyExtraSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }

  Widget _warningRow(String text) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(
          AppIcons.warning,
          size: AppIconSize.medium,
          color: colors.icon.muted,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodyExtraSmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }

  void _syncMigrationProgressPolling(bool enabled) {
    if (enabled && _progressRefreshTimer == null) {
      _progressRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        unawaited(_refreshMigrationProgress());
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_refreshMigrationProgress());
      });
      return;
    }

    if (!enabled && _progressRefreshTimer != null) {
      _progressRefreshTimer?.cancel();
      _progressRefreshTimer = null;
    }
  }

  Future<void> _refreshMigrationProgress() async {
    try {
      await ref
          .read(syncProvider.notifier)
          .refreshAfterSend(
            transactionHistoryLimit: migrationProgressTransactionHistoryLimit,
          );
    } catch (e) {
      log('MigrationScreen: migration progress refresh failed: $e');
    }
  }

  void _clearExpiredExpectedTransferCount({
    required String? accountUuid,
    required MigrationExpectedTransferCount? expectedTransferCount,
    required bool hasPendingMigration,
  }) {
    if (accountUuid == null ||
        expectedTransferCount == null ||
        hasPendingMigration ||
        !expectedTransferCount.isExpired(DateTime.now())) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(migrationExpectedTransferCountProvider.notifier)
          .clearCount(accountUuid);
    });
  }
}

List<rust_sync.TransactionInfo> _migrationTransactions(
  Iterable<rust_sync.TransactionInfo> transactions,
) {
  return transactions
      .where((tx) => tx.txKind == 'migration')
      .toList(growable: false);
}

List<rust_sync.TransactionInfo> _currentRunMigrationTransactions(
  List<rust_sync.TransactionInfo> migrationTransactions,
  MigrationExpectedTransferCount? expectedTransferCount,
) {
  final firstTxid = expectedTransferCount?.firstTxid.toLowerCase();
  if (firstTxid == null) return migrationTransactions;

  final firstTxIndex = migrationFirstTransactionIndex(
    transactionTxids: migrationTransactions.map((tx) => tx.txidHex),
    firstTxid: firstTxid,
  );
  if (firstTxIndex < 0) return const [];

  return migrationTransactions.take(firstTxIndex + 1).toList(growable: false);
}

bool _isPendingMigration(rust_sync.TransactionInfo tx) =>
    tx.minedHeight == BigInt.zero && !tx.expiredUnmined;

bool _isCompletedMigration(rust_sync.TransactionInfo tx) =>
    tx.minedHeight != BigInt.zero && !tx.expiredUnmined;

BigInt _migrationDisplayAmount(
  SyncState sync,
  List<rust_sync.TransactionInfo> migrationTransactions,
) {
  final txAmount = migrationTransactions.fold<BigInt>(
    BigInt.zero,
    (sum, tx) => sum + tx.displayAmount,
  );
  if (txAmount > BigInt.zero) return txAmount;
  return sync.orchardBalance;
}

/// Compact title/body note used for the pre-card loading and status-error
/// branches.
class _StatusNote extends StatelessWidget {
  const _StatusNote({
    required this.title,
    required this.body,
    this.details,
    this.onRetry,
  });

  final String title;
  final String body;
  final String? details;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        if (details != null && details!.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s),
          Text(
            details!,
            style: AppTypography.bodyExtraSmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton(
            onPressed: onRetry,
            child: const Text(MigrationCopy.retryCta),
          ),
        ],
      ],
    );
  }
}

/// Small-print run details below the cards (batch limit, window, counts).
class _RunDetails extends StatelessWidget {
  const _RunDetails({required this.status});

  final rust_sync.MigrationStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = status.totalCount;
    final rows = <String>[
      if (total > 0) 'Prepared notes: ${status.preparedNoteCount} of $total',
      if (status.pendingTxCount > 0)
        'Scheduled transactions: ${status.pendingTxCount}',
      if (total > 0)
        'Broadcasted transactions: ${status.broadcastedTxCount} of $total',
      if (status.confirmedTxCount > 0)
        'Confirmed transactions: ${status.confirmedTxCount} of $total',
      'Signing batch limit: ${status.signingBatchLimit}',
      'Broadcast window: ${status.broadcastWindowSeconds}s',
    ];

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows) ...[
            Text(
              row,
              style: AppTypography.bodyExtraSmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
        ],
      ),
    );
  }
}

class _SoftwareRequiredView extends StatelessWidget {
  const _SoftwareRequiredView();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.softwareRequiredTitle,
          style: AppTypography.displaySmall.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.s),
        _Card(
          child: Text(
            MigrationCopy.softwareRequiredBody,
            key: const ValueKey('migration_software_required'),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Transfer list shown inside step 2 while migration transactions confirm.
class _MigrationTransfersList extends StatelessWidget {
  const _MigrationTransfersList({
    required this.migrationTransactions,
    required this.expectedTransferCount,
    required this.amountZatoshi,
  });

  final List<rust_sync.TransactionInfo> migrationTransactions;
  final int? expectedTransferCount;
  final BigInt amountZatoshi;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = ZecAmount.fromZatoshi(
      amountZatoshi,
    ).pretty(denomStyle: ZecDenomStyle.upper).toString();
    final total = [
      migrationTransactions.length,
      expectedTransferCount ?? 0,
      1,
    ].reduce((a, b) => a > b ? a : b);
    final transferTransactions = migrationTransactions.reversed.toList(
      growable: false,
    );
    final completed = transferTransactions.where(_isCompletedMigration).length;
    final progress = migrationTransactions.isEmpty ? null : completed / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          MigrationCopy.migratingAmount(amount),
          style: AppTypography.labelLarge.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.full),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: colors.background.neutralSubtleOpacity,
            color: colors.icon.success,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$completed of $total confirmed',
          style: AppTypography.bodyExtraSmall.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        for (var i = 0; i < total; i++) ...[
          if (i > 0)
            Divider(height: AppSpacing.md, color: colors.border.subtle),
          _MigrationTransferRow(
            index: i,
            total: total,
            transaction: i < transferTransactions.length
                ? transferTransactions[i]
                : null,
          ),
        ],
      ],
    );
  }
}

class _MigrationTransferRow extends StatelessWidget {
  const _MigrationTransferRow({
    required this.index,
    required this.total,
    required this.transaction,
  });

  final int index;
  final int total;
  final rust_sync.TransactionInfo? transaction;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tx = transaction;
    final isComplete = tx != null && _isCompletedMigration(tx);
    final isFailed = tx?.expiredUnmined ?? false;
    final statusText = isFailed
        ? 'Failed'
        : isComplete
        ? 'Completed'
        : 'In progress';
    final icon = isFailed
        ? AppIcons.warning
        : isComplete
        ? AppIcons.checkCircle
        : AppIcons.time;
    final iconColor = isFailed
        ? colors.icon.destructive
        : isComplete
        ? colors.icon.success
        : colors.icon.muted;

    return Row(
      children: [
        AppIcon(icon, size: AppIconSize.medium, color: iconColor),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            MigrationCopy.transferLabel(index + 1, total),
            style: AppTypography.bodyMedium.copyWith(color: colors.text.accent),
          ),
        ),
        Text(
          statusText,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

class _PoolTransition extends StatelessWidget {
  const _PoolTransition();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: _Card(
            child: Column(
              children: [
                Text(
                  MigrationCopy.fromPoolName,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                Text(
                  MigrationCopy.fromPoolTag,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
          child: AppIcon(
            AppIcons.arrowForwardIos,
            size: AppIconSize.medium,
            color: colors.icon.muted,
          ),
        ),
        Expanded(
          child: _Card(
            child: Column(
              children: [
                Text(
                  MigrationCopy.toPoolName,
                  style: AppTypography.bodyLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                Text(
                  MigrationCopy.toPoolTag,
                  style: AppTypography.bodyExtraSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: child,
    );
  }
}
```

- [ ] **Step 2: Delete the overlay and the dead dialog**

```bash
git rm lib/src/features/migration/widgets/migration_signing_overlay.dart lib/src/features/migration/widgets/migration_completion_dialog.dart
```

- [ ] **Step 3: Prune obsolete copy**

In `lib/src/features/migration/migration_copy.dart` delete these members (now unreferenced): `startCta`, `bullet1`, `bullet2`, `bullet3`, `noOrchardFundsTitle`, `noOrchardFundsBody`, `waitingForSpendableTitle`, `waitingForSpendableBody`, `preparingDenominationsTitle`, `preparingDenominationsBody`, `waitingDenomTitle`, `waitingDenomBody`, `readyPreparedTitle`, `readyPreparedBody`, `readyPreparedCta`, `buildingBatchTitle`, `buildingBatchBody`, `signingBatchTitle`, `signingBatchBody`, `broadcastScheduledTitle`, `broadcastScheduledBody`, `broadcastingStatusTitle`, `broadcastingStatusBody`, `pausedTitle`, `pausedBody`, `signTitle`, `signSubtitle`, `signInstruction`, `signCancel`, `broadcastingTitle`, `broadcastingSubtitle`, `broadcastingInstruction`, `signBack`, `completeTitle`, `completeBody`, `completeButton`, `inProgressTitle`, `doneTitle`, `failedTerminalTitle`, `abandonedTitle`, `genericError`.

Keep: `tabLabel`, `idleTitle`, `idleBody`, `fromPoolName`, `fromPoolTag`, `toPoolName`, `toPoolTag`, `readyToMigrateLabel`, `poolFlow`, all `stepOne*`/`stepTwo*`/`partialBroadcastError`/`migrationWindowText`, `softwareRequired*`, `checking*`, `retryCta`, `failedRecoverableTitle`, `failedRecoverableBody`, `failedTerminalBody`, `abandonedBody`, `scan*`, `inProgressBody`, `migratingAmount`, `transferLabel`, `keepOpenWarning`, `doneBody`.

After pruning run `grep -rn "MigrationCopy\." lib test | grep -oE "MigrationCopy\.[a-zA-Z]+" | sort -u` and cross-check the list against the class: every referenced member must exist, and any member referenced by nothing gets deleted.

- [ ] **Step 4: Analyze and run the full test suite**

Run: `fvm flutter analyze && fvm flutter test`
Expected: no analyzer issues; all tests pass (the deleted overlay had no tests; `migration_view_state_test.dart` untouched and green).

- [ ] **Step 5: Commit**

```bash
git add -A lib/src/features/migration
git commit -m "Recompose migration tab as two-step cards"
```

---

### Task 7: Full verification

**Files:** none (verification only; fix-up commits if needed)

- [ ] **Step 1: Static + unit gate**

Run: `fvm flutter analyze && fvm flutter test`
Expected: clean analyze, full suite green.

- [ ] **Step 2: macOS debug build**

Reapply the local-only bundle-id patches if missing (keep UNSTAGED, never commit — see `~/.claude/CLAUDE.md`): `macos/Runner/Configs/AppInfo.xcconfig` and `macos/Runner.xcodeproj/project.pbxproj` → `com.adamtucker.vizor.local`. Then from the worktree root:

```bash
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Debug \
  -destination 'platform=macOS' SYMROOT="$PWD/build/macos/Build/Products" \
  CODE_SIGNING_ALLOWED=NO build
pkill -x Vizor || true
open -n "$PWD/build/macos/Build/Products/Debug/Vizor.app"
```

Expected: `** BUILD SUCCEEDED **`, app launches.

- [ ] **Step 3: Manual two-step run (testnet)**

1. Select a testnet endpoint; let the wallet sync. Watch the migration tab during the scan: the cards must hold steady (no waiting/ready flapping).
2. Step 1 card active → click "Prepare denominations" → inline spinner → card flips to waiting with prepared-note counts; step 2 stays locked.
3. After confirmations: step 1 done (check badge), step 2 ready with "signs N … about one minute" copy.
4. Click "Start migration" → inline signing line, then submitting i-of-N with progress bar over ~60 s; keep-open line visible.
5. Transfers list appears (confirming); rows complete as txs mine; then step 2 done.
6. Sanity: send screen not intermittently blocked while the tab is open during sync.

- [ ] **Step 4: Commit any fix-ups**

```bash
git status --short   # review, then commit fixes with focused messages
```
