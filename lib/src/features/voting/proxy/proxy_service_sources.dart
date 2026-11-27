import 'package:flutter/foundation.dart';

import '../../../rust/api/proxy_registry.dart' as rust;
import '../../../services/voting/voting_config_loader.dart';
import 'proxy_delegation_models.dart';

/// Where a network's proxy services are, as the latest dynamic config load
/// named them (contracts-v1 section 12.1). The URL lists are unsigned:
/// what they serve proves or authenticates itself, or is display data.
@immutable
class ProxyRegistrySources {
  /// Creates the sources.
  const ProxyRegistrySources({
    this.proofRpcUrls = const [],
    this.verifierApiUrls = const [],
  });

  /// The hosts that serve the participation reader's proofs.
  final List<String> proofRpcUrls;

  /// The attester API delegate mode registers through, most preferred
  /// first.
  final List<String> verifierApiUrls;
}

/// Each network's [ProxyRegistrySources], fed by every dynamic config
/// document the config loader fetches.
class ProxyServiceSources {
  /// The latest sources per network.
  final _sources = <String, ProxyRegistrySources>{};

  /// Reads `extensions.proxy_delegation_v1` from each document of [fetch],
  /// in fetch order, and keeps the last one's URL lists for [network].
  /// A document without the extension, or one that does not parse, changes
  /// nothing; nothing here throws.
  Future<void> ingest(
    VotingDynamicConfigFetch fetch, {
    required String network,
  }) async {
    for (final document in fetch.documents) {
      try {
        final urls = await rust.proxyServiceUrls(dynamicConfigBytes: document);
        if (urls == null) continue;
        _sources[network] = ProxyRegistrySources(
          proofRpcUrls: List.unmodifiable(urls.proofRpcUrls),
          verifierApiUrls: List.unmodifiable(urls.verifierApiUrls),
        );
      } catch (error) {
        debugPrint(
          '[zcash] Proxy registry: service URLs not read: '
          '${describeProxyRegistryError(error)}',
        );
      }
    }
  }

  /// The sources the latest load named for [network], or null before one.
  ProxyRegistrySources? of(String network) => _sources[network];

  /// Forgets every network's sources, as account deletion and wallet reset
  /// require.
  void clear() => _sources.clear();
}
