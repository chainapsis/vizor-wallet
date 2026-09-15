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
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../ledger/ledger_error_messages.dart';
import '../../ledger/services/ledger_account_service.dart';
import '../../ledger/services/ledger_app_readiness_service.dart';
import '../../ledger/services/ledger_mobile_ble_service.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/ledger_app_instructions.dart';
import '../../ledger/ledger_capability.dart';
import '../../ledger/widgets/ledger_connection_guide.dart';
import '../import/import_split_view.dart';
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
      if (showPasswordStep) LedgerOnboardingStep.setPassword,
      LedgerOnboardingStep.customiseAccount,
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
        illustration: switch (activeStep) {
          LedgerOnboardingStep.connect => IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Image.asset(
                'assets/illustrations/onboarding_ledger_sidebar.png',
                key: const ValueKey('ledger_connect_sidebar_illustration'),
                // Figma 8495:28027 is 256 × 430, exported at 2×.
                width: 256,
                height: 430,
                scale: 2,
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
                excludeFromSemantics: true,
              ),
            ),
          ),
          LedgerOnboardingStep.birthday =>
            const ImportOnboardingSidebarIllustration(
              activeStep: ImportOnboardingStep.walletBirthdayHeight,
            ),
          LedgerOnboardingStep.setPassword =>
            const ImportOnboardingSidebarIllustration(
              activeStep: ImportOnboardingStep.setPassword,
            ),
          LedgerOnboardingStep.customiseAccount =>
            const ImportOnboardingSidebarIllustration(
              activeStep: ImportOnboardingStep.customiseAccount,
            ),
        },
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
  String? _accountIndexError;
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
      await ref.read(ledgerAccountDuplicateCheckerProvider)(account.ufvk);
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
    var duplicate = false;
    final account = await showLedgerDesktopBleConnectDialog(
      context: context,
      service: ref.read(ledgerMobileBleServiceProvider),
      connector: (targetIndex, device) async {
        final account = await ref.read(ledgerBluetoothAccountConnectorProvider)(
          targetIndex,
          device,
        );
        if (!mounted) throw StateError('Ledger import was cancelled.');
        await ref.read(ledgerAccountDuplicateCheckerProvider)(account.ufvk);
        return account;
      },
      onAccountError: (error) {
        if (error is! LedgerDuplicateAccountException) return false;
        duplicate = true;
        return true;
      },
      accountIndex: accountIndex,
    );
    if (!mounted) return;
    if (duplicate) {
      setState(() {
        _showAdvancedOptions = true;
        _accountIndexError = const LedgerDuplicateAccountException().toString();
        _error = null;
      });
      return;
    }
    if (account == null) return;
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
    setState(() {
      _accountIndexError = 'Account index must be between 0 and 2147483647.';
      _error = null;
    });
    return null;
  }

  void _handleAccountIndexChanged(String value) {
    setState(() {
      _accountIndexError = null;
      _error = null;
    });
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    final networkName = ref.read(rpcEndpointProvider).networkName;
    final appInstruction = ledgerZcashAppOpenErrorInstruction(networkName);
    final usb = ledgerUsbErrorMessage(
      raw,
      appInstruction: appInstruction,
      platform: ref.read(ledgerTargetPlatformProvider),
    );
    if (usb != null) return usb;
    if (lower.contains('rejected') || lower.contains('6985')) {
      return 'The viewing-key request was rejected on your Ledger.';
    }
    if (lower.contains('locked') || lower.contains('5515')) {
      return 'Unlock your Ledger. $appInstruction';
    }
    if (lower.contains('not found')) {
      return 'Connect and unlock your Ledger. $appInstruction';
    }
    if (lower.contains('already') || lower.contains('duplicate')) {
      return 'This Ledger account is already in Vizor.';
    }
    return 'Vizor could not read this Ledger account. $appInstruction Then try again.';
  }

  @override
  Widget build(BuildContext context) {
    final networkName = ref.watch(
      rpcEndpointProvider.select((endpoint) => endpoint.networkName),
    );
    final disclosureLabel =
        'Advanced · Account ${_accountIndexController.text.isEmpty ? '—' : _accountIndexController.text}';
    return LedgerOnboardingShell(
      activeStep: LedgerOnboardingStep.connect,
      backTarget: const OnboardingBackTarget.route(
        label: 'Add account',
        routePath: '/add-account',
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const ValueKey('ledger_connect_scroll'),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
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
                      'Add your Ledger account to Vizor.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: context.colors.text.secondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    LedgerConnectionGuide(
                      networkName: networkName,
                      awaitingAccountApproval: _busy,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Semantics(
                              key: const ValueKey(
                                'ledger_advanced_options_disclosure',
                              ),
                              button: true,
                              enabled: !_busy,
                              expanded: _showAdvancedOptions,
                              label: disclosureLabel,
                              onTap: _busy ? null : _toggleAdvancedOptions,
                              child: ExcludeSemantics(
                                child: AppButton(
                                  onPressed: _busy
                                      ? null
                                      : _toggleAdvancedOptions,
                                  variant: AppButtonVariant.ghost,
                                  size: AppButtonSize.small,
                                  expand: false,
                                  constrainContent: false,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.s,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(disclosureLabel),
                                      const SizedBox(width: AppSpacing.xs),
                                      RotatedBox(
                                        quarterTurns: _showAdvancedOptions
                                            ? 2
                                            : 0,
                                        child: const AppIcon(
                                          AppIcons.arrowDown,
                                          key: ValueKey(
                                            'ledger_advanced_options_chevron',
                                          ),
                                          size: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_showAdvancedOptions) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  AppTextField(
                                    key: const ValueKey(
                                      'ledger_account_index_field',
                                    ),
                                    label: 'Ledger account index',
                                    controller: _accountIndexController,
                                    enabled: !_busy,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    onChanged: _handleAccountIndexChanged,
                                    tone: _accountIndexError == null
                                        ? AppTextFieldTone.neutral
                                        : AppTextFieldTone.destructive,
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    "Shielded: m/32'/133'/${_accountIndexController.text.isEmpty ? '—' : _accountIndexController.text}'\n"
                                    "Transparent: m/44'/133'/${_accountIndexController.text.isEmpty ? '—' : _accountIndexController.text}'",
                                    key: const ValueKey(
                                      'ledger_account_derivation_paths',
                                    ),
                                    style: AppTypography.bodySmall.copyWith(
                                      color: context.colors.text.secondary,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    _accountIndexError ??
                                        'Use a different index to restore or add another Ledger account.',
                                    key: const ValueKey(
                                      'ledger_account_index_message',
                                    ),
                                    style: AppTypography.bodySmall.copyWith(
                                      color: _accountIndexError == null
                                          ? context.colors.text.secondary
                                          : context.colors.text.destructive,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
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
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            key: const ValueKey('ledger_connect_button'),
                            onPressed: _busy
                                ? null
                                : () => unawaited(_connect()),
                            variant: AppButtonVariant.secondary,
                            leading: _busy ? null : const AppIcon(AppIcons.usb),
                            expand: true,
                            constrainContent: true,
                            trailing: _busy
                                ? const AppIcon(
                                    AppIcons.loader,
                                    key: ValueKey('ledger_connect_spinner'),
                                    semanticLabel: 'Connecting to Ledger',
                                  )
                                : null,
                            child: Text(_busy ? 'Waiting for Ledger' : 'USB'),
                          ),
                        ),
                        if (isLedgerBluetoothPlatform(
                          ref.watch(ledgerTargetPlatformProvider),
                        )) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: AppButton(
                              key: const ValueKey(
                                'ledger_desktop_ble_connect_button',
                              ),
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_connectBluetooth()),
                              variant: AppButtonVariant.secondary,
                              expand: true,
                              leading: const AppIcon(AppIcons.bluetooth),
                              constrainContent: true,
                              child: const Text('Bluetooth'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
