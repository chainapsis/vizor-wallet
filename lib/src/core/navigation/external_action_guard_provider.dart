import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Actions initiated outside the screen that owns an in-progress operation.
/// Screen completion and security-driven locking do not consult this guard.
enum ExternalAction { navigation, paymentRequest, updatePrompt, appReview }

class ExternalActionGuardState {
  const ExternalActionGuardState({
    this.activeHoldCount = 0,
    this.pendingNavigationCount = 0,
    this.blockedActions = const {},
  });

  final int activeHoldCount;
  final int pendingNavigationCount;
  final Set<ExternalAction> blockedActions;

  bool blocks(ExternalAction action) => blockedActions.contains(action);

  bool get canProtect =>
      pendingNavigationCount == 0 && !blocks(ExternalAction.navigation);
}

/// An owned hold. Releasing it twice cannot release another owner's hold.
class ExternalActionLease {
  ExternalActionLease._(this._release);

  final void Function() _release;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _release();
  }

  /// Widget disposal cannot synchronously write a provider. Keep the hold
  /// until that lifecycle call returns, including any replacement mount.
  void releaseAfterNavigation() => scheduleMicrotask(release);
}

/// Coordinates protected work and already accepted asynchronous navigation.
/// Intake queues and route-specific policies remain owned by their callers.
class ExternalActionGuardNotifier extends Notifier<ExternalActionGuardState> {
  final _holds = <Object, Set<ExternalAction>>{};
  final _pendingNavigations = <Object>{};
  bool _disposed = false;

  @override
  ExternalActionGuardState build() {
    ref.onDispose(() => _disposed = true);
    return const ExternalActionGuardState();
  }

  /// Signing surfaces keep the existing payment-request and review holds.
  ExternalActionLease acquire({
    Set<ExternalAction> blocks = const {
      ExternalAction.paymentRequest,
      ExternalAction.appReview,
    },
  }) {
    final owner = Object();
    if (!_disposed) {
      _holds[owner] = Set.unmodifiable(blocks);
      _publish();
    }
    return ExternalActionLease._(() {
      if (_disposed || _holds.remove(owner) == null) return;
      _publish();
    });
  }

  /// Begin persistence only when no accepted navigation can unmount its UI.
  /// The screen's own success navigation remains allowed while it holds this.
  ExternalActionLease? tryProtect() {
    if (_disposed || !state.canProtect) return null;
    return acquire(blocks: ExternalAction.values.toSet());
  }

  /// Register before the first await so persistence cannot race a callback
  /// that was accepted before pointer/focus input became blocked.
  ExternalActionLease? tryBeginNavigation() {
    if (_disposed || state.blocks(ExternalAction.navigation)) return null;
    final owner = Object();
    _pendingNavigations.add(owner);
    _publish();
    return ExternalActionLease._(() {
      if (_disposed || !_pendingNavigations.remove(owner)) return;
      _publish();
    });
  }

  Future<void> runNavigation(Future<void> Function() action) async {
    final lease = tryBeginNavigation();
    if (lease == null) return;
    try {
      await action();
    } finally {
      lease.release();
    }
  }

  void _publish() {
    state = ExternalActionGuardState(
      activeHoldCount: _holds.length,
      pendingNavigationCount: _pendingNavigations.length,
      blockedActions: Set.unmodifiable(
        _holds.values.expand((actions) => actions),
      ),
    );
  }
}

final externalActionGuardProvider =
    NotifierProvider<ExternalActionGuardNotifier, ExternalActionGuardState>(
      ExternalActionGuardNotifier.new,
    );
