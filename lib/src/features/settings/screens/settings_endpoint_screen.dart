import 'package:flutter/material.dart'
    show Scrollbar, ScrollbarTheme, ScrollbarThemeData;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';

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
    final currentPreset = findRpcEndpointPresetByUrl(
      endpoint.normalizedLightwalletdUrl,
      networkName: endpoint.networkName,
    );
    _selectedPresetId = currentPreset?.id;
    if (currentPreset == null) {
      _activeTab = _EndpointTab.custom;
      _customController.text = endpoint.hostPort;
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _handleBack() {
    context.go('/settings');
  }

  void _selectTab(_EndpointTab tab) {
    if (_isSubmitting) return;
    if (tab == _EndpointTab.custom && _customController.text.trim().isEmpty) {
      _customController.text = ref.read(rpcEndpointProvider).hostPort;
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
      return normalizeRpcEndpointUrl(
            _customController.text,
            allowDefaultPort: true,
          ) !=
          current.normalizedLightwalletdUrl;
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
      setState(() {
        _selectedPresetId = findRpcEndpointPresetByUrl(
          next.normalizedLightwalletdUrl,
          networkName: next.networkName,
        )?.id;
        if (_selectedPresetId == null) {
          _customController.text = next.hostPort;
        }
        _isSubmitting = false;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e.message;
        _isSubmitting = false;
      });
    } catch (e, st) {
      log('SettingsEndpointScreen._submit: ERROR: $e\n$st');
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
    final current = ref.watch(rpcEndpointProvider);

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: _SettingsEndpointPane(
          current: current,
          activeTab: _activeTab,
          selectedPresetId: _selectedPresetId,
          customController: _customController,
          customMessageText: _customMessageText(),
          submitError: _submitError,
          isSubmitting: _isSubmitting,
          canUpdate: _canUpdate(current),
          onBack: _handleBack,
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

class _SettingsEndpointPane extends StatelessWidget {
  const _SettingsEndpointPane({
    required this.current,
    required this.activeTab,
    required this.selectedPresetId,
    required this.customController,
    required this.customMessageText,
    required this.submitError,
    required this.isSubmitting,
    required this.canUpdate,
    required this.onBack,
    required this.onSelectTab,
    required this.onSelectPreset,
    required this.onCustomChanged,
    required this.onSubmit,
  });

  final RpcEndpointConfig current;
  final _EndpointTab activeTab;
  final String? selectedPresetId;
  final TextEditingController customController;
  final String? customMessageText;
  final String? submitError;
  final bool isSubmitting;
  final bool canUpdate;
  final VoidCallback onBack;
  final ValueChanged<_EndpointTab> onSelectTab;
  final ValueChanged<String> onSelectPreset;
  final ValueChanged<String> onCustomChanged;
  final Future<void> Function() onSubmit;

  static const _widgetWidth = 352.0;
  static const _buttonWidth = 256.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _BackButton(onTap: onBack),
          ),
          const SizedBox(height: AppSpacing.s),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Endpoint',
                    textAlign: TextAlign.center,
                    style: AppTypography.displaySmall.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _CurrentEndpointText(current: current),
                  const SizedBox(height: AppSpacing.sm),
                  _EndpointSelector(
                    width: _widgetWidth,
                    current: current,
                    activeTab: activeTab,
                    selectedPresetId: selectedPresetId,
                    customController: customController,
                    customMessageText: customMessageText,
                    onSelectTab: onSelectTab,
                    onSelectPreset: onSelectPreset,
                    onCustomChanged: onCustomChanged,
                    onSubmit: onSubmit,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (submitError != null) ...[
                    SizedBox(
                      width: _widgetWidth,
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
                  AppButton(
                    onPressed: canUpdate ? onSubmit : null,
                    variant: AppButtonVariant.primary,
                    minWidth: _buttonWidth,
                    trailing: const AppIcon(AppIcons.chevronForward),
                    child: Text(isSubmitting ? 'Updating...' : 'Update'),
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

class _CurrentEndpointText extends StatelessWidget {
  const _CurrentEndpointText({required this.current});

  final RpcEndpointConfig current;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final preset = findRpcEndpointPresetByUrl(
      current.normalizedLightwalletdUrl,
      networkName: current.networkName,
    );
    final suffix = [
      if (preset?.latencyLabel != null) preset!.latencyLabel!,
      if (preset?.isDefault ?? false) '(Default)',
    ].join(' ');

    return Text.rich(
      TextSpan(
        text: 'Current: ',
        children: [
          TextSpan(
            text: current.hostPort,
            style: TextStyle(color: colors.text.brandCrimson),
          ),
          if (suffix.isNotEmpty) TextSpan(text: ' $suffix'),
        ],
      ),
      textAlign: TextAlign.center,
      style: AppTypography.bodyMedium.copyWith(color: colors.text.primary),
    );
  }
}

class _EndpointSelector extends StatelessWidget {
  const _EndpointSelector({
    required this.width,
    required this.current,
    required this.activeTab,
    required this.selectedPresetId,
    required this.customController,
    required this.customMessageText,
    required this.onSelectTab,
    required this.onSelectPreset,
    required this.onCustomChanged,
    required this.onSubmit,
  });

  final double width;
  final RpcEndpointConfig current;
  final _EndpointTab activeTab;
  final String? selectedPresetId;
  final TextEditingController customController;
  final String? customMessageText;
  final ValueChanged<_EndpointTab> onSelectTab;
  final ValueChanged<String> onSelectPreset;
  final ValueChanged<String> onCustomChanged;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: width,
      height: 395,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.xLarge),
      ),
      child: Column(
        children: [
          _EndpointTabs(activeTab: activeTab, onSelect: onSelectTab),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.background.ground,
                borderRadius: BorderRadius.circular(AppRadii.large),
              ),
              child: switch (activeTab) {
                _EndpointTab.list => _PresetList(
                  networkName: current.networkName,
                  selectedPresetId: selectedPresetId,
                  onSelect: onSelectPreset,
                ),
                _EndpointTab.custom => Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xs,
                    AppSpacing.s,
                    AppSpacing.sm,
                    AppSpacing.xs,
                  ),
                  child: _CustomEndpointForm(
                    controller: customController,
                    messageText: customMessageText,
                    onChanged: onCustomChanged,
                    onSubmit: onSubmit,
                  ),
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EndpointTabs extends StatelessWidget {
  const _EndpointTabs({required this.activeTab, required this.onSelect});

  final _EndpointTab activeTab;
  final ValueChanged<_EndpointTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: _EndpointTabButton(
              label: 'Select from list',
              selected: activeTab == _EndpointTab.list,
              onTap: () => onSelect(_EndpointTab.list),
            ),
          ),
          Expanded(
            child: _EndpointTabButton(
              label: 'Custom Endpoint',
              selected: activeTab == _EndpointTab.custom,
              onTap: () => onSelect(_EndpointTab.custom),
            ),
          ),
        ],
      ),
    );
  }
}

class _EndpointTabButton extends StatelessWidget {
  const _EndpointTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMedium.copyWith(
              color: selected ? colors.text.accent : colors.text.secondary,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetList extends StatefulWidget {
  const _PresetList({
    required this.networkName,
    required this.selectedPresetId,
    required this.onSelect,
  });

  final String networkName;
  final String? selectedPresetId;
  final ValueChanged<String> onSelect;

  @override
  State<_PresetList> createState() => _PresetListState();
}

class _PresetListState extends State<_PresetList> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final groups = <String, List<RpcEndpointPreset>>{};
    for (final preset in rpcEndpointPresetsForNetwork(widget.networkName)) {
      groups.putIfAbsent(preset.region, () => []).add(preset);
    }

    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(colors.background.overlay),
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(AppRadii.full),
        thumbVisibility: const WidgetStatePropertyAll(true),
        trackVisibility: const WidgetStatePropertyAll(false),
        crossAxisMargin: 3,
        mainAxisMargin: 3,
      ),
      child: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.s,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in groups.entries) ...[
                _PresetRegionLabel(label: entry.key),
                const SizedBox(height: AppSpacing.xs),
                for (final preset in entry.value) ...[
                  _PresetCard(
                    preset: preset,
                    selected: preset.id == widget.selectedPresetId,
                    onTap: () => widget.onSelect(preset.id),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                const SizedBox(height: AppSpacing.xs),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetRegionLabel extends StatelessWidget {
  const _PresetRegionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: context.colors.text.secondary,
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final RpcEndpointPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(
              color: selected ? colors.border.strong : colors.border.regular,
              width: selected ? 2 : 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      preset.hostPort,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    if (preset.latencyLabel != null)
                      Text(
                        preset.latencyLabel!,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelMedium.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _PresetIndicator(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetIndicator extends StatelessWidget {
  const _PresetIndicator({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: selected
            ? colors.background.inverse
            : colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: selected
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

class _CustomEndpointForm extends StatelessWidget {
  const _CustomEndpointForm({
    required this.controller,
    required this.messageText,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? messageText;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 86,
            child: AppTextField(
              label: 'Custom Endpoint',
              hintText: '<hostname>:<port>',
              controller: controller,
              autofocus: true,
              leading: const AppIcon(AppIcons.endpoint),
              leadingSlotWidth: 32,
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
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIcon(AppIcons.book, size: 20, color: colors.icon.accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text:
                        "If the endpoint is configured wrong, your wallet won't "
                        'be able to sync with Zcash blockchain.\n',
                    children: [
                      TextSpan(
                        text:
                            "The wallet will show the balance from the last "
                            "time it was successfully connected. It won't "
                            'show any ZEC you recently received.',
                        style: TextStyle(color: colors.text.primary),
                      ),
                    ],
                  ),
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                AppIcons.chevronBackward,
                size: 16,
                color: colors.icon.accent,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                'Back',
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
