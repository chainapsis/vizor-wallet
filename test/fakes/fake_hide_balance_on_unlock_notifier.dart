import 'package:zcash_wallet/src/providers/hide_balance_on_unlock_provider.dart';

class FakeHideBalanceOnUnlockNotifier extends HideBalanceOnUnlockNotifier {
  FakeHideBalanceOnUnlockNotifier({
    this.enabled = false,
    this.failSave = false,
  });
  final bool enabled;
  final bool failSave;

  @override
  bool build() => enabled;

  @override
  Future<void> set(bool enabled) async {
    if (failSave) throw StateError('save failed');
    state = enabled;
  }
}
