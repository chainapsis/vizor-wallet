import 'dart:async';

import 'package:flutter/material.dart';
import '../../ledger/widgets/ledger_bluetooth_settings_button.dart';
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
import '../ledger/ledger_setup_args.dart';
import 'mobile_ledger_device_sheet.dart';
import 'mobile_onboarding_scaffold.dart';

enum _MobileLedgerConnectPhase { idle, awaitingApproval }

class MobileLedgerConnectScreen extends ConsumerStatefulWidget {
  const MobileLedgerConnectScreen({this.connectionAccountUuid, super.key});

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
    _accountIndexController = TextEditingController(
      text: '${_connectionAccount()?.zip32AccountIndex ?? 0}',
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
      final account = await ref.read(ledgerBluetoothAccountConnectorProvider)(
        accountIndex,
        _selectedDevice!,
      );
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
      await ref.read(ledgerAccountDuplicateCheckerProvider)(account.ufvk);
      if (!mounted) return;
      setState(() => _phase = _MobileLedgerConnectPhase.idle);
      context.push(
        '/onboarding/ledger/birthday',
        extra: LedgerBirthdayArgs(account: account),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _MobileLedgerConnectPhase.idle;
        _error = error is LedgerAppReadinessException
            ? error.message
            : _friendlyError(error);
      });
    }
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

  String _friendlyError(Object error) {
    if (ledgerPairingNeedsReset(error)) return kLedgerPairingInvalidMessage;
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
    if (error is LedgerDuplicateAccountException) return error.toString();
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
    final disclosureLabel =
        'Advanced · Account ${_accountIndexController.text.isEmpty ? '—' : _accountIndexController.text}';
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
                : ledgerPairingNeedsReset(_error)
                ? 'Try again'
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
                    "Shielded: m/32'/133'/${_accountIndexController.text.isEmpty ? '—' : _accountIndexController.text}'\n"
                    "Transparent: m/44'/133'/${_accountIndexController.text.isEmpty ? '—' : _accountIndexController.text}'",
                    key: const ValueKey('ledger_account_derivation_paths'),
                    style: AppTypography.bodySmall.copyWith(
                      color: context.colors.text.secondary,
                    ),
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
          if (ledgerPairingNeedsReset(_error)) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              kLedgerPairingInvalidTitle,
              textAlign: TextAlign.center,
              style: AppTypography.bodyLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ],
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
            if (ledgerPairingNeedsReset(_error))
              const LedgerBluetoothSettingsButton(),
          ],
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
