import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/wallet_pir_server_provider.dart';
import '../../../providers/wallet_pir_latency_provider.dart';
import '../../../services/wallet_pir/wallet_pir_config.dart';
import '../../../services/wallet_pir/wallet_pir_latency.dart';

final walletPirConfigRepositoryUri = Uri.parse(
  'https://github.com/valargroup/wallet-pir-config',
);
final walletPirConfigRepositoryLauncherProvider =
    Provider<Future<bool> Function(Uri)>(
      (ref) =>
          (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
    );

/// The shared server picker content for desktop dialogs and mobile sheets.
class WalletPirServerSettings extends ConsumerStatefulWidget {
  const WalletPirServerSettings({this.onSelected, super.key});

  final VoidCallback? onSelected;

  @override
  ConsumerState<WalletPirServerSettings> createState() =>
      _WalletPirServerSettingsState();
}

class _WalletPirServerSettingsState
    extends ConsumerState<WalletPirServerSettings> {
  bool _selecting = false;
  String? _selectionError;
  bool _editingCustom = false;
  final _customController = TextEditingController();
  late WalletPirLatencyMonitor _ping;
  AppLifecycleListener? _pingLifecycle;
  Set<String> _pingTargets = {};
  String? _linkError;

  @override
  void initState() {
    super.initState();
    _ping = WalletPirLatencyMonitor(
      probe: (url, cancelled) =>
          ref.read(walletPirServerProbeProvider)(url, cancelled),
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _pingLifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.resumed) {
          _ping.resume();
        } else {
          _ping.pause();
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
        _ping.resume();
      }
      unawaited(
        ref.read(walletPirServerProvider.notifier).refreshAutomatically(),
      );
    });
  }

  void _updatePingTargets(WalletPirServerState state) {
    final targets = {
      for (final server in state.servers) server.baseUrl,
      if (state.customServer case final custom? when custom.isValid)
        custom.baseUrl,
    };
    if (setEquals(targets, _pingTargets)) return;
    _pingTargets = targets;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ping.updateTargets(_pingTargets);
    });
  }

  Future<void> _shareRepository() async {
    setState(() => _linkError = null);
    try {
      final opened = await ref.read(walletPirConfigRepositoryLauncherProvider)(
        walletPirConfigRepositoryUri,
      );
      if (opened) return;
    } catch (_) {}
    if (mounted) {
      setState(() => _linkError = "Couldn't open the config repository.");
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    _pingLifecycle?.dispose();
    _ping.dispose();
    super.dispose();
  }

  Future<void> _select(String baseUrl) => _runSelection(
    () => ref.read(walletPirServerProvider.notifier).selectServer(baseUrl),
  );

  Future<void> _selectCustom() => _runSelection(
    () => ref
        .read(walletPirServerProvider.notifier)
        .selectCustomServer(_customController.text),
  );

  Future<void> _runSelection(Future<void> Function() select) async {
    setState(() {
      _selecting = true;
      _selectionError = null;
    });
    try {
      await select();
      if (mounted) widget.onSelected?.call();
    } catch (_) {
      if (mounted) {
        setState(() => _selectionError = "Couldn't change server. Try again.");
      }
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  String? _customMessage() {
    if (_customController.text.trim().isEmpty) return null;
    try {
      ref
          .read(walletPirConfigResolverProvider)
          .normalizeCustomServer(_customController.text);
      return null;
    } catch (_) {
      return 'Enter an HTTPS base URL without credentials, a query or a fragment.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(walletPirServerProvider);
    final state = async.value;
    if (state == null) {
      return async.hasError
          ? WalletPirServerSettingsView.message(
              'Couldn\'t read the private query server settings.',
            )
          : const Text('Loading the server list…');
    }
    _updatePingTargets(state);
    final customMessage = _customMessage();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_selectionError != null) ...[
          Text(
            _selectionError!,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.text.destructive,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (_editingCustom) ...[
          SizedBox(
            height: 106,
            child: AppTextField(
              key: const ValueKey('wallet_pir_custom_server_input'),
              label: 'Custom server',
              hintText: 'https://pir.example',
              controller: _customController,
              enabled: !_selecting,
              autofocus: true,
              leading: const AppIcon(AppIcons.endpoint),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              messageText: customMessage,
              tone: customMessage == null
                  ? AppTextFieldTone.neutral
                  : AppTextFieldTone.destructive,
              onChanged: (_) => setState(() => _selectionError = null),
              onSubmitted: (_) {
                if (!_selecting &&
                    _customController.text.trim().isNotEmpty &&
                    customMessage == null) {
                  unawaited(_selectCustom());
                }
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                onPressed: _selecting
                    ? null
                    : () => setState(() => _editingCustom = false),
                variant: AppButtonVariant.secondary,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                key: const ValueKey('wallet_pir_custom_server_save'),
                onPressed:
                    _selecting ||
                        _customController.text.trim().isEmpty ||
                        customMessage != null
                    ? null
                    : () => unawaited(_selectCustom()),
                child: Text(
                  _selecting ? 'Updating server…' : 'Use custom server',
                ),
              ),
            ],
          ),
        ] else
          WalletPirServerSettingsView(
            state: state,
            onSelect: _selecting
                ? null
                : (baseUrl) => unawaited(_select(baseUrl)),
            pingSamples: _ping.samples,
            onCustom: _selecting || state.source == null
                ? null
                : () => setState(() {
                    _customController.text = state.customServer?.baseUrl ?? '';
                    _editingCustom = true;
                    _selectionError = null;
                  }),
          ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            key: const ValueKey('wallet_pir_share_server'),
            onPressed: _selecting ? null : () => unawaited(_shareRepository()),
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            child: const Text('Share your server'),
          ),
        ),
        if (_linkError != null)
          Text(
            _linkError!,
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
      ],
    );
  }
}

/// Renders a [WalletPirServerState]. Free of providers, so Widgetbook and
/// tests drive it directly.
class WalletPirServerSettingsView extends StatelessWidget {
  const WalletPirServerSettingsView({
    required this.state,
    required this.onSelect,
    this.onCustom,
    this.pingSamples = const {},
    super.key,
  }) : _message = null;

  const WalletPirServerSettingsView.message(String message, {super.key})
    : state = null,
      onSelect = null,
      onCustom = null,
      pingSamples = const {},
      _message = message;

  final WalletPirServerState? state;
  final ValueChanged<String>? onSelect;
  final Map<String, WalletPirPingSample> pingSamples;
  final VoidCallback? onCustom;
  final String? _message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = this.state;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.muted,
    );
    if (state == null) {
      return Text(_message ?? '', style: bodyStyle);
    }
    final status = walletPirServerStatusText(state);
    return Column(
      key: const ValueKey('wallet_pir_server_settings'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Choose a server',
          style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.xxs),
        if (status != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            status.text,
            key: const ValueKey('wallet_pir_server_status'),
            style: bodyStyle.copyWith(
              color: status.warning ? colors.text.destructive : null,
            ),
          ),
        ],
        if (state.servers.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          for (final server in state.servers) ...[
            _ServerRow(
              server: server,
              selected:
                  state.customServer == null &&
                  server.baseUrl == state.selectedBaseUrl,
              onTap: onSelect == null ? null : () => onSelect!(server.baseUrl),
              ping: pingSamples[server.baseUrl],
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
        ],
        if (state.customServer case final custom?) ...[
          _ServerRow(
            server: WalletPirServerOption(
              label: 'Custom server',
              baseUrl: custom.baseUrl,
            ),
            selected: custom.isValid,
            onTap: onCustom,
            ping: pingSamples[custom.baseUrl],
          ),
          const SizedBox(height: AppSpacing.xxs),
        ],
        if (state.source != null) ...[
          AppButton(
            key: const ValueKey('wallet_pir_custom_server_option'),
            onPressed: onCustom,
            variant: AppButtonVariant.ghost,
            trailing: const AppIcon(AppIcons.chevronForward),
            child: Text(
              state.customServer == null
                  ? 'Custom server…'
                  : 'Edit custom server…',
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

/// The one status line under the source, in everyday words. `null` when
/// everything is in order.
({String text, bool warning})? walletPirServerStatusText(
  WalletPirServerState state,
) {
  if (state.source == null) {
    return (
      text: 'Private queries are unavailable on this network.',
      warning: true,
    );
  }
  if (state.customServer case final custom?) {
    if (!custom.isValid) {
      return (
        text:
            'The saved custom server is invalid. Edit it or choose another server.',
        warning: true,
      );
    }
    return state.refreshError == null
        ? null
        : (
            text:
                "Couldn't update the list. Your custom server is still selected.",
            warning: true,
          );
  }
  if (state.refreshing && state.config == null) {
    return (text: 'Loading the server list…', warning: false);
  }
  final error = state.refreshError;
  if (state.config == null) {
    return error == null
        ? (text: 'Loading the server list…', warning: false)
        : (
            text:
                'Couldn\'t load the server list. Try again or enter a custom server.',
            warning: true,
          );
  }
  if (state.needsSelection) {
    return (
      text:
          'The server you chose is no longer offered. Choose another to '
          'resume private queries.',
      warning: true,
    );
  }
  if (state.hasNoServers) {
    return (
      text: 'No servers are offered yet. You can enter a custom server.',
      warning: true,
    );
  }
  if (error != null) {
    return (
      text: 'Couldn\'t update the server list. Using the last list loaded.',
      warning: true,
    );
  }
  if (state.refreshing) {
    return (text: 'Checking for updates…', warning: false);
  }
  return null;
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.selected,
    required this.onTap,
    this.ping,
  });

  final WalletPirServerOption server;
  final bool selected;
  final VoidCallback? onTap;
  final WalletPirPingSample? ping;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final address = server.baseUrl.replaceFirst('https://', '');
    return Semantics(
      button: true,
      selected: selected,
      label: server.label,
      child: MouseRegion(
        cursor: onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('wallet_pir_server_option_${server.baseUrl}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? colors.background.raised : colors.surface.card,
              borderRadius: BorderRadius.circular(AppRadii.small),
              border: Border.all(
                color: selected ? colors.border.medium : colors.border.subtle,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Row(
                children: [
                  _SelectionDot(selected: selected),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                        Text(
                          address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: colors.text.muted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ping?.label ?? 'Checking...',
                          key: ValueKey(
                            'wallet_pir_server_ping_${server.baseUrl}',
                          ),
                          style: AppTypography.labelMedium.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.icon.brandCrimson : colors.background.ground,
        border: Border.all(
          color: selected ? colors.icon.brandCrimson : colors.border.medium,
        ),
      ),
      child: SizedBox.square(
        dimension: 20,
        child: Center(
          child: selected
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.background.ground,
                  ),
                  child: const SizedBox.square(dimension: 8),
                )
              : null,
        ),
      ),
    );
  }
}
