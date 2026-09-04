import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_security_provider.dart';
import 'payment_link_claim_lifecycle_registry_provider.dart';
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
  final Map<String, Future<void>> _retentions = {};
  Future<List<PaymentLinkReceivedRecord>>? _recoveryInFlight;
  Timer? _retryTimer;
  bool _enabled = false;
  bool _resetQuiesced = false;
  bool _disposed = false;

  @visibleForTesting
  int get activeSubmissionCount => _submissions.length;

  bool isSubmitting(String address) => _submissions.containsKey(address);

  Future<PaymentLinkClaimResult> submit(PaymentLinkClaimSession session) {
    if (_resetQuiesced) {
      return Future.error(
        StateError(
          'Gift Card claims are paused while the wallet is being changed.',
        ),
      );
    }
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

  /// A retention writes the received store, so a reset drains it; one started
  /// after quiesce is skipped so it cannot resurrect a Card in the wiped wallet.
  Future<void> trackRetention(String address, Future<void> Function() run) {
    if (_resetQuiesced) {
      debugPrint(
        '[zcash] PaymentLinkClaim: skipped retaining a claim during reset',
      );
      return Future<void>.value();
    }
    late final Future<void> tracked;
    tracked = Future<void>.sync(run).whenComplete(() {
      if (identical(_retentions[address], tracked)) {
        _retentions.remove(address);
      }
    });
    _retentions[address] = tracked;
    return tracked;
  }

  Future<List<PaymentLinkReceivedRecord>> refresh() {
    if (_resetQuiesced) return Future.value(const []);
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
    if (_disposed || _resetQuiesced) return;
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
    _resetQuiesced = true;
    pause();
  }

  Future<void> quiesceAndDrain() async {
    _resetQuiesced = true;
    pause();
    while (_submissions.isNotEmpty ||
        _retentions.isNotEmpty ||
        _recoveryInFlight != null) {
      final pending = <Future<Object?>>[
        ..._submissions.values,
        ..._retentions.values,
        ?_recoveryInFlight,
      ];
      await Future.wait(pending.map(_ignoreOutcome));
    }
  }

  void resumeAfterReset() {
    if (_disposed) return;
    _resetQuiesced = false;
    if (!_ref.read(appSecurityProvider).requiresUnlock) resume();
  }

  Future<void> _ignoreOutcome(Future<Object?> operation) async {
    try {
      await operation;
    } catch (_) {
      // A failed operation is settled and no longer blocks destructive reset.
    }
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
  final lifecycleRegistry = ref.read(paymentLinkClaimLifecycleRegistryProvider);
  lifecycleRegistry.register(
    owner: coordinator,
    quiesceAndDrain: coordinator.quiesceAndDrain,
    resume: coordinator.resumeAfterReset,
  );
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
    lifecycleRegistry.unregister(coordinator);
    lifecycleListener.dispose();
    coordinator.dispose();
  });
  return coordinator;
});
