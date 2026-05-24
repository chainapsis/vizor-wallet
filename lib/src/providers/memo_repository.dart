import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/wallet_paths.dart';
import '../providers/app_security_provider.dart';
import '../providers/rpc_endpoint_provider.dart';
import '../rust/api/sync.dart' as rust_sync;

/// Value type used as the family key for [receivedMemosProvider].
/// Dart records provide structural equality automatically.
typedef MemoQuery = ({String accountUuid, String? query});

/// Repository interface allowing test overrides without FFI.
abstract class MemoRepository {
  Future<List<rust_sync.ReceivedMemo>> receivedMemos({
    required String accountUuid,
    String? query,
  });
}

class _DefaultMemoRepository implements MemoRepository {
  const _DefaultMemoRepository(this._ref);

  final Ref _ref;

  @override
  Future<List<rust_sync.ReceivedMemo>> receivedMemos({
    required String accountUuid,
    String? query,
  }) async {
    final dbPath = await getWalletDbPath();
    final network = _ref.read(rpcEndpointProvider).networkName;
    return rust_sync.getReceivedMemos(
      dbPath: dbPath,
      network: network,
      accountUuid: accountUuid,
      query: query?.isEmpty == true ? null : query,
    );
  }
}

final memoRepositoryProvider = Provider<MemoRepository>(
  (ref) => _DefaultMemoRepository(ref),
);

final receivedMemosProvider = FutureProvider.family<
  List<rust_sync.ReceivedMemo>,
  MemoQuery
>((ref, q) async {
  if (ref.watch(appSecurityProvider).requiresUnlock) return const [];
  return ref
      .watch(memoRepositoryProvider)
      .receivedMemos(accountUuid: q.accountUuid, query: q.query);
});
