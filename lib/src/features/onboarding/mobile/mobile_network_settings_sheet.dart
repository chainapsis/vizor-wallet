import 'package:flutter/material.dart' show Divider;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/mobile_text_field.dart';
import '../../../providers/network_privacy_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../settings/widgets/mobile/mobile_tor_control.dart';
import '../providers/welcome_network_settings_provider.dart';

Future<void> showMobileWelcomeNetworkSettings(
  BuildContext context,
  WidgetRef ref,
) async {
  if (ref.read(welcomeNetworkSettingsPresentedProvider)) return;
  final presentation = ref.read(
    welcomeNetworkSettingsPresentedProvider.notifier,
  );
  presentation.setPresented(true);
  final dismissal = ValueNotifier(
    welcomeNetworkReady(ref.read(networkPrivacyProvider)),
  );
  try {
    await showAppMobileSheet<void>(
      context: context,
      canDismiss: dismissal,
      builder: (_) => MobileNetworkSettingsSheet(
        dismissal: dismissal,
        onUpdated: () => showAppToast(context, 'Endpoint updated'),
      ),
    );
  } finally {
    dismissal.dispose();
    presentation.setPresented(false);
  }
}

class MobileNetworkSettingsSheet extends ConsumerStatefulWidget {
  const MobileNetworkSettingsSheet({
    required this.dismissal,
    this.onUpdated,
    super.key,
  });

  final ValueNotifier<bool> dismissal;
  final VoidCallback? onUpdated;

  @override
  ConsumerState<MobileNetworkSettingsSheet> createState() =>
      _MobileNetworkSettingsSheetState();
}

class _MobileNetworkSettingsSheetState
    extends ConsumerState<MobileNetworkSettingsSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _fieldRegion = GlobalKey();
  bool _submitting = false;
  bool _torRequestPending = false;
  int _torRequestGeneration = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.text = rpcEndpointInputText(
      ref.read(rpcEndpointProvider).lightwalletdUrl,
    );
    _focus.addListener(_revealInput);
    _updateDismissal();
    ref.listenManual(
      networkPrivacyProvider,
      (_, next) => _updateDismissal(next),
    );
  }

  void _revealInput() {
    if (!_focus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final field = _fieldRegion.currentContext;
      if (mounted && field != null) {
        Scrollable.ensureVisible(field, alignment: 1);
      }
    });
  }

  void _updateDismissal([NetworkPrivacyState? state]) {
    widget.dismissal.value =
        !_submitting &&
        !_torRequestPending &&
        welcomeNetworkReady(state ?? ref.read(networkPrivacyProvider));
  }

  Future<void> _requestTor(bool enabled) async {
    if (_submitting ||
        (_torRequestPending && !ref.read(networkPrivacyProvider).isBusy)) {
      return;
    }
    final generation = ++_torRequestGeneration;
    setState(() => _torRequestPending = true);
    _updateDismissal();
    try {
      await ref.read(networkPrivacyProvider.notifier).setTorEnabled(enabled);
    } finally {
      if (mounted && generation == _torRequestGeneration) {
        setState(() => _torRequestPending = false);
        _updateDismissal();
      }
    }
  }

  String? get _inputError {
    if (_controller.text.trim().isEmpty) return null;
    try {
      normalizeRpcEndpointUrl(_controller.text, allowDefaultPort: true);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  bool _canUpdate(RpcEndpointConfig current) {
    if (!widget.dismissal.value ||
        _controller.text.trim().isEmpty ||
        _inputError != null) {
      return false;
    }
    return normalizeRpcEndpointUrl(_controller.text, allowDefaultPort: true) !=
        current.normalizedLightwalletdUrl;
  }

  Future<void> _submit() async {
    if (!_canUpdate(ref.read(rpcEndpointProvider))) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    _updateDismissal();
    try {
      await ref.read(rpcEndpointProvider.notifier).setCustom(_controller.text);
      if (!mounted) return;
      setState(() => _submitting = false);
      _updateDismissal();
      // A transport change outside this sheet must not cause an unsafe pop.
      if (!widget.dismissal.value) return;
      Navigator.of(context).pop();
      widget.onUpdated?.call();
    } on FormatException catch (error) {
      _finishWithError(error.message);
    } on RpcEndpointSaveException {
      _finishWithError("Couldn't save the endpoint. Try again.");
    } catch (_) {
      _finishWithError(
        "Couldn't verify that endpoint. Check the address and try again.",
      );
    }
  }

  void _finishWithError(String message) {
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = message;
    });
    _updateDismissal();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.removeListener(_revealInput);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(networkPrivacyProvider);
    final current = ref.watch(rpcEndpointProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: widget.dismissal,
      builder: (context, canDismiss, _) => MobileNetworkSettingsContent(
        torControl: MobileTorControl(
          enabled: !_submitting && !(_torRequestPending && !state.isBusy),
          onRequest: _requestTor,
        ),
        current: current,
        controller: _controller,
        focusNode: _focus,
        fieldRegion: _fieldRegion,
        onChanged: (_) => setState(() => _error = null),
        onSubmit: _submit,
        onClose: canDismiss ? () => Navigator.of(context).pop() : null,
        canUpdate: _canUpdate(current),
        submitting: _submitting,
        transportReady: welcomeNetworkReady(state),
        error: _error ?? _inputError,
      ),
    );
  }
}

/// Presentation shared by the live editor and deterministic Widgetbook states.
class MobileNetworkSettingsContent extends StatelessWidget {
  const MobileNetworkSettingsContent({
    required this.torControl,
    required this.current,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmit,
    required this.onClose,
    required this.canUpdate,
    required this.submitting,
    required this.transportReady,
    this.fieldRegion,
    this.error,
    super.key,
  });

  final Widget torControl;
  final RpcEndpointConfig current;
  final TextEditingController controller;
  final FocusNode focusNode;
  final GlobalKey? fieldRegion;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback? onClose;
  final bool canUpdate;
  final bool submitting;
  final bool transportReady;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      title: 'Network settings',
      onClose: onClose,
      constrainBody: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  torControl,
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Divider(height: 1, color: colors.border.regular),
                  ),
                  Text(
                    'Custom endpoint',
                    style: AppTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Current: ${current.hostPort}',
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Column(
                    key: fieldRegion,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MobileTextField(
                        controller: controller,
                        focusNode: focusNode,
                        fieldKey: const ValueKey('welcome_endpoint_input'),
                        hintText: 'server.example:443',
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        enabled: !submitting,
                        onChanged: onChanged,
                        onSubmitted: (_) => onSubmit(),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Use a lightwalletd server for this wallet’s network.',
                        style: AppTypography.bodySmall.copyWith(
                          color: colors.text.secondary,
                        ),
                      ),
                      if (error case final String message) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          message,
                          style: AppTypography.bodySmall.copyWith(
                            color: colors.text.destructive,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (!transportReady) ...[
            Text(
              'Connect to Tor or turn it off before updating the endpoint.',
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppButton(
            key: const ValueKey('welcome_endpoint_update'),
            variant: AppButtonVariant.primary,
            expand: true,
            onPressed: canUpdate ? onSubmit : null,
            child: Text(submitting ? 'Checking endpoint…' : 'Update endpoint'),
          ),
        ],
      ),
    );
  }
}
