import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_security_provider.dart';
import '../services/payment_link_received_store.dart';
import '../services/payment_link_service.dart';

typedef PaymentLinkClaimSubmitter =
    Future<PaymentLinkClaimResult> Function(PaymentLinkClaimSession session);

typedef PaymentLinkClaimRecoveryRunner =
    Future<List<PaymentLinkReceivedRecord>> Function();

@visibleForTesting
final paymentLinkClaimSubmitterProvider = Provider<PaymentLinkClaimSubmitter>((
  ref,
) {
  final operations = ref.watch(paymentLinkOperationsProvider);
  return operations.claimPreparedLink;
});

@visibleForTesting
final paymentLinkClaimRecoveryRunnerProvider =
    Provider<PaymentLinkClaimRecoveryRunner>((ref) {
      final operations = ref.watch(paymentLinkOperationsProvider);
      return () async {
        final records = await operations.loadReceivedLinkRecoveries();
        if (!records.any((record) => record.isClaimInFlight)) {
          return records;
        }
        return operations.inspectReceivedLinkClaims(records);
      };
    });

@visibleForTesting
final paymentLinkClaimRecoveryRetryDelayProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 10);
});

/// Owns claim work whose lifetime must not depend on a Gift Card screen.
///
/// Different addresses submit independently. Repeated submission of the same
/// address joins the existing future, while retained receiving claims are
/// reconciled on app start, unlock, resume, and a bounded foreground timer.
class PaymentLinkClaimCoordinator {
  PaymentLinkClaimCoordinator(this._ref);

  final Ref _ref;
  final Map<String, Future<PaymentLinkClaimResult>> _submissions = {};
  Future<List<PaymentLinkReceivedRecord>>? _recoveryInFlight;
  Timer? _retryTimer;
  bool _enabled = false;
  bool _disposed = false;

  @visibleForTesting
  int get activeSubmissionCount => _submissions.length;

  bool isSubmitting(String address) => _submissions.containsKey(address);

  Future<PaymentLinkClaimResult> submit(PaymentLinkClaimSession session) {
    final claimId = session.link.address;
    final existing = _submissions[claimId];
    if (existing != null) return existing;

    late final Future<PaymentLinkClaimResult> tracked;
    tracked =
        Future<PaymentLinkClaimResult>.sync(
          () => _ref.read(paymentLinkClaimSubmitterProvider)(session),
        ).whenComplete(() {
          if (identical(_submissions[claimId], tracked)) {
            _submissions.remove(claimId);
          }
          if (_enabled && !_disposed) _refreshInBackground();
        });
    _submissions[claimId] = tracked;
    return tracked;
  }

  Future<List<PaymentLinkReceivedRecord>> refresh() {
    final existing = _recoveryInFlight;
    if (existing != null) return existing;

    late final Future<List<PaymentLinkReceivedRecord>> tracked;
    tracked = _refreshOnce().whenComplete(() {
      if (identical(_recoveryInFlight, tracked)) {
        _recoveryInFlight = null;
      }
    });
    _recoveryInFlight = tracked;
    return tracked;
  }

  void resume() {
    if (_disposed) return;
    _enabled = true;
    _refreshInBackground();
  }

  void pause() {
    _enabled = false;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void dispose() {
    _disposed = true;
    pause();
  }

  Future<List<PaymentLinkReceivedRecord>> _refreshOnce() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!_enabled || _ref.read(appSecurityProvider).requiresUnlock) {
      return const [];
    }

    var retry = true;
    try {
      final records = await _ref.read(paymentLinkClaimRecoveryRunnerProvider)();
      retry = records.any((record) => record.isClaimInFlight);
      return records;
    } finally {
      if (retry && _enabled && !_disposed) _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    final configured = _ref.read(paymentLinkClaimRecoveryRetryDelayProvider);
    final delay = configured.isNegative ? Duration.zero : configured;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (_enabled && !_disposed) _refreshInBackground();
    });
  }

  void _refreshInBackground() {
    unawaited(
      refresh().catchError((Object error, StackTrace stackTrace) {
        debugPrint(
          '[zcash] PaymentLinkClaim: background recovery failed: '
          '$error\n$stackTrace',
        );
        return <PaymentLinkReceivedRecord>[];
      }),
    );
  }
}

final paymentLinkClaimCoordinatorProvider = Provider((ref) {
  final coordinator = PaymentLinkClaimCoordinator(ref);
  ref.listen<AppSecurityState>(appSecurityProvider, (previous, next) {
    if (next.requiresUnlock) {
      coordinator.pause();
    } else if (previous?.requiresUnlock == true) {
      coordinator.resume();
    }
  });
  if (!ref.read(appSecurityProvider).requiresUnlock) coordinator.resume();

  final lifecycleListener = AppLifecycleListener(
    onHide: coordinator.pause,
    onPause: coordinator.pause,
    onResume: coordinator.resume,
  );
  ref.onDispose(() {
    lifecycleListener.dispose();
    coordinator.dispose();
  });
  return coordinator;
});
