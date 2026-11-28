import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/proxy_delegation_feature_config.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/voting/voting_home_cache_provider.dart';
import '../../../services/voting/voting_config_loader.dart';
import 'proxy_registry_store.dart';
import 'proxy_service_sources.dart';

/// The persisted registry state, in the voting cache directory.
final proxyRegistryStoreProvider = Provider<ProxyRegistryStore>(
  (ref) => ProxyRegistryStore(ref.watch(votingFileCacheProvider)),
);

/// The wallet network whose registry state the delegator screens use.
final proxyRegistryNetworkProvider = Provider<String>(
  (ref) => ref.watch(
    rpcEndpointFailoverProvider.select((state) => state.current.networkName),
  ),
);

/// The proxy service URLs the latest dynamic config load named.
final proxyServiceSourcesProvider = Provider<ProxyServiceSources>(
  (_) => ProxyServiceSources(),
);

/// The voting config loader's proxy delegation hook. Null while the dormant
/// flag is off, so the shipped loader fetches and stores nothing new.
final proxyDynamicConfigObserverProvider =
    Provider<VotingDynamicConfigObserver?>((ref) {
      if (!ref.watch(proxyDelegationFeatureEnabledProvider)) return null;
      final sources = ref.watch(proxyServiceSourcesProvider);
      return (fetch) => sources.ingest(
        fetch,
        network: ref.read(proxyRegistryNetworkProvider),
      );
    });

/// Deletes the stored registry state and the sources held in memory, as
/// account deletion and wallet reset require (plan section 4.4, Deletion).
/// Does nothing while the dormant flag is off.
final proxyRegistryDeletionProvider = Provider<Future<void> Function()>((ref) {
  final enabled = ref.watch(proxyDelegationFeatureEnabledProvider);
  return () async {
    if (!enabled) return;
    ref.read(proxyServiceSourcesProvider).clear();
    await ref.read(proxyRegistryStoreProvider).clear();
  };
});
