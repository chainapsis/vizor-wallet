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
import '../../ledger/widgets/ledger_device_app_prompt.dart';
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
      final identity = await ref.read(ledgerWalletIdentityConnectorProvider)(
        accountContext?.sourceAccount.zip32AccountIndex,
      );
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
        )(accountContext?.sourceAccount.zip32AccountIndex, device);
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
    if (storedFingerprint != null) {
      if (storedFingerprint != identity.fingerprint) {
        throw const _LedgerWalletMismatchException();
      }
      return;
    }
    final deviceAddress = identity.verificationAddress;
    if (source.zip32AccountIndex == null || deviceAddress == null) {
      throw const _LedgerWalletMismatchException();
    }
    final matches = await ref.read(ledgerAccountIdentityVerifierProvider)(
      accountUuid: source.uuid,
      deviceAddress: deviceAddress,
    );
    if (!matches) throw const _LedgerWalletMismatchException();
    await ref
        .read(accountProvider.notifier)
        .recordLedgerWalletFingerprint(
          uuid: source.uuid,
          fingerprint: identity.fingerprint,
        );
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
    final disclosureLabel = accountContext == null
        ? 'Advanced options'
        : 'Choose a different index';
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
                if (accountContext != null) ...[
                  const SizedBox(height: AppSpacing.base),
                  _KnownLedgerAccountsCard(accountContext: accountContext),
                ],
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
                        label: disclosureLabel,
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
                            child: Text(disclosureLabel),
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
                          onChanged: _handleAccountIndexChanged,
                          messageText: _accountIndexError,
                          tone: _accountIndexError == null
                              ? AppTextFieldTone.neutral
                              : AppTextFieldTone.destructive,
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
                      ? null
                      : const AppIcon(AppIcons.ledger, semanticLabel: 'Ledger'),
                  trailing: _busy
                      ? const AppIcon(
                          AppIcons.loader,
                          key: ValueKey('ledger_connect_spinner'),
                          semanticLabel: 'Connecting to Ledger',
                        )
                      : null,
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
