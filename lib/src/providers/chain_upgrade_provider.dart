import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/rpc_endpoint_config.dart';
import '../rust/api/wallet.dart' as rust_wallet;
import 'rpc_endpoint_failover_provider.dart';

String ironwoodActiveSeenStorageKey(String network) {
  return 'zcash_ironwood_active_seen_$network';
}

abstract class IronwoodActivationStore {
  Future<bool> isActiveSeen(String network);
  Future<void> markActiveSeen(String network);
}

class SharedPreferencesIronwoodActivationStore
    implements IronwoodActivationStore {
  const SharedPreferencesIronwoodActivationStore();

  @override
  Future<bool> isActiveSeen(String network) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(ironwoodActiveSeenStorageKey(network)) ?? false;
  }

  @override
  Future<void> markActiveSeen(String network) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ironwoodActiveSeenStorageKey(network), true);
  }
}

typedef ChainUpgradeStatusGetter =
    Future<rust_wallet.ChainUpgradeStatus> Function({
      required String lightwalletdUrl,
      required String network,
    });

typedef ChainUpgradeStatusAtHeightGetter =
    Future<rust_wallet.ChainUpgradeActivationStatus> Function({
      required String network,
      required BigInt tipHeight,
    });

class ChainUpgradeStatusState {
  const ChainUpgradeStatusState({
    required this.network,
    required this.endpointUrl,
    required this.tipHeight,
    required this.nu63ActivationHeight,
    required this.ironwoodActiveAtTip,
    this.lightwalletdChainName,
    this.lightwalletdReportedHeight,
    this.lightwalletdEstimatedHeight,
    this.lightwalletdConsensusBranchId,
    this.lightwalletdUpgradeName,
    this.lightwalletdUpgradeHeight,
    this.endpointMatchesNetwork,
  });

  factory ChainUpgradeStatusState.fromLightwalletd(
    rust_wallet.ChainUpgradeStatus status,
    RpcEndpointConfig endpoint, {
    ChainUpgradeStatusState? previous,
  }) {
    return ChainUpgradeStatusState(
      network: status.network,
      endpointUrl: endpoint.normalizedLightwalletdUrl,
      tipHeight: status.tipHeight,
      nu63ActivationHeight: status.nu63ActivationHeight,
      ironwoodActiveAtTip: _resolveIronwoodActive(
        previous,
        endpoint,
        status.ironwoodActiveAtTip,
      ),
      lightwalletdChainName: status.lightwalletdChainName,
      lightwalletdReportedHeight: status.lightwalletdReportedHeight,
      lightwalletdEstimatedHeight: status.lightwalletdEstimatedHeight,
      lightwalletdConsensusBranchId: status.lightwalletdConsensusBranchId,
      lightwalletdUpgradeName: status.lightwalletdUpgradeName,
      lightwalletdUpgradeHeight: status.lightwalletdUpgradeHeight,
      endpointMatchesNetwork: status.endpointMatchesNetwork,
    );
  }

  factory ChainUpgradeStatusState.cachedActive(
    RpcEndpointConfig endpoint, {
    BigInt? tipHeight,
    ChainUpgradeStatusState? previous,
  }) {
    final preserveMetadata = _sameEndpoint(previous, endpoint);
    return ChainUpgradeStatusState(
      network: endpoint.networkName,
      endpointUrl: endpoint.normalizedLightwalletdUrl,
      tipHeight: tipHeight ?? previous?.tipHeight ?? BigInt.zero,
      nu63ActivationHeight: previous?.nu63ActivationHeight,
      ironwoodActiveAtTip: true,
      lightwalletdChainName: preserveMetadata
          ? previous?.lightwalletdChainName
          : null,
      lightwalletdReportedHeight: preserveMetadata
          ? previous?.lightwalletdReportedHeight
          : null,
      lightwalletdEstimatedHeight: preserveMetadata
          ? previous?.lightwalletdEstimatedHeight
          : null,
      lightwalletdConsensusBranchId: preserveMetadata
          ? previous?.lightwalletdConsensusBranchId
          : null,
      lightwalletdUpgradeName: preserveMetadata
          ? previous?.lightwalletdUpgradeName
          : null,
      lightwalletdUpgradeHeight: preserveMetadata
          ? previous?.lightwalletdUpgradeHeight
          : null,
      endpointMatchesNetwork: preserveMetadata
          ? previous?.endpointMatchesNetwork
          : null,
    );
  }

  factory ChainUpgradeStatusState.fromActivationStatus(
    rust_wallet.ChainUpgradeActivationStatus status,
    RpcEndpointConfig endpoint, {
    ChainUpgradeStatusState? previous,
  }) {
    final preserveMetadata = _sameEndpoint(previous, endpoint);
    return ChainUpgradeStatusState(
      network: status.network,
      endpointUrl: endpoint.normalizedLightwalletdUrl,
      tipHeight: status.tipHeight,
      nu63ActivationHeight: status.nu63ActivationHeight,
      ironwoodActiveAtTip: _resolveIronwoodActive(
        previous,
        endpoint,
        status.ironwoodActiveAtTip,
      ),
      lightwalletdChainName: preserveMetadata
          ? previous?.lightwalletdChainName
          : null,
      lightwalletdReportedHeight: preserveMetadata
          ? previous?.lightwalletdReportedHeight
          : null,
      lightwalletdEstimatedHeight: preserveMetadata
          ? previous?.lightwalletdEstimatedHeight
          : null,
      lightwalletdConsensusBranchId: preserveMetadata
          ? previous?.lightwalletdConsensusBranchId
          : null,
      lightwalletdUpgradeName: preserveMetadata
          ? previous?.lightwalletdUpgradeName
          : null,
      lightwalletdUpgradeHeight: preserveMetadata
          ? previous?.lightwalletdUpgradeHeight
          : null,
      endpointMatchesNetwork: preserveMetadata
          ? previous?.endpointMatchesNetwork
          : null,
    );
  }

  final String network;
  final String endpointUrl;
  final BigInt tipHeight;
  final BigInt? nu63ActivationHeight;
  final bool ironwoodActiveAtTip;
  final String? lightwalletdChainName;
  final BigInt? lightwalletdReportedHeight;
  final BigInt? lightwalletdEstimatedHeight;
  final String? lightwalletdConsensusBranchId;
  final String? lightwalletdUpgradeName;
  final BigInt? lightwalletdUpgradeHeight;
  final bool? endpointMatchesNetwork;

  bool get hasLightwalletdMetadata => lightwalletdChainName != null;

  static bool _sameEndpoint(
    ChainUpgradeStatusState? previous,
    RpcEndpointConfig endpoint,
  ) {
    return previous != null &&
        previous.network == endpoint.networkName &&
        previous.endpointUrl == endpoint.normalizedLightwalletdUrl;
  }

  static bool _resolveIronwoodActive(
    ChainUpgradeStatusState? previous,
    RpcEndpointConfig endpoint,
    bool nextActive,
  ) {
    if (_sameEndpoint(previous, endpoint) &&
        previous!.ironwoodActiveAtTip &&
        !nextActive) {
      return true;
    }
    return nextActive;
  }
}

final chainUpgradeStatusGetterProvider = Provider<ChainUpgradeStatusGetter>(
  (_) => rust_wallet.getChainUpgradeStatus,
);

final chainUpgradeStatusAtHeightGetterProvider =
    Provider<ChainUpgradeStatusAtHeightGetter>(
      (_) => rust_wallet.getChainUpgradeStatusAtHeight,
    );

final ironwoodActivationStoreProvider = Provider<IronwoodActivationStore>(
  (_) => const SharedPreferencesIronwoodActivationStore(),
);

class ChainUpgradeStatusNotifier
    extends AsyncNotifier<ChainUpgradeStatusState> {
  var _generation = 0;

  @override
  Future<ChainUpgradeStatusState> build() async {
    final generation = ++_generation;
    final endpoint = ref.watch(
      rpcEndpointFailoverProvider.select((state) => state.current),
    );
    final store = ref.watch(ironwoodActivationStoreProvider);
    if (await store.isActiveSeen(endpoint.networkName)) {
      return ChainUpgradeStatusState.cachedActive(
        endpoint,
        previous: state.value,
      );
    }
    final getChainUpgradeStatus = ref.watch(chainUpgradeStatusGetterProvider);
    final status = await getChainUpgradeStatus(
      lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
      network: endpoint.networkName,
    );
    final next = ChainUpgradeStatusState.fromLightwalletd(
      status,
      endpoint,
      previous: state.value,
    );
    if (generation != _generation && state.value != null) {
      return state.value!;
    }
    if (next.ironwoodActiveAtTip) {
      await store.markActiveSeen(endpoint.networkName);
    }
    return next;
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    final previous = state.value;
    final endpoint = ref.read(rpcEndpointFailoverProvider).current;
    if (previous == null) {
      state = const AsyncLoading();
    }
    try {
      final store = ref.read(ironwoodActivationStoreProvider);
      if (await store.isActiveSeen(endpoint.networkName)) {
        if (generation != _generation) return;
        state = AsyncData(
          ChainUpgradeStatusState.cachedActive(endpoint, previous: previous),
        );
        return;
      }
      final status = await ref.read(chainUpgradeStatusGetterProvider)(
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
      );
      if (generation != _generation) return;
      state = AsyncData(
        ChainUpgradeStatusState.fromLightwalletd(
          status,
          endpoint,
          previous: previous,
        ),
      );
      if (state.value?.ironwoodActiveAtTip ?? false) {
        await store.markActiveSeen(endpoint.networkName);
      }
    } catch (e, st) {
      if (generation != _generation) return;
      if (previous == null) {
        state = AsyncError(e, st);
      }
    }
  }

  Future<void> refreshAtTip(BigInt tipHeight) async {
    final generation = ++_generation;
    final previous = state.value;
    final endpoint = ref.read(rpcEndpointFailoverProvider).current;
    try {
      final store = ref.read(ironwoodActivationStoreProvider);
      if (await store.isActiveSeen(endpoint.networkName)) {
        if (generation != _generation) return;
        state = AsyncData(
          ChainUpgradeStatusState.cachedActive(
            endpoint,
            tipHeight: tipHeight,
            previous: previous,
          ),
        );
        return;
      }
      final status = await ref.read(chainUpgradeStatusAtHeightGetterProvider)(
        network: endpoint.networkName,
        tipHeight: tipHeight,
      );
      if (generation != _generation) return;
      state = AsyncData(
        ChainUpgradeStatusState.fromActivationStatus(
          status,
          endpoint,
          previous: previous,
        ),
      );
      if (state.value?.ironwoodActiveAtTip ?? false) {
        await store.markActiveSeen(endpoint.networkName);
      }
    } catch (e, st) {
      if (generation != _generation) return;
      if (previous == null) {
        state = AsyncError(e, st);
      }
    }
  }
}

final chainUpgradeStatusProvider =
    AsyncNotifierProvider<ChainUpgradeStatusNotifier, ChainUpgradeStatusState>(
      ChainUpgradeStatusNotifier.new,
    );
