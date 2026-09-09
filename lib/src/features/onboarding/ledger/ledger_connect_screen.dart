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
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../ledger/services/ledger_account_service.dart';
import '../../ledger/services/ledger_app_readiness_service.dart';
import '../../ledger/services/ledger_mobile_ble_service.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/ledger_app_instructions.dart';
import '../../ledger/widgets/ledger_connection_guide.dart';
import '../shared/onboarding_chrome.dart';
import 'ledger_desktop_ble_probe_dialog.dart';
import 'ledger_account_import_context.dart';
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
        illustration: activeStep == LedgerOnboardingStep.connect
            ? IgnorePointer(
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
              )
            : Center(
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
  const LedgerConnectScreen({this.sourceAccountUuid, super.key});

  final String? sourceAccountUuid;

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
  bool _accountIndexInitialized = false;
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
    final accountContext = _resolveAccountContext();
    _accountIndexInitialized =
        widget.sourceAccountUuid == null || accountContext != null;
    _accountIndexController = TextEditingController(
      text: '${accountContext?.suggestedIndex ?? 0}',
    );
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
      final accountContext = _resolveAccountContext();
      final identity = await ref.read(ledgerWalletIdentityConnectorProvider)();
      await _verifyWalletIdentity(identity, accountContext);
      _throwIfConnectedWalletUsesIndex(identity, accountIndex);
      final account = (await ref.read(ledgerAccountConnectorProvider)(
        accountIndex,
      )).withWalletIdentity(identity);
      if (!mounted) return;
      setState(() => _phase = _LedgerConnectPhase.idle);
      context.go(
        '/onboarding/ledger/birthday',
        extra: LedgerBirthdayArgs(
          account: account,
          sourceAccountUuid: widget.sourceAccountUuid,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _LedgerConnectPhase.idle;
        if (error case _LedgerDuplicateIndexException(:final accountIndex)) {
          _accountIndexError =
              'Index $accountIndex is already used by this Ledger wallet.';
          _showAdvancedOptions = true;
          _error = null;
        } else {
          _error = error is LedgerAppReadinessException
              ? error.message
              : _friendlyError('$error');
        }
      });
    }
  }

  Future<void> _connectBluetooth() async {
    if (_busy) return;
    final accountIndex = _validatedAccountIndex();
    if (accountIndex == null) return;
    final accountContext = _resolveAccountContext();
    final account = await showLedgerDesktopBleConnectDialog(
      context: context,
      service: ref.read(ledgerMobileBleServiceProvider),
      connector: (targetIndex, device) async {
        final identity = await ref.read(
          ledgerBluetoothWalletIdentityConnectorProvider,
        )(device);
        await _verifyWalletIdentity(identity, accountContext);
        _throwIfConnectedWalletUsesIndex(identity, targetIndex);
        return (await ref.read(ledgerBluetoothAccountConnectorProvider)(
          targetIndex,
          device,
        )).withWalletIdentity(identity);
      },
      accountIndex: accountIndex,
    );
    if (!mounted || account == null) return;
    context.go(
      '/onboarding/ledger/birthday',
      extra: LedgerBirthdayArgs(
        account: account,
        sourceAccountUuid: widget.sourceAccountUuid,
      ),
    );
  }

  int? _validatedAccountIndex() {
    final accountIndex = int.tryParse(_accountIndexController.text);
    if (accountIndex != null &&
        accountIndex >= 0 &&
        accountIndex < 0x80000000) {
      final duplicateError = _duplicateIndexError(accountIndex);
      if (duplicateError == null) return accountIndex;
      setState(() {
        _accountIndexError = duplicateError;
        _error = null;
      });
      return null;
    }
    setState(() {
      _accountIndexError = 'Account index must be between 0 and 2147483647.';
      _error = null;
    });
    return null;
  }

  LedgerAccountImportContext? _resolveAccountContext() {
    final accounts = ref.read(accountProvider).value?.accounts ?? const [];
    return resolveLedgerAccountImportContext(
      accounts: accounts,
      sourceAccountUuid: widget.sourceAccountUuid,
    );
  }

  String? _duplicateIndexError(int accountIndex) {
    final accountContext = _resolveAccountContext();
    if (accountContext == null || !accountContext.usesIndex(accountIndex)) {
      return null;
    }
    return 'Index $accountIndex is already used by this Ledger wallet.';
  }

  void _handleAccountIndexChanged(String value) {
    final accountIndex = int.tryParse(value);
    setState(() {
      _accountIndexError = accountIndex == null
          ? null
          : _duplicateIndexError(accountIndex);
      _error = null;
    });
  }

  Future<void> _verifyWalletIdentity(
    LedgerWalletIdentity identity,
    LedgerAccountImportContext? accountContext,
  ) async {
    if (accountContext == null) return;
    final source = accountContext.sourceAccount;
    final storedFingerprint = source.ledgerWalletFingerprint;
    if (storedFingerprint == null ||
        storedFingerprint != identity.fingerprint) {
      throw const _LedgerWalletMismatchException();
    }
  }

  void _throwIfConnectedWalletUsesIndex(
    LedgerWalletIdentity identity,
    int accountIndex,
  ) {
    final accounts = ref.read(accountProvider).value?.accounts ?? const [];
    final duplicate = accounts.any(
      (account) =>
          account.isLedger &&
          account.ledgerWalletFingerprint == identity.fingerprint &&
          account.zip32AccountIndex == accountIndex,
    );
    if (duplicate) {
      throw _LedgerDuplicateIndexException(accountIndex);
    }
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
    if (raw.contains(_LedgerWalletMismatchException.message)) {
      return _LedgerWalletMismatchException.message;
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
    final accounts = ref.watch(accountProvider).value?.accounts ?? const [];
    final accountContext = resolveLedgerAccountImportContext(
      accounts: accounts,
      sourceAccountUuid: widget.sourceAccountUuid,
    );
    if (accountContext != null && !_accountIndexInitialized) {
      _accountIndexInitialized = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _busy) return;
        _accountIndexController.text = '${accountContext.suggestedIndex}';
        setState(() {});
      });
    }
    final disclosureLabel =
        'Account index · ${_accountIndexController.text.isEmpty ? '—' : _accountIndexController.text}';
    return LedgerOnboardingShell(
      activeStep: LedgerOnboardingStep.connect,
      backTarget: accountContext == null
          ? const OnboardingBackTarget.route(
              label: 'Add account',
              routePath: '/add-account',
            )
          : const OnboardingBackTarget.route(
              label: 'Accounts',
              routePath: '/accounts',
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
                    if (accountContext != null) ...[
                      const SizedBox(height: AppSpacing.base),
                      _KnownLedgerAccountsCard(accountContext: accountContext),
                    ],
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

class _KnownLedgerAccountsCard extends StatelessWidget {
  const _KnownLedgerAccountsCard({required this.accountContext});

  final LedgerAccountImportContext accountContext;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('ledger_known_accounts_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.surface.card,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: context.colors.border.subtleOpacity),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accounts on this Ledger',
            style: AppTypography.labelLarge.copyWith(
              color: context.colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final account in accountContext.knownAccounts) ...[
            Row(
              key: ValueKey('ledger_known_account_${account.uuid}'),
              children: [
                Expanded(
                  child: Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.colors.text.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  account.zip32AccountIndex == null
                      ? 'Index unavailable'
                      : 'Index ${account.zip32AccountIndex}',
                  style: AppTypography.labelMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Next available index: ${accountContext.suggestedIndex}',
            key: const ValueKey('ledger_suggested_account_index'),
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerWalletMismatchException implements Exception {
  const _LedgerWalletMismatchException();

  static const message =
      'This Ledger does not match the account you started from.';

  @override
  String toString() => message;
}

class _LedgerDuplicateIndexException implements Exception {
  const _LedgerDuplicateIndexException(this.accountIndex);

  final int accountIndex;

  @override
  String toString() =>
      'Index $accountIndex is already used by this Ledger wallet.';
}
