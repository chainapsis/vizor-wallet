import 'package:flutter/services.dart'
    show SystemMouseCursors, TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/rpc_endpoint_latency_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';

class CustomEndpointSettingsPanel extends ConsumerStatefulWidget {
  const CustomEndpointSettingsPanel({
    this.onClose,
    this.onUpdated,
    this.restartSyncAfterUpdate = true,
    this.width = 424,
    super.key,
  });

  final VoidCallback? onClose;
  final VoidCallback? onUpdated;
  final bool restartSyncAfterUpdate;
  final double width;

  @override
  ConsumerState<CustomEndpointSettingsPanel> createState() =>
      _CustomEndpointSettingsPanelState();
}

class _CustomEndpointSettingsPanelState
    extends ConsumerState<CustomEndpointSettingsPanel> {
  final _controller = TextEditingController();
  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _controller.text = rpcEndpointInputText(
      ref.read(rpcEndpointProvider).lightwalletdUrl,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _canUpdate(RpcEndpointConfig current) {
    if (_isSubmitting) return false;
    try {
      final normalized = normalizeRpcEndpointUrl(
        _controller.text,
        allowDefaultPort: true,
      );
      return normalized != current.normalizedLightwalletdUrl ||
          current.effectivePresetId != kCustomRpcEndpointPresetId;
    } on FormatException {
      return false;
    }
  }

  String? _customMessageText() {
    if (_controller.text.trim().isEmpty) return null;
    try {
      normalizeRpcEndpointUrl(_controller.text, allowDefaultPort: true);
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
      await ref.read(rpcEndpointProvider.notifier).setCustom(_controller.text);
      if (widget.restartSyncAfterUpdate) {
        await ref.read(syncProvider.notifier).restartSync();
      }
      if (!mounted) return;
      final next = ref.read(rpcEndpointProvider);
      _controller.text = rpcEndpointInputText(next.lightwalletdUrl);
      setState(() {
        _isSubmitting = false;
      });
      widget.onUpdated?.call();
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e.message;
        _isSubmitting = false;
      });
    } catch (e, st) {
      log('CustomEndpointSettingsPanel._submit: ERROR: $e\n$st');
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

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: colors.border.subtle),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints.tightFor(width: widget.width),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PanelHeader(onClose: widget.onClose),
              const SizedBox(height: AppSpacing.xs),
              CurrentEndpointText(current: current, latencyState: latencyState),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: 352,
                child: CustomEndpointForm(
                  controller: _controller,
                  messageText: _customMessageText(),
                  onChanged: (_) => setState(() {
                    _submitError = null;
                  }),
                  onSubmit: _submit,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_submitError != null) ...[
                SizedBox(
                  width: 352,
                  child: Text(
                    _submitError!,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.destructive,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              AppButton(
                onPressed: _canUpdate(current) ? _submit : null,
                variant: AppButtonVariant.primary,
                minWidth: 256,
                trailing: const AppIcon(AppIcons.chevronForward),
                child: Text(_isSubmitting ? 'Updating...' : 'Update'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Text(
              'Endpoint',
              style: AppTypography.headlineMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          if (onClose != null)
            Positioned(
              right: 0,
              child: _SmallIconButton(
                icon: AppIcons.cross,
                semanticLabel: 'Close endpoint settings',
                onTap: onClose!,
              ),
            ),
        ],
      ),
    );
  }
}

class CurrentEndpointText extends StatelessWidget {
  const CurrentEndpointText({
    required this.current,
    required this.latencyState,
    super.key,
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

class CustomEndpointForm extends StatelessWidget {
  const CustomEndpointForm({
    required this.controller,
    required this.messageText,
    required this.onChanged,
    required this.onSubmit,
    super.key,
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
                        'be able to sync with the Zcash network.\n',
                    children: [
                      TextSpan(
                        text:
                            "The wallet will show the balance from the last "
                            "time it was successfully connected. It won't "
                            'show any $kZcashDefaultCurrencyTicker you recently received.',
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

class _SmallIconButton extends StatefulWidget {
  const _SmallIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final String icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<_SmallIconButton> createState() => _SmallIconButtonState();
}

class _SmallIconButtonState extends State<_SmallIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _hovered
                    ? colors.button.ghost.bgHover
                    : colors.background.ground.withValues(alpha: 0),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: AppIcon(
                    widget.icon,
                    size: AppIconSize.medium,
                    color: colors.icon.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() {
      _hovered = hovered;
    });
  }
}
