import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../ledger/ledger_setup_args.dart';
import 'mobile_ledger_device_sheet.dart';
import 'mobile_onboarding_scaffold.dart';

enum _MobileLedgerConnectPhase { idle, awaitingApproval }

class MobileLedgerConnectScreen extends ConsumerStatefulWidget {
  const MobileLedgerConnectScreen({super.key});

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
  bool _showAdvancedOptions = false;

  bool get _busy => _phase != _MobileLedgerConnectPhase.idle;

  @override
  void initState() {
    super.initState();
    _cancelLedgerOperation = ref.read(ledgerOperationCancellerProvider);
    _accountIndexController = TextEditingController(text: '0');
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
    final accountIndex = int.tryParse(_accountIndexController.text);
    if (accountIndex == null ||
        accountIndex < 0 ||
        accountIndex >= 0x80000000) {
      setState(
        () => _error = 'Account index must be between 0 and 2147483647.',
      );
      return;
    }
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
                    key: const ValueKey('mobile_ledger_account_index_field'),
                    label: 'Ledger account index',
                    controller: _accountIndexController,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
