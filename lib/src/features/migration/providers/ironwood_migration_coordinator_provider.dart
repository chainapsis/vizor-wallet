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
import '../services/ironwood_migration_service.dart';
import 'ironwood_migration_announcement_provider.dart';

const _migrationStatusPollInterval = Duration(seconds: 5);
const _migrationAdvanceInterval = Duration(
  seconds:
      String.fromEnvironment('ZCASH_DEFAULT_NETWORK') == 'regtest' ||
          kZcashFastTestnetMigration
      ? 1
      : 30,
);

class IronwoodMigrationCoordinatorState {
  const IronwoodMigrationCoordinatorState({
    this.statuses = const {},
    this.errors = const {},
    this.advancingAccounts = const {},
    this.foregroundProgressPermits = const {},
    this.childProofBatchPermits = const {},
  });

  final Map<String, rust_sync.MigrationStatus> statuses;
  final Map<String, String> errors;
  final Set<String> advancingAccounts;

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
    Set<String>? foregroundProgressPermits,
    Set<String>? childProofBatchPermits,
  }) {
    return IronwoodMigrationCoordinatorState(
      statuses: statuses ?? this.statuses,
      errors: errors ?? this.errors,
      advancingAccounts: advancingAccounts ?? this.advancingAccounts,
      foregroundProgressPermits:
          foregroundProgressPermits ?? this.foregroundProgressPermits,
      childProofBatchPermits:
          childProofBatchPermits ?? this.childProofBatchPermits,
    );
  }
}

class IronwoodMigrationCoordinator
    extends Notifier<IronwoodMigrationCoordinatorState> {
  bool _refreshing = false;
  bool _refreshPending = false;
  bool _forceAdvancePending = false;
  bool _foreground = true;
  bool _hasObservedInitialAccountList = false;
  Future<void>? _backgroundPreparationRecovery;
  final Map<String, DateTime> _lastAdvanceAt = {};
  final Map<String, String> _lastAdvanceProgressKeys = {};
  final Map<String, Future<void>> _advanceOperations = {};

  @override
  IronwoodMigrationCoordinatorState build() {
    ref.listen(accountProvider, (_, next) {
      final hasAccounts = next.value?.accounts.isNotEmpty ?? false;
      if (!_hasObservedInitialAccountList && hasAccounts) {
        _hasObservedInitialAccountList = true;
        unawaited(refreshNow());
      } else {
        unawaited(refreshNow());
      }
    });
    ref.listen(appSecurityProvider, (previous, next) {
      if (previous?.requiresUnlock == true && !next.requiresUnlock) {
        unawaited(refreshNow());
      } else {
        unawaited(refreshNow());
      }
    });
    ref.listen(rpcEndpointFailoverProvider, (_, _) => unawaited(refreshNow()));
    return const IronwoodMigrationCoordinatorState();
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (foreground) {
      unawaited(
        refreshNow(forceAdvance: kAppFormFactor == AppFormFactor.desktop),
      );
    } else if (kAppFormFactor == AppFormFactor.mobile &&
        (state.foregroundProgressPermits.isNotEmpty ||
            state.childProofBatchPermits.isNotEmpty)) {
      state = state.copyWith(
        foregroundProgressPermits: const {},
        childProofBatchPermits: const {},
      );
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
    if (accountState == null || accountState.accounts.isEmpty) return;
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

  Future<void> retry(String accountUuid) async {
    final status = state.statuses[accountUuid];
    if (status != null && _isChildProofBatchAdvance(status)) {
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
      await _advance(accountUuid, status: status);
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

  Future<void> refreshNow({bool forceAdvance = false}) async {
    if (!ref.mounted) return;
    if (!canRunAppProcessWork(isInForeground: _foreground)) return;
    if (ref.read(appSecurityProvider).requiresUnlock) return;

    if (_refreshing) {
      _refreshPending = true;
      _forceAdvancePending = _forceAdvancePending || forceAdvance;
      return;
    }

    final accountState = ref.read(accountProvider).value;
    if (accountState == null || accountState.accounts.isEmpty) return;

    _refreshing = true;
    try {
      final service = ref.read(ironwoodMigrationServiceProvider);
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      final nextStatuses = Map<String, rust_sync.MigrationStatus>.from(
        state.statuses,
      );
      final nextErrors = Map<String, String>.from(state.errors);

      for (final account in accountState.accounts) {
        try {
          var status = await service.status(
            network: endpoint.networkName,
            accountUuid: account.uuid,
          );
          if (!ref.mounted) return;
          nextStatuses[account.uuid] = status;
          nextErrors.remove(account.uuid);

          if (_shouldAdvance(
            status,
            isHardware: account.isHardware,
            usesNativeOutbox: service.supportsBackgroundMigrationRetry,
            force: forceAdvance,
            accountUuid: account.uuid,
          )) {
            await _advance(account.uuid, status: status);
            if (!ref.mounted) return;
            status = await service.status(
              network: endpoint.networkName,
              accountUuid: account.uuid,
            );
            if (!ref.mounted) return;
            nextStatuses[account.uuid] = status;
          }
        } catch (error) {
          nextErrors[account.uuid] = error.toString();
          log(
            'Ironwood migration coordinator failed for ${account.uuid}: $error',
          );
        }
      }

      if (!ref.mounted) return;
      state = state.copyWith(statuses: nextStatuses, errors: nextErrors);
      _invalidateMigrationProviders(accountState.activeAccountUuid);
    } finally {
      _refreshing = false;
      if (ref.mounted && _refreshPending) {
        final pendingForceAdvance = _forceAdvancePending;
        _refreshPending = false;
        _forceAdvancePending = false;
        unawaited(refreshNow(forceAdvance: pendingForceAdvance));
      }
    }
  }

  bool _shouldAdvance(
    rust_sync.MigrationStatus status, {
    required bool isHardware,
    required bool usesNativeOutbox,
    required bool force,
    required String accountUuid,
  }) {
    if (status.activeRunId == null) return false;
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
    final currentHeight = _safelyObservedHeight();
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
    if (status.signedChildPcztCount <= 0 || nextActionHeight == null) {
      return false;
    }
    final currentHeight = _safelyObservedHeight();
    return currentHeight > 0 && nextActionHeight <= currentHeight;
  }

  int _safelyObservedHeight() {
    final syncState = ref.read(syncProvider).value;
    if (syncState == null) return 0;

    final scannedHeight = syncState.scannedHeight;
    final chainTipHeight = syncState.chainTipHeight;
    final currentHeight = scannedHeight > 0 && chainTipHeight > 0
        ? (scannedHeight < chainTipHeight ? scannedHeight : chainTipHeight)
        : (scannedHeight > chainTipHeight ? scannedHeight : chainTipHeight);
    return currentHeight;
  }

  Future<void> _advance(
    String accountUuid, {
    rust_sync.MigrationStatus? status,
  }) {
    final existing = _advanceOperations[accountUuid];
    if (existing != null) return existing;
    final operation = _runAdvance(accountUuid, status: status);
    _advanceOperations[accountUuid] = operation;
    return operation.whenComplete(() {
      if (identical(_advanceOperations[accountUuid], operation)) {
        _advanceOperations.remove(accountUuid);
      }
    });
  }

  Future<void> _runAdvance(
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
      await ref
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
    ref.listen(syncProvider, (_, next) {
      unawaited(
        ref.read(ironwoodMigrationCoordinatorProvider.notifier).refreshNow(),
      );
    });
    ref.watch(ironwoodMigrationCoordinatorProvider);
    return widget.child;
  }
}
