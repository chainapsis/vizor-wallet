import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/privacy/sensitive_privacy_overlay.dart';
import '../../../core/storage/app_secure_store.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/voting/delegate_mode_host.dart';
import 'composite_delegate_mode_repository.dart';
import 'delegate_error_log.dart';
import 'delegate_key_store.dart';
import 'delegate_mode_models.dart';
import 'delegate_mode_repository.dart';
import 'proxy_delegation_providers.dart';

/// The delegate-mode data source: zcash_voting's delegate APIs (see
/// [CompositeDelegateModeRepository]). Nothing reads it unless the dormant
/// flag is on. Kept alive, like the delegator source, so its reads survive
/// navigation.
final delegateModeRepositoryProvider = Provider<DelegateModeRepository>((ref) {
  final clock = ref.watch(proxyClockProvider);
  return CompositeDelegateModeRepository(
    host: AppDelegateModeHost(ref),
    keys: ref.watch(delegateKeyStoreProvider),
    verifier: ref.watch(delegateVerifierClientProvider),
    clock: clock,
  );
});

/// Where the delegate key's secret is kept: app-level secure storage.
/// Tests replace it.
final delegateKeyStoreProvider = Provider<DelegateKeyStore>(
  (_) => SecureStoreDelegateKeyStore(AppSecureStore.instance),
);

/// Builds the controller that covers a shown key export when the app loses
/// the foreground; tests pass one that is always safe.
final delegatePrivacyControllerFactoryProvider =
    Provider<SensitivePrivacyOverlayController Function()>(
      (_) => SensitivePrivacyEnvironmentController.new,
    );

/// How often DG-8 refreshes the live count and ballot state.
const kDelegateDashboardRefresh = Duration(seconds: 30);

/// The delegate key on this device and its entry.
final delegateModeStatusProvider = FutureProvider.autoDispose<DelegateModeView>(
  (ref) {
    return ref.watch(delegateModeRepositoryProvider).status();
  },
  retry: proxyNoRetry,
);

/// Proxy rounds for the DG-8 dashboard.
final delegateRoundsProvider = FutureProvider.autoDispose<List<DelegateRound>>((
  ref,
) {
  return ref.watch(delegateModeRepositoryProvider).rounds();
}, retry: proxyNoRetry);

/// One round for DG-9.
final delegateRoundProvider = FutureProvider.autoDispose
    .family<DelegateRound, String>((ref, roundId) {
      return ref.watch(delegateModeRepositoryProvider).round(roundId);
    }, retry: proxyNoRetry);

/// How often a submitted ballot the round's list does not show yet is sent
/// again in the background.
const kDelegateBallotResendInterval = Duration(seconds: 15);

/// How long DG-9's processing view waits for the round's ballot list to
/// show a submitted ballot before it lets the delegate leave. An accepted
/// ballot lands in the next block (p99 3 s) and the list is read again every
/// [kDelegateBallotResendInterval], so this allows 8 reads.
const kDelegateBallotConfirmTimeout = Duration(minutes: 2);

/// The background resend of the stored ballot in one round, by round id,
/// from DG-8, DG-9 and restart discovery. Its state is the chain's
/// rejection of that ballot, which ends the resends, or null.
final delegateBallotResenderProvider =
    NotifierProvider.family<
      DelegateBallotResender,
      ApiBallotSubmitResult?,
      String
    >(DelegateBallotResender.new);

/// Sends the stored ballot of a round again, byte for byte and without
/// re-auth, until the round's ballot list shows it, the chain rejects it or
/// the round is no longer ACTIVE (zcash_voting's identical-retry rule). The
/// chain's answer ends it, never the device clock. While the entry is
/// suspended it posts nothing but keeps checking. Kept alive, so it keeps
/// going after the screen that started it closes.
class DelegateBallotResender extends Notifier<ApiBallotSubmitResult?> {
  /// Creates the resender for [roundId].
  DelegateBallotResender(this.roundId);

  /// The round whose ballot is resent.
  final String roundId;

  Timer? _timer;
  bool _sending = false;

  @override
  ApiBallotSubmitResult? build() {
    // A new data source starts over.
    ref.watch(delegateModeRepositoryProvider);
    ref.onDispose(_stop);
    return null;
  }

  /// Starts the resends, unless they already run or the chain rejected the
  /// ballot. Changes no state, so a screen may call it while it builds.
  void keepSending() {
    if (_timer != null || (state != null && !state!.blocksForNow)) return;
    _timer = Timer.periodic(kDelegateBallotResendInterval, (_) => _send());
  }

  /// Resends now rather than on the next tick, as discovery does after a
  /// restart.
  void sendNow() => unawaited(_send());

  /// Records the chain's [rejection] of the stored ballot. A final one
  /// stops the resends; one coordinators can lift
  /// ([DelegateBallotSubmitOutcome.blocksForNow]) keeps them checking.
  void rejected(ApiBallotSubmitResult rejection) {
    if (!rejection.blocksForNow) _stop();
    state = rejection;
  }

  /// One resend, skipped while the last one is still out.
  Future<void> _send() async {
    if (_sending) return;
    _sending = true;
    try {
      final result = await ref
          .read(delegateModeRepositoryProvider)
          .resendStoredBallot(roundId);
      if (!ref.mounted) return;
      switch (result) {
        case DelegateBallotResendDone():
          _stop();
        case DelegateBallotResendBlocked():
          // Checked again on the next tick, until the chain ends it.
          return;
        case DelegateBallotResendPosted(:final result) when result.rejected:
          rejected(result);
        case DelegateBallotResendPosted():
          // A lifted block no longer explains the wait.
          if (state != null) state = null;
      }
      _refresh();
    } catch (error) {
      // No verdict: the next tick sends the same bytes again.
      debugPrint(
        '[zcash] Delegate mode: a ballot resend got no verdict: '
        '${describeDelegateError(error)}',
      );
    } finally {
      _sending = false;
    }
  }

  /// Drops the cached round reads so DG-8 and DG-9 show the chain's state.
  void _refresh() {
    ref.invalidate(delegateRoundProvider(roundId));
    ref.invalidate(delegateRoundsProvider);
  }

  /// Ends the resends.
  void _stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// The wait before a stored-ballot discovery that failed is tried again;
/// tests shorten it.
final delegateBallotRestoreRetryDelayProvider = Provider(
  (ref) => kDelegateBallotResendInterval,
);

/// Resumes the background resends of this device's stored ballots after
/// the app starts, resumes or unlocks, so a ballot whose post got no
/// verdict keeps going without the delegate opening delegate mode. It
/// starts [DelegateBallotResender] for every running round holding one,
/// which sends the same bytes at once and then on its cadence until the
/// list shows them. Nothing runs
/// while the wallet is locked.
class DelegateBallotResendRestorer {
  /// Creates the restorer.
  DelegateBallotResendRestorer(this._ref);

  final Ref _ref;
  Future<void>? _inFlight;
  Timer? _retryTimer;

  /// Starts the resends of every stored ballot; joins a pass in flight.
  Future<void> restore() {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    _cancelRetry();
    if (_ref.read(appSecurityProvider).requiresUnlock) return Future.value();
    late final Future<void> pass;
    pass = _restore().whenComplete(() {
      if (identical(_inFlight, pass)) _inFlight = null;
    });
    return _inFlight = pass;
  }

  /// One discovery pass; a failure, or a round that could not be read,
  /// schedules another.
  Future<void> _restore() async {
    try {
      final found = await _ref
          .read(delegateModeRepositoryProvider)
          .storedBallotRounds();
      for (final roundId in found.roundIds) {
        // One resend right away rather than after the first tick.
        _ref.read(delegateBallotResenderProvider(roundId).notifier)
          ..keepSending()
          ..sendNow();
      }
      if (!found.complete) _scheduleRetry();
    } catch (error) {
      debugPrint(
        '[zcash] Delegate mode: stored ballot discovery failed: '
        '${describeDelegateError(error)}',
      );
      if (!_ref.read(appSecurityProvider).requiresUnlock) _scheduleRetry();
    }
  }

  /// Tries again after the retry delay.
  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    _retryTimer = Timer(_ref.read(delegateBallotRestoreRetryDelayProvider), () {
      _retryTimer = null;
      unawaited(restore());
    });
  }

  /// Drops a scheduled retry.
  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }
}

/// The stored-ballot restorer, which runs once built: the app builds it
/// only while `VIZOR_PROXY_DELEGATION_ENABLED` is on. It restores on start,
/// when the app resumes and when the wallet unlocks.
final delegateBallotResendRestorerProvider = Provider((ref) {
  final restorer = DelegateBallotResendRestorer(ref);
  ref.listen<AppSecurityState>(appSecurityProvider, (previous, next) {
    if (previous?.requiresUnlock == true && !next.requiresUnlock) {
      unawaited(restorer.restore());
    }
  });
  unawaited(restorer.restore());
  final lifecycle = AppLifecycleListener(
    onResume: () => unawaited(restorer.restore()),
  );
  ref.onDispose(() {
    lifecycle.dispose();
    restorer._cancelRetry();
  });
  return restorer;
});

/// The marker a key is posted with.
final delegateMarkerProvider = FutureProvider.autoDispose
    .family<String, DelegateKeyInfo>((ref, key) {
      return ref.watch(delegateModeRepositoryProvider).markerText(key);
    }, retry: proxyNoRetry);

/// Drops every cached delegate-mode read after a change on the device.
void invalidateDelegateMode(WidgetRef ref) {
  ref.invalidate(delegateModeStatusProvider);
  ref.invalidate(delegateRoundsProvider);
  ref.invalidate(delegateRoundProvider);
  ref.invalidate(delegateMarkerProvider);
  ref.invalidate(delegateBallotResenderProvider);
}
