import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../rust/api/sync.dart' as rust_sync;

final publicDetailsLoadsProvider = Provider(
  (ref) => PublicDetailsLoads(
    cancelInRust: rust_sync.cancelPublicTransactionLoads,
    epochInRust: rust_sync.publicTransactionLoadEpoch,
  ),
);

/// One load registered by [PublicDetailsLoads.run]: what its native step
/// needs to stay cancellable before it reaches Rust.
class PublicDetailsLoadTicket {
  PublicDetailsLoadTicket._(this._loads, this._generation, this.cancelEpoch);

  final PublicDetailsLoads _loads;
  final int _generation;

  /// Rust's cancellation epoch when the load registered, for
  /// `enhanceTransactionPublicly`: a cancellation since then stops the native
  /// load even if it lands before Rust registers it.
  final BigInt cancelEpoch;

  /// Whether a lock or wallet change has cancelled this load.
  bool get cancelled => _generation != _loads._generation;

  /// Throws when [cancelled]. Call after each asynchronous step that precedes
  /// the native load.
  void ensureNotCancelled() {
    if (cancelled) throw StateError('The load was cancelled.');
  }
}

/// The "Load publicly" requests in flight: one transaction's details fetched
/// from the server because the user asked. Each runs under [run], so a lock
/// or a destructive wallet change can stop it: [cancel] has Rust send and
/// store nothing from a load, whether it is already in Rust or still in its
/// Dart steps, and [quiesceAndDrain] also refuses new loads and waits for
/// running ones before an account or the wallet is deleted.
class PublicDetailsLoads {
  PublicDetailsLoads({
    required void Function() cancelInRust,
    required BigInt Function() epochInRust,
  }) : _cancelInRust = cancelInRust,
       _epochInRust = epochInRust;

  final void Function() _cancelInRust;
  final BigInt Function() _epochInRust;
  final Set<Future<void>> _running = {};
  int _pauseDepth = 0;
  int _generation = 0;

  bool get isPaused => _pauseDepth > 0;

  /// Runs [load], or returns false without running it while loads are
  /// paused for a wallet change. Register before the load's first wallet or
  /// network step; [load] checks its ticket after each asynchronous step and
  /// passes its epoch to the native load.
  Future<bool> run(
    Future<void> Function(PublicDetailsLoadTicket ticket) load,
  ) async {
    if (isPaused) return false;
    final ticket = PublicDetailsLoadTicket._(this, _generation, _epochInRust());
    final done = Completer<void>();
    _running.add(done.future);
    try {
      await load(ticket);
      return true;
    } finally {
      _running.remove(done.future);
      done.complete();
    }
  }

  /// Has every running load send and store nothing, as on lock.
  void cancel() {
    if (_running.isEmpty) return;
    _generation++;
    try {
      _cancelInRust();
    } catch (error) {
      log('PublicDetailsLoads: cancel failed: $error');
    }
  }

  /// Refuses new loads, cancels running ones and waits for them. Must be
  /// paired with [resume], including when the destructive action fails.
  Future<void> quiesceAndDrain() async {
    _pauseDepth++;
    cancel();
    while (_running.isNotEmpty) {
      await Future.wait(_running.toList());
    }
  }

  void resume() {
    if (_pauseDepth > 0) _pauseDepth--;
  }
}
