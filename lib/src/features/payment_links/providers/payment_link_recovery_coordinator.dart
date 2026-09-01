import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/sync_provider.dart';
import '../services/payment_link_received_store.dart';
import '../services/payment_link_recovery_store.dart';
import '../services/payment_link_service.dart';

final paymentLinkRecoveryCoordinatorProvider =
    NotifierProvider<PaymentLinkRecoveryCoordinator, int>(
      PaymentLinkRecoveryCoordinator.new,
    );

/// Reconciles durable Gift Card work at existing app lifecycle boundaries.
///
/// This coordinator does not poll and does not own a network loop. It only
/// runs after startup/unlock, foreground resume, account availability, or a
/// main-wallet sync/tip transition. Separate claim databases are still scanned
/// concurrently by [PaymentLinkOperations.inspectReceivedLinkClaims].
class PaymentLinkRecoveryCoordinator extends Notifier<int> {
  AppLifecycleListener? _lifecycleListener;
  Future<void>? _activeRecovery;
  bool _trailingRecoveryRequested = false;

  @override
  int build() {
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(recoverNow()),
    );
    ref.onDispose(() => _lifecycleListener?.dispose());

    ref.listen(appSecurityProvider, (previous, next) {
      if ((previous?.requiresUnlock ?? true) && !next.requiresUnlock) {
        unawaited(recoverNow());
      }
    });
    ref.listen(accountProvider, (previous, next) {
      final previousHasAccount = previous?.value?.accounts.isNotEmpty ?? false;
      final nextHasAccount = next.value?.accounts.isNotEmpty ?? false;
      if (!previousHasAccount && nextHasAccount) unawaited(recoverNow());
    });
    ref.listen(syncProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (after == null) return;
      final syncCompleted = before?.isSyncing == true && !after.isSyncing;
      final tipChanged =
          before != null && before.chainTipHeight != after.chainTipHeight;
      if (syncCompleted || tipChanged) unawaited(recoverNow());
    });

    Future<void>.microtask(recoverNow);
    return 0;
  }

  Future<void> recoverNow() {
    final active = _activeRecovery;
    if (active != null) {
      _trailingRecoveryRequested = true;
      return active;
    }
    final recovery = _drainRecoveries();
    _activeRecovery = recovery;
    return recovery.whenComplete(() {
      if (identical(_activeRecovery, recovery)) _activeRecovery = null;
    });
  }

  Future<void> _drainRecoveries() async {
    do {
      _trailingRecoveryRequested = false;
      await _recoverOnce();
    } while (ref.mounted && _trailingRecoveryRequested);
  }

  Future<void> _recoverOnce() async {
    if (ref.read(appSecurityProvider).requiresUnlock ||
        (ref.read(accountProvider).value?.accounts.isEmpty ?? true)) {
      return;
    }
    try {
      final operations = ref.read(paymentLinkOperationsProvider);
      final persisted = await Future.wait<Object>([
        operations.loadCreatedLinkRecoveries(),
        operations.loadReceivedLinkRecoveries(),
      ]);
      if (!ref.mounted || ref.read(appSecurityProvider).requiresUnlock) return;

      final created = (persisted[0] as List<PaymentLinkRecoveryRecord>)
          .where((record) => record.state == PaymentLinkRecoveryState.draft)
          .toList();
      final received = (persisted[1] as List<PaymentLinkReceivedRecord>).where(
        (record) =>
            record.status != PaymentLinkReceivedStatus.received &&
            record.destinationAccountUuid != null,
      );
      if (created.isEmpty && received.isEmpty) return;

      await Future.wait<void>([
        if (created.isNotEmpty)
          operations.inspectCreatedLinkFundings(created).then((_) {}),
        if (received.isNotEmpty)
          operations.inspectReceivedLinkClaims().then((_) {}),
      ]);
      if (ref.mounted) state++;
    } catch (error, stackTrace) {
      log(
        'PaymentLinkRecoveryCoordinator: recovery failed: '
        '$error\n$stackTrace',
      );
    }
  }
}
