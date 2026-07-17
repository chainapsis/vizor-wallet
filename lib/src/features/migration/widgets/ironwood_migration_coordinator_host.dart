import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../providers/ironwood_migration_announcement_provider.dart';
import '../services/ironwood_migration_service.dart';

/// Keeps an active software migration progressing for the lifetime of the app,
/// independently from whichever route is currently visible.
class IronwoodMigrationCoordinatorHost extends ConsumerStatefulWidget {
  const IronwoodMigrationCoordinatorHost({
    required this.child,
    this.statusRefreshInterval = const Duration(seconds: 5),
    this.actionRetryInterval = const Duration(seconds: 30),
    super.key,
  });

  final Widget child;
  final Duration statusRefreshInterval;
  final Duration actionRetryInterval;

  @override
  ConsumerState<IronwoodMigrationCoordinatorHost> createState() =>
      _IronwoodMigrationCoordinatorHostState();
}

class _IronwoodMigrationCoordinatorHostState
    extends ConsumerState<IronwoodMigrationCoordinatorHost> {
  AppLifecycleListener? _lifecycleListener;
  Timer? _pollTimer;
  IronwoodHomeMigrationCtaState? _latestCta;
  bool _isForeground = true;
  bool _isAdvancing = false;
  String? _lastAdvanceKey;
  DateTime? _lastAdvanceAt;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onHide: () {
        _isForeground = false;
        _pollTimer?.cancel();
        _pollTimer = null;
      },
      onResume: () {
        _isForeground = true;
        _refreshStatus();
      },
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
    final ctaAsync = ref.watch(ironwoodMigrationRouteCtaProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ctaAsync.when(
        data: _handleCta,
        error: (error, _) {
          debugPrint(
            '[ironwood-migration-coordinator] status lookup failed: $error',
          );
          _schedule(widget.statusRefreshInterval);
        },
        loading: () {},
      );
    });
    ref.listen(appSecurityProvider, (_, next) {
      if (next.isUnlocked) {
        _refreshStatus();
      } else {
        _pollTimer?.cancel();
        _pollTimer = null;
      }
    });
    return widget.child;
  }

  void _handleCta(IronwoodHomeMigrationCtaState cta) {
    _latestCta = cta;
    _pollTimer?.cancel();
    _pollTimer = null;

    final status = cta.status;
    if (!_isForeground ||
        cta.mode != IronwoodHomeMigrationCtaMode.resume ||
        cta.accountUuid == null ||
        status == null ||
        status.activeRunId == null ||
        _isTerminal(status.phase)) {
      return;
    }

    if (_shouldAutomaticallyContinue(status)) {
      final scheduledDelay = ironwoodMigrationScheduledAdvanceDelay(status);
      if (scheduledDelay > Duration.zero) {
        _schedule(scheduledDelay);
        return;
      }
      final delay = _remainingActionRetryDelay(status);
      if (delay == Duration.zero) {
        unawaited(_advance(cta));
      } else {
        _schedule(delay);
      }
      return;
    }

    _schedule(widget.statusRefreshInterval);
  }

  Future<void> _advance(IronwoodHomeMigrationCtaState cta) async {
    if (_isAdvancing || !_isForeground) return;
    if (!ref.read(appSecurityProvider).isUnlocked) return;

    _isAdvancing = true;
    try {
      final accountUuid = cta.accountUuid;
      final status = cta.status;
      if (accountUuid == null || status == null) return;

      final accountState = await ref.read(accountProvider.future);
      if (!mounted ||
          accountState.activeAccountUuid != accountUuid ||
          (accountState.activeAccount?.isHardware ?? false)) {
        return;
      }

      _lastAdvanceKey = _advanceKey(status);
      _lastAdvanceAt = DateTime.now();
      await ref
          .read(ironwoodMigrationServiceProvider)
          .continueSoftwarePrivateMigration(accountUuid: accountUuid);
    } catch (error) {
      debugPrint(
        '[ironwood-migration-coordinator] automatic continuation failed: '
        '$error',
      );
    } finally {
      _lastAdvanceAt = DateTime.now();
      _isAdvancing = false;
      if (mounted) _refreshStatus();
    }
  }

  void _refreshStatus() {
    if (!mounted || !_isForeground) return;
    final cta = _latestCta;
    final network = cta?.network;
    final accountUuid = cta?.accountUuid;
    if (network != null && accountUuid != null) {
      ref.invalidate(
        ironwoodMigrationStatusProvider(
          IronwoodMigrationStatusRequest(
            network: network,
            accountUuid: accountUuid,
          ),
        ),
      );
    }
    ref.invalidate(ironwoodMigrationRouteCtaProvider);
    ref.invalidate(ironwoodHomeMigrationCtaProvider);
    ref.invalidate(ironwoodPostMigrationStateProvider);
  }

  void _schedule(Duration delay) {
    if (!mounted || !_isForeground) return;
    _pollTimer?.cancel();
    _pollTimer = Timer(delay, _refreshStatus);
  }

  Duration _remainingActionRetryDelay(rust_sync.MigrationStatus status) {
    final lastAt = _lastAdvanceAt;
    if (_lastAdvanceKey != _advanceKey(status) || lastAt == null) {
      return Duration.zero;
    }
    final elapsed = DateTime.now().difference(lastAt);
    if (elapsed >= widget.actionRetryInterval) return Duration.zero;
    return widget.actionRetryInterval - elapsed;
  }
}

Duration ironwoodMigrationScheduledAdvanceDelay(
  rust_sync.MigrationStatus status, {
  DateTime? now,
}) {
  if (status.phase != kIronwoodMigrationBroadcastScheduledPhase) {
    return Duration.zero;
  }

  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  int? nextScheduledAtMs;
  for (final broadcast in status.scheduledBroadcasts) {
    if (broadcast.status != 'scheduled') continue;
    if (broadcast.scheduledAtMs <= nowMs) return Duration.zero;
    if (nextScheduledAtMs == null ||
        broadcast.scheduledAtMs < nextScheduledAtMs) {
      nextScheduledAtMs = broadcast.scheduledAtMs;
    }
  }

  if (nextScheduledAtMs == null) return Duration.zero;
  return Duration(milliseconds: nextScheduledAtMs - nowMs);
}

bool _shouldAutomaticallyContinue(rust_sync.MigrationStatus status) {
  return (status.phase == kIronwoodMigrationWaitingDenomConfirmationsPhase &&
          status.pendingSplitStageCount > 0) ||
      status.phase == kIronwoodMigrationReadyToMigratePhase ||
      status.phase == kIronwoodMigrationBroadcastScheduledPhase;
}

bool _isTerminal(String phase) {
  return phase == kIronwoodMigrationCompletePhase ||
      phase == kIronwoodMigrationFailedTerminalPhase ||
      phase == kIronwoodMigrationAbandonedPhase;
}

String _advanceKey(rust_sync.MigrationStatus status) {
  return '${status.activeRunId}|${status.phase}|'
      '${status.pendingSplitStageCount}|${status.broadcastedTxCount}|'
      '${status.confirmedTxCount}';
}
