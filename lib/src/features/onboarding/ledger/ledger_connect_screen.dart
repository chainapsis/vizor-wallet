import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../ledger/services/ledger_account_service.dart';
import '../../ledger/services/ledger_app_readiness_service.dart';
import '../../ledger/services/ledger_mobile_ble_service.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/widgets/ledger_device_app_prompt.dart';
import '../shared/onboarding_chrome.dart';
import 'ledger_desktop_ble_probe_dialog.dart';
import 'ledger_setup_args.dart';

enum LedgerOnboardingStep { connect, birthday, customiseAccount }

class LedgerOnboardingShell extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return AppDesktopShell(
      sidebar: OnboardingSidebarChrome(
        steps: [
          for (final step in LedgerOnboardingStep.values)
            OnboardingSidebarStepData(
              label: switch (step) {
                LedgerOnboardingStep.connect => 'Connect Ledger',
                LedgerOnboardingStep.birthday => 'Wallet Birthday Height',
                LedgerOnboardingStep.customiseAccount => 'Customise wallet',
              },
              iconName: switch (step) {
                LedgerOnboardingStep.connect => AppIcons.ledger,
                LedgerOnboardingStep.birthday => AppIcons.block,
                LedgerOnboardingStep.customiseAccount => AppIcons.user,
              },
              active: step == activeStep,
            ),
        ],
        illustration: Center(
          child: AppIcon(
            AppIcons.ledgerBrand,
            size: 88,
            color: context.colors.icon.muted,
            semanticLabel: 'Ledger',
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

enum _LedgerConnectPhase { idle, awaitingApproval }

class LedgerConnectScreen extends ConsumerStatefulWidget {
  const LedgerConnectScreen({super.key});

  @override
  ConsumerState<LedgerConnectScreen> createState() =>
      _LedgerConnectScreenState();
}

class _LedgerConnectScreenState extends ConsumerState<LedgerConnectScreen> {
  late final TextEditingController _accountIndexController;

  _LedgerConnectPhase _phase = _LedgerConnectPhase.idle;
  String? _error;
  bool _showAdvancedOptions = false;
  late final LedgerOperationCanceller _cancelLedgerOperation;

  bool get _busy => _phase != _LedgerConnectPhase.idle;

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
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    final accountIndex = _validatedAccountIndex();
    if (accountIndex == null) return;
    setState(() {
      _phase = _LedgerConnectPhase.awaitingApproval;
      _error = null;
    });

    try {
      final account = await ref.read(ledgerAccountConnectorProvider)(
        accountIndex,
      );
      if (!mounted) return;
      setState(() => _phase = _LedgerConnectPhase.idle);
      context.go(
        '/onboarding/ledger/birthday',
        extra: LedgerBirthdayArgs(account: account),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _LedgerConnectPhase.idle;
        _error = error is LedgerAppReadinessException
            ? error.message
            : _friendlyError('$error');
      });
    }
  }

  Future<void> _connectBluetooth() async {
    if (_busy) return;
    final accountIndex = _validatedAccountIndex();
    if (accountIndex == null) return;
    final account = await showLedgerDesktopBleConnectDialog(
      context: context,
      service: ref.read(ledgerMobileBleServiceProvider),
      connector: ref.read(ledgerBluetoothAccountConnectorProvider),
      accountIndex: accountIndex,
    );
    if (!mounted || account == null) return;
    context.go(
      '/onboarding/ledger/birthday',
      extra: LedgerBirthdayArgs(account: account),
    );
  }

  int? _validatedAccountIndex() {
    final accountIndex = int.tryParse(_accountIndexController.text);
    if (accountIndex != null &&
        accountIndex >= 0 &&
        accountIndex < 0x80000000) {
      return accountIndex;
    }
    setState(() => _error = 'Account index must be between 0 and 2147483647.');
    return null;
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    final networkName = ref.read(rpcEndpointProvider).networkName;
    final appInstruction = ledgerZcashAppOpenErrorInstruction(networkName);
    if (lower.contains('rejected') || lower.contains('6985')) {
      return 'The viewing-key request was rejected on your Ledger.';
    }
    if (lower.contains('locked') || lower.contains('5515')) {
      return 'Unlock your Ledger. $appInstruction';
    }
    if (lower.contains('not found') || lower.contains('hid')) {
      return 'Connect and unlock your Ledger. $appInstruction';
    }
    if (lower.contains('already') || lower.contains('duplicate')) {
      return 'This Ledger account is already in Vizor.';
    }
    return 'Vizor could not read this Ledger account. $appInstruction Then try again.';
  }

  String _connectButtonLabel(LedgerAppReadinessState readiness) {
    if (_phase == _LedgerConnectPhase.idle) return 'Connect and continue';
    return switch (readiness.phase) {
      LedgerAppReadinessPhase.checkingDevice => 'Checking device',
      LedgerAppReadinessPhase.confirmOpening => 'Confirm opening Zcash',
      LedgerAppReadinessPhase.ready ||
      LedgerAppReadinessPhase.idle ||
      LedgerAppReadinessPhase.failed => 'Approve on Ledger',
    };
  }

  @override
  Widget build(BuildContext context) {
    final networkName = ref.watch(
      rpcEndpointProvider.select((endpoint) => endpoint.networkName),
    );
    final readiness = ref.watch(ledgerAppReadinessStateProvider);
    return LedgerOnboardingShell(
      activeStep: LedgerOnboardingStep.connect,
      backTarget: const OnboardingBackTarget.route(
        label: 'Add account',
        routePath: '/add-account',
      ),
      child: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                  'Vizor imports a watch-only account after you approve sharing its viewing key.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.base),
                LedgerDeviceAppPrompt(networkName: networkName),
                const SizedBox(height: AppSpacing.base),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.colors.background.neutralSubtleOpacity,
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        key: const ValueKey(
                          'ledger_advanced_options_disclosure',
                        ),
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
                            trailing: RotatedBox(
                              quarterTurns: _showAdvancedOptions ? 2 : 0,
                              child: const AppIcon(AppIcons.arrowDown),
                            ),
                            child: const Text('Advanced options'),
                          ),
                        ),
                      ),
                      if (_showAdvancedOptions) ...[
                        const SizedBox(height: AppSpacing.sm),
                        AppTextField(
                          key: const ValueKey('ledger_account_index_field'),
                          label: 'Ledger account index',
                          controller: _accountIndexController,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    error,
                    key: const ValueKey('ledger_connect_error'),
                    style: AppTypography.bodySmall.copyWith(
                      color: context.colors.text.destructive,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: AppSpacing.base),
                AppButton(
                  key: const ValueKey('ledger_connect_button'),
                  onPressed: _busy ? null : () => unawaited(_connect()),
                  variant: AppButtonVariant.primary,
                  minWidth: 230,
                  leading: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const AppIcon(AppIcons.ledger, semanticLabel: 'Ledger'),
                  child: Text(_connectButtonLabel(readiness)),
                ),
                const SizedBox(height: AppSpacing.xs),
                AppButton(
                  key: const ValueKey('ledger_desktop_ble_connect_button'),
                  onPressed: _busy
                      ? null
                      : () => unawaited(_connectBluetooth()),
                  variant: AppButtonVariant.ghost,
                  leading: const AppIcon(
                    AppIcons.ledger,
                    semanticLabel: 'Ledger',
                  ),
                  child: const Text('Connect with Bluetooth'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
