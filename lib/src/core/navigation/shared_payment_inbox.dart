import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/shared_payment_service.dart';
import 'shared_payment_intake.dart';

/// Shares waiting behind the one being resolved; the runner keeps the same
/// number waiting for Dart. A sender sharing faster than images can be read
/// cannot pile copies up in the cache.
const kMaxQueuedShares = 4;

/// Hands what the share sheet delivers to the intake, one share at a time and
/// in arrival order, and emits the outcomes still worth presenting.
///
/// Something newer than a share overtakes it: a later share, a link tapped
/// on the other channel, or a wallet reset (the host reports a reset through
/// [supersede]). Newer is by the runner's intake sequence, which numbers
/// links and shares alike. Text arrives at once with its number; an image's
/// number is announced the moment it is captured and its payload follows
/// once its copy is written. So a link tapped during that copy carries the
/// higher number whichever channel reached Dart first, a reset during it
/// counts the image too, and no clock is involved. An overtaken payment
/// or notice is dropped rather than presented over the newer thing, as a
/// parked link would be. A Gift Card is emitted anyway, because Gift Cards
/// queue rather than replace each other and outlive a reset.
///
/// Every share is resolved, even once nothing listens any more, because
/// resolving is what deletes the image copy the runner made; only outcomes
/// are dropped. Provider-scoped for that reason: it outlives the host.
class SharedPaymentInbox {
  SharedPaymentInbox({
    required this.intake,
    required Stream<List<SharedIntakeEvent>> events,
  }) {
    _subscription = events.listen(_onBatch);
  }

  final SharedPaymentIntake intake;
  late final StreamSubscription<List<SharedIntakeEvent>> _subscription;
  final _outcomes = StreamController<SharedPaymentOutcome>.broadcast();
  final _queue = <SharedPayload>[];
  var _resolving = false;

  /// The highest capture number seen on the channel.
  var _highestSeq = 0;

  /// Every share numbered up to here has been overtaken: by the capture that
  /// followed it, or by a reset that came after everything seen so far.
  var _staleThrough = 0;

  Stream<SharedPaymentOutcome> get outcomes => _outcomes.stream;

  /// The wallet was reset: everything captured so far is overtaken.
  void supersede() => _staleThrough = _highestSeq;

  Future<void> dispose() async {
    await _subscription.cancel();
    await _outcomes.close();
  }

  /// Every number in the batch counts before any payload in it is resolved:
  /// a cold start can drain `[text 1, captured 2]` in one batch, and the
  /// text resolves in a microtask, sooner than a second stream event would
  /// arrive.
  void _onBatch(List<SharedIntakeEvent> batch) {
    for (final event in batch) {
      if (event.seq > _highestSeq) _highestSeq = event.seq;
      // Whatever was captured before this one is older than it, an image's
      // own payload included: it was announced at capture and arrives later
      // with the same number.
      if (event.seq - 1 > _staleThrough) _staleThrough = event.seq - 1;
    }
    for (final event in batch) {
      if (event is SharedPayload) _enqueue(event);
    }
  }

  void _enqueue(SharedPayload payload) {
    _queue.add(payload);
    if (_queue.length > kMaxQueuedShares) intake.discard(_queue.removeAt(0));
    unawaited(_resolveQueued());
  }

  Future<void> _resolveQueued() async {
    if (_resolving) return;
    _resolving = true;
    while (_queue.isNotEmpty) {
      final payload = _queue.removeAt(0);
      try {
        final outcome = await intake.resolve(payload);
        final overtaken = payload.seq <= _staleThrough;
        if ((outcome is SharedGiftCard || !overtaken) && !_outcomes.isClosed) {
          _outcomes.add(outcome);
        }
      } catch (error) {
        // One failed share must not take the ones behind it with it.
        debugPrint('SharedPaymentInbox: share failed: $error');
      }
    }
    _resolving = false;
  }
}
