import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_secure_store.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../models/vizor_payment_link.dart';
import 'payment_link_claim_lifecycle_registry_provider.dart';
import '../services/payment_link_received_store.dart';
import '../services/payment_link_service.dart';

typedef PaymentLinkClaimSubmitter =
    Future<PaymentLinkClaimResult> Function(PaymentLinkClaimSession session);

typedef PaymentLinkClaimRecoveryRunner =
    Future<List<PaymentLinkReceivedRecord>> Function();

typedef PaymentLinkSetupClaimPreparer =
    Future<PaymentLinkClaimSession> Function(
      VizorPaymentLink link, {
      required String destinationAccountUuid,
    });

typedef PaymentLinkSetupClaimPreparation =
    Future<PaymentLinkClaimSession> Function();

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
        if (!records.any((record) => record.needsClaimRecovery)) {
          return records;
        }
        return operations.inspectReceivedLinkClaims(records);
      };
    });

@visibleForTesting
final paymentLinkSetupClaimPreparerProvider =
    Provider<PaymentLinkSetupClaimPreparer>((ref) {
      final operations = ref.watch(paymentLinkOperationsProvider);
      return (link, {required destinationAccountUuid}) async {
        final inspection = await operations.inspectClaim(
          link,
          allowLongSync: true,
        );
        try {
          return await operations.bindClaimDestination(
            inspection,
            destinationAccountUuid: destinationAccountUuid,
          );
        } catch (error, stackTrace) {
          try {
            await operations.discardClaimInspection(inspection);
          } catch (_) {
            // A saved Card owns the wallet; retain the preparation failure.
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
      };
    });

@visibleForTesting
final paymentLinkClaimRecoveryRetryDelayProvider = Provider<Duration>((ref) {
  return const Duration(seconds: 10);
});

/// Owns claim work whose lifetime must not depend on a Gift Card screen.
///
/// Different addresses submit independently. Repeated submission of the same
/// address joins the existing future. Retained receiving claims are reconciled,
/// and setup Cards that become ready are submitted into their saved account, on
/// app start, unlock, resume, and a bounded foreground timer.
class PaymentLinkClaimCoordinator {
  PaymentLinkClaimCoordinator(this._ref);

  final Ref _ref;
  final Map<String, _AccountClaimOperation<PaymentLinkClaimResult>>
  _submissions = {};
  final Map<String, _AccountClaimOperation<PaymentLinkClaimSession>>
  _setupPreparations = {};
  final Map<String, _AccountClaimOperation<void>> _setupHandoffs = {};
  final Set<Future<void>> _retentions = {};
  Future<List<PaymentLinkReceivedRecord>>? _recoveryInFlight;
  Timer? _retryTimer;
  bool _enabled = false;
  bool _resetQuiesced = false;
  bool _disposed = false;

  @visibleForTesting
  int get activeSubmissionCount => _submissions.length;

  @visibleForTesting
  int get activeSetupPreparationCount => _setupPreparations.length;

  bool isSubmitting(String address) => _submissions.containsKey(address);

  /// Shares the first setup-account preparation for a Card between its screen
  /// and background recovery. Submission already has address-level joining,
  /// but it starts too late to prevent two scans from opening the same claim
  /// wallet after an app lifecycle resume.
  Future<PaymentLinkClaimSession> prepareSetupClaim(
    VizorPaymentLink link, {
    required String destinationAccountUuid,
    required PaymentLinkSetupClaimPreparation prepare,
  }) {
    if (_resetQuiesced) {
      return Future.error(
        StateError(
          'Gift Card claims are paused while the wallet is being changed.',
        ),
      );
    }
    final claimId = link.address;
    if (isSubmitting(claimId)) {
      return Future.error(const PaymentLinkClaimInFlightException());
    }
    final existing = _setupPreparations[claimId];
    if (existing != null) {
      if (existing.destinationAccountUuid != destinationAccountUuid) {
        return Future.error(
          const PaymentLinkClaimDestinationChangedException(),
        );
      }
      return existing.future;
    }

    late final Future<PaymentLinkClaimSession> tracked;
    tracked = Future<PaymentLinkClaimSession>.sync(prepare)
        .then((session) {
          if (session.destinationAccountUuid != destinationAccountUuid ||
              !session.link.hasSameCanonicalPayload(link)) {
            throw const PaymentLinkClaimDestinationChangedException();
          }
          return session;
        })
        .whenComplete(() {
          if (identical(_setupPreparations[claimId]?.future, tracked)) {
            _setupPreparations.remove(claimId);
          }
        });
    _setupPreparations[claimId] = _AccountClaimOperation(
      destinationAccountUuid: destinationAccountUuid,
      future: tracked,
    );
    return tracked;
  }

  /// Hands the inspected Card to work that outlives the onboarding screen.
  /// The caller can continue to Face ID/Home without awaiting this future.
  /// Binding uses the existing inspection; only later recovery scans again.
  Future<void> claimSetupCard(
    PaymentLinkClaimInspection inspection, {
    required String destinationAccountUuid,
  }) {
    final claimId = inspection.link.address;
    final existing = _setupHandoffs[claimId];
    if (existing != null) {
      if (existing.destinationAccountUuid != destinationAccountUuid) {
        return Future.error(
          const PaymentLinkClaimDestinationChangedException(),
        );
      }
      return existing.future;
    }
    late final Future<void> tracked;
    tracked =
        Future<void>.sync(
          () => _claimSetupCard(inspection, destinationAccountUuid),
        ).whenComplete(() {
          if (identical(_setupHandoffs[claimId]?.future, tracked)) {
            _setupHandoffs.remove(claimId);
          }
        });
    _setupHandoffs[claimId] = _AccountClaimOperation(
      destinationAccountUuid: destinationAccountUuid,
      future: tracked,
    );
    return tracked;
  }

  Future<void> _claimSetupCard(
    PaymentLinkClaimInspection inspection,
    String destinationAccountUuid,
  ) async {
    if (!_canRunRecovery) {
      throw StateError('The wallet is not ready to claim the Gift Card.');
    }
    final operations = _ref.read(paymentLinkOperationsProvider);
    final saved = await _ref
        .read(paymentLinkReceivedStoreProvider)
        .find(inspection.link.address);
    if (!_canRunRecovery) return;
    if (saved?.setupAccountUuid != destinationAccountUuid ||
        saved?.claimLink?.hasSameCanonicalPayload(inspection.link) != true) {
      throw const PaymentLinkClaimDestinationChangedException();
    }
    final session = await prepareSetupClaim(
      inspection.link,
      destinationAccountUuid: destinationAccountUuid,
      prepare: () => operations.bindClaimDestination(
        inspection,
        destinationAccountUuid: destinationAccountUuid,
      ),
    );
    if (!_canRunRecovery) return;
    await _submitOrRetainSetupClaim(session);
  }

  Future<void> _submitOrRetainSetupClaim(
    PaymentLinkClaimSession session,
  ) async {
    if (session.canClaim) {
      await submit(session);
    } else {
      await _ref
          .read(paymentLinkOperationsProvider)
          .retainPendingClaim(session);
    }
  }

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
    if (existing != null) {
      if (existing.destinationAccountUuid != session.destinationAccountUuid) {
        return Future.error(
          const PaymentLinkClaimDestinationChangedException(),
        );
      }
      return existing.future;
    }

    late final Future<PaymentLinkClaimResult> tracked;
    tracked =
        Future<PaymentLinkClaimResult>.sync(
          () => _ref.read(paymentLinkClaimSubmitterProvider)(session),
        ).whenComplete(() {
          if (identical(_submissions[claimId]?.future, tracked)) {
            _submissions.remove(claimId);
          }
          if (_enabled && !_disposed) _refreshInBackground();
        });
    _submissions[claimId] = _AccountClaimOperation(
      destinationAccountUuid: session.destinationAccountUuid,
      future: tracked,
    );
    return tracked;
  }

  /// A retention writes the received store, so a reset drains it; one started
  /// after quiesce is skipped so it cannot resurrect a Card in the wiped wallet.
  Future<void> trackRetention(
    Future<void> Function() run, {
    bool scheduleReadySetupRecovery = false,
  }) {
    if (_resetQuiesced) {
      debugPrint(
        '[zcash] PaymentLinkClaim: skipped retaining a claim during reset',
      );
      return Future<void>.value();
    }
    // Every retention is tracked on its own: retentions for one Card can
    // overlap, and a reset has to outlast the slowest of them.
    late final Future<void> tracked;
    tracked = Future<void>.sync(run).whenComplete(() {
      _retentions.remove(tracked);
      // A retained waiting session is fully bound and safe to reopen. Merely
      // saving the link is earlier than that and can overlap its first scan.
      if (scheduleReadySetupRecovery &&
          _enabled &&
          !_disposed &&
          !_resetQuiesced) {
        _scheduleRetry();
      }
    });
    _retentions.add(tracked);
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
        _setupPreparations.isNotEmpty ||
        _setupHandoffs.isNotEmpty ||
        _retentions.isNotEmpty ||
        _recoveryInFlight != null) {
      final pending = <Future<Object?>>[
        ..._submissions.values.map((submission) => submission.future),
        ..._setupPreparations.values.map((preparation) => preparation.future),
        ..._setupHandoffs.values.map((handoff) => handoff.future),
        ..._retentions,
        ?_recoveryInFlight,
      ];
      await Future.wait(pending.map(_ignoreOutcome));
    }
  }

  void resumeAfterReset() {
    if (_disposed) return;
    _resetQuiesced = false;
    final security = _ref.read(appSecurityProvider);
    if (security.isPasswordConfigured && security.isUnlocked) resume();
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
    if (!_canRunRecovery) {
      return const [];
    }

    var retry = true;
    try {
      final records = await _ref.read(paymentLinkClaimRecoveryRunnerProvider)();
      await _resumeReadySetupClaims(records);
      if (!_canRunRecovery) {
        retry = false;
        return records;
      }
      retry = records.any(
        (record) =>
            record.needsClaimRecovery || _shouldRetryReadySetupClaim(record),
      );
      return records;
    } finally {
      if (retry && _enabled && !_disposed) _scheduleRetry();
    }
  }

  Future<void> _resumeReadySetupClaims(
    List<PaymentLinkReceivedRecord> records,
  ) async {
    if (!records.any(_isReadySetupClaim) || !_canRunRecovery) return;
    // Security opens its session before unlock restores interrupted account
    // setup. Never submit a setup Card until that durable journal is cleared.
    // The same gate protects the password-commit -> journal-cleanup boundary.
    final store = AppSecureStore.instance;
    if (await store.readPlain(kPendingAccountMnemonicStorageKey) != null ||
        await store.readPlain(kGiftWalletSetupStartedStorageKey) != null) {
      return;
    }
    for (final record in records) {
      if (!_canRunRecovery) return;
      if (!_isReadySetupClaim(record)) continue;
      if (isSubmitting(record.address)) continue;
      if (_setupHandoffs.containsKey(record.address)) continue;

      final link = record.claimLink!;
      final destinationAccountUuid = record.setupAccountUuid!;
      final accounts = _ref.read(accountProvider).value?.accounts;
      if (accounts == null ||
          !accounts.any((account) => account.uuid == destinationAccountUuid)) {
        continue;
      }

      PaymentLinkClaimSession session;
      try {
        session = await prepareSetupClaim(
          link,
          destinationAccountUuid: destinationAccountUuid,
          prepare: () => _ref.read(paymentLinkSetupClaimPreparerProvider)(
            link,
            destinationAccountUuid: destinationAccountUuid,
          ),
        );
      } catch (error, stackTrace) {
        debugPrint(
          '[zcash] PaymentLinkClaim: automatic setup claim preparation failed '
          'type=${error.runtimeType}\n$stackTrace',
        );
        continue;
      }

      if (!_canRunRecovery) {
        return;
      }
      try {
        await _submitOrRetainSetupClaim(session);
      } catch (error, stackTrace) {
        debugPrint(
          '[zcash] PaymentLinkClaim: automatic setup claim submission failed '
          'type=${error.runtimeType}\n$stackTrace',
        );
      }
    }
  }

  bool get _canRunRecovery {
    if (_disposed || !_ref.mounted || !_enabled || _resetQuiesced) {
      return false;
    }
    final security = _ref.read(appSecurityProvider);
    return security.isPasswordConfigured && security.isUnlocked;
  }

  bool _isReadySetupClaim(PaymentLinkReceivedRecord record) =>
      record.status == PaymentLinkReceivedStatus.readyToClaim &&
      !record.archived &&
      record.claimLink != null &&
      record.setupAccountUuid != null &&
      (record.availability == PaymentLinkAvailability.unchecked ||
          record.availability == PaymentLinkAvailability.checking ||
          record.availability == PaymentLinkAvailability.available);

  bool _shouldRetryReadySetupClaim(PaymentLinkReceivedRecord record) {
    if (!_isReadySetupClaim(record)) return false;
    final accounts = _ref.read(accountProvider).value?.accounts;
    return accounts == null ||
        accounts.any((account) => account.uuid == record.setupAccountUuid);
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

class _AccountClaimOperation<T> {
  const _AccountClaimOperation({
    required this.destinationAccountUuid,
    required this.future,
  });

  final String destinationAccountUuid;
  final Future<T> future;
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
    final ready = next.isPasswordConfigured && next.isUnlocked;
    final wasReady =
        previous?.isPasswordConfigured == true && previous?.isUnlocked == true;
    if (!ready) {
      coordinator.pause();
    } else if (!wasReady) {
      coordinator.resume();
    }
  });
  final security = ref.read(appSecurityProvider);
  if (security.isPasswordConfigured && security.isUnlocked) {
    coordinator.resume();
  }
  // Unlock recovery may restore account metadata after the security state
  // changes. Wake claims when the receiving account becomes available.
  ref.listen(accountProvider, (previous, next) {
    final previousUuids = {
      for (final account in previous?.value?.accounts ?? const <AccountInfo>[])
        account.uuid,
    };
    if (next.value?.accounts.any(
          (account) => !previousUuids.contains(account.uuid),
        ) ==
        true) {
      coordinator.resume();
    }
  });

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
