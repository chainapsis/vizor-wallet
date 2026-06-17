import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../main.dart' show log;
import '../../../../core/config/rpc_endpoint_config.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile_text_field.dart';
import '../../../../providers/rpc_endpoint_latency_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/sync_provider.dart';

enum _EndpointTab { list, custom }

/// Mobile endpoint settings — Figma `Endpoints` (4494:67671 list /
/// 4494:86583 custom): preset cards grouped by region with the live
/// latency line, or a custom host:port behind the second tab. Same
/// state machine as the desktop screen; only the layout differs.
class MobileEndpointScreen extends ConsumerStatefulWidget {
  const MobileEndpointScreen({super.key});

  @override
  ConsumerState<MobileEndpointScreen> createState() =>
      _MobileEndpointScreenState();
}

class _MobileEndpointScreenState extends ConsumerState<MobileEndpointScreen> {
  static const _floatingCtaClearance = AppSpacing.xl2 + AppSpacing.md;

  final _customController = TextEditingController();
  final _customFocusNode = FocusNode();
  _EndpointTab _activeTab = _EndpointTab.list;
  String? _selectedPresetId;
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    final endpoint = ref.read(rpcEndpointProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(rpcEndpointLatencyProvider.notifier)
          .refresh(endpoint.networkName);
    });
    final currentPreset = explicitRpcEndpointPresetFor(endpoint);
    _selectedPresetId = currentPreset?.id;
    if (currentPreset == null) {
      _activeTab = _EndpointTab.custom;
      _customController.text = rpcEndpointInputText(endpoint.lightwalletdUrl);
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    _customFocusNode.dispose();
    super.dispose();
  }

  void _selectTab(_EndpointTab tab) {
    if (_isSubmitting || _activeTab == tab) return;
    if (tab == _EndpointTab.custom && _customController.text.trim().isEmpty) {
      final endpoint = ref.read(rpcEndpointProvider);
      _customController.text = rpcEndpointInputText(endpoint.lightwalletdUrl);
    }
    setState(() {
      _activeTab = tab;
      _submitError = null;
    });
  }

  bool _canUpdate(RpcEndpointConfig current) {
    if (_isSubmitting) return false;
    return switch (_activeTab) {
      _EndpointTab.list =>
        _selectedPresetId != null &&
            findRpcEndpointPresetById(
                  current.networkName,
                  _selectedPresetId!,
                ) !=
                null &&
            _selectedPresetId != current.effectivePresetId,
      _EndpointTab.custom => _customEndpointChanged(current),
    };
  }

  bool _customEndpointChanged(RpcEndpointConfig current) {
    try {
      final normalized = normalizeRpcEndpointUrl(
        _customController.text,
        allowDefaultPort: true,
      );
      return normalized != current.normalizedLightwalletdUrl ||
          current.effectivePresetId != kCustomRpcEndpointPresetId;
    } on FormatException {
      return false;
    }
  }

  String? _customMessageText() {
    if (_customController.text.trim().isEmpty) return null;
    try {
      normalizeRpcEndpointUrl(_customController.text, allowDefaultPort: true);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  Future<void> _submit() async {
    final current = ref.read(rpcEndpointProvider);
    if (!_canUpdate(current)) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final notifier = ref.read(rpcEndpointProvider.notifier);
      if (_activeTab == _EndpointTab.list) {
        final preset = findRpcEndpointPresetById(
          current.networkName,
          _selectedPresetId!,
        );
        if (preset == null) {
          throw const FormatException('Select an endpoint.');
        }
        await notifier.setPreset(preset);
      } else {
        await notifier.setCustom(_customController.text);
      }
      await ref.read(syncProvider.notifier).restartSync();
      if (!mounted) return;
      final next = ref.read(rpcEndpointProvider);
      ref.read(rpcEndpointLatencyProvider.notifier).refresh(next.networkName);
      setState(() {
        _selectedPresetId = explicitRpcEndpointPresetFor(next)?.id;
        if (_selectedPresetId == null) {
          _customController.text = rpcEndpointInputText(next.lightwalletdUrl);
        }
        _isSubmitting = false;
      });
      showAppToast(context, 'Endpoint updated');
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e.message;
        _isSubmitting = false;
      });
    } catch (e, st) {
      log('MobileEndpointScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitError =
            "Couldn't connect to that endpoint. Check the host and port.";
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final current = ref.watch(rpcEndpointProvider);
    final latencyState = ref.watch(rpcEndpointLatencyProvider);

    return Scaffold(
      backgroundColor: colors.background.window,
      body: AppToastHost(
        child: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: 'Endpoints',
                onBack: _isSubmitting ? null : () => context.pop(),
              ),
              const SizedBox(height: AppSpacing.xs),
              _MobileCurrentEndpointText(
                current: current,
                latencyState: latencyState,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: _ModeTab(
                      key: const ValueKey('mobile_endpoint_tab_list'),
                      iconName: AppIcons.endpoint,
                      label: 'Select from the list',
                      selected: _activeTab == _EndpointTab.list,
                      alignment: Alignment.centerRight,
                      onTap: () => _selectTab(_EndpointTab.list),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _ModeTab(
                      key: const ValueKey('mobile_endpoint_tab_custom'),
                      iconName: AppIcons.edit,
                      label: 'Custom endpoint',
                      selected: _activeTab == _EndpointTab.custom,
                      alignment: Alignment.centerLeft,
                      onTap: () => _selectTab(_EndpointTab.custom),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s),
              if (_submitError != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Text(
                    _submitError!,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.destructive,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              Expanded(
                child: switch (_activeTab) {
                  _EndpointTab.list => Stack(
                    children: [
                      Positioned.fill(
                        child: _buildPresetList(current, latencyState),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 112,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  colors.background.window.withValues(alpha: 0),
                                  colors.background.window,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.sm,
                        right: AppSpacing.sm,
                        bottom: AppSpacing.s,
                        child: Center(
                          child: AppButton(
                            key: const ValueKey('mobile_endpoint_update'),
                            onPressed: _canUpdate(current) ? _submit : null,
                            child: Text(
                              _isSubmitting ? 'Updating...' : 'Update endpoint',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  _EndpointTab.custom => _buildCustomForm(colors, current),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPresetList(
    RpcEndpointConfig current,
    RpcEndpointLatencyState latencyState,
  ) {
    final colors = context.colors;
    final groups = <String, List<RpcEndpointPreset>>{};
    for (final preset in rpcEndpointPresetsForNetwork(current.networkName)) {
      groups.putIfAbsent(preset.region, () => []).add(preset);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        _floatingCtaClearance,
      ),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xxs,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              entry.key,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          for (final preset in entry.value) ...[
            _PresetCard(
              key: ValueKey('mobile_endpoint_preset_${preset.id}'),
              preset: preset,
              latencyLabel: latencyState.sampleForUrl(preset.url)?.label,
              selected: preset.id == _selectedPresetId,
              onTap: _isSubmitting
                  ? null
                  : () => setState(() {
                      _selectedPresetId = preset.id;
                      _submitError = null;
                    }),
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          const SizedBox(height: AppSpacing.s),
        ],
      ],
    );
  }

  Widget _buildCustomForm(AppColors colors, RpcEndpointConfig current) {
    final customMessage = _customMessageText();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      children: [
        // Dark hero card with the host:port field — Figma `Custom
        // endpoint` card (4083:457541): 200 high with the faded
        // castle-library line art along the bottom edge.
        Container(
          key: const ValueKey('mobile_endpoint_custom_card'),
          height: 200,
          decoration: BoxDecoration(
            color: colors.background.homeCard,
            borderRadius: BorderRadius.circular(AppRadii.large),
            border: Border.all(color: colors.border.subtleOpacity, width: 1.5),
            image: const DecorationImage(
              image: AssetImage('assets/illustrations/endpoint_custom_bg.png'),
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
            ),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.sm,
                  AppSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Custom endpoint',
                      style: AppTypography.displaySmall.copyWith(
                        color: colors.text.homeCard,
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MobileTextField(
                          key: const ValueKey(
                            'mobile_endpoint_custom_field_shell',
                          ),
                          fieldKey: const ValueKey(
                            'mobile_endpoint_custom_field',
                          ),
                          hintText: '<hostname>:<port>',
                          controller: _customController,
                          focusNode: _customFocusNode,
                          backgroundColor: colors.background.ground,
                          restingBorderColor: colors.border.subtle,
                          textStyle: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.w400,
                            color: colors.text.accent,
                          ),
                          hintStyle: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.w400,
                            color: colors.text.muted,
                          ),
                          onChanged: (_) => setState(() => _submitError = null),
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: Opacity(
                  opacity: 0.5,
                  child: AppIcon(
                    AppIcons.endpoint,
                    size: 32,
                    color: colors.text.homeCard,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (customMessage != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            customMessage,
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.destructive,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxs),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(AppIcons.book, size: 20, color: colors.icon.accent),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "If the endpoint is configured wrong, your wallet won't be able "
                'to sync with the Zcash blockchain.',
                style: AppTypography.bodyMediumStrong.copyWith(
                  color: colors.text.accent,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The wallet will show the balance from the last time it was '
                "successfully connected. It won't show any ZEC you recently "
                'received.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Center(
          child: AppButton(
            key: const ValueKey('mobile_endpoint_update'),
            minWidth: 226,
            onPressed: _canUpdate(current) ? _submit : null,
            child: Text(_isSubmitting ? 'Updating...' : 'Customise endpoint'),
          ),
        ),
      ],
    );
  }
}

/// One side of the list / custom toggle (same shape as the import
/// birthday mode tabs).
class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.iconName,
    required this.label,
    required this.selected,
    required this.onTap,
    this.alignment = Alignment.center,
    super.key,
  });

  final String iconName;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = selected
        ? colors.text.accent
        : colors.text.accent.withValues(alpha: 0.5);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: 2,
            ),
            child: SizedBox(
              height: 28,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(iconName, size: AppIconSize.medium, color: color),
                  const SizedBox(width: AppSpacing.xxs),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (selected
                                  ? AppTypography.bodyMediumStrong
                                  : AppTypography.bodyMedium)
                              .copyWith(color: color),
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

class _MobileCurrentEndpointText extends StatelessWidget {
  const _MobileCurrentEndpointText({
    required this.current,
    required this.latencyState,
  });

  final RpcEndpointConfig current;
  final RpcEndpointLatencyState latencyState;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final preset = findRpcEndpointPresetByUrl(
      current.normalizedLightwalletdUrl,
      networkName: current.networkName,
    );
    final latency = latencyState.sampleForUrl(
      current.normalizedLightwalletdUrl,
    );
    final suffix = [
      if (latency != null) latency.label,
      if (preset?.isDefault ?? false) '(Default)',
    ].join(' ');

    return Text.rich(
      TextSpan(
        text: 'Current: ',
        style: AppTypography.labelMedium.copyWith(
          fontWeight: FontWeight.w500,
          color: colors.text.primary,
        ),
        children: [
          TextSpan(
            text: current.hostPort,
            style: AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w400,
              color: colors.text.accent,
            ),
          ),
          if (suffix.isNotEmpty)
            TextSpan(
              text: ' $suffix',
              style: AppTypography.labelMedium.copyWith(
                fontWeight: FontWeight.w500,
                color: colors.text.primary,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// White endpoint card with the selection radio — Figma preset row.
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.latencyLabel,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final RpcEndpointPreset preset;
  final String? latencyLabel;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final titleStyle = AppTypography.labelMedium.copyWith(
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
      color: colors.text.accent,
    );
    final detailStyle = AppTypography.labelMedium.copyWith(
      fontWeight: FontWeight.w400,
      color: selected ? colors.text.accent : colors.text.secondary,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: preset.hostPort,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.xxs,
            AppSpacing.s,
            AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: selected
                ? Border.all(color: colors.border.strong, width: 2)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: Opacity(
                    opacity: selected ? 1 : 0.5,
                    child: AppIcon(
                      AppIcons.endpoint,
                      size: 20,
                      color: colors.icon.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.hostPort,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      if (latencyLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          latencyLabel!,
                          overflow: TextOverflow.ellipsis,
                          style: detailStyle,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (selected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colors.background.inverse,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: AppIcon(
                      AppIcons.check,
                      size: 14,
                      color: colors.text.inverse,
                    ),
                  ),
                )
              else
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.background.raised,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
