import 'dart:async';
import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rust/api/one_time_ivk.dart' as rust_swap;
import 'enhance_pir_provider.dart';
import 'sync_provider.dart';

/// The wallet calls behind "Check swap history". Overridable in tests.
class SwapHistoryApi {
  const SwapHistoryApi({
    required this.begin,
    required this.status,
    required this.cancel,
    this.pollInterval = const Duration(seconds: 5),
    this.maxWait = const Duration(minutes: 3),
  });

  /// Starts or resumes the durable explicit history job for eligible accounts.
  final Future<void> Function() begin;

  /// Cancels the job without discarding its durable position.
  final Future<void> Function() cancel;

  /// Whether manual recovery or a restored wallet's seed walk is unfinished, and
  /// whether the receiver service needs a newer app.
  final Future<rust_swap.SwapRecoveryStatus> Function() status;

  /// How often a running check asks the wallet whether it is done.
  final Duration pollInterval;

  /// How long the check waits before leaving the rest to later syncs.
  final Duration maxWait;
}

final swapHistoryApiProvider = Provider<SwapHistoryApi>((ref) {
  return SwapHistoryApi(
    begin: () => ref.read(syncProvider.notifier).checkSwapHistory(),
    cancel: () => ref.read(syncProvider.notifier).cancelSwapHistory(),
    // Without a wallet there is no history left to check.
    status: () async =>
        await ref.read(swapRecoveryStatusReaderProvider)() ??
        const rust_swap.SwapRecoveryStatus(
          roundDue: false,
          awaitingAdmission: false,
          checkingHistory: false,
          manualCheckActive: false,
          upgradeRequired: false,
        ),
  );
});

/// Where the user's "Check swap history" stands.
enum SwapHistoryCheck {
  /// Not run since launch.
  idle,

  /// Waiting for receiver recovery to finish the check.
  checking,

  /// The check finished.
  done,

  /// The check outlasted [SwapHistoryApi.maxWait]; later recovery rounds finish it.
  continuing,

  /// The user paused the durable job.
  paused,

  /// A round ran but did not finish, such as when the receiver service can't
  /// be reached. A job the wallet saved shows as checking again.
  failed,

  /// A round stopped because the wallet was changing, such as an account
  /// change. A job it saved shows as checking again once the change is done.
  walletChanged,

  /// The check never reached the receiver service, because another wallet or
  /// setting change was running or the wallet was locked.
  notStarted,

  /// Pausing did not reach the wallet, which still has the job and resumes it
  /// in later rounds. Pause stays offered.
  pauseFailed,

  /// The check could not start because wallet sync has not caught up with the
  /// receiver service yet. Nothing was lost; checking again shortly starts it.
  waitingForSync,

  /// The check could not start because the receiver service has not yet
  /// published the blocks this wallet starts from, as for a wallet created
  /// moments ago. Nothing was lost; checking again shortly starts it.
  waitingForService,

  /// The receiver service needs a newer app. The saved job resumes after an update.
  updateRequired,
}

/// Tracks the explicit check for older repeat payments that automatic catch-up
/// skips. What it shows follows the wallet's saved state: a manual job the
/// wallet still has shows as checking, with Pause, and is watched until it ends.
/// Only the call in flight and its last answer are kept here.
class SwapHistoryCheckNotifier extends Notifier<SwapHistoryCheck> {
  /// Starts idle, then reads the wallet's saved job again whenever it can have
  /// changed: now, once a setting change has finished with the wallet, and
  /// after every recovery round. NEAR swap privacy doesn't affect it, since a
  /// running check keeps its accounts in a round's account set. Detection runs
  /// only for accounts in that set, which also takes accounts with evidence of
  /// use and, with the toggle on, every software account. A round that finds
  /// the service compatible again ends an update request.
  @override
  SwapHistoryCheck build() {
    ref.listen(enhancePirTransitionProvider, (previous, next) {
      if (previous == kEnhancePirChangingMessage &&
          next != kEnhancePirChangingMessage) {
        unawaited(_reconcile());
      }
    });
    ref.listen(swapRecoveryRoundsProvider, (_, _) => unawaited(_reconcile()));
    ref.listen(swapRecoveryUpdateRequiredProvider, (_, required) {
      if (required case AsyncData(value: false)
          when state == SwapHistoryCheck.updateRequired) {
        state = SwapHistoryCheck.idle;
      }
    });
    // After build returns, once there is a state to compare.
    unawaited(Future<void>.microtask(_reconcile));
    return SwapHistoryCheck.idle;
  }

  int _generation = 0;

  /// Whether a check is being watched, so the saved state is already followed.
  bool _observing = false;

  /// Whether a pause is waiting for the wallet, during which no saved-state
  /// read starts.
  bool _cancelling = false;

  /// Saved-state reads refused in a row, which [_reconcile] retries.
  int _refusedReads = 0;

  /// Whether the shown failure is a check that failed before it started its
  /// jobs (see `ReceiveError.historyStarted`). Any saved job is then an
  /// earlier check's, so the failure stays until the user checks again,
  /// whatever that job does, Pause included.
  bool _failedBeforeJobs = false;

  /// Reads the wallet's saved job and projects it: while the user's manual
  /// check is still active, a state that shows no running job turns into a
  /// watched check, with Pause, and once it is gone a check left to continue in
  /// the background, or one the user could not pause, shows as done, except
  /// after a check that failed before its jobs (see [_failedBeforeJobs]).
  /// Automatic seed recovery alone changes nothing. A refused read, such as
  /// one made while a wallet change holds admission, is tried again shortly.
  /// With `afterFailure`, the read follows a failed check, so a refusal means
  /// such a change stopped it and a failed check shows as a wallet change.
  Future<void> _reconcile({bool afterFailure = false}) async {
    if (_observing || _cancelling) return;
    final generation = _generation;
    final rust_swap.SwapRecoveryStatus? status;
    try {
      status = await ref.read(swapRecoveryStatusReaderProvider)();
    } catch (error) {
      log('Saved swap history check not read: $error');
      // Rust read errors arrive as ReceiveError. A StateError is the refusal.
      if (afterFailure &&
          error is StateError &&
          ref.mounted &&
          generation == _generation &&
          state == SwapHistoryCheck.failed) {
        state = SwapHistoryCheck.walletChanged;
      }
      if (ref.mounted && _refusedReads++ < 6) {
        final retry = ref.read(swapHistoryApiProvider).pollInterval;
        unawaited(
          Future<void>.delayed(retry).then((_) {
            if (ref.mounted) return _reconcile();
          }),
        );
      }
      return;
    }
    _refusedReads = 0;
    if (!ref.mounted || generation != _generation || _observing) return;
    final saved = status?.manualCheckActive ?? false;
    _setJobSaved(saved);
    if (saved && !_failedBeforeJobs && _shownWithoutJob.contains(state)) {
      await _watch(begin: false);
    } else if (!saved &&
        (state == SwapHistoryCheck.continuing ||
            state == SwapHistoryCheck.pauseFailed)) {
      state = SwapHistoryCheck.done;
    }
  }

  /// Records whether the wallet still has the user's manual job, which decides
  /// whether Pause is offered (see [swapHistoryJobSavedProvider]).
  void _setJobSaved(bool saved) =>
      ref.read(swapHistoryJobSavedProvider.notifier).set(saved);

  /// States for a check that stopped before it finished.
  static const _stopped = {
    SwapHistoryCheck.failed,
    SwapHistoryCheck.walletChanged,
    SwapHistoryCheck.notStarted,
    SwapHistoryCheck.waitingForSync,
    SwapHistoryCheck.waitingForService,
  };

  /// States that show no running job, so a saved one must replace them.
  static const _shownWithoutJob = {
    SwapHistoryCheck.idle,
    SwapHistoryCheck.done,
    SwapHistoryCheck.paused,
    ..._stopped,
  };

  /// Starts a check and polls until the wallet reports it done, or until
  /// [SwapHistoryApi.maxWait] passes. Does nothing while one is running.
  Future<void> check() async {
    if (state == SwapHistoryCheck.checking) return;
    await _watch(begin: true);
  }

  /// Shows a check as checking, with Pause, and watches it until it ends. It
  /// starts one when `begin`, else follows a saved job the wallet resumes.
  Future<void> _watch({required bool begin}) async {
    final generation = ++_generation;
    _observing = true;
    _failedBeforeJobs = false;
    state = SwapHistoryCheck.checking;
    final api = ref.read(swapHistoryApiProvider);
    try {
      if (begin) {
        await api.begin();
        if (!ref.mounted || generation != _generation) return;
      }
      await _observe(generation, api);
    } catch (error) {
      _fail(generation, error);
    } finally {
      if (generation == _generation) _observing = false;
    }
  }

  /// Polls the wallet for the check started under `generation` until it is
  /// done, needs an update, or outlasts [SwapHistoryApi.maxWait]. It reads no
  /// status while a setting change still holds the wallet.
  Future<void> _observe(int generation, SwapHistoryApi api) async {
    final deadline = DateTime.now().add(api.maxWait);
    while (true) {
      // Receiver work has its own lifecycle and never occupies ordinary sync.
      // The check drives rounds while it runs. A pending retry after a failed
      // round holds them.
      ref.read(syncProvider.notifier).pollSwapRecovery();
      await Future<void>.delayed(api.pollInterval);
      if (!ref.mounted || generation != _generation) return;
      if (ref.read(enhancePirTransitionProvider) !=
          kEnhancePirChangingMessage) {
        rust_swap.SwapRecoveryStatus? status;
        try {
          status = await api.status();
        } catch (error) {
          // A wallet change refuses reads for a moment without touching the
          // job, so the next poll asks again.
          log('Swap history check progress not read: $error');
        }
        if (!ref.mounted || generation != _generation) return;
        if (status != null) {
          _setJobSaved(status.manualCheckActive);
          if (status.upgradeRequired) {
            _requireUpdate();
            return;
          }
          if (!status.checkingHistory) {
            state = SwapHistoryCheck.done;
            return;
          }
        }
      }
      if (!DateTime.now().isBefore(deadline)) {
        state = SwapHistoryCheck.continuing;
        return;
      }
    }
  }

  /// Ends the check under `generation` with `error`: an update request when
  /// the service needs a newer app, waiting when wallet sync or the service
  /// has not caught up,
  /// not started when the wallet refused to begin, else failed. The saved-state
  /// read that follows can still show it as a wallet change.
  void _fail(int generation, Object error) {
    log('Swap history check failed: $error');
    if (ref.mounted && generation == _generation) {
      _failedBeforeJobs =
          error is rust_swap.ReceiveError && error.historyStarted == false;
      final kind = error is rust_swap.ReceiveError ? error.kind : null;
      if (kind == rust_swap.ReceiveErrorKind.upgradeRequired) {
        _requireUpdate();
      } else if (kind == rust_swap.ReceiveErrorKind.waitingForSync) {
        state = SwapHistoryCheck.waitingForSync;
      } else if (kind == rust_swap.ReceiveErrorKind.waitingForService) {
        state = SwapHistoryCheck.waitingForService;
      } else if (error is StateError) {
        // Sync refuses before any request while the wallet is locked or
        // another wallet or setting change holds it.
        state = SwapHistoryCheck.notStarted;
      } else {
        state = SwapHistoryCheck.failed;
      }
      // Whether an earlier job is still saved decides if Pause is offered.
      unawaited(Future<void>.microtask(() => _reconcile(afterFailure: true)));
    }
  }

  /// Shows the update request. The wallet saved it, so the next round that
  /// finds the service compatible clears it (see
  /// [swapRecoveryUpdateRequiredProvider]).
  void _requireUpdate() => state = SwapHistoryCheck.updateRequired;

  /// Pauses the current job and prevents a late poll from overwriting that
  /// state. Pausing an earlier check's job leaves a newer check's failure shown
  /// (see [_failedBeforeJobs]).
  Future<void> cancel() async {
    final generation = ++_generation;
    _observing = false;
    _cancelling = true;
    try {
      await ref.read(swapHistoryApiProvider).cancel();
      if (ref.mounted && generation == _generation) {
        // Drops any saved-state read that started before the pause landed,
        // which could still report the job active.
        _generation++;
        _setJobSaved(false);
        if (!_failedBeforeJobs) state = SwapHistoryCheck.paused;
      }
    } catch (error) {
      log('Could not pause swap history check: $error');
      if (ref.mounted && generation == _generation && !_failedBeforeJobs) {
        // The round has stopped either way. Only a job the wallet still has
        // resumes, and later reads show it again if this answer is stale.
        state = ref.read(swapHistoryJobSavedProvider)
            ? SwapHistoryCheck.pauseFailed
            : SwapHistoryCheck.paused;
      }
    } finally {
      _cancelling = false;
    }
  }
}

/// Whether the wallet still has the user's manual history check, as the
/// history check last read it. Pause is offered while it does, or while a check
/// call is in flight.
final swapHistoryJobSavedProvider = NotifierProvider<SwapHistoryJobSaved, bool>(
  SwapHistoryJobSaved.new,
);

/// See [swapHistoryJobSavedProvider].
class SwapHistoryJobSaved extends Notifier<bool> {
  @override
  bool build() => false;

  /// Records the latest answer.
  void set(bool saved) => state = saved;
}

final swapHistoryCheckProvider =
    NotifierProvider<SwapHistoryCheckNotifier, SwapHistoryCheck>(
      SwapHistoryCheckNotifier.new,
    );
