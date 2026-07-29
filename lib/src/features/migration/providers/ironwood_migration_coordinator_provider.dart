import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/app_process_work_policy.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../models/ironwood_migration_presentation.dart';
import '../models/mobile_ironwood_migration_attention_state.dart';
import '../services/ironwood_migration_service.dart';
import 'ironwood_migration_announcement_provider.dart';

const _migrationStatusPollInterval = Duration(seconds: 5);
const _migrationAdvanceInterval = Duration(
  seconds: String.fromEnvironment('ZCASH_DEFAULT_NETWORK') == 'regtest'
      ? 1
      : kZcashFastTestnetMigration
      ? 5
      : 30,
);

/// Enforces ZIP 318's wallet-global, one-transfer fallback allowance for
/// transfers that were already overdue when a desktop foreground epoch began.
class DesktopOpenMigrationFallbackGate {
  bool _available = true;
  bool _foreground = true;
  int? _foregroundEntryHeight;
  bool _openStatusSnapshotReady = false;
  final Map<String, int> _openOverdueScheduleByTxid = {};

  bool get needsAuthoritativeEntryHeight =>
      _foreground && _foregroundEntryHeight == null;
  bool get needsOpenStatusSnapshot =>
      _foreground &&
      _foregroundEntryHeight != null &&
      !_openStatusSnapshotReady;

  void enterForeground() {
    if (_foreground) return;
    _foreground = true;
    _available = true;
    _foregroundEntryHeight = null;
    _openStatusSnapshotReady = false;
    _openOverdueScheduleByTxid.clear();
  }

  void leaveForeground() {
    _foreground = false;
    _available = false;
    _foregroundEntryHeight = null;
    _openStatusSnapshotReady = false;
    _openOverdueScheduleByTxid.clear();
  }

  void observeForegroundEntryHeight(int height) {
    if (height > 0) {
      _foregroundEntryHeight ??= height;
    }
  }

  void captureOpenStatuses(Iterable<rust_sync.MigrationStatus> statuses) {
    final entryHeight = _foregroundEntryHeight;
    if (entryHeight == null || entryHeight <= 0) return;
    _openOverdueScheduleByTxid.clear();
    for (final status in statuses) {
      for (final broadcast in status.scheduledBroadcasts) {
        if (broadcast.status.toLowerCase() == 'scheduled' &&
            broadcast.scheduledHeight > 0 &&
            broadcast.scheduledHeight <= entryHeight) {
          _openOverdueScheduleByTxid[broadcast.txidHex] =
              broadcast.scheduledHeight;
        }
      }
    }
    _openStatusSnapshotReady = true;
  }

  bool allows(rust_sync.MigrationStatus status) {
    if ((_foregroundEntryHeight == null || !_openStatusSnapshotReady) &&
        _hasScheduledTransfer(status)) {
      // Neither a cached wallet height nor a partial account snapshot can
      // establish the wallet-wide set that was overdue when the app opened.
      // Fail closed until lightwalletd and every account status are available.
      return false;
    }
    return !isOpenOverdue(status) || _available;
  }

  bool tryAcquireForAdvance(rust_sync.MigrationStatus status) {
    if (!allows(status)) return false;
    consumeIfOpenOverdue(status);
    return true;
  }

  void consumeIfOpenOverdue(rust_sync.MigrationStatus status) {
    if (isOpenOverdue(status)) {
      _available = false;
    }
  }

  void completeAdvance(
    rust_sync.MigrationStatus before,
    rust_sync.IronwoodMigrationResult result,
  ) {
    if (!isOpenOverdue(before)) return;
    // The one-due Rust endpoint defines txids as the exact transactions
    // accepted by this invocation, including the accepted-but-not-stored
    // recovery case. Do not infer acceptance from aggregate run counters.
    final resultTxids = result.txids
        .split(',')
        .map((txid) => txid.trim().toLowerCase())
        .where((txid) => txid.isNotEmpty)
        .toSet();
    final acceptedOpenOverdueTx = before.scheduledBroadcasts.any(
      (broadcast) =>
          broadcast.status.toLowerCase() == 'scheduled' &&
          _openOverdueScheduleByTxid[broadcast.txidHex] ==
              broadcast.scheduledHeight &&
          resultTxids.contains(broadcast.txidHex.toLowerCase()),
    );
    if (!acceptedOpenOverdueTx && _foreground) {
      _available = true;
    }
  }

  void failAdvance(rust_sync.MigrationStatus before) {
    if (isOpenOverdue(before) && _foreground) {
      _available = true;
    }
  }

  bool isOpenOverdue(rust_sync.MigrationStatus status) {
    return status.scheduledBroadcasts.any(
      (broadcast) =>
          broadcast.status.toLowerCase() == 'scheduled' &&
          _openOverdueScheduleByTxid[broadcast.txidHex] ==
              broadcast.scheduledHeight,
    );
  }

  bool _hasScheduledTransfer(rust_sync.MigrationStatus status) {
    return status.scheduledBroadcasts.any(
      (broadcast) =>
          broadcast.status.toLowerCase() == 'scheduled' &&
          broadcast.scheduledHeight > 0,
    );
  }
}

class IronwoodMigrationCoordinatorState {
  const IronwoodMigrationCoordinatorState({
    this.statuses = const {},
    this.errors = const {},
    this.advancingAccounts = const {},
    this.stoppingAccounts = const {},
    this.finishingImmediatelyAccounts = const {},
    this.foregroundProgressPermits = const {},
    this.childProofBatchPermits = const {},
  });

  final Map<String, rust_sync.MigrationStatus> statuses;
  final Map<String, String> errors;
  final Set<String> advancingAccounts;
  final Set<String> stoppingAccounts;
  final Set<String> finishingImmediatelyAccounts;

  /// Accounts whose migration may continue in the current foreground session.
  ///
  /// Mobile grants this only after an explicit user action and clears it
  /// whenever the app backgrounds. Child proofs additionally require the
  /// one-shot [childProofBatchPermits] gate.
  final Set<String> foregroundProgressPermits;

  /// Accounts for which the user explicitly approved one child-proof batch.
  /// Unlike [foregroundProgressPermits], this is consumed by one proof attempt.
  final Set<String> childProofBatchPermits;

  IronwoodMigrationCoordinatorState copyWith({
    Map<String, rust_sync.MigrationStatus>? statuses,
    Map<String, String>? errors,
    Set<String>? advancingAccounts,
    Set<String>? stoppingAccounts,
    Set<String>? finishingImmediatelyAccounts,
    Set<String>? foregroundProgressPermits,
    Set<String>? childProofBatchPermits,
  }) {
    return IronwoodMigrationCoordinatorState(
      statuses: statuses ?? this.statuses,
      errors: errors ?? this.errors,
      advancingAccounts: advancingAccounts ?? this.advancingAccounts,
      stoppingAccounts: stoppingAccounts ?? this.stoppingAccounts,
      finishingImmediatelyAccounts:
          finishingImmediatelyAccounts ?? this.finishingImmediatelyAccounts,
      foregroundProgressPermits:
          foregroundProgressPermits ?? this.foregroundProgressPermits,
      childProofBatchPermits:
          childProofBatchPermits ?? this.childProofBatchPermits,
    );
  }
}

class IronwoodMigrationCoordinator
    extends Notifier<IronwoodMigrationCoordinatorState> {
  Future<void>? _refreshOperation;
  bool _refreshPending = false;
  bool _forceAdvancePending = false;
  bool _foreground = true;
  int _accountStateEpoch = 0;
  final _desktopOpenFallbackGate = DesktopOpenMigrationFallbackGate();
  bool _hasObservedInitialAccountList = false;
  Future<void>? _backgroundPreparationRecovery;
  final Map<String, DateTime> _lastAdvanceAt = {};
  final Map<String, ({String progressKey, DateTime retryAt})>
  _outboxRecoveryWindows = {};
  final Map<String, String> _lastAdvanceProgressKeys = {};
  final Map<String, Future<void>> _advanceOperations = {};
  final Map<({String accountUuid, String runId}), Future<void>>
  _stopOperations = {};
  final Map<String, Future<void>> _stopOperationTails = {};
  final Set<String> _stoppingAccounts = {};
  final Map<String, Future<void>> _finishImmediatelyOperations = {};
  final Set<String> _finishingImmediatelyAccounts = {};

  @override
  IronwoodMigrationCoordinatorState build() {
    ref.listen(accountProvider, (_, next) {
      _accountStateEpoch += 1;
      final accountState = next.value;
      if (accountState == null) {
        unawaited(refreshNow());
        return;
      }
      final hasAccounts = accountState.accounts.isNotEmpty;
      if (!hasAccounts) {
        _clearProcessLocalStateForNoAccounts();
        return;
      }
      if (!_hasObservedInitialAccountList) {
        _hasObservedInitialAccountList = true;
        unawaited(resumeBackgroundPreparations());
        unawaited(refreshNow());
      } else {
        unawaited(refreshNow());
      }
    });
    ref.listen(appSecurityProvider, (previous, next) {
      if (previous?.requiresUnlock == true && !next.requiresUnlock) {
        unawaited(resumeBackgroundPreparations());
        unawaited(refreshNow());
      } else {
        unawaited(refreshNow());
      }
    });
    ref.listen(rpcEndpointFailoverProvider, (_, _) => unawaited(refreshNow()));
    return const IronwoodMigrationCoordinatorState();
  }

  void setForeground(bool foreground) {
    final wasForeground = _foreground;
    _foreground = foreground;
    if (foreground) {
      if (kAppFormFactor == AppFormFactor.desktop && !wasForeground) {
        _desktopOpenFallbackGate.enterForeground();
      }
      unawaited(resumeBackgroundPreparations());
      unawaited(
        refreshNow(forceAdvance: kAppFormFactor == AppFormFactor.desktop),
      );
    } else {
      if (kAppFormFactor == AppFormFactor.desktop) {
        _desktopOpenFallbackGate.leaveForeground();
      } else if (state.foregroundProgressPermits.isNotEmpty ||
          state.childProofBatchPermits.isNotEmpty) {
        state = state.copyWith(
          foregroundProgressPermits: const {},
          childProofBatchPermits: const {},
        );
      }
    }
  }

  /// Allows automatic progression for [accountUuid] until the app backgrounds.
  ///
  /// The mobile UI should call this after an explicit signing/resume action.
  /// Software migration start and [retry] grant it automatically.
  void grantForegroundProgressPermit(String accountUuid) {
    if (kAppFormFactor != AppFormFactor.mobile ||
        state.foregroundProgressPermits.contains(accountUuid)) {
      return;
    }
    state = state.copyWith(
      foregroundProgressPermits: {
        ...state.foregroundProgressPermits,
        accountUuid,
      },
    );
  }

  /// Allows exactly one k-max child-proof batch for [accountUuid].
  ///
  /// This also grants the general foreground permit required to enter the
  /// migration operation. The proof-specific permit is consumed before the
  /// batch attempt starts.
  void grantChildProofBatchPermit(String accountUuid) {
    if (kAppFormFactor != AppFormFactor.mobile) return;
    state = state.copyWith(
      foregroundProgressPermits: {
        ...state.foregroundProgressPermits,
        accountUuid,
      },
      childProofBatchPermits: {...state.childProofBatchPermits, accountUuid},
    );
  }

  /// Removes a previously granted child-proof approval without revoking the
  /// broader foreground continuation permit.
  ///
  /// Keystone QR signing and child proof generation are separate user actions.
  /// Completing a QR round must therefore leave the account waiting until the
  /// proof window is actually due and the user explicitly approves that batch.
  void clearChildProofBatchPermit(String accountUuid) {
    if (kAppFormFactor != AppFormFactor.mobile ||
        !state.childProofBatchPermits.contains(accountUuid)) {
      return;
    }
    state = state.copyWith(
      childProofBatchPermits: {...state.childProofBatchPermits}
        ..remove(accountUuid),
    );
  }

  /// Performs the one foreground sync required when a migration status flow is
  /// entered from a cold launch or after returning from background, then
  /// reconciles status without advancing migration work.
  ///
  /// The route owns whether this is an actual entry/resume event. Periodic sync
  /// must not call this API or use its Future as a full-screen loading signal.
  Future<void> synchronizeAndReconcileAfterReentry() async {
    if (kAppFormFactor == AppFormFactor.mobile &&
        (state.foregroundProgressPermits.isNotEmpty ||
            state.childProofBatchPermits.isNotEmpty)) {
      state = state.copyWith(
        foregroundProgressPermits: const {},
        childProofBatchPermits: const {},
      );
    }
    await ref.read(syncProvider.future);
    if (!ref.mounted) return;
    await ref.read(syncProvider.notifier).synchronizeForMigrationEntry();
    if (!ref.mounted) return;
    await refreshNow();
  }

  Future<void> resumeBackgroundPreparations() {
    final inFlight = _backgroundPreparationRecovery;
    if (inFlight != null) return inFlight;

    late final Future<void> tracked;
    tracked = _resumeBackgroundPreparations().whenComplete(() {
      if (identical(_backgroundPreparationRecovery, tracked)) {
        _backgroundPreparationRecovery = null;
      }
    });
    _backgroundPreparationRecovery = tracked;
    return tracked;
  }

  Future<void> _resumeBackgroundPreparations() async {
    if (!ref.mounted || !canRunAppProcessWork(isInForeground: _foreground)) {
      return;
    }
    if (ref.read(appSecurityProvider).requiresUnlock) return;

    final accountState = ref.read(accountProvider).value;
    if (accountState == null) return;
    if (accountState.accounts.isEmpty) {
      _clearProcessLocalStateForNoAccounts();
      return;
    }
    _hasObservedInitialAccountList = true;

    final service = ref.read(ironwoodMigrationServiceProvider);
    final network = ref.read(rpcEndpointFailoverProvider).current.networkName;
    for (final account in accountState.accounts) {
      try {
        await service.resumeBackgroundPreparationIfNeeded(
          network: network,
          accountUuid: account.uuid,
        );
      } catch (error) {
        log(
          'Ironwood migration preparation recovery failed for '
          '${account.uuid}: $error',
        );
      }
      if (!ref.mounted) return;
    }
  }

  Future<void> startSoftwareMigration({
    required String accountUuid,
    required List<rust_sync.MigrationScheduledTransfer> approvedSchedule,
  }) async {
    await ref
        .read(ironwoodMigrationServiceProvider)
        .startSoftwarePrivateMigration(
          accountUuid: accountUuid,
          approvedSchedule: approvedSchedule,
        );
    if (!ref.mounted) return;
    grantForegroundProgressPermit(accountUuid);
    await refreshNow(forceAdvance: true);
  }

  Future<void> resumeSoftwarePreparation({
    required String accountUuid,
    required rust_sync.MigrationStatus status,
  }) async {
    if (status.activeRunId == null ||
        status.phase != kIronwoodMigrationAwaitingPreparationPhase) {
      throw StateError(
        'Only a saved private migration draft can resume preparation.',
      );
    }
    final service = ref.read(ironwoodMigrationServiceProvider);
    final currentStatus = await service.status(
      network: ref.read(rpcEndpointFailoverProvider).current.networkName,
      accountUuid: accountUuid,
    );
    if (currentStatus.activeRunId != status.activeRunId) {
      throw StateError('The saved private migration draft changed.');
    }
    if (currentStatus.phase != kIronwoodMigrationAwaitingPreparationPhase) {
      await refreshNow();
      return;
    }
    await startSoftwareMigration(
      accountUuid: accountUuid,
      // Rust reloads the approved schedule from the durable draft. Keeping this
      // empty prevents stale route or plan data from becoming a second source
      // of truth during recovery.
      approvedSchedule: const [],
    );
  }

  Future<void> retry(
    String accountUuid, {
    rust_sync.MigrationStatus? status,
  }) async {
    // A status screen can be the first migration surface after a cold launch.
    // Its route provider may already have a current status while this
    // coordinator has not completed its first polling pass. Preserve that
    // observed proof state for the explicit user action.
    final statusForAdvance = status ?? state.statuses[accountUuid];
    if (statusForAdvance != null &&
        _isChildProofBatchAdvance(statusForAdvance)) {
      grantChildProofBatchPermit(accountUuid);
    } else {
      grantForegroundProgressPermit(accountUuid);
    }
    try {
      final inFlight = _advanceOperations[accountUuid];
      if (inFlight != null) {
        try {
          await inFlight;
        } catch (_) {
          // A manual retry must still run after the automatic attempt fails.
        }
      }
      final service = ref.read(ironwoodMigrationServiceProvider);
      if (statusForAdvance != null &&
          service.supportsBackgroundMigrationRetry &&
          _manualRetryNeedsOutboxRecovery(statusForAdvance)) {
        final recovery = await service.recoverDueMigrationOutbox(
          network: ref.read(rpcEndpointFailoverProvider).current.networkName,
          accountUuid: accountUuid,
        );
        final refreshedStatus = await service.status(
          network: ref.read(rpcEndpointFailoverProvider).current.networkName,
          accountUuid: accountUuid,
        );
        if (_manualRetryNeedsOutboxRecovery(refreshedStatus)) {
          _validateDueOutboxRecovery(recovery, accountUuid: accountUuid);
        }
        if (!ref.mounted) return;
        state = state.copyWith(
          errors: Map<String, String>.from(state.errors)..remove(accountUuid),
        );
        await refreshNow();
        return;
      }
      await _advance(accountUuid, status: statusForAdvance);
      if (!ref.mounted) return;
      state = state.copyWith(
        errors: Map<String, String>.from(state.errors)..remove(accountUuid),
      );
      await refreshNow();
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          errors: {...state.errors, accountUuid: error.toString()},
        );
      }
      rethrow;
    }
  }

  Future<void> recover(String accountUuid) async {
    grantForegroundProgressPermit(accountUuid);
    final inFlight = _advanceOperations[accountUuid];
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // Recovery intentionally takes over after the automatic attempt.
      }
    }
    if (!ref.mounted) return;

    state = state.copyWith(
      advancingAccounts: {...state.advancingAccounts, accountUuid},
    );
    try {
      await ref
          .read(ironwoodMigrationServiceProvider)
          .recoverSoftwarePrivateMigration(accountUuid: accountUuid);
      if (!ref.mounted) return;
      state = state.copyWith(
        errors: Map<String, String>.from(state.errors)..remove(accountUuid),
      );
      await refreshNow(forceAdvance: true);
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          errors: {...state.errors, accountUuid: error.toString()},
        );
      }
      rethrow;
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          advancingAccounts: {...state.advancingAccounts}..remove(accountUuid),
        );
      }
    }
  }

  Future<void> stop({required String accountUuid, required String runId}) {
    final key = (accountUuid: accountUuid, runId: runId);
    final existing = _stopOperations[key];
    if (existing != null) return existing;

    final previous = _stopOperationTails[accountUuid];
    if (previous == null) {
      _stoppingAccounts.add(accountUuid);
      state = state.copyWith(
        advancingAccounts: {...state.advancingAccounts, accountUuid},
        stoppingAccounts: {...state.stoppingAccounts, accountUuid},
        foregroundProgressPermits: {...state.foregroundProgressPermits}
          ..remove(accountUuid),
        childProofBatchPermits: {...state.childProofBatchPermits}
          ..remove(accountUuid),
      );
    }
    final operation = _runStopAfter(
      previous,
      accountUuid: accountUuid,
      runId: runId,
    );
    late final Future<void> tracked;
    tracked = operation.whenComplete(() {
      if (identical(_stopOperations[key], tracked)) {
        _stopOperations.remove(key);
      }
      if (identical(_stopOperationTails[accountUuid], tracked)) {
        _stopOperationTails.remove(accountUuid);
        _stoppingAccounts.remove(accountUuid);
        if (ref.mounted) {
          state = state.copyWith(
            advancingAccounts: {...state.advancingAccounts}
              ..remove(accountUuid),
            stoppingAccounts: {...state.stoppingAccounts}..remove(accountUuid),
          );
        }
      }
    });
    _stopOperations[key] = tracked;
    _stopOperationTails[accountUuid] = tracked;
    return tracked;
  }

  Future<void> finishImmediately({
    required String accountUuid,
    required String runId,
    required rust_sync.OrchardMigrationImmediatePlan approvedPlan,
  }) {
    final existing = _finishImmediatelyOperations[accountUuid];
    if (existing != null) return existing;

    _finishingImmediatelyAccounts.add(accountUuid);
    state = state.copyWith(
      advancingAccounts: {...state.advancingAccounts, accountUuid},
      finishingImmediatelyAccounts: {
        ...state.finishingImmediatelyAccounts,
        accountUuid,
      },
      foregroundProgressPermits: {...state.foregroundProgressPermits}
        ..remove(accountUuid),
      childProofBatchPermits: {...state.childProofBatchPermits}
        ..remove(accountUuid),
    );
    late final Future<void> tracked;
    tracked =
        _runFinishImmediately(
          accountUuid: accountUuid,
          runId: runId,
          approvedPlan: approvedPlan,
        ).whenComplete(() {
          if (identical(_finishImmediatelyOperations[accountUuid], tracked)) {
            _finishImmediatelyOperations.remove(accountUuid);
            _finishingImmediatelyAccounts.remove(accountUuid);
          }
          if (ref.mounted) {
            state = state.copyWith(
              advancingAccounts: {...state.advancingAccounts}
                ..remove(accountUuid),
              finishingImmediatelyAccounts: {
                ...state.finishingImmediatelyAccounts,
              }..remove(accountUuid),
            );
          }
        });
    _finishImmediatelyOperations[accountUuid] = tracked;
    return tracked;
  }

  void reportAccountError({
    required String accountUuid,
    required Object error,
  }) {
    state = state.copyWith(
      errors: {...state.errors, accountUuid: error.toString()},
    );
  }

  Future<void> _runFinishImmediately({
    required String accountUuid,
    required String runId,
    required rust_sync.OrchardMigrationImmediatePlan approvedPlan,
  }) async {
    try {
      final inFlight = _advanceOperations[accountUuid];
      if (inFlight != null) {
        try {
          await inFlight;
        } catch (_) {
          // Immediate completion takes over after foreground work exits.
        }
      }
      await ref
          .read(ironwoodMigrationServiceProvider)
          .finishSoftwarePrivateMigrationImmediately(
            accountUuid: accountUuid,
            expectedRunId: runId,
            approvedPlan: approvedPlan,
          );
      if (!ref.mounted) return;
      state = state.copyWith(
        errors: Map<String, String>.from(state.errors)..remove(accountUuid),
      );
      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (error) {
        log('Ironwood migration post-completion refresh failed: $error');
      }
      if (!ref.mounted) return;
      await refreshNow();
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          errors: {...state.errors, accountUuid: error.toString()},
        );
      }
      rethrow;
    }
  }

  Future<void> _runStopAfter(
    Future<void>? previous, {
    required String accountUuid,
    required String runId,
  }) async {
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // A stop for another run must still execute after the account lease is
        // released, even when the preceding stale cleanup failed.
      }
    }
    await _runStop(accountUuid: accountUuid, runId: runId);
  }

  Future<void> _runStop({
    required String accountUuid,
    required String runId,
  }) async {
    try {
      final inFlight = _advanceOperations[accountUuid];
      if (inFlight != null) {
        try {
          await inFlight;
        } catch (_) {
          // Stop takes over after any already-started foreground attempt exits.
        }
      }
      await ref
          .read(ironwoodMigrationServiceProvider)
          .stop(accountUuid: accountUuid, expectedRunId: runId);
      if (!ref.mounted) return;
      state = state.copyWith(
        errors: Map<String, String>.from(state.errors)..remove(accountUuid),
      );
      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (error) {
        // The durable stop has already committed. A balance refresh failure
        // must not invite the user to repeat the destructive action.
        log('Ironwood migration post-stop balance refresh failed: $error');
      }
      if (!ref.mounted) return;
      await refreshNow();
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          errors: {...state.errors, accountUuid: error.toString()},
        );
      }
      rethrow;
    }
  }

  Future<void> refreshNow({bool forceAdvance = false}) async {
    if (!ref.mounted) return;
    if (!canRunAppProcessWork(isInForeground: _foreground)) return;
    if (ref.read(appSecurityProvider).requiresUnlock) return;

    _refreshPending = true;
    _forceAdvancePending = _forceAdvancePending || forceAdvance;

    final existing = _refreshOperation;
    if (existing != null) return existing;

    late final Future<void> tracked;
    tracked = _drainRefreshes().whenComplete(() {
      if (identical(_refreshOperation, tracked)) {
        _refreshOperation = null;
      }
    });
    _refreshOperation = tracked;
    return tracked;
  }

  Future<void> _drainRefreshes() async {
    while (ref.mounted && _refreshPending) {
      final forceAdvance = _forceAdvancePending;
      _refreshPending = false;
      _forceAdvancePending = false;
      await _refreshOnce(forceAdvance: forceAdvance);
    }
  }

  Future<void> _refreshOnce({required bool forceAdvance}) async {
    if (!ref.mounted) return;
    if (!canRunAppProcessWork(isInForeground: _foreground)) return;
    if (ref.read(appSecurityProvider).requiresUnlock) return;

    final accountState = ref.read(accountProvider).value;
    if (accountState == null || accountState.accounts.isEmpty) return;
    final accountStateEpoch = _accountStateEpoch;
    if (kAppFormFactor == AppFormFactor.desktop &&
        _desktopOpenFallbackGate.needsAuthoritativeEntryHeight) {
      try {
        final entryHeight = await ref
            .read(rpcEndpointFailoverProvider.notifier)
            .getLatestBlockHeight();
        if (!_canApplyRefreshForAccountEpoch(accountStateEpoch)) return;
        _desktopOpenFallbackGate.observeForegroundEntryHeight(
          entryHeight.toInt(),
        );
      } catch (error) {
        // Status reconciliation and non-broadcast migration work may continue,
        // but the gate remains fail-closed for scheduled transfers until an
        // authoritative foreground-entry height can be read.
        log(
          'Ironwood migration on-open height lookup failed; '
          'scheduled fallback remains paused: $error',
        );
      }
    }

    final service = ref.read(ironwoodMigrationServiceProvider);
    final endpoint = ref.read(rpcEndpointFailoverProvider).current;
    final desktopOpenStatuses = <String, rust_sync.MigrationStatus>{};
    if (kAppFormFactor == AppFormFactor.desktop &&
        _desktopOpenFallbackGate.needsOpenStatusSnapshot) {
      var snapshotComplete = true;
      for (final account in accountState.accounts) {
        try {
          desktopOpenStatuses[account.uuid] = await service.status(
            network: endpoint.networkName,
            accountUuid: account.uuid,
          );
          if (!_canApplyRefreshForAccountEpoch(accountStateEpoch)) return;
        } catch (error) {
          snapshotComplete = false;
          log(
            'Ironwood migration on-open status snapshot failed for '
            '${account.uuid}; scheduled fallback remains paused: $error',
          );
        }
      }
      if (snapshotComplete) {
        _desktopOpenFallbackGate.captureOpenStatuses(
          desktopOpenStatuses.values,
        );
      }
    }
    final nextStatuses = Map<String, rust_sync.MigrationStatus>.from(
      state.statuses,
    );
    final nextErrors = Map<String, String>.from(state.errors);
    var activeBalanceMayHaveChanged = false;

    for (final account in accountState.accounts) {
      try {
        final previousStatus = state.statuses[account.uuid];
        var status =
            desktopOpenStatuses[account.uuid] ??
            await service.status(
              network: endpoint.networkName,
              accountUuid: account.uuid,
            );
        if (!_canApplyRefreshForAccountEpoch(accountStateEpoch)) return;
        nextStatuses[account.uuid] = status;
        nextErrors.remove(account.uuid);

        if (_shouldRecoverDueNativeOutbox(
          status,
          usesNativeOutbox: service.supportsBackgroundMigrationRetry,
          accountUuid: account.uuid,
        )) {
          final recovery = await service.recoverDueMigrationOutbox(
            network: endpoint.networkName,
            accountUuid: account.uuid,
          );
          if (!_canApplyRefreshForAccountEpoch(accountStateEpoch)) return;
          status = await service.status(
            network: endpoint.networkName,
            accountUuid: account.uuid,
          );
          if (!_canApplyRefreshForAccountEpoch(accountStateEpoch)) return;
          nextStatuses[account.uuid] = status;
          final stillDue = migrationHasDueScheduledBroadcast(
            status,
            currentHeight: _safelyObservedProofHeight(),
          );
          if (stillDue) {
            _validateDueOutboxRecovery(recovery, accountUuid: account.uuid);
          }
          if (!stillDue ||
              _outboxRecoveryCanWait(recovery, accountUuid: account.uuid)) {
            if (stillDue) {
              _outboxRecoveryWindows[account.uuid] = (
                progressKey: _outboxRecoveryProgressKey(status),
                retryAt: DateTime.now().add(_outboxRecoveryDelay(recovery)),
              );
            } else {
              _outboxRecoveryWindows.remove(account.uuid);
            }
          }
        }

        if (_shouldAdvance(
          status,
          isHardware: account.isHardware,
          usesNativeOutbox: service.supportsBackgroundMigrationRetry,
          force: forceAdvance,
          accountUuid: account.uuid,
        )) {
          await _advance(account.uuid, status: status);
          if (!_canApplyRefreshForAccountEpoch(accountStateEpoch)) return;
          status = await service.status(
            network: endpoint.networkName,
            accountUuid: account.uuid,
          );
          if (!_canApplyRefreshForAccountEpoch(accountStateEpoch)) return;
          nextStatuses[account.uuid] = status;
        }
        if (account.uuid == accountState.activeAccountUuid &&
            _migrationBalanceMayHaveChanged(previousStatus, status)) {
          activeBalanceMayHaveChanged = true;
        }
      } catch (error) {
        nextErrors[account.uuid] = error.toString();
        log(
          'Ironwood migration coordinator failed for ${account.uuid}: $error',
        );
      }
    }

    if (!_canApplyRefreshForAccountEpoch(accountStateEpoch)) return;
    if (activeBalanceMayHaveChanged) {
      try {
        // Migration status reads reconcile the database, but the home card
        // renders SyncState. Refresh that active-account snapshot when a
        // broadcast or confirmation transition can change its balances.
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (error) {
        // Status polling must remain available if a best-effort home balance
        // refresh races with a normal sync.
        log('Ironwood migration balance refresh failed: $error');
      }
      if (!_canApplyRefreshForAccountEpoch(accountStateEpoch)) return;
    }
    state = state.copyWith(statuses: nextStatuses, errors: nextErrors);
    _invalidateMigrationProviders(accountState.activeAccountUuid);
  }

  bool _canApplyRefreshForAccountEpoch(int accountStateEpoch) =>
      ref.mounted && accountStateEpoch == _accountStateEpoch;

  void _clearProcessLocalStateForNoAccounts() {
    final hadWalletState =
        _hasObservedInitialAccountList ||
        state.statuses.isNotEmpty ||
        state.errors.isNotEmpty ||
        state.advancingAccounts.isNotEmpty ||
        state.finishingImmediatelyAccounts.isNotEmpty ||
        state.foregroundProgressPermits.isNotEmpty ||
        state.childProofBatchPermits.isNotEmpty ||
        _lastAdvanceAt.isNotEmpty ||
        _outboxRecoveryWindows.isNotEmpty ||
        _lastAdvanceProgressKeys.isNotEmpty;
    if (!hadWalletState) return;

    _hasObservedInitialAccountList = false;
    _lastAdvanceAt.clear();
    _outboxRecoveryWindows.clear();
    _lastAdvanceProgressKeys.clear();
    _desktopOpenFallbackGate.leaveForeground();
    if (_foreground) {
      _desktopOpenFallbackGate.enterForeground();
    }
    state = const IronwoodMigrationCoordinatorState();
    _invalidateMigrationProviders(null);
  }

  bool _migrationBalanceMayHaveChanged(
    rust_sync.MigrationStatus? previous,
    rust_sync.MigrationStatus current,
  ) {
    // The first observation is normally paired with bootstrap/re-entry sync,
    // so do not add an extra balance fetch merely because the coordinator was
    // mounted. Subsequent child transaction transitions need a fresh snapshot
    // for the home balance card.
    if (previous == null) return false;

    if (previous.pendingTxCount != current.pendingTxCount ||
        previous.broadcastedTxCount != current.broadcastedTxCount ||
        previous.confirmedTxCount != current.confirmedTxCount ||
        previous.denominationConfirmationCount !=
            current.denominationConfirmationCount ||
        previous.denominationSplitCompletedCount !=
            current.denominationSplitCompletedCount) {
      return true;
    }

    final previousParts = {
      for (final part in previous.parts) part.partIndex: part,
    };
    if (previousParts.length != current.parts.length) return true;
    for (final part in current.parts) {
      final before = previousParts[part.partIndex];
      if (before == null ||
          before.state != part.state ||
          before.txidHex != part.txidHex ||
          before.confirmationCount != part.confirmationCount) {
        return true;
      }
    }
    return false;
  }

  bool _shouldRecoverDueNativeOutbox(
    rust_sync.MigrationStatus status, {
    required bool usesNativeOutbox,
    required String accountUuid,
  }) {
    if (_stoppingAccounts.contains(accountUuid) ||
        _finishingImmediatelyAccounts.contains(accountUuid) ||
        status.phase == kIronwoodMigrationImmediatePendingPhase) {
      return false;
    }
    final due =
        kAppFormFactor == AppFormFactor.mobile &&
        usesNativeOutbox &&
        migrationHasDueScheduledBroadcast(
          status,
          currentHeight: _safelyObservedProofHeight(),
        );
    if (!due) {
      _outboxRecoveryWindows.remove(accountUuid);
      return false;
    }
    final window = _outboxRecoveryWindows[accountUuid];
    final progressKey = _outboxRecoveryProgressKey(status);
    if (window == null || window.progressKey != progressKey) {
      _outboxRecoveryWindows.remove(accountUuid);
      return true;
    }
    return !DateTime.now().isBefore(window.retryAt);
  }

  /// Whether an explicit retry must go through native outbox recovery instead of
  /// the ordinary advance.
  ///
  /// A manual retry can run before sync reports a height: a migration status
  /// screen may be the first surface after a cold launch, and
  /// [_safelyObservedProofHeight] stays 0 until the first sync snapshot arrives.
  /// Reading that unknown height as "not due" is what sent an explicit retry
  /// back into [_advance], which cannot restore a missing native outbox batch.
  /// Recovery neither creates proofs nor signs anything, and the native runner
  /// applies its own height gate before it submits, so an unknown height resolves
  /// to recovery whenever a scheduled broadcast exists.
  bool _manualRetryNeedsOutboxRecovery(rust_sync.MigrationStatus status) {
    if (status.phase == kIronwoodMigrationImmediatePendingPhase) return false;
    final currentHeight = _safelyObservedProofHeight();
    if (currentHeight > 0) {
      return migrationHasDueScheduledBroadcast(
        status,
        currentHeight: currentHeight,
      );
    }
    return status.scheduledBroadcasts.any(
      (broadcast) =>
          broadcast.status.toLowerCase() == 'scheduled' &&
          broadcast.txidHex.isNotEmpty,
    );
  }

  void _validateDueOutboxRecovery(
    IronwoodMigrationOutboxRunResult result, {
    required String accountUuid,
  }) {
    switch (result.outcome) {
      case IronwoodMigrationOutboxRunOutcome.accepted:
        return;
      case IronwoodMigrationOutboxRunOutcome.waiting:
        if (result.accountUuid != accountUuid ||
            _outboxRecoveryCanWait(result, accountUuid: accountUuid)) {
          return;
        }
        throw StateError('Scheduled migration submission is waiting to retry.');
      case IronwoodMigrationOutboxRunOutcome.noWork:
        throw StateError(
          'The scheduled migration transaction is not available in the '
          'background outbox.',
        );
      case IronwoodMigrationOutboxRunOutcome.needsUserAction:
        if (result.accountUuid == accountUuid) {
          throw StateError('Scheduled migration submission needs user action.');
        }
        return;
      case IronwoodMigrationOutboxRunOutcome.temporarilyUnavailable:
        return;
      case IronwoodMigrationOutboxRunOutcome.cancelled:
        return;
    }
  }

  bool _outboxRecoveryCanWait(
    IronwoodMigrationOutboxRunResult result, {
    required String accountUuid,
  }) {
    if (result.outcome != IronwoodMigrationOutboxRunOutcome.waiting ||
        result.accountUuid != accountUuid) {
      return false;
    }
    final observedHeight = result.observedHeight;
    final nextHeight = result.nextHeight;
    return (result.retryDelay?.inMilliseconds ?? 0) > 0 ||
        (observedHeight != null &&
            nextHeight != null &&
            nextHeight > observedHeight);
  }

  Duration _outboxRecoveryDelay(IronwoodMigrationOutboxRunResult result) {
    final nativeDelay = result.retryDelay;
    if (nativeDelay == null || nativeDelay < _migrationAdvanceInterval) {
      return _migrationAdvanceInterval;
    }
    return nativeDelay;
  }

  String _outboxRecoveryProgressKey(rust_sync.MigrationStatus status) {
    final scheduled =
        status.scheduledBroadcasts
            .where((broadcast) => broadcast.status.toLowerCase() == 'scheduled')
            .map(
              (broadcast) =>
                  '${broadcast.txidHex.toLowerCase()}:${broadcast.scheduledHeight}',
            )
            .toList()
          ..sort();
    return '${status.activeRunId}:${scheduled.join(',')}';
  }

  bool _shouldAdvance(
    rust_sync.MigrationStatus status, {
    required bool isHardware,
    required bool usesNativeOutbox,
    required bool force,
    required String accountUuid,
  }) {
    if (_stoppingAccounts.contains(accountUuid) ||
        _finishingImmediatelyAccounts.contains(accountUuid)) {
      return false;
    }
    if (status.activeRunId == null) return false;
    if (kAppFormFactor == AppFormFactor.desktop &&
        !_desktopOpenFallbackGate.allows(status)) {
      return false;
    }
    if (kAppFormFactor == AppFormFactor.mobile &&
        !state.foregroundProgressPermits.contains(accountUuid)) {
      return false;
    }
    final hasChildProofBatchPermit =
        kAppFormFactor != AppFormFactor.mobile ||
        state.childProofBatchPermits.contains(accountUuid);
    final canPrepareNextProof = _canPrepareNextProof(status);
    final phaseCanAdvance =
        (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0) ||
        (status.phase == kIronwoodMigrationReadyToMigratePhase &&
            hasChildProofBatchPermit &&
            (!isHardware || canPrepareNextProof)) ||
        (kAppFormFactor == AppFormFactor.mobile &&
            status.phase == kIronwoodMigrationBroadcastScheduledPhase &&
            ((usesNativeOutbox &&
                    status.signedChildPcztCount == 0 &&
                    _hasScheduledBroadcast(status)) ||
                (!usesNativeOutbox && _hasDueScheduledBroadcast(status)) ||
                (hasChildProofBatchPermit && canPrepareNextProof))) ||
        (kAppFormFactor == AppFormFactor.desktop &&
            {
              kIronwoodMigrationBroadcastScheduledPhase,
              kIronwoodMigrationBroadcastingPhase,
              kIronwoodMigrationWaitingConfirmationsPhase,
            }.contains(status.phase));
    if (!phaseCanAdvance) return false;
    if (force) return true;
    final progressKey = _advanceProgressKey(status);
    final lastProgressKey = _lastAdvanceProgressKeys[accountUuid];
    if (lastProgressKey != null && lastProgressKey != progressKey) return true;
    final lastAdvance = _lastAdvanceAt[accountUuid];
    return lastAdvance == null ||
        DateTime.now().difference(lastAdvance) >= _migrationAdvanceInterval;
  }

  bool _hasScheduledBroadcast(rust_sync.MigrationStatus status) {
    return status.scheduledBroadcasts.any(
      (broadcast) =>
          broadcast.status.toLowerCase() == 'scheduled' &&
          broadcast.scheduledHeight > 0,
    );
  }

  bool _hasDueScheduledBroadcast(rust_sync.MigrationStatus status) {
    final currentHeight = _observedBroadcastHeight();
    if (currentHeight <= 0) return false;

    return status.scheduledBroadcasts.any(
      (broadcast) =>
          broadcast.status.toLowerCase() == 'scheduled' &&
          broadcast.scheduledHeight > 0 &&
          broadcast.scheduledHeight <= currentHeight,
    );
  }

  bool _canPrepareNextProof(rust_sync.MigrationStatus status) {
    final nextActionHeight = status.nextActionHeight;
    if (status.signedChildPcztCount <= 0 ||
        status.proofReady != true ||
        nextActionHeight == null) {
      return false;
    }
    final currentHeight = _safelyObservedProofHeight();
    return currentHeight > 0 && nextActionHeight <= currentHeight;
  }

  int _safelyObservedProofHeight() {
    final syncState = ref.read(syncProvider).value;
    if (syncState == null) return 0;
    return mobileIronwoodSafelyObservedHeight(
      scannedHeight: syncState.scannedHeight,
      chainTipHeight: syncState.chainTipHeight,
    );
  }

  int _observedBroadcastHeight() {
    final syncState = ref.read(syncProvider).value;
    if (syncState == null) return 0;
    return mobileIronwoodObservedBroadcastHeight(
      scannedHeight: syncState.scannedHeight,
      chainTipHeight: syncState.chainTipHeight,
    );
  }

  Future<void> _advance(
    String accountUuid, {
    rust_sync.MigrationStatus? status,
  }) {
    final existing = _advanceOperations[accountUuid];
    if (existing != null) return existing;
    final reservesOpenOverdueAllowance =
        kAppFormFactor == AppFormFactor.desktop &&
        status != null &&
        _desktopOpenFallbackGate.isOpenOverdue(status);
    if (kAppFormFactor == AppFormFactor.desktop &&
        (status == null ||
            !_desktopOpenFallbackGate.tryAcquireForAdvance(status))) {
      // `_advance` is also called by manual retry, which bypasses
      // `_shouldAdvance`. Keep the ZIP 318 on-open allowance centralized at
      // this last coordinator boundary so no UI or polling entry point can
      // submit a second overdue transfer in the same foreground epoch.
      return Future.value();
    }
    final operation = () async {
      try {
        final result = await _runAdvance(accountUuid, status: status);
        if (reservesOpenOverdueAllowance) {
          // The authoritative open tip can be ahead of Rust's locally synced
          // tip. In that case Rust correctly performs no broadcast, so return
          // the reservation and let a later refresh retry after sync catches
          // up.
          _desktopOpenFallbackGate.completeAdvance(status, result);
        }
      } catch (_) {
        if (reservesOpenOverdueAllowance) {
          // The one-due Rust endpoint converts every failure after network
          // acceptance into a successful result carrying the accepted txid.
          // An exception here therefore happened before a transfer was
          // accepted and the wallet-global reservation can be retried.
          _desktopOpenFallbackGate.failAdvance(status);
        }
        rethrow;
      }
    }();
    _advanceOperations[accountUuid] = operation;
    return operation.whenComplete(() {
      if (identical(_advanceOperations[accountUuid], operation)) {
        _advanceOperations.remove(accountUuid);
      }
    });
  }

  Future<rust_sync.IronwoodMigrationResult> _runAdvance(
    String accountUuid, {
    rust_sync.MigrationStatus? status,
  }) async {
    final consumesProofBatchPermit =
        kAppFormFactor == AppFormFactor.mobile &&
        status != null &&
        state.childProofBatchPermits.contains(accountUuid) &&
        _isChildProofBatchAdvance(status);
    if (consumesProofBatchPermit) {
      state = state.copyWith(
        childProofBatchPermits: {...state.childProofBatchPermits}
          ..remove(accountUuid),
      );
    }
    state = state.copyWith(
      advancingAccounts: {...state.advancingAccounts, accountUuid},
    );
    _lastAdvanceAt[accountUuid] = DateTime.now();
    if (status != null) {
      _lastAdvanceProgressKeys[accountUuid] = _advanceProgressKey(status);
    }
    try {
      return await ref
          .read(ironwoodMigrationServiceProvider)
          .continueSoftwarePrivateMigration(accountUuid: accountUuid);
    } finally {
      if (ref.mounted) {
        state = state.copyWith(
          advancingAccounts: {...state.advancingAccounts}..remove(accountUuid),
        );
      }
    }
  }

  bool _isChildProofBatchAdvance(rust_sync.MigrationStatus status) {
    if (status.phase == kIronwoodMigrationReadyToMigratePhase) {
      return status.signedChildPcztCount <= 0 || _canPrepareNextProof(status);
    }
    return status.phase == kIronwoodMigrationBroadcastScheduledPhase &&
        _canPrepareNextProof(status);
  }

  String _advanceProgressKey(rust_sync.MigrationStatus status) {
    return [
      status.activeRunId,
      status.phase,
      status.pendingSplitStageCount,
      status.denominationConfirmationCount,
      status.denominationSplitCompletedCount,
      status.broadcastedTxCount,
      status.confirmedTxCount,
      status.signedChildPcztCount,
      for (final part in status.parts) ...[
        part.partIndex,
        part.state.name,
        part.confirmationCount,
      ],
    ].join(':');
  }

  void _invalidateMigrationProviders(String? activeAccountUuid) {
    if (activeAccountUuid != null) {
      final network = ref.read(rpcEndpointFailoverProvider).current.networkName;
      ref.invalidate(
        ironwoodMigrationStatusProvider(
          IronwoodMigrationStatusRequest(
            network: network,
            accountUuid: activeAccountUuid,
          ),
        ),
      );
    }
    ref.invalidate(ironwoodPostMigrationStateProvider);
    ref.invalidate(ironwoodMigrationRouteCtaProvider);
    ref.invalidate(ironwoodHomeMigrationCtaProvider);
  }
}

final ironwoodMigrationCoordinatorProvider =
    NotifierProvider<
      IronwoodMigrationCoordinator,
      IronwoodMigrationCoordinatorState
    >(IronwoodMigrationCoordinator.new);

class IronwoodMigrationCoordinatorHost extends ConsumerStatefulWidget {
  const IronwoodMigrationCoordinatorHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<IronwoodMigrationCoordinatorHost> createState() =>
      _IronwoodMigrationCoordinatorHostState();
}

class _IronwoodMigrationCoordinatorHostState
    extends ConsumerState<IronwoodMigrationCoordinatorHost> {
  AppLifecycleListener? _lifecycleListener;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .resumeBackgroundPreparations(),
    );
    unawaited(
      ref.read(ironwoodMigrationCoordinatorProvider.notifier).refreshNow(),
    );
    _pollTimer = Timer.periodic(_migrationStatusPollInterval, (_) {
      unawaited(
        ref.read(ironwoodMigrationCoordinatorProvider.notifier).refreshNow(),
      );
    });
    _lifecycleListener = AppLifecycleListener(
      onResume: () => ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .setForeground(true),
      onHide: () => ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .setForeground(false),
      onPause: () => ref
          .read(ironwoodMigrationCoordinatorProvider.notifier)
          .setForeground(false),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Narrowed to the completion timestamp on purpose. `SyncState` has no
    // `operator ==` and a 20ms timer rewrites it for the whole of a sync
    // (`sync_provider.dart` `_displayProgressTimer`), so an unnarrowed listen
    // fires up to 50x/second. Every fire set `_refreshPending`, which kept
    // `_drainRefreshes()` from ever draining: `_refreshOnce()` then ran
    // back-to-back for the entire sync, and it is not cheap — a full
    // `get_wallet_summary`, a migration-status read on its own connection, and
    // a Keychain read, per account, while the scanner was writing to the same
    // SQLite. The 5s `_pollTimer` above already covers periodic refresh, so
    // the unconditional `refreshNow()` here was redundant as well as hot.
    ref.listen(
      syncProvider.select((sync) => sync.asData?.value.lastSyncCompletedAt),
      (previousCompletedAt, nextCompletedAt) {
        if (nextCompletedAt == null || nextCompletedAt == previousCompletedAt) {
          return;
        }
        final coordinator = ref.read(
          ironwoodMigrationCoordinatorProvider.notifier,
        );
        unawaited(coordinator.refreshNow());
        unawaited(coordinator.resumeBackgroundPreparations());
      },
    );
    ref.watch(ironwoodMigrationCoordinatorProvider);
    return widget.child;
  }
}
