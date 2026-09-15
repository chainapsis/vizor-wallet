import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final giftCardTrackingLifecycleProvider = Provider(
  (ref) => GiftCardTrackingLifecycle(),
);

/// Remembers a destructive-operation fence even before the observer is lazily
/// instantiated. Only the destructive-operation owner may release this fence.
class GiftCardTrackingLifecycle {
  Object? _owner;
  Future<void> Function()? _drain;
  void Function()? _resume;
  bool _quiesced = false;
  Future<void>? _pending;

  void register({
    required Object owner,
    required Future<void> Function() quiesceAndDrain,
    required void Function() resume,
  }) {
    if (_owner != null && !identical(_owner, owner)) {
      throw StateError('Gift Card observer already registered');
    }
    _owner = owner;
    _drain = quiesceAndDrain;
    _resume = resume;
    if (_quiesced) _pending = quiesceAndDrain();
  }

  void unregister(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _drain = null;
    _resume = null;
  }

  Future<void> quiesceAndDrain() async {
    _quiesced = true;
    await _drain?.call();
    await _pending;
  }

  void resume() {
    _quiesced = false;
    _resume?.call();
  }
}
