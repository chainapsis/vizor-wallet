import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../providers/account_provider.dart';
import '../services/ledger_app_readiness_service.dart';
import '../services/ledger_device_selection.dart';
import '../services/ledger_failure_guidance.dart';
import 'ledger_bluetooth_recovery.dart';
import 'ledger_pairing_recovery.dart';
import 'ledger_progress_status.dart';
import 'mobile/mobile_ledger_access_content.dart';

/// A connection recovery surface, never used for saved/broadcast transactions.
class LedgerAccessRecoveryModal extends ConsumerStatefulWidget {
  const LedgerAccessRecoveryModal({
    required this.account,
    required this.onRetry,
    required this.onClose,
    this.pairingRecovery = false,
    this.pairingInvalid = false,
    this.selectionRequest,
    this.retrySelectsDevice = false,
    this.onChangeConnection,
    super.key,
  });
  final AccountInfo? account;
  final bool pairingRecovery;
  final bool pairingInvalid;
  final LedgerDeviceSelectionRequest? selectionRequest;
  final bool retrySelectsDevice;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  final VoidCallback? onChangeConnection;

  @override
  ConsumerState<LedgerAccessRecoveryModal> createState() =>
      _LedgerAccessRecoveryModalState();
}

class _LedgerAccessRecoveryModalState
    extends ConsumerState<LedgerAccessRecoveryModal> {
  late LedgerConnectionTransport? _transport;
  bool _usbBusy = false;
  bool _changing = false;
  bool _canChange = true;
  Object? _usbError;
  String? _changeError;

  @override
  void initState() {
    super.initState();
    final request = widget.selectionRequest;
    _transport = request?.canChooseTransport == true
        ? request!.initialTransport
        : LedgerConnectionTransport.bluetooth;
    if (_transport == LedgerConnectionTransport.usb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_connectUsb());
      });
    }
  }

  Future<void> _connectUsb() async {
    if (_usbBusy || _changing) return;
    setState(() {
      _transport = LedgerConnectionTransport.usb;
      _usbBusy = true;
      _usbError = null;
    });
    try {
      await widget.selectionRequest!.selectUsb();
    } catch (error) {
      if (mounted) setState(() => _usbError = error);
    } finally {
      if (mounted) setState(() => _usbBusy = false);
    }
  }

  Future<void> _changeConnection() async {
    if (_changing || _usbBusy || !_canChange) return;
    final request = widget.selectionRequest;
    if (request == null) {
      widget.onChangeConnection?.call();
      return;
    }
    if (request.busy) return;
    setState(() {
      _changing = true;
      _changeError = null;
    });
    try {
      // Stop the current scan before disposing its UI or allowing USB work.
      await request.stop();
      request.chooseTransport(null);
      if (mounted) {
        setState(() {
          _transport = null;
          _usbError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _changeError = 'Could not stop the search. Try again.');
      }
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  void _refresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    widget.selectionRequest?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kAppFormFactor == AppFormFactor.mobile) {
      return MobileLedgerAccessContent(
        account: widget.account,
        onRetry: widget.onRetry,
        onClose: widget.onClose == null
            ? null
            : () {
                widget.selectionRequest?.cancel();
                widget.onClose?.call();
              },
        pairingRecovery: widget.pairingRecovery,
        pairingInvalid: widget.pairingInvalid,
        selectionRequest: widget.selectionRequest,
        retrySelectsDevice: widget.retrySelectsDevice,
      );
    }
    final request = widget.selectionRequest;
    final canGoBack =
        (request?.canChooseTransport == true ||
            widget.onChangeConnection != null) &&
        _transport != null &&
        _canChange &&
        !_usbBusy &&
        request?.busy != true;
    return AppModalCard(
      width: 328,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (canGoBack) ...[
                  AppButton(
                    onPressed: _changing
                        ? null
                        : () => unawaited(_changeConnection()),
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.small,
                    child: const AppIcon(
                      AppIcons.chevronBackward,
                      size: 16,
                      semanticLabel: 'Change connection',
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(
                  child: Text(
                    _transport == null
                        ? 'Ledger'
                        : 'Ledger · ${_transport == LedgerConnectionTransport.usb ? 'USB' : 'Bluetooth'}',
                    style: AppTypography.bodySmall.copyWith(
                      color: context.colors.text.secondary,
                    ),
                  ),
                ),
                if (widget.onClose != null)
                  AppButton(
                    onPressed: () {
                      request?.cancel();
                      widget.onClose?.call();
                    },
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.small,
                    child: const AppIcon(
                      AppIcons.cross,
                      size: 16,
                      semanticLabel: 'Close',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (_changeError != null) ...[
              Text(
                _changeError!,
                style: AppTypography.bodySmall.copyWith(
                  color: context.colors.text.destructive,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (_transport == null) ...[
              _title(context, 'How would you like to connect?'),
              const SizedBox(height: AppSpacing.xs),
              _message(context, 'Choose a connection for this request.'),
              const SizedBox(height: AppSpacing.sm),
              for (final transport in LedgerConnectionTransport.values)
                _choice(context, transport),
            ] else if (_transport == LedgerConnectionTransport.usb)
              _usbContent(context)
            else if ((widget.pairingRecovery || request != null) &&
                widget.account != null)
              LedgerPairingRecovery(
                accountUuid: widget.account!.uuid,
                pairingInvalid: widget.pairingInvalid,
                selectionRequest: request,
                retrySelectsDevice: widget.retrySelectsDevice,
                onRetry: widget.onRetry,
                onClose: widget.onClose,
                enabled: !_changing,
                onBusyChanged: (_) => _refresh(),
                onCanChangeConnectionChanged: (canChange) {
                  _canChange = canChange;
                  _refresh();
                },
              )
            else
              LedgerBluetoothRecovery(
                enabled: !_changing,
                onRetry: widget.onRetry,
                onClose: widget.onClose,
                onBusyChanged: (busy) {
                  _canChange = !busy;
                  _refresh();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _title(BuildContext context, String text) => Text(
    text,
    style: AppTypography.headlineSmall.copyWith(
      color: context.colors.text.accent,
    ),
  );
  Widget _message(BuildContext context, String text) => Text(
    text,
    style: AppTypography.bodyMedium.copyWith(
      color: context.colors.text.secondary,
    ),
  );

  Widget _choice(
    BuildContext context,
    LedgerConnectionTransport transport,
  ) => Container(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.colors.border.subtle)),
    ),
    child: AppButton(
      key: ValueKey('ledger_choose_${transport.name}'),
      variant: AppButtonVariant.ghost,
      expand: true,
      constrainContent: true,
      height: 64,
      onPressed: _changing
          ? null
          : () {
              if (transport == LedgerConnectionTransport.usb) {
                unawaited(_connectUsb());
              } else {
                widget.selectionRequest!.chooseTransport(transport);
                setState(() {
                  _transport = transport;
                  _canChange = true;
                });
              }
            },
      child: Row(
        children: [
          Icon(
            transport == LedgerConnectionTransport.usb
                ? Icons.usb
                : Icons.bluetooth,
            size: 20,
            color: context.colors.icon.regular,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              transport == LedgerConnectionTransport.usb ? 'USB' : 'Bluetooth',
              style: AppTypography.bodyMediumStrong,
            ),
          ),
          const AppIcon(AppIcons.chevronForward, size: 16),
        ],
      ),
    ),
  );

  Widget _usbContent(BuildContext context) {
    final readiness = ref.watch(ledgerAppReadinessStateProvider);
    final opening =
        _usbBusy && readiness.phase == LedgerAppReadinessPhase.confirmOpening;
    final declined =
        _usbError != null &&
        LedgerRequestFailure.fromError(_usbError!) ==
            LedgerRequestFailure.declined;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(
          context,
          _usbError != null
              ? (declined
                    ? 'Request declined'
                    : 'Couldn’t connect to your Ledger')
              : (opening ? 'Confirm on your Ledger' : 'Checking your Ledger'),
        ),
        const SizedBox(height: AppSpacing.xs),
        _message(
          context,
          _usbError != null
              ? (declined
                    ? LedgerRequestFailure.declined.message
                    : ledgerFailureGuidance(_usbError!)?.message ??
                          'Check the USB cable, unlock your Ledger, and open the Zcash app.')
              : (opening
                    ? 'Approve opening the Zcash app on your Ledger.'
                    : 'Connect your Ledger with a USB cable, unlock it, and open the Zcash app.'),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_usbError == null)
          LedgerProgressStatus(
            label: opening
                ? 'Waiting for approval…'
                : 'Checking USB connection…',
          )
        else
          AppButton(
            expand: true,
            constrainContent: true,
            size: AppButtonSize.large,
            onPressed: () => unawaited(_connectUsb()),
            child: const Text('Try again'),
          ),
      ],
    );
  }
}
