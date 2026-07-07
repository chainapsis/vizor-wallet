import 'package:flutter/services.dart' show TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_floating_bar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/rpc_endpoint_latency_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../../l10n/app_localizations.dart';

class SettingsEndpointScreen extends ConsumerStatefulWidget {
  const SettingsEndpointScreen({super.key});

  @override
  ConsumerState<SettingsEndpointScreen> createState() =>
      _SettingsEndpointScreenState();
}

enum _EndpointTab { list, custom }

class _SettingsEndpointScreenState
    extends ConsumerState<SettingsEndpointScreen> {
  final _customController = TextEditingController();
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
    super.dispose();
  }

  void _selectTab(_EndpointTab tab) {
    if (_isSubmitting) return;
    if (tab == _EndpointTab.custom && _customController.text.trim().isEmpty) {
      final endpoint = ref.read(rpcEndpointProvider);
      _customController.text = rpcEndpointInputText(endpoint.lightwalletdUrl);
    }
    setState(() {
      _activeTab = tab;
      _submitError = null;
    });
  }

  void _selectPreset(String id) {
    if (_isSubmitting) return;
    setState(() {
      _selectedPresetId = id;
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
    if (_activeTab != _EndpointTab.custom) return null;
    if (_customController.text.trim().isEmpty) return null;
    try {
      normalizeRpcEndpointUrl(_customController.text, allowDefaultPort: true);
      return null;
    } on FormatException catch (e) {
      return localizedRpcEndpointFormatMessage(e, AppLocalizations.of(context));
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
          throw FormatException(AppLocalizations.of(context).endpointSelectAnEndpoint);
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
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = localizedRpcEndpointFormatMessage(
          e,
          AppLocalizations.of(context),
        );
        _isSubmitting = false;
      });
    } catch (e, st) {
      log('SettingsEndpointScreen._submit: ERROR: $e\n$st');
      if (!mounted) return;
      setState(() {
        _submitError =
            AppLocalizations.of(context).endpointConnectFailed;
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(rpcEndpointProvider);
    final latencyState = ref.watch(rpcEndpointLatencyProvider);

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: _SettingsEndpointPane(
          current: current,
          latencyState: latencyState,
          activeTab: _activeTab,
          selectedPresetId: _selectedPresetId,
          customController: _customController,
          customMessageText: _customMessageText(),
          submitError: _submitError,
          isSubmitting: _isSubmitting,
          canUpdate: _canUpdate(current),
          onSelectTab: _selectTab,
          onSelectPreset: _selectPreset,
          onCustomChanged: (_) => setState(() {
            _submitError = null;
          }),
          onSubmit: _submit,
        ),
      ),
    );
  }
}

class _SettingsEndpointPane extends StatefulWidget {
  const _SettingsEndpointPane({
    required this.current,
    required this.latencyState,
    required this.activeTab,
    required this.selectedPresetId,
    required this.customController,
    required this.customMessageText,
    required this.submitError,
    required this.isSubmitting,
    required this.canUpdate,
    required this.onSelectTab,
    required this.onSelectPreset,
    required this.onCustomChanged,
    required this.onSubmit,
  });

  final RpcEndpointConfig current;
  final RpcEndpointLatencyState latencyState;
  final _EndpointTab activeTab;
  final String? selectedPresetId;
  final TextEditingController customController;
  final String? customMessageText;
  final String? submitError;
  final bool isSubmitting;
  final bool canUpdate;
  final ValueChanged<_EndpointTab> onSelectTab;
  final ValueChanged<String> onSelectPreset;
  final ValueChanged<String> onCustomChanged;
  final Future<void> Function() onSubmit;

  @override
  State<_SettingsEndpointPane> createState() => _SettingsEndpointPaneState();
}

class _SettingsEndpointPaneState extends State<_SettingsEndpointPane> {
  static const _contentWidth = 420.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final showFloatingBar =
        widget.activeTab == _EndpointTab.list &&
        (widget.canUpdate || widget.isSubmitting || widget.submitError != null);

    return AppPaneFloatingBar(
      visible: showFloatingBar,
      // The scrim box is the 420 content column in the design, not the full
      // pane width.
      overlayWidth: _contentWidth,
      bar: _FloatingUpdateBar(
        submitError: widget.submitError,
        isSubmitting: widget.isSubmitting,
        canUpdate: widget.canUpdate,
        showButton: widget.canUpdate || widget.isSubmitting,
        onSubmit: widget.onSubmit,
      ),
      builder: (context, bottomReserve) => AppPaneScrollScaffold(
        toolbar: const AppPaneToolbar(backLinkMinWidth: 60),
        padding: EdgeInsets.only(bottom: bottomReserve),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: _contentWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppLocalizations.of(context).settingsEndpoint,
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  _CurrentEndpointSubtitle(
                    current: widget.current,
                    latencyState: widget.latencyState,
                  ),
                  const SizedBox(height: AppSpacing.base),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _EndpointTabs(
                          activeTab: widget.activeTab,
                          onSelect: widget.onSelectTab,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        switch (widget.activeTab) {
                          _EndpointTab.list => _PresetList(
                            networkName: widget.current.networkName,
                            latencyState: widget.latencyState,
                            currentPresetId: widget.current.effectivePresetId,
                            pendingPresetId: widget.selectedPresetId,
                            onSelect: widget.onSelectPreset,
                          ),
                          _EndpointTab.custom => _CustomEndpointTab(
                            controller: widget.customController,
                            messageText: widget.customMessageText,
                            submitError: widget.submitError,
                            isSubmitting: widget.isSubmitting,
                            canUpdate: widget.canUpdate,
                            onChanged: widget.onCustomChanged,
                            onSubmit: widget.onSubmit,
                          ),
                        },
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

class _CurrentEndpointSubtitle extends StatelessWidget {
  const _CurrentEndpointSubtitle({
    required this.current,
    required this.latencyState,
  });

  final RpcEndpointConfig current;
  final RpcEndpointLatencyState latencyState;

  @override
  Widget build(BuildContext context) {
    final preset = findRpcEndpointPresetByUrl(
      current.normalizedLightwalletdUrl,
      networkName: current.networkName,
    );
    final latency = latencyState.sampleForUrl(
      current.normalizedLightwalletdUrl,
    );
    final text = [
      '${AppLocalizations.of(context).endpointCurrentPrefix}${current.hostPort}',
      if (latency != null) latency.label(AppLocalizations.of(context)),
      if (preset?.isDefault ?? false) AppLocalizations.of(context).endpointDefaultSuffix,
    ].join(' ');

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: AppTypography.labelLarge.copyWith(
        color: context.colors.text.accent,
      ),
    );
  }
}

class _EndpointTabs extends StatelessWidget {
  const _EndpointTabs({required this.activeTab, required this.onSelect});

  static const _width = 304.0;

  final _EndpointTab activeTab;
  final ValueChanged<_EndpointTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: _width,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _EndpointTabButton(
              label: AppLocalizations.of(context).endpointSelectFromList,
              icon: AppIcons.endpoint,
              selected: activeTab == _EndpointTab.list,
              onTap: () => onSelect(_EndpointTab.list),
            ),
            const SizedBox(width: AppSpacing.xs),
            _EndpointTabButton(
              label: AppLocalizations.of(context).endpointCustomEndpoint,
              icon: AppIcons.edit,
              selected: activeTab == _EndpointTab.custom,
              onTap: () => onSelect(_EndpointTab.custom),
            ),
          ],
        ),
      ),
    );
  }
}

class _EndpointTabButton extends StatelessWidget {
  const _EndpointTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelStyle = selected
        ? AppTypography.bodyMediumStrong
        : AppTypography.bodyMedium;
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxs,
        vertical: 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 16, color: colors.icon.accent),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle.copyWith(color: colors.text.accent),
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: selected ? content : Opacity(opacity: 0.5, child: content),
      ),
    );
  }
}

class _PresetList extends StatelessWidget {
  const _PresetList({
    required this.networkName,
    required this.latencyState,
    required this.currentPresetId,
    required this.pendingPresetId,
    required this.onSelect,
  });

  final String networkName;
  final RpcEndpointLatencyState latencyState;
  final String currentPresetId;
  final String? pendingPresetId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<RpcEndpointPreset>>{};
    for (final preset in rpcEndpointPresetsForNetwork(networkName)) {
      groups.putIfAbsent(preset.region, () => []).add(preset);
    }
    final entries = groups.entries.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          _PresetRegionSegment(
            label: localizedRpcEndpointRegion(
              entries[i].key,
              AppLocalizations.of(context),
            ),
            presets: entries[i].value,
            latencyState: latencyState,
            currentPresetId: currentPresetId,
            pendingPresetId: pendingPresetId,
            onSelect: onSelect,
          ),
          if (i != entries.length - 1) const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _PresetRegionSegment extends StatelessWidget {
  const _PresetRegionSegment({
    required this.label,
    required this.presets,
    required this.latencyState,
    required this.currentPresetId,
    required this.pendingPresetId,
    required this.onSelect,
  });

  final String label;
  final List<RpcEndpointPreset> presets;
  final RpcEndpointLatencyState latencyState;
  final String currentPresetId;
  final String? pendingPresetId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.secondary,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        for (var i = 0; i < presets.length; i++) ...[
          _PresetCard(
            preset: presets[i],
            latency: latencyState.sampleForUrl(presets[i].url),
            isCurrent: presets[i].id == currentPresetId,
            isSelected: presets[i].id == pendingPresetId,
            onTap: () => onSelect(presets[i].id),
          ),
          if (i != presets.length - 1) const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.latency,
    required this.isCurrent,
    required this.isSelected,
    required this.onTap,
  });

  final RpcEndpointPreset preset;
  final RpcEndpointLatencySample? latency;

  /// Currently applied endpoint (`current.effectivePresetId`).
  final bool isCurrent;

  /// Pending user selection (`_selectedPresetId`).
  final bool isSelected;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bordered = isCurrent || isSelected;
    // Current card demotes to the regular border while a different row is
    // the pending selection.
    final borderColor = isCurrent && !isSelected
        ? colors.border.regular
        : colors.border.strong;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.xxs,
            AppSpacing.s,
            AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: colors.background.ground,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            boxShadow: bordered
                ? _selectedPresetCardShadow(colors)
                : _presetCardShadow(colors),
          ),
          foregroundDecoration: bordered
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                  border: Border.all(
                    color: borderColor,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignInside,
                  ),
                )
              : null,
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.hostPort,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelMedium.copyWith(
                          color: colors.text.accent,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      if (latency != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          latency!.label(AppLocalizations.of(context)),
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelMedium.copyWith(
                            color: isCurrent
                                ? colors.text.accent
                                : colors.text.secondary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              _PresetIndicator(isCurrent: isCurrent),
            ],
          ),
        ),
      ),
    );
  }
}

List<BoxShadow> _presetCardShadow(AppColors colors) {
  return [
    BoxShadow(color: colors.shadows.subtle, blurRadius: 0.5),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 2),
      blurRadius: 2,
    ),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 1),
      blurRadius: 1,
    ),
    BoxShadow(color: colors.shadows.subtle, blurRadius: 0.5),
  ];
}

List<BoxShadow> _selectedPresetCardShadow(AppColors colors) {
  return [
    BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 2),
      blurRadius: 4,
    ),
    BoxShadow(
      color: colors.shadows.subtle,
      offset: const Offset(0, 1),
      blurRadius: 2,
    ),
    BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
  ];
}

class _PresetIndicator extends StatelessWidget {
  const _PresetIndicator({required this.isCurrent});

  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: isCurrent
            ? colors.background.inverse
            : colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: isCurrent
          ? Center(
              child: AppIcon(
                AppIcons.check,
                size: 12,
                color: colors.background.ground,
              ),
            )
          : null,
    );
  }
}

class _FloatingUpdateBar extends StatelessWidget {
  const _FloatingUpdateBar({
    required this.submitError,
    required this.isSubmitting,
    required this.canUpdate,
    required this.showButton,
    required this.onSubmit,
  });

  final String? submitError;
  final bool isSubmitting;
  final bool canUpdate;
  final bool showButton;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (submitError != null) ...[
          SizedBox(
            width: 396,
            child: Text(
              submitError!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.destructive,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (showButton)
          AppButton(
            onPressed: canUpdate ? onSubmit : null,
            variant: AppButtonVariant.primary,
            minWidth: 196,
            child: Text(
              isSubmitting
                  ? AppLocalizations.of(context).endpointUpdating
                  : AppLocalizations.of(context).endpointUpdateEndpoint,
            ),
          ),
      ],
    );
  }
}

class _CustomEndpointTab extends StatelessWidget {
  const _CustomEndpointTab({
    required this.controller,
    required this.messageText,
    required this.submitError,
    required this.isSubmitting,
    required this.canUpdate,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? messageText;
  final String? submitError;
  final bool isSubmitting;
  final bool canUpdate;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CustomEndpointHeroCard(
          controller: controller,
          messageText: messageText,
          onChanged: onChanged,
          onSubmit: onSubmit,
        ),
        const SizedBox(height: AppSpacing.xxs),
        const _CustomEndpointInfo(),
        const SizedBox(height: AppSpacing.xxs),
        if (submitError != null) ...[
          Text(
            submitError!,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.destructive,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Center(
          child: AppButton(
            onPressed: canUpdate ? onSubmit : null,
            variant: AppButtonVariant.primary,
            minWidth: 196,
            child: Text(
              isSubmitting
                  ? AppLocalizations.of(context).endpointUpdating
                  : AppLocalizations.of(context).endpointCustomizeEndpoint,
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomEndpointHeroCard extends StatelessWidget {
  const _CustomEndpointHeroCard({
    required this.controller,
    required this.messageText,
    required this.onChanged,
    required this.onSubmit,
  });

  static const _height = 200.0;

  // Figma: 1.5px rgba(255,255,255,0.07) in both modes — no semantic token.
  static const _borderColor = Color(0x12FFFFFF);

  // Export of Figma node 4083:457542 with the design's 30% art opacity and
  // the bottom gradient to #1B1F1F baked in — drawn as-is, no code overlay.
  static const _backgroundAsset =
      'assets/illustrations/settings_endpoint_custom_bg.png';

  final TextEditingController controller;
  final String? messageText;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      height: _height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: _borderColor, width: 1.5),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              _backgroundAsset,
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
            ),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: AppIcon(
              AppIcons.endpoint,
              size: 32,
              color: colors.text.homeCard.withValues(alpha: 0.5),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).endpointCustomEndpoint,
                    style: AppTypography.headlineLarge.copyWith(
                      color: colors.text.homeCard,
                    ),
                  ),
                  const Spacer(),
                  _CustomEndpointField(
                    controller: controller,
                    messageText: messageText,
                    onChanged: onChanged,
                    onSubmit: onSubmit,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomEndpointField extends StatelessWidget {
  const _CustomEndpointField({
    required this.controller,
    required this.messageText,
    required this.onChanged,
    required this.onSubmit,
  });

  // Input shell (46) + 4 gap + reserved 16px message line.
  static const _height = 66.0;

  final TextEditingController controller;
  final String? messageText;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox(
      height: _height,
      child: AppTextField(
        label: AppLocalizations.of(context).endpointCustomEndpoint,
        showLabel: false,
        hintText: AppLocalizations.of(context).endpointHostPortHint,
        hintStyle: AppTypography.labelMedium.copyWith(
          fontWeight: FontWeight.w400,
          color: colors.text.muted,
        ),
        controller: controller,
        autofocus: true,
        trailingSlotWidth: 40,
        inputHorizontalPadding: AppSpacing.s,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.done,
        messageText: messageText,
        tone: messageText == null
            ? AppTextFieldTone.neutral
            : AppTextFieldTone.destructive,
        onChanged: onChanged,
        onSubmitted: (_) => onSubmit(),
      ),
    );
  }
}

class _CustomEndpointInfo extends StatelessWidget {
  const _CustomEndpointInfo();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.book, size: 20, color: colors.icon.accent),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppLocalizations.of(context).endpointMisconfiguredNetwork,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            AppLocalizations.of(context).endpointStaleBalanceWarning(kZcashDefaultCurrencyTicker),
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
        ],
      ),
    );
  }
}
