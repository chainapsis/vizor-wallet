import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/wallet_paths.dart';
import '../providers/app_security_provider.dart';
import '../providers/rpc_endpoint_provider.dart';
import '../rust/api/wallet.dart' as rust_wallet;

/// Repository interface allowing test overrides without FFI.
abstract class AddressRepository {
  Future<List<rust_wallet.AccountAddress>> list(String accountUuid);
}

class _DefaultAddressRepository implements AddressRepository {
  const _DefaultAddressRepository(this._ref);

  final Ref _ref;

  @override
  Future<List<rust_wallet.AccountAddress>> list(String accountUuid) async {
    final dbPath = await getWalletDbPath();
    final network = _ref.read(rpcEndpointProvider).networkName;
    return rust_wallet.listAccountAddresses(
      dbPath: dbPath,
      network: network,
      accountUuid: accountUuid,
    );
  }
}

final addressRepositoryProvider = Provider<AddressRepository>(
  (ref) => _DefaultAddressRepository(ref),
);

final addressListProvider = FutureProvider.family<
  List<rust_wallet.AccountAddress>,
  String
>((ref, accountUuid) async {
  if (ref.watch(appSecurityProvider).requiresUnlock) return const [];
  return ref.watch(addressRepositoryProvider).list(accountUuid);
});
