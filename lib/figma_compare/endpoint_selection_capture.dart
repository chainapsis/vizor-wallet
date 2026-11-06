import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/app_bootstrap.dart';
import '../src/core/config/rpc_endpoint_config.dart';
import '../src/features/settings/screens/mobile/mobile_endpoint_screen.dart';
import '../src/providers/rpc_endpoint_failover_provider.dart';
import '../src/providers/rpc_endpoint_latency_provider.dart';
import '../src/providers/rpc_endpoint_provider.dart';
import '../src/providers/network_privacy_provider.dart';
import '../src/providers/sync_provider.dart';
import '../widgetbook/screen_use_cases.dart';

/// Production endpoint screens with fixed example latencies and no network I/O.
Widget buildDesktopEndpointSelectionCapture(BuildContext context) =>
    _captureScope(Builder(builder: buildSettingsEndpointUseCase));

Widget buildMobileEndpointSelectionCapture(BuildContext context) =>
    _captureScope(const MobileEndpointScreen());

Widget _captureScope(Widget child) => ProviderScope(
  overrides: [
    appBootstrapProvider.overrideWithValue(AppBootstrapState.empty),
    syncProvider.overrideWith(_CaptureSync.new),
    networkPrivacyProvider.overrideWith(_CaptureNetworkPrivacy.new),
    rpcEndpointProvider.overrideWith(_CapturePreference.new),
    rpcEndpointFailoverProvider.overrideWith(_CaptureEffectiveEndpoint.new),
    rpcEndpointLatencyProvider.overrideWith(_CaptureLatencies.new),
  ],
  child: child,
);

class _CaptureSync extends SyncNotifier {
  @override
  Future<SyncState> build() async => SyncState(percentage: 1);
}

class _CaptureNetworkPrivacy extends NetworkPrivacyNotifier {
  @override
  NetworkPrivacyState build() => const NetworkPrivacyState.off();
}

class _CapturePreference extends RpcEndpointNotifier {
  @override
  RpcEndpointConfig build() => defaultRpcEndpointConfig('main');
}

class _CaptureEffectiveEndpoint extends RpcEndpointFailoverNotifier {
  @override
  RpcEndpointFailoverState build() => RpcEndpointFailoverState(
    primary: defaultRpcEndpointConfig('main'),
    current: const RpcEndpointConfig(
      networkName: 'main',
      lightwalletdUrl: 'https://kr.zec.stardust.rest:443',
      presetId: 'kr-zec-stardust',
    ),
    fallbackCandidates: const [],
  );
}

class _CaptureLatencies extends RpcEndpointLatencyNotifier {
  @override
  RpcEndpointLatencyState build() => RpcEndpointLatencyState(
    samples: {
      for (final preset in rpcEndpointPresetsForNetwork('main'))
        if (!preset.isAutomatic)
          preset.url: RpcEndpointLatencySample.available(
            Duration(milliseconds: _exampleLatencyMs(preset.id)),
          ),
    },
  );

  @override
  Future<void> refresh(String networkName) async {}
}

int _exampleLatencyMs(String presetId) => switch (presetId) {
  'kr-zec-stardust' => 42,
  'ap-zec-rocks' => 87,
  'eu-zec-stardust' || 'eu-zec-rocks' => 213,
  'sa-zec-rocks' => 288,
  _ => 165,
};
