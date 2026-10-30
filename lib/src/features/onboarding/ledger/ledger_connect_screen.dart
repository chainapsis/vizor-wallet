import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../import/desktop_import_navigation.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../ledger/services/ledger_failure_guidance.dart';
import '../../ledger/ledger_onboarding_policy.dart';
import '../../ledger/ledger_capability.dart';
import '../../ledger/services/ledger_account_service.dart';
import '../../ledger/services/ledger_app_readiness_service.dart';
import '../../ledger/services/ledger_mobile_ble_service.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../../providers/account_models.dart';
import '../../ledger/widgets/ledger_device_app_prompt.dart';
import '../shared/onboarding_chrome.dart';
import 'ledger_desktop_ble_probe_dialog.dart';
import 'ledger_setup_args.dart';

enum LedgerOnboardingStep { connect, birthday, setPassword, customiseAccount }

class LedgerOnboardingShell extends ConsumerWidget {
  const LedgerOnboardingShell({
    required this.activeStep,
    required this.backTarget,
    required this.child,
    this.overlay,
    super.key,
  });

  final LedgerOnboardingStep activeStep;
  final OnboardingBackTarget? backTarget;
  final Widget child;
  final Widget? overlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showPasswordStep = !ref.watch(
      appSecurityProvider.select((state) => state.isPasswordConfigured),
    );
    final steps = [
      LedgerOnboardingStep.connect,
      LedgerOnboardingStep.birthday,
      LedgerOnboardingStep.customiseAccount,
      if (showPasswordStep) LedgerOnboardingStep.setPassword,
    ];
    return AppDesktopShell(
      sidebar: OnboardingSidebarChrome(
        steps: [
          for (final step in steps)
            OnboardingSidebarStepData(
              label: switch (step) {
                LedgerOnboardingStep.connect => 'Connect Ledger',
                LedgerOnboardingStep.birthday => 'Wallet Birthday Height',
                LedgerOnboardingStep.setPassword => 'Set Password',
                LedgerOnboardingStep.customiseAccount => 'Customise wallet',
              },
              iconName: switch (step) {
                LedgerOnboardingStep.connect => AppIcons.ledger,
                LedgerOnboardingStep.birthday => AppIcons.block,
                LedgerOnboardingStep.setPassword => AppIcons.lock,
                LedgerOnboardingStep.customiseAccount => AppIcons.user,
              },
              active: step == activeStep,
            ),
        ],
        illustration: IgnorePointer(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              'assets/illustrations/desktop/onboarding_ledger_sidebar.webp',
              width: 256,
              height: 430,
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
      pane: OnboardingPaneChrome(
        backTarget: backTarget,
        overlay: overlay,
        child: child,
      ),
    );
  }
}

class LedgerConnectScreen extends ConsumerStatefulWidget {
  const LedgerConnectScreen({this.backTarget, super.key});

  final OnboardingBackTarget? backTarget;

  @override
  ConsumerState<LedgerConnectScreen> createState() =>
      _LedgerConnectScreenState();
}

class _LedgerConnectScreenState extends ConsumerState<LedgerConnectScreen> {
  late final TextEditingController _accountIndexController;
  final _supportedDevicesFocusNode = FocusNode();

  Completer<LedgerDeviceAccount?>? _connection;
  int _connectionAccountIndex = 0;
  String? _error;
  bool _invalidAccountIndex = false;
  bool _showAdvancedOptions = false;
  LedgerConnectionTransport _transport = LedgerConnectionTransport.usb;
  late final LedgerOperationCanceller _cancelLedgerOperation;

  bool get _busy => _connection != null;

  void _toggleAdvancedOptions() {
    if (_busy) return;
    setState(() => _showAdvancedOptions = !_showAdvancedOptions);
  }

  @override
  void initState() {
    super.initState();
    _cancelLedgerOperation = ref.read(ledgerOperationCancellerProvider);
    _accountIndexController = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    if (_busy) {
      unawaited(_cancelLedgerOperation());
    }
    _accountIndexController.dispose();
    _supportedDevicesFocusNode.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    final accountIndex = _validatedAccountIndex();
    if (accountIndex == null) return;
    final connection = Completer<LedgerDeviceAccount?>();
    setState(() {
      _connection = connection;
      _connectionAccountIndex = accountIndex;
      _error = null;
      _invalidAccountIndex = false;
    });

    try {
      final account = await connection.future;
      if (!mounted) return;
      setState(() => _connection = null);
      if (account == null) return;
      context.go(
        desktopImportLocation(context, '/onboarding/ledger/birthday'),
        extra: LedgerBirthdayArgs(account: account),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connection = null;
        _error = error is LedgerAppReadinessException
            ? error.message
            : _friendlyError(error);
      });
    }
  }

  Widget? _connectionOverlay() {
    final connection = _connection;
    if (connection == null) return null;
    return LedgerDesktopConnectModal(
      transport: _transport,
      service: ref.read(ledgerMobileBleServiceProvider),
      usbConnector: ref.read(ledgerAccountConnectorProvider),
      bluetoothConnector: ref.read(ledgerBluetoothAccountConnectorProvider),
      cancelOperation: _cancelLedgerOperation,
      accountIndex: _connectionAccountIndex,
      onConnected: (account) {
        if (!connection.isCompleted) connection.complete(account);
      },
      onClose: () {
        if (!connection.isCompleted) connection.complete();
      },
    );
  }

  int? _validatedAccountIndex() {
    final accountIndex = parseLedgerOnboardingAccountIndex(
      _accountIndexController.text,
    );
    if (accountIndex != null) {
      return accountIndex;
    }
    setState(() {
      _invalidAccountIndex = true;
      _error = null;
      _showAdvancedOptions = true;
    });
    return null;
  }

  String _friendlyError(Object error) {
    final lower = '$error'.toLowerCase();
    final networkName = ref.read(rpcEndpointProvider).networkName;
    final appInstruction = ledgerZcashAppOpenErrorInstruction(networkName);
    final failure = LedgerRequestFailure.fromError(error);
    if (failure == LedgerRequestFailure.declined) {
      return 'The viewing-key request was rejected on your Ledger.';
    }
    if (failure == LedgerRequestFailure.deviceLocked) {
      return 'Unlock your Ledger. $appInstruction';
    }
    final guidance = ledgerFailureGuidance(
      error,
      requestKind: LedgerRequestKind.viewingKey,
    );
    if (guidance != null) return guidance.message;
    if (failure == LedgerRequestFailure.transportLost) {
      return 'Connect and unlock your Ledger. $appInstruction';
    }
    if (lower.contains('already') || lower.contains('duplicate')) {
      return 'This Ledger account is already in Vizor.';
    }
    return 'Vizor could not read this Ledger account. $appInstruction Then try again.';
  }

  Widget _transportChoice(LedgerConnectionTransport transport) {
    final bluetooth = transport == LedgerConnectionTransport.bluetooth;
    final selected = _transport == transport;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? context.colors.text.primary
                  : context.colors.border.subtle,
            ),
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
          child: AppButton(
            key: ValueKey('ledger_transport_${transport.name}'),
            variant: AppButtonVariant.ghost,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            expand: true,
            constrainContent: true,
            growWithContent: true,
            height: 72,
            contentPadding: const EdgeInsets.all(AppSpacing.xs),
            onPressed: _busy
                ? null
                : () => setState(() => _transport = transport),
            child: Row(
              children: [
                if (bluetooth)
                  const Icon(Icons.bluetooth, size: 20)
                else
                  const AppIcon(AppIcons.usb, size: 20),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    bluetooth ? 'Bluetooth' : 'USB',
                    style: AppTypography.bodyMediumStrong,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                ExcludeSemantics(
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: selected
                          ? context.colors.background.inverse
                          : context.colors.background.neutralSubtleOpacity,
                      shape: BoxShape.circle,
                    ),
                    child: selected
                        ? Center(
                            child: AppIcon(
                              AppIcons.check,
                              size: 12,
                              color: context.colors.icon.inverse,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _supportedDevicesHelp() => Focus(
    canRequestFocus: false,
    onFocusChange: (focused) {
      if (!focused) Tooltip.dismissAllToolTips();
    },
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          Tooltip.dismissAllToolTips()) {
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: AppTooltip(
      message: 'Nano X · Flex · Stax · Nano Gen5',
      preferBelow: true,
      tapToShow: true,
      child: Builder(
        builder: (context) => Semantics(
          button: true,
          child: AppButton(
            key: const ValueKey('ledger_supported_devices'),
            focusNode: _supportedDevicesFocusNode,
            onPressed: _busy
                ? null
                : () {
                    _supportedDevicesFocusNode.requestFocus();
                    context
                        .findAncestorStateOfType<TooltipState>()
                        ?.ensureTooltipVisible();
                  },
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            growWithContent: true,
            child: const Text('Supported devices'),
          ),
        ),
      ),
    ),
  );

  Widget _accountIndexMessage() => Stack(
    children: [
      // Preserve the helper's wrapping height when showing validation feedback.
      Visibility(
        visible: !_invalidAccountIndex,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: Text(
          'Keep 0 unless you used a different index for this Ledger account.',
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
      if (_invalidAccountIndex)
        Positioned.fill(
          child: Semantics(
            liveRegion: true,
            child: Text(
              kLedgerOnboardingAccountIndexError,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.destructive,
              ),
            ),
          ),
        ),
    ],
  );

  Widget _advancedOptions() => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: context.colors.background.neutralSubtleOpacity,
      borderRadius: BorderRadius.circular(AppRadii.medium),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          key: const ValueKey('ledger_advanced_options_disclosure'),
          button: true,
          enabled: !_busy,
          expanded: _showAdvancedOptions,
          label: 'Advanced options',
          onTap: _busy ? null : _toggleAdvancedOptions,
          child: ExcludeSemantics(
            child: AppButton(
              onPressed: _busy ? null : _toggleAdvancedOptions,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.medium,
              height: 44,
              expand: true,
              constrainContent: true,
              growWithContent: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
                vertical: AppSpacing.xs,
              ),
              borderRadius: BorderRadius.circular(AppRadii.medium),
              pressedBackgroundColor: context.colors.state.hoverOpacity,
              child: Row(
                children: [
                  const Expanded(child: Text('Advanced options')),
                  const SizedBox(width: AppSpacing.xs),
                  RotatedBox(
                    quarterTurns: _showAdvancedOptions ? 2 : 0,
                    child: const AppIcon(AppIcons.arrowDown, size: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_showAdvancedOptions)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _accountIndexMessage(),
                const SizedBox(height: AppSpacing.s),
                AppTextField(
                  key: const ValueKey('ledger_account_index_field'),
                  label: kLedgerOnboardingAccountIndexLabel,
                  controller: _accountIndexController,
                  enabled: !_busy,
                  tone: _invalidAccountIndex
                      ? AppTextFieldTone.destructive
                      : AppTextFieldTone.neutral,
                  onChanged: (value) {
                    final invalid =
                        parseLedgerOnboardingAccountIndex(value) == null;
                    if (_invalidAccountIndex != invalid) {
                      setState(() => _invalidAccountIndex = invalid);
                    }
                  },
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ],
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LedgerOnboardingShell(
    activeStep: LedgerOnboardingStep.connect,
    backTarget:
        widget.backTarget ??
        const OnboardingBackTarget.route(
          label: 'Add account',
          routePath: '/add-account',
        ),
    overlay: _connectionOverlay(),
    child: Center(
      child: SizedBox(
        width: 420,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Connect Ledger',
                        style: AppTypography.displayLarge.copyWith(
                          fontFamily: 'Young Serif',
                          fontWeight: FontWeight.w400,
                          color: context.colors.text.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Prepare your Ledger wallet.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: context.colors.text.secondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (ledgerSupportsBluetooth(
                        ref.watch(ledgerTargetPlatformProvider),
                      )) ...[
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _transportChoice(LedgerConnectionTransport.usb),
                              const SizedBox(width: AppSpacing.xs),
                              _transportChoice(
                                LedgerConnectionTransport.bluetooth,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: context.colors.background.base,
                          borderRadius: BorderRadius.circular(AppRadii.large),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xxs,
                              children: [
                                Text(
                                  'On your Ledger',
                                  style: AppTypography.bodyMediumStrong
                                      .copyWith(
                                        color: context.colors.text.primary,
                                      ),
                                ),
                                if (_transport ==
                                    LedgerConnectionTransport.bluetooth)
                                  _supportedDevicesHelp(),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.s),
                            Text(
                              '1. Unlock with your PIN.\n\n2. ${_transport == LedgerConnectionTransport.usb ? 'Connect with a USB cable.' : 'Enable Bluetooth and keep Ledger nearby.'}',
                              style: AppTypography.bodyMedium.copyWith(
                                color: context.colors.text.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _advancedOptions(),
                      if (_error case final error?)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.s),
                          child: Text(
                            error,
                            key: const ValueKey('ledger_connect_error'),
                            style: AppTypography.bodySmall.copyWith(
                              color: context.colors.text.destructive,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'See your balance and activity in Vizor.\nApprove transactions on Ledger.',
                        style: AppTypography.bodySmall.copyWith(
                          color: context.colors.text.secondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: AppButton(
                key: const ValueKey('ledger_connect_button'),
                onPressed: _busy ? null : () => unawaited(_connect()),
                variant: AppButtonVariant.primary,
                growWithContent: true,
                minWidth: 196,
                child: const Text('Connect Ledger'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
