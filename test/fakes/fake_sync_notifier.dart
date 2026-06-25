import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

class FakeSyncNotifier extends SyncNotifier {
  FakeSyncNotifier([this.initialState]);

  final SyncState? initialState;

  @override
  Future<SyncState> build() async => initialState ?? SyncState();

  void setSyncState(SyncState nextState) {
    state = AsyncData(nextState);
  }
}
