import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../main.dart' show log;
import '../app_bootstrap.dart';
import '../core/config/rpc_endpoint_config.dart';
import '../core/storage/app_secure_store.dart';
import '../rust/api/wallet.dart' as rust_wallet;
import '../services/background_sync_service.dart' as bg_sync;

class RpcEndpointNotifier extends Notifier<RpcEndpointConfig> {
  static final _store = AppSecureStore.instance;

  @override
  RpcEndpointConfig build() =>
      ref.watch(appBootstrapProvider).rpcEndpointConfig;

  Future<void> setPreset(RpcEndpointPreset preset) async {
    final normalized = normalizeRpcEndpointUrl(
      preset.url,
      allowDefaultPort: true,
    );
    await _verifyNetwork(normalized);
    await _persist(
      state.copyWith(lightwalletdUrl: normalized, presetId: preset.id),
    );
  }

  Future<void> setCustom(String input) async {
    final normalized = normalizeRpcEndpointUrl(input, allowDefaultPort: true);
    await _verifyNetwork(normalized);
    await _persist(
      state.copyWith(
        lightwalletdUrl: normalized,
        presetId: kCustomRpcEndpointPresetId,
      ),
    );
  }

  Future<void> _persist(RpcEndpointConfig next) async {
    final effectivePresetId = next.effectivePresetId;
    if (effectivePresetId == kDefaultRpcEndpointPresetId) {
      await _store.delete(kRpcEndpointUrlKey);
      await _store.writePlain(kRpcEndpointPresetKey, effectivePresetId);
    } else {
      await _store.writePlain(
        kRpcEndpointUrlKey,
        next.normalizedLightwalletdUrl,
      );
      await _store.writePlain(kRpcEndpointPresetKey, effectivePresetId);
    }
    try {
      await bg_sync.updateBackgroundSyncEndpoint(endpoint: next);
    } catch (e) {
      log('RpcEndpointNotifier: failed to update iOS endpoint mirror: $e');
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
