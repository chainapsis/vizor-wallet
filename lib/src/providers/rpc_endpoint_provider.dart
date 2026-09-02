import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_bootstrap.dart';
import '../core/config/rpc_endpoint_config.dart';
import '../core/storage/app_secure_store.dart';
import '../rust/api/wallet.dart' as rust_wallet;

class RpcEndpointNotifier extends Notifier<RpcEndpointConfig> {
  static final _store = AppSecureStore.instance;
  late final int _walletSessionEpoch = _store.captureWalletSessionEpoch();

  @override
  RpcEndpointConfig build() =>
      ref.watch(appBootstrapProvider).rpcEndpointConfig;

  Future<void> setPreset(RpcEndpointPreset preset) async {
    final normalized = normalizeRpcEndpointUrl(
      preset.url,
      allowDefaultPort: true,
    );
    _requireAllowedEndpoint(normalized);
    await _verifyNetwork(normalized);
    await _persist(
      state.copyWith(lightwalletdUrl: normalized, presetId: preset.id),
    );
  }

  Future<void> setCustom(String input) async {
    final normalized = normalizeRpcEndpointUrl(input, allowDefaultPort: true);
    _requireAllowedEndpoint(normalized);
    await _verifyNetwork(normalized);
    await _persist(
      state.copyWith(
        lightwalletdUrl: normalized,
        presetId: kCustomRpcEndpointPresetId,
      ),
    );
  }

  void _requireAllowedEndpoint(String lightwalletdUrl) {
    if (!isRpcEndpointAllowedForBuild(lightwalletdUrl)) {
      throw const FormatException(
        'Ironwood Masquerade uses a fixed test endpoint.',
      );
    }
  }

  Future<void> _persist(RpcEndpointConfig next) async {
    final effectivePresetId = next.effectivePresetId;
    if (effectivePresetId == kDefaultRpcEndpointPresetId) {
      await _store.deleteWalletKey(
        kRpcEndpointUrlKey,
        epoch: _walletSessionEpoch,
      );
      await _store.writeWalletPlain(
        kRpcEndpointPresetKey,
        effectivePresetId,
        epoch: _walletSessionEpoch,
      );
    } else {
      await _store.writeWalletPlain(
        kRpcEndpointUrlKey,
        next.normalizedLightwalletdUrl,
        epoch: _walletSessionEpoch,
      );
      await _store.writeWalletPlain(
        kRpcEndpointPresetKey,
        effectivePresetId,
        epoch: _walletSessionEpoch,
      );
    }
    state = next;
  }

  Future<void> _verifyNetwork(String lightwalletdUrl) async {
    final chainName = await rust_wallet.getLightwalletdChainName(
      lightwalletdUrl: lightwalletdUrl,
    );
    if (chainName != state.networkName) {
      throw FormatException(
        'Endpoint is for $chainName, but this wallet uses ${state.networkName}.',
      );
    }
  }
}

final rpcEndpointProvider =
    NotifierProvider<RpcEndpointNotifier, RpcEndpointConfig>(
      RpcEndpointNotifier.new,
    );
