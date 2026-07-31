import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

class FakeSyncNotifier extends SyncNotifier {
  FakeSyncNotifier([this.initialState]);

  final SyncState? initialState;
  int balanceRefreshes = 0;
  int accountSwitchRefreshes = 0;

  @override
  Future<SyncState> build() async => initialState ?? SyncState();

  void emit(SyncState next) {
    state = AsyncData(next);
  }

  void setSyncState(SyncState nextState) {
    state = AsyncData(nextState);
  }

  @override
  Future<void> refreshAfterSend() async {
    balanceRefreshes++;
  }

  @override
  Future<void> refreshAfterAccountSwitch() async {
    accountSwitchRefreshes++;
    await refreshAfterSend();
  }
}
