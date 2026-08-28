import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../ledger/services/ledger_account_service.dart';
import '../../ledger/services/ledger_app_readiness_service.dart';
import '../../ledger/services/ledger_mobile_ble_service.dart';
import '../../ledger/services/ledger_signing_service.dart';
import '../../ledger/widgets/ledger_device_app_prompt.dart';
import '../ledger/ledger_account_import_context.dart';
import '../ledger/ledger_setup_args.dart';
import 'mobile_ledger_device_sheet.dart';
import 'mobile_onboarding_scaffold.dart';

enum _MobileLedgerConnectPhase { idle, awaitingApproval }

class MobileLedgerConnectScreen extends ConsumerStatefulWidget {
  const MobileLedgerConnectScreen({this.sourceAccountUuid, super.key});

  final String? sourceAccountUuid;

  @override
  ConsumerState<MobileLedgerConnectScreen> createState() =>
      _MobileLedgerConnectScreenState();
}

class _MobileLedgerConnectScreenState
    extends ConsumerState<MobileLedgerConnectScreen> {
  late final TextEditingController _accountIndexController;
  late final LedgerOperationCanceller _cancelLedgerOperation;

  LedgerBleDevice? _selectedDevice;
  _MobileLedgerConnectPhase _phase = _MobileLedgerConnectPhase.idle;
  String? _error;
  String? _accountIndexError;
  bool _showAdvancedOptions = false;
  bool _accountIndexInitialized = false;

  bool get _busy => _phase != _MobileLedgerConnectPhase.idle;

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
    if (_busy) unawaited(_cancelLedgerOperation());
    _accountIndexController.dispose();
    super.dispose();
  }

  Future<void> _chooseDevice() async {
    if (_busy) return;
    final device = await showMobileLedgerDeviceSheet(
      context: context,
      service: ref.read(ledgerMobileBleServiceProvider),
    );
    if (!mounted || device == null) return;
    setState(() {
      _selectedDevice = device;
      _error = null;
    });
  }

  void _toggleAdvancedOptions() {
    if (_busy) return;
    setState(() => _showAdvancedOptions = !_showAdvancedOptions);
  }

  Future<void> _continue() async {
    if (_busy || _selectedDevice == null) return;
    final accountIndex = _validatedAccountIndex();
    if (accountIndex == null) return;
    setState(() {
      _phase = _MobileLedgerConnectPhase.awaitingApproval;
      _error = null;
    });
    try {
      final accountContext = _resolveAccountContext();
      final identity = await ref.read(
        ledgerBluetoothWalletIdentityConnectorProvider,
      )(accountContext?.sourceAccount.zip32AccountIndex, _selectedDevice!);
      await _verifyWalletIdentity(identity, accountContext);
      _throwIfConnectedWalletUsesIndex(identity, accountIndex);
      final account = (await ref.read(ledgerBluetoothAccountConnectorProvider)(
        accountIndex,
        _selectedDevice!,
      )).withWalletIdentity(identity);
      if (!mounted) return;
      setState(() => _phase = _MobileLedgerConnectPhase.idle);
      context.push(
        '/onboarding/ledger/birthday',
        extra: LedgerBirthdayArgs(
          account: account,
          sourceAccountUuid: widget.sourceAccountUuid,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _MobileLedgerConnectPhase.idle;
        if (error case _LedgerDuplicateIndexException(:final accountIndex)) {
          _accountIndexError =
              'Index $accountIndex is already used by this Ledger wallet.';
          _showAdvancedOptions = true;
          _error = null;
        } else {
          _error = error is LedgerAppReadinessException
              ? error.message
              : _friendlyError(error);
        }
      });
    }
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
    if (duplicate) throw _LedgerDuplicateIndexException(accountIndex);
  }

  String _friendlyError(Object error) {
    if (error is LedgerMobileException) {
      return switch (error.failure) {
        LedgerMobileFailure.disconnected ||
        LedgerMobileFailure.pairingRejected =>
          'Reconnect your Ledger, then try again.',
        LedgerMobileFailure.locked => 'Unlock your Ledger, then try again.',
        LedgerMobileFailure.rejected =>
          'The viewing-key request was rejected on your Ledger.',
        _ => error.message,
      };
    }
    final lower = '$error'.toLowerCase();
    if (lower.contains('rejected') || lower.contains('6985')) {
      return 'The viewing-key request was rejected on your Ledger.';
    }
    if ('$error'.contains(_LedgerWalletMismatchException.message)) {
      return _LedgerWalletMismatchException.message;
    }
    return 'Vizor could not read this Ledger account. Check the connection and try again.';
  }

  String _buttonLabel(LedgerAppReadinessState readiness) {
    if (_phase == _MobileLedgerConnectPhase.idle) return 'Continue';
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
    final colors = context.colors;
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
    return MobileOnboardingStepScaffold(
      progress: 0.25,
      title: 'Connect Ledger',
      subtitle:
          'Select your Ledger, then approve sharing its viewing key to add a watch-only account.',
      onBack: () => context.pop(),
      bottomArea: SizedBox(
        width: double.infinity,
        child: AppButton(
          key: const ValueKey('mobile_ledger_import_button'),
          onPressed: _busy || _selectedDevice == null
              ? null
              : () => unawaited(_continue()),
          leading: _busy
              ? null
              : const AppIcon(AppIcons.ledger, semanticLabel: 'Ledger'),
          trailing: _busy
              ? const AppIcon(
                  AppIcons.loader,
                  key: ValueKey('mobile_ledger_import_spinner'),
                  semanticLabel: 'Connecting to Ledger',
                )
              : null,
          child: Text(_buttonLabel(readiness)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerDeviceAppPrompt(networkName: networkName),
          if (accountContext != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _KnownLedgerAccountsCard(accountContext: accountContext),
          ],
          const SizedBox(height: AppSpacing.sm),
          _DeviceSelectionCard(
            device: _selectedDevice,
            enabled: !_busy,
            onPressed: () => unawaited(_chooseDevice()),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.background.neutralSubtleOpacity,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  key: const ValueKey(
                    'mobile_ledger_advanced_options_disclosure',
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
                    key: const ValueKey('mobile_ledger_account_index_field'),
                    label: 'Ledger account index',
                    controller: _accountIndexController,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
              key: const ValueKey('mobile_ledger_connect_error'),
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.destructive,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
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
      key: const ValueKey('mobile_ledger_known_accounts_card'),
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
              key: ValueKey('mobile_ledger_known_account_${account.uuid}'),
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
            key: const ValueKey('mobile_ledger_suggested_account_index'),
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
}

class _DeviceSelectionCard extends StatelessWidget {
  const _DeviceSelectionCard({
    required this.device,
    required this.enabled,
    required this.onPressed,
  });

  final LedgerBleDevice? device;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = device;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selected == null)
            Text(
              'Choose a nearby Bluetooth Ledger before importing.',
              style: AppTypography.bodyMedium.copyWith(
                color: colors.text.secondary,
              ),
            )
          else ...[
            Text(
              'Selected device',
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              selected.name,
              key: const ValueKey('mobile_ledger_selected_device_name'),
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.accent,
              ),
            ),
            Text(
              selected.model,
              key: const ValueKey('mobile_ledger_selected_device_model'),
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            key: const ValueKey('mobile_ledger_select_device_button'),
            onPressed: enabled ? onPressed : null,
            variant: AppButtonVariant.secondary,
            child: Text(selected == null ? 'Select Ledger' : 'Change device'),
          ),
        ],
      ),
    );
  }
}
