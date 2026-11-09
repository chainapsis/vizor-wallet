import 'package:flutter/material.dart' show Divider;
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/mobile_text_field.dart';
import '../../../providers/network_privacy_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../settings/widgets/mobile/mobile_private_queries_control.dart';
import '../../settings/widgets/mobile/mobile_tor_control.dart';
import '../../settings/widgets/private_queries_turn_off.dart';
import '../providers/welcome_network_settings_provider.dart';
import '../shared/onboarding_error_messages.dart';

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
    welcomeNetworkReady(ref.read(networkPrivacyProvider)) &&
        ref.read(enhancePirTransitionProvider) != EnhancePirTransition.changing,
  );
  try {
    await showAppMobileSheet<void>(
      context: context,
      canDismiss: dismissal,
      builder: (_) => MobileNetworkSettingsSheet(
        dismissal: dismissal,
        onUpdated: () => showAppToast(context, context.l10n.endpointUpdated),
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
  bool _privateQueriesRequestPending = false;
  int _torRequestGeneration = 0;
  OnboardingSubmitError? _error;

  @override
  void initState() {
    super.initState();
    final endpoint = ref.read(rpcEndpointProvider);
    if (!isAutomaticRpcEndpointConfig(endpoint)) {
      _controller.text = rpcEndpointInputText(endpoint.lightwalletdUrl);
    }
    _focus.addListener(_revealInput);
    _updateDismissal();
    ref.listenManual(
      networkPrivacyProvider,
      (_, next) => _updateDismissal(next),
    );
    ref.listenManual(
      enhancePirTransitionProvider,
      (_, _) => _updateDismissal(),
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
        !_privateQueriesRequestPending &&
        !_changingPrivateQueries &&
        welcomeNetworkReady(state ?? ref.read(networkPrivacyProvider));
  }

  bool get _changingPrivateQueries =>
      ref.read(enhancePirTransitionProvider) == EnhancePirTransition.changing;

  Future<void> _requestPrivateQueries() async {
    if (_submitting ||
        _torRequestPending ||
        _privateQueriesRequestPending ||
        _changingPrivateQueries ||
        ref.read(networkPrivacyProvider).isBusy) {
      return;
    }
    setState(() => _privateQueriesRequestPending = true);
    _updateDismissal();
    try {
      await togglePrivateQueries(context, ref);
    } finally {
      if (mounted) {
        setState(() => _privateQueriesRequestPending = false);
        _updateDismissal();
      }
    }
  }

  Future<void> _requestTor(bool enabled) async {
    if (_submitting ||
        _privateQueriesRequestPending ||
        _changingPrivateQueries ||
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
      return rpcEndpointErrorText(context.l10n, error);
    }
  }

  bool _canUpdate(RpcEndpointConfig current) {
    if (!widget.dismissal.value ||
        _controller.text.trim().isEmpty ||
        _inputError != null) {
      return false;
    }
    return normalizeRpcEndpointUrl(_controller.text, allowDefaultPort: true) !=
            current.normalizedLightwalletdUrl ||
        current.effectivePresetId != kCustomRpcEndpointPresetId;
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
      _finishWithError(
        OnboardingSubmitError.localized(
          (l10n) => rpcEndpointErrorText(l10n, error),
        ),
      );
    } on RpcEndpointSaveException {
      _finishWithError(
        OnboardingSubmitError.localized((l10n) => l10n.endpointSaveFailed),
      );
    } catch (_) {
      _finishWithError(
        OnboardingSubmitError.localized(
          (l10n) => l10n.onboardingNetworkVerifyFailed,
        ),
      );
    }
  }

  Future<void> _useAutomatic() async {
    if (!widget.dismissal.value) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    _updateDismissal();
    try {
      await ref.read(rpcEndpointProvider.notifier).setAutomatic();
      if (!mounted) return;
      setState(() => _submitting = false);
      _updateDismissal();
      if (!widget.dismissal.value) return;
      Navigator.of(context).pop();
      widget.onUpdated?.call();
    } catch (_) {
      _finishWithError(
        OnboardingSubmitError.localized((l10n) => l10n.endpointSaveFailed),
      );
    }
  }

  void _finishWithError(OnboardingSubmitError message) {
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
    final automatic = isAutomaticRpcEndpointConfig(current);
    final effective = automatic ? ref.watch(rpcEndpointFailoverProvider) : null;
    final currentLabel = automatic
        ? effective!.automaticReady
              ? context.l10n.endpointAutomaticWithHost(
                  effective.current.hostPort,
                )
              : context.l10n.endpointAutomatic
        : current.hostPort;
    final changingPrivateQueries =
        ref.watch(enhancePirTransitionProvider) ==
        EnhancePirTransition.changing;
    return ValueListenableBuilder<bool>(
      valueListenable: widget.dismissal,
      builder: (context, canDismiss, _) => MobileNetworkSettingsContent(
        torControl: MobileTorControl(
          useGeneralDescription: true,
          enabled:
              !_submitting &&
              !_privateQueriesRequestPending &&
              !changingPrivateQueries &&
              !(_torRequestPending && !state.isBusy),
          onRequest: _requestTor,
        ),
        privateQueriesControl: MobilePrivateQueriesControl(
          enabled:
              !_submitting &&
              !_torRequestPending &&
              !_privateQueriesRequestPending &&
              !state.isBusy,
          onRequest: _requestPrivateQueries,
        ),
        current: current,
        currentEndpointLabel: currentLabel,
        onUseAutomatic: current.network == ZcashNetwork.mainnet && !automatic
            ? canDismiss
                  ? _useAutomatic
                  : null
            : null,
        controller: _controller,
        focusNode: _focus,
        fieldRegion: _fieldRegion,
        onChanged: (_) => setState(() => _error = null),
        onSubmit: _submit,
        onClose: canDismiss ? () => Navigator.of(context).pop() : null,
        canUpdate: _canUpdate(current),
        submitting: _submitting,
        error: _error?.resolve(context.l10n) ?? _inputError,
      ),
    );
  }
}

/// Presentation shared by the live editor and deterministic Widgetbook states.
class MobileNetworkSettingsContent extends StatelessWidget {
  const MobileNetworkSettingsContent({
    required this.torControl,
    required this.privateQueriesControl,
    required this.current,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmit,
    required this.onClose,
    required this.canUpdate,
    required this.submitting,
    this.fieldRegion,
    this.error,
    this.currentEndpointLabel,
    this.onUseAutomatic,
    super.key,
  });

  final Widget torControl;
  final Widget privateQueriesControl;
  final RpcEndpointConfig current;
  final TextEditingController controller;
  final FocusNode focusNode;
  final GlobalKey? fieldRegion;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;
  final VoidCallback? onClose;
  final bool canUpdate;
  final bool submitting;
  final String? error;
  final String? currentEndpointLabel;
  final VoidCallback? onUseAutomatic;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MobileModalScaffold(
      title: context.l10n.networkSettingsTitle,
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
                  privateQueriesControl,
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Divider(height: 1, color: colors.border.regular),
                  ),
                  Text(
                    context.l10n.endpointCustom,
                    style: AppTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.text.accent,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    context.l10n.endpointCurrent(
                      currentEndpointLabel ??
                          (isAutomaticRpcEndpointConfig(current)
                              ? context.l10n.endpointAutomatic
                              : current.hostPort),
                    ),
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                  if (current.network == ZcashNetwork.mainnet &&
                      !isAutomaticRpcEndpointConfig(current)) ...[
                    const SizedBox(height: AppSpacing.xs),
                    AppButton(
                      key: const ValueKey('welcome_endpoint_automatic'),
                      variant: AppButtonVariant.secondary,
                      onPressed: onUseAutomatic,
                      child: Text(context.l10n.endpointUseAutomatic),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Column(
                    key: fieldRegion,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MobileTextField(
                        controller: controller,
                        focusNode: focusNode,
                        fieldKey: const ValueKey('welcome_endpoint_input'),
                        hintText:
                            'server.example:443', // l10n-ignore: sample endpoint
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.done,
                        enabled: !submitting,
                        onChanged: onChanged,
                        onSubmitted: (_) => onSubmit(),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        context.l10n.onboardingNetworkEndpointHelper,
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
          AppButton(
            key: const ValueKey('welcome_endpoint_update'),
            variant: AppButtonVariant.primary,
            expand: true,
            onPressed: canUpdate ? onSubmit : null,
            child: Text(
              submitting
                  ? context.l10n.onboardingNetworkCheckingEndpoint
                  : context.l10n.endpointUpdate,
            ),
          ),
        ],
      ),
    );
  }
}
