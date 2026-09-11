import 'package:flutter_riverpod/flutter_riverpod.dart';

final paymentLinkClaimLifecycleRegistryProvider = Provider(
  (ref) => PaymentLinkClaimLifecycleRegistry(),
);

class PaymentLinkClaimLifecycleRegistry {
  Object? _owner;
  Future<void> Function()? _quiesceAndDrain;
  void Function()? _resume;

  void register({
    required Object owner,
    required Future<void> Function() quiesceAndDrain,
    required void Function() resume,
  }) {
    final currentOwner = _owner;
    if (currentOwner != null && !identical(currentOwner, owner)) {
      throw StateError('A Gift Card claim lifecycle owner is already active.');
    }
    _owner = owner;
    _quiesceAndDrain = quiesceAndDrain;
    _resume = resume;
  }

  void unregister(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _quiesceAndDrain = null;
    _resume = null;
  }

  Future<void> quiesceAndDrain() async {
    await _quiesceAndDrain?.call();
  }

  void resume() {
    _resume?.call();
  }
}
