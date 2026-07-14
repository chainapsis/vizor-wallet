import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rust/api/wallet.dart' as rust_wallet;
import 'rpc_endpoint_failover_provider.dart';

typedef ChainUpgradeStatusGetter =
    Future<rust_wallet.ChainUpgradeStatus> Function({
      required String lightwalletdUrl,
      required String network,
    });

final chainUpgradeStatusGetterProvider = Provider<ChainUpgradeStatusGetter>(
  (_) => rust_wallet.getChainUpgradeStatus,
);

final chainUpgradeStatusProvider =
    FutureProvider<rust_wallet.ChainUpgradeStatus>((ref) {
      final endpoint = ref.watch(
        rpcEndpointFailoverProvider.select((state) => state.current),
      );
      final getChainUpgradeStatus = ref.watch(chainUpgradeStatusGetterProvider);
      return getChainUpgradeStatus(
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
      );
    });
