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
import '../../ledger/widgets/ledger_connection_guide.dart';
import '../ledger/ledger_account_import_context.dart';
import '../ledger/ledger_setup_args.dart';
import 'mobile_ledger_device_sheet.dart';
import 'mobile_onboarding_scaffold.dart';

enum _MobileLedgerConnectPhase { idle, awaitingApproval }

class MobileLedgerConnectScreen extends ConsumerStatefulWidget {
  const MobileLedgerConnectScreen({
    this.sourceAccountUuid,
    this.connectionAccountUuid,
    super.key,
  }) : assert(sourceAccountUuid == null || connectionAccountUuid == null);

  final String? sourceAccountUuid;

  /// Verify and connect an existing account without importing another account.
  final String? connectionAccountUuid;

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
  bool get _connectingExisting => widget.connectionAccountUuid != null;

  AccountInfo? _connectionAccount() => ref
      .read(accountProvider)
      .value
      ?.accounts
      .where(
        (account) =>
            account.uuid == widget.connectionAccountUuid && account.isLedger,
      )
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _cancelLedgerOperation = ref.read(ledgerOperationCancellerProvider);
    final accountContext = _resolveAccountContext();
    _accountIndexInitialized =
        widget.sourceAccountUuid == null || accountContext != null;
    _accountIndexController = TextEditingController(
      text:
          '${_connectionAccount()?.zip32AccountIndex ?? accountContext?.suggestedIndex ?? 0}',
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
    final existingAccount = _connectionAccount();
    if (_connectingExisting &&
        (existingAccount == null ||
            existingAccount.zip32AccountIndex == null)) {
      setState(
        () =>
            _error = 'This Ledger account is missing its recovery information.',
      );
      return;
    }
    final accountIndex = _connectingExisting
        ? existingAccount!.zip32AccountIndex
        : _validatedAccountIndex();
    if (accountIndex == null) return;
    setState(() {
      _phase = _MobileLedgerConnectPhase.awaitingApproval;
      _error = null;
    });
    try {
      final accountContext = _resolveAccountContext();
      final identity = await ref.read(
        ledgerBluetoothWalletIdentityConnectorProvider,
      )(_selectedDevice!);
      if (!mounted) return;
      if (existingAccount != null &&
          existingAccount.ledgerWalletFingerprint != identity.fingerprint) {
        throw const _LedgerWalletMismatchException();
      }
      await _verifyWalletIdentity(identity, accountContext);
      if (!mounted) return;
      if (!_connectingExisting) {
        _throwIfConnectedWalletUsesIndex(identity, accountIndex);
      }
      final account = (await ref.read(ledgerBluetoothAccountConnectorProvider)(
        accountIndex,
        _selectedDevice!,
      )).withWalletIdentity(identity);
      if (!mounted) return;
      if (existingAccount != null) {
        final storedUfvk = await ref.read(ledgerAccountUfvkLoaderProvider)(
          existingAccount.uuid,
        );
        if (!mounted) return;
        if (account.ufvk != storedUfvk) {
          throw const _LedgerWalletMismatchException();
        }
        await ref
            .read(accountProvider.notifier)
            .recordLedgerConnection(
              uuid: existingAccount.uuid,
              transport: LedgerConnectionTransport.bluetooth,
              deviceId: _selectedDevice!.id,
              deviceName: _selectedDevice!.name,
              deviceModel: _selectedDevice!.model,
            );
        if (!mounted) return;
        await ref
            .read(accountProvider.notifier)
            .updateLedgerConnectionPreference(
              existingAccount.uuid,
              LedgerConnectionPreference.bluetooth,
            );
        if (!mounted) return;
        setState(() => _phase = _MobileLedgerConnectPhase.idle);
        Navigator.of(context).pop(true);
        return;
      }
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
    return MobileOnboardingStepScaffold(
      progress: 0.25,
      showProgress: !_connectingExisting,
      title: 'Connect Ledger',
      subtitle: _connectingExisting
          ? 'Connect the Ledger for this account.'
          : 'Add your Ledger account to Vizor.',
      onBack: () =>
          _connectingExisting ? Navigator.of(context).pop() : context.pop(),
      bottomArea: SizedBox(
        width: double.infinity,
        child: AppButton(
          key: const ValueKey('mobile_ledger_import_button'),
          expand: true,
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
          child: Text(
            _busy
                ? 'Waiting for Ledger'
                : _connectingExisting
                ? 'Connect'
                : 'Continue',
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerConnectionGuide(
            networkName: networkName,
            awaitingAccountApproval: _busy,
            connectionAction: _DeviceSelection(
              device: _selectedDevice,
              enabled: !_busy,
              onPressed: () => unawaited(_chooseDevice()),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _connectingExisting
                ? 'Approve sharing the viewing key to verify this account. Connecting does not sign or send a transaction.'
                : 'The viewing key lets Vizor show your balance and activity. You’ll still approve spending on your Ledger.',
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
          if (accountContext != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _KnownLedgerAccountsCard(accountContext: accountContext),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (!_connectingExisting)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(
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
                        size: AppButtonSize.small,
                        constrainContent: false,
                        trailing: RotatedBox(
                          quarterTurns: _showAdvancedOptions ? 2 : 0,
                          child: const AppIcon(AppIcons.arrowDown),
                        ),
                        child: Text(disclosureLabel),
                      ),
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
                    tone: _accountIndexError == null
                        ? AppTextFieldTone.neutral
                        : AppTextFieldTone.destructive,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _accountIndexError ??
                        'Use a different index to restore or add another Ledger account.',
                    key: const ValueKey('mobile_ledger_account_index_message'),
                    style: AppTypography.bodySmall.copyWith(
                      color: _accountIndexError == null
                          ? colors.text.secondary
                          : colors.text.destructive,
                    ),
                  ),
                ],
              ],
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

class _DeviceSelection extends StatelessWidget {
  const _DeviceSelection({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected != null)
          Row(
            children: [
              AppIcon(AppIcons.ledger, size: 32, color: colors.text.accent),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.name,
                      key: const ValueKey('mobile_ledger_selected_device_name'),
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      selected.model,
                      key: const ValueKey(
                        'mobile_ledger_selected_device_model',
                      ),
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppIcon(
                AppIcons.checkCircle,
                size: 20,
                color: colors.text.accent,
                semanticLabel: 'Selected device',
              ),
            ],
          )
        else
          Text(
            'Connect a nearby device with Bluetooth.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          key: const ValueKey('mobile_ledger_select_device_button'),
          onPressed: enabled ? onPressed : null,
          variant: AppButtonVariant.secondary,
          child: Text(selected == null ? 'Select Ledger' : 'Change device'),
        ),
      ],
    );
  }
}
