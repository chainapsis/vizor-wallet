// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

import '../src/core/theme/app_theme.dart';
import '../src/core/widgets/mobile/mobile_surface_card.dart';
import '../src/features/settings/widgets/wallet_pir_server_settings.dart';
import '../src/providers/wallet_pir_server_provider.dart';
import '../src/services/wallet_pir/wallet_pir_config.dart';
import '../src/services/wallet_pir/wallet_pir_latency.dart';

// Demo fixtures only: hosts are reserved example names, never contacted.
final _source =
    'https://valargroup.github.io/wallet-pir-config/pins/demo/static.json'
    '?checksum=sha256:${'0' * 64}';
const _first = WalletPirServerOption(
  label: 'Demo server A',
  baseUrl: 'https://pir-a.example',
);
const _second = WalletPirServerOption(
  label: 'Demo server B',
  baseUrl: 'https://pir-b.example/wallet',
);

WalletPirConfigView _config(
  List<WalletPirServerOption> servers,
  WalletPirSelectionState selection, {
  String? selected,
  String? removed,
}) => WalletPirConfigView(
  scope: 'demo',
  snapshotJson: '{}',
  servers: servers,
  selectionState: selection,
  selectedBaseUrl: selected,
  removedBaseUrl: removed,
);

WalletPirServerState _state({
  WalletPirConfigView? config,
  bool refreshing = false,
  String? error,
  String? source = '',
}) => WalletPirServerState(
  source: source == '' ? _source : source,
  config: config,
  refreshing: refreshing,
  refreshError: error,
);

final _twoServers = _state(
  config: _config(
    const [_first, _second],
    WalletPirSelectionState.kept,
    selected: _first.baseUrl,
  ),
);

final _demoStates = <String, WalletPirServerState>{
  'Two servers': _twoServers,
  'Empty list': _state(
    config: _config(const [], WalletPirSelectionState.noServers),
  ),
  'Outage with last good list': _state(
    config: _config(
      const [_first, _second],
      WalletPirSelectionState.kept,
      selected: _second.baseUrl,
    ),
    error: 'Could not reach the config source',
  ),
  'Chosen server removed': _state(
    config: _config(
      const [_first],
      WalletPirSelectionState.selectionRequired,
      removed: _second.baseUrl,
    ),
  ),
  'First load failed': _state(error: 'Could not reach the config source'),
  'No server list': _state(source: null),
};

/// Desktop and mobile previews of every demo state.
WidgetbookComponent buildWalletPirServerWidgetbookComponent() =>
    WidgetbookComponent(
      name: 'Private query server',
      useCases: [
        for (final entry in _demoStates.entries) ...[
          WidgetbookUseCase(
            name: 'Desktop - ${entry.key}',
            builder: (_) => _DemoPreview(initial: entry.value, mobile: false),
          ),
          WidgetbookUseCase(
            name: 'Mobile - ${entry.key}',
            builder: (_) => _DemoPreview(initial: entry.value, mobile: true),
          ),
        ],
      ],
    );

/// Holds the preview's state locally, so picking a server or refreshing is
/// visible without any provider, storage, network or Rust.
class _DemoPreview extends StatefulWidget {
  const _DemoPreview({required this.initial, required this.mobile});

  final WalletPirServerState initial;
  final bool mobile;

  @override
  State<_DemoPreview> createState() => _DemoPreviewState();
}

class _DemoPreviewState extends State<_DemoPreview> {
  late WalletPirServerState _state = widget.initial;

  void _select(String baseUrl) {
    final config = _state.config;
    if (config == null) return;
    setState(() {
      _state = _state.copyWith(
        config: _config(
          config.servers,
          WalletPirSelectionState.kept,
          selected: baseUrl,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = WalletPirServerSettingsView(
      state: _state,
      onSelect: _select,
      pingSamples: {
        _first.baseUrl: const WalletPirPingSample.available(
          Duration(milliseconds: 42),
        ),
        _second.baseUrl: const WalletPirPingSample.available(
          Duration(milliseconds: 76),
        ),
      },
    );
    return Center(
      child: SizedBox(
        width: widget.mobile ? 375 : 560,
        child: widget.mobile
            ? MobileSurfaceCard(
                cornerRadius: AppRadii.large,
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: view,
              )
            : Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: view,
              ),
      ),
    );
  }
}
