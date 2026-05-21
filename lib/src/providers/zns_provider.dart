import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zcashname_sdk/zcashname_sdk.dart';

import '../rust/api/wallet.dart' as rust_wallet;
import '../core/storage/wallet_paths.dart';
import 'rpc_endpoint_provider.dart';

class ZnsResolver {
  ZnsResolver(this._zns);

  final ZNS _zns;
  final _nameCache = <String, String?>{};

  String get _networkName => switch (_zns.network) {
    Network.mainnet => 'main',
    Network.testnet => 'test',
  };

  Future<String?> resolveName(String name) async {
    final registration = await _zns.resolveName(name);
    return registration?.address;
  }

  Future<String?> reverseResolve(String address) async {
    if (_nameCache.containsKey(address)) return _nameCache[address];
    final registrations = await _zns.resolveAddress(address);
    final name = registrations.isEmpty ? null : '${registrations.first.name}.zcash';
    _nameCache[address] = name;
    return name;
  }

  Future<bool> isOwnedByAccount(String name, String accountUuid) async {
    final ua = await resolveName(name);
    if (ua == null) return false;
    final dbPath = await getWalletDbPath();
    return rust_wallet.isAddressFromAccount(
      dbPath: dbPath,
      network: _networkName,
      accountUuid: accountUuid,
      address: ua,
    );
  }

  void close() => _zns.close();
}

final znsResolverProvider = Provider<ZnsResolver>((ref) {
  final networkName = ref.watch(
    rpcEndpointProvider.select((config) => config.networkName),
  );

  final zns = switch (networkName) {
    'main' => ZNS(network: Network.mainnet),
    'test' => ZNS(network: Network.testnet),
    _ => ZNS(url: Uri.parse('http://localhost:3000')),
  };

  final resolver = ZnsResolver(zns);
  ref.onDispose(resolver.close);
  return resolver;
});
