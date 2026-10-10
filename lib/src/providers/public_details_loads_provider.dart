import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../rust/api/sync.dart' as rust_sync;

final publicDetailsLoadsProvider = Provider(
  (ref) =>
      PublicDetailsLoads(cancelInRust: rust_sync.cancelPublicTransactionLoads),
);

/// The "Load publicly" requests in flight: one transaction's details fetched
/// from the server because the user asked. Each runs under [run], so a lock
/// or a destructive wallet change can stop it: [cancel] has Rust store
/// nothing from a load already running, and [quiesceAndDrain] also refuses
/// new loads and waits for running ones before an account or the wallet is
/// deleted.
class PublicDetailsLoads {
  PublicDetailsLoads({required void Function() cancelInRust})
    : _cancelInRust = cancelInRust;

  final void Function() _cancelInRust;
  final Set<Future<void>> _running = {};
  int _pauseDepth = 0;

  bool get isPaused => _pauseDepth > 0;

  /// Runs [load], or returns false without running it while loads are
  /// paused for a wallet change. Register before the load's first wallet or
  /// network step.
  Future<bool> run(Future<void> Function() load) async {
    if (isPaused) return false;
    final done = Completer<void>();
    _running.add(done.future);
    try {
      await load();
      return true;
    } finally {
      _running.remove(done.future);
      done.complete();
    }
  }

  /// Has every running load store nothing, as on lock.
  void cancel() {
    if (_running.isEmpty) return;
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
