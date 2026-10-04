import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/features/onboarding/providers/welcome_network_settings_provider.dart';
import '../src/providers/network_privacy_provider.dart';
import '../src/providers/rpc_endpoint_provider.dart';

/// Deterministic provider scope for previews and captures of the mobile
/// Welcome screen.
///
/// `MobileWelcomeScreen` reads the network route and the Welcome network
/// sheet hold. This scope pins both without touching storage, the network,
/// or Rust: the route starts at [state], the RPC endpoint is the mainnet
/// default, and the startup network sheet counts as already presented, so
/// Welcome never auto-presents it on top of the scene.
Widget mobileWelcomePreviewScope({
  required NetworkPrivacyState state,
  required Widget child,
}) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    networkPrivacyProvider.overrideWith(() => _PreviewPrivacy(state)),
    rpcEndpointProvider.overrideWith(_PreviewRpc.new),
    welcomeNetworkSettingsPresentedProvider.overrideWith(_PreviewPresented.new),
  ],
  child: child,
);

class _PreviewPresented extends WelcomeNetworkSettingsNotifier {
  @override
  bool build() => true;
}

class _PreviewPrivacy extends NetworkPrivacyNotifier {
  _PreviewPrivacy(this.initial);
  final NetworkPrivacyState initial;
  @override
  NetworkPrivacyState build() => initial;
  @override
  Future<void> setTorEnabled(bool enabled) async {
    state = enabled
        ? const NetworkPrivacyState(
            torEnabled: true,
            status: NetworkPrivacyConnectionStatus.connected,
          )
        : const NetworkPrivacyState.off();
  }
}

class _PreviewRpc extends RpcEndpointNotifier {
  @override
  RpcEndpointConfig build() => defaultRpcEndpointConfig('main');
  @override
  Future<void> setCustom(String input) async {
    state = state.copyWith(
      lightwalletdUrl: normalizeRpcEndpointUrl(input, allowDefaultPort: true),
      presetId: kCustomRpcEndpointPresetId,
    );
  }
}
