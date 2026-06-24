import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcash_wallet/src/providers/sync_provider.dart';

class FakeSyncNotifier extends SyncNotifier {
  FakeSyncNotifier([this.initialState]);

  final SyncState? initialState;

  @override
  Future<SyncState> build() async => initialState ?? SyncState();

  void emit(SyncState next) {
    state = AsyncData(next);
  }
}
