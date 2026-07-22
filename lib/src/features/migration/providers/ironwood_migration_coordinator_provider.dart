import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../core/layout/app_form_factor.dart';
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
  });

  final Map<String, rust_sync.MigrationStatus> statuses;
  final Map<String, String> errors;
  final Set<String> advancingAccounts;

  IronwoodMigrationCoordinatorState copyWith({
    Map<String, rust_sync.MigrationStatus>? statuses,
    Map<String, String>? errors,
    Set<String>? advancingAccounts,
  }) {
    return IronwoodMigrationCoordinatorState(
      statuses: statuses ?? this.statuses,
      errors: errors ?? this.errors,
      advancingAccounts: advancingAccounts ?? this.advancingAccounts,
    );
  }
}

class IronwoodMigrationCoordinator
    extends Notifier<IronwoodMigrationCoordinatorState> {
  bool _refreshing = false;
  bool _refreshPending = false;
  bool _forceAdvancePending = false;
  bool _foreground = true;
  final Map<String, DateTime> _lastAdvanceAt = {};
  final Map<String, String> _lastAdvanceProgressKeys = {};
  final Map<String, Future<void>> _advanceOperations = {};

  @override
  IronwoodMigrationCoordinatorState build() {
    ref.listen(accountProvider, (_, _) => unawaited(refreshNow()));
    ref.listen(appSecurityProvider, (_, _) => unawaited(refreshNow()));
    ref.listen(rpcEndpointFailoverProvider, (_, _) => unawaited(refreshNow()));
    return const IronwoodMigrationCoordinatorState();
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (foreground) {
      unawaited(
        refreshNow(forceAdvance: kAppFormFactor == AppFormFactor.desktop),
      );
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
    await refreshNow(forceAdvance: true);
  }

  Future<void> retry(String accountUuid) async {
    try {
      final inFlight = _advanceOperations[accountUuid];
      if (inFlight != null) {
        try {
          await inFlight;
        } catch (_) {
          // A manual retry must still run after the automatic attempt fails.
        }
      }
      await _advance(accountUuid);
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

  Future<void> refreshNow({bool forceAdvance = false}) async {
    if (!ref.mounted) return;
    if (!_foreground) return;
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
    final phaseCanAdvance =
        (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
            status.pendingSplitStageCount > 0) ||
        (!isHardware &&
            status.phase == kIronwoodMigrationReadyToMigratePhase) ||
        (kAppFormFactor == AppFormFactor.mobile &&
            status.phase == kIronwoodMigrationBroadcastScheduledPhase &&
            ((usesNativeOutbox && _hasScheduledBroadcast(status)) ||
                (!usesNativeOutbox && _hasDueScheduledBroadcast(status)) ||
                _canPrepareNextProof(status))) ||
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
      final syncedToTip = next.value?.isSyncedToTip ?? false;
      unawaited(
        ref
            .read(ironwoodMigrationCoordinatorProvider.notifier)
            .refreshNow(forceAdvance: syncedToTip),
      );
    });
    ref.watch(ironwoodMigrationCoordinatorProvider);
    return widget.child;
  }
}
