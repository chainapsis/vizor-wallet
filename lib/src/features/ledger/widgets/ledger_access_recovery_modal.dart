import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import 'ledger_modal_content.dart';
import 'ledger_pairing_session.dart';
import 'ledger_bluetooth_session.dart';
import 'ledger_bluetooth_restricted_help.dart';
import '../ledger_device_label.dart';
import '../ledger_capability.dart';
import '../../../providers/account_provider.dart';
import '../services/ledger_app_readiness_service.dart';
import '../services/ledger_bluetooth_access.dart';
import '../services/ledger_device_selection.dart';
import '../services/ledger_failure_guidance.dart';
import '../services/ledger_pairing_recovery_service.dart';
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
  final _pairing = GlobalKey<LedgerPairingSessionState>();
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
    if (request?.busy == true) return;
    setState(() {
      _changing = true;
      _changeError = null;
    });
    try {
      // Stop the current scan before disposing its UI or allowing USB work.
      if (_pairing.currentState case final pairing?) {
        await pairing.stopSearch();
      } else {
        await request?.stop();
      }
      if (!mounted) return;
      if (request == null) {
        widget.onChangeConnection?.call();
        return;
      }
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
    void close() {
      request?.cancel();
      widget.onClose?.call();
    }

    Widget footer({String? label, VoidCallback? action}) {
      if (label == 'Close') {
        return Center(
          child: AppButton(
            size: AppButtonSize.mediumLarge,
            minWidth: kAppModalButtonMinWidth,
            onPressed: action,
            child: const Text('Close'),
          ),
        );
      }
      if (label != null && widget.onClose != null) {
        return AppModalActions(
          onCancel: close,
          actionLabel: label,
          onAction: action,
        );
      }
      if (label != null) {
        return AppButton(
          size: AppButtonSize.mediumLarge,
          expand: true,
          constrainContent: true,
          onPressed: action,
          child: Text(label),
        );
      }
      if (widget.onClose != null) {
        return Center(
          child: AppButton(
            size: AppButtonSize.mediumLarge,
            variant: AppButtonVariant.ghost,
            minWidth: kAppModalButtonMinWidth,
            onPressed: close,
            child: const Text('Cancel'),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    Widget frame(
      String title,
      Widget body, {
      String? label,
      VoidCallback? action,
      String? identity,
    }) => LedgerModalContent(
      title: title,
      identity: identity,
      backLabel: 'Change connection',
      onBack: canGoBack && !_changing
          ? () => unawaited(_changeConnection())
          : null,
      footer: _changing ? null : footer(label: label, action: action),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_changeError != null) ...[
            _message(context, _changeError!),
            const SizedBox(height: AppSpacing.s),
          ],
          body,
        ],
      ),
    );
    Widget bluetooth(VoidCallback? retry) => LedgerBluetoothSession(
      enabled: !_changing,
      onRetry: retry,
      onClose: widget.onClose == null ? null : close,
      retryLabel: 'Find Ledger',
      onBusyChanged: (busy) {
        _canChange = !busy;
        _refresh();
      },
      builder: (context, c) => frame(
        c.title,
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _message(context, c.message),
            LedgerBluetoothRestrictedHelp(model: c),
            if (c.busy)
              const LedgerProgressStatus(label: 'Checking Bluetooth access…'),
          ],
        ),
        label: c.label,
        action: c.onAction,
      ),
    );
    if (_transport == null) {
      return frame(
        'Connect Ledger',
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _message(context, 'Connect the Ledger for this account.'),
            const SizedBox(height: AppSpacing.sm),
            for (final transport in LedgerConnectionTransport.values)
              _choice(context, transport),
          ],
        ),
      );
    }
    if (_transport == LedgerConnectionTransport.usb) {
      return frame(
        'Connect Ledger',
        _usbContent(context),
        label: _usbError == null ? null : 'Try again',
        action: _usbError == null ? null : () => unawaited(_connectUsb()),
        identity: 'USB connection',
      );
    }
    if ((!widget.pairingRecovery && request == null) ||
        widget.account == null) {
      return bluetooth(widget.onRetry);
    }
    final savedId = ref
        .watch(accountProvider)
        .value
        ?.accounts
        .where((account) => account.uuid == widget.account!.uuid)
        .firstOrNull
        ?.ledgerDeviceId;
    final platform = ref.watch(ledgerTargetPlatformProvider);
    return LedgerPairingSession(
      key: _pairing,
      accountUuid: widget.account!.uuid,
      pairingInvalid: widget.pairingInvalid,
      selectionRequest: request,
      retrySelectsDevice: widget.retrySelectsDevice,
      onRetry: widget.onRetry,
      onClose: widget.onClose,
      enabled: !_changing,
      onBusyChanged: (_) => _refresh(),
      onCanChangeConnectionChanged: (value) {
        _canChange = value;
        _refresh();
      },
      builder: (context, c) {
        if (_changing) {
          return frame(
            'Stopping search',
            const LedgerProgressStatus(
              label: 'Returning to connection options…',
            ),
          );
        }
        if (c.accessRecovery) return bluetooth(c.scan);
        final choosing =
            c.stage == LedgerPairingStage.scanning ||
            c.stage == LedgerPairingStage.devices;
        final message = switch (c.stage) {
          LedgerPairingStage.scanning || LedgerPairingStage.devices =>
            c.devices.isEmpty
                ? c.busy
                      ? 'Unlock Ledger, enable Bluetooth and keep it nearby.'
                      : 'No Ledger found. Unlock Ledger, enable Bluetooth and keep it nearby. Then search again.'
                : 'Choose a device to continue.',
          LedgerPairingStage.verifying =>
            c.sameSavedDevice
                ? 'Unlock Ledger and confirm opening Zcash if prompted.'
                : 'Complete pairing if prompted, then approve sharing your viewing key.',
          LedgerPairingStage.saving =>
            'Your account matches. Saving the verified connection.',
          LedgerPairingStage.saved =>
            'This Ledger matches your account. Find it again to continue.',
          LedgerPairingStage.ready =>
            'Your Ledger is ready. Continue signing when you’re ready.',
          LedgerPairingStage.mismatch =>
            'Choose the Ledger that holds this account. Your saved connection has not changed.',
          LedgerPairingStage.failed =>
            c.pairingInvalid
                ? 'Your Ledger no longer recognizes this Bluetooth pairing.'
                : c.failureMessage,
        };
        final title = choosing
            ? 'Find Ledger'
            : c.stage == LedgerPairingStage.mismatch
            ? 'This Ledger doesn’t match'
            : c.stage == LedgerPairingStage.failed
            ? c.pairingInvalid
                  ? 'Pair your Ledger again'
                  : c.requestFailure.title
            : 'Connect Ledger';
        final label = c.busy
            ? null
            : switch (c.stage) {
                LedgerPairingStage.ready => 'Continue signing',
                LedgerPairingStage.devices => 'Search again',
                LedgerPairingStage.mismatch => 'Choose another Ledger',
                LedgerPairingStage.failed when !c.pairingInvalid =>
                  c.failureRetryable ? 'Try again' : 'Choose another Ledger',
                _ => 'Find Ledger',
              };
        return frame(
          title,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _message(context, message),
              if (c.stage == LedgerPairingStage.failed && c.pairingInvalid) ...[
                const SizedBox(height: AppSpacing.sm),
                _recoveryStep(
                  context,
                  '1',
                  'Remove the old pairing',
                  platform == TargetPlatform.iOS
                      ? 'Open Settings > Bluetooth. If your Ledger is listed, tap its info button and forget the device.'
                      : 'Open ${platform == TargetPlatform.macOS ? 'System Settings > Bluetooth' : 'Bluetooth settings'}. If your Ledger is listed, remove its saved pairing.',
                ),
                if (platform != TargetPlatform.iOS &&
                    c.service is LedgerBluetoothPairingSettings)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      onPressed: c.busy ? null : c.settings,
                      variant: AppButtonVariant.ghost,
                      child: const Text('Open settings'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                _recoveryStep(
                  context,
                  '2',
                  'Come back and reconnect',
                  'Keep your Ledger unlocked, then select Find Ledger below.',
                ),
              ],
              if (choosing)
                for (final device in c.devices)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: AppButton(
                      variant: AppButtonVariant.secondary,
                      borderRadius: BorderRadius.circular(AppRadii.small),
                      expand: true,
                      constrainContent: true,
                      growWithContent: true,
                      height: 54,
                      onPressed: c.invalidated ? null : () => c.select(device),
                      child: Row(
                        children: [
                          const AppIcon(AppIcons.ledger, size: 20),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ledgerDeviceLabel(device)),
                                if (ledgerDeviceDiffersFromSavedConnection(
                                  savedId,
                                  device.id,
                                ))
                                  Text(
                                    'Different from saved connection',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: context.colors.text.secondary,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const AppIcon(AppIcons.chevronForward, size: 16),
                        ],
                      ),
                    ),
                  ),
              if (c.busy)
                LedgerProgressStatus(
                  label: choosing
                      ? 'Searching for nearby Ledgers…'
                      : 'Follow the prompts on Ledger.',
                ),
              if (c.error != null) _message(context, c.error!),
            ],
          ),
          label: label,
          action: c.invalidated
              ? null
              : c.stage == LedgerPairingStage.ready
              ? c.continueSigning
              : c.scan,
          identity: c.selectedDevice == null
              ? null
              : '${ledgerDeviceLabel(c.selectedDevice!)} · Bluetooth',
        );
      },
    );
  }

  Widget _message(BuildContext context, String text) => Text(
    text,
    style: AppTypography.bodyMedium.copyWith(
      color: context.colors.text.secondary,
    ),
  );

  Widget _recoveryStep(
    BuildContext context,
    String number,
    String title,
    String message,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 24, child: _message(context, number)),
      const SizedBox(width: AppSpacing.s),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppTypography.bodyMediumStrong),
            const SizedBox(height: AppSpacing.xs),
            _message(context, message),
          ],
        ),
      ),
    ],
  );

  Widget _choice(BuildContext context, LedgerConnectionTransport transport) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: AppButton(
          key: ValueKey('ledger_choose_${transport.name}'),
          variant: AppButtonVariant.secondary,
          borderRadius: BorderRadius.circular(AppRadii.small),
          expand: true,
          constrainContent: true,
          growWithContent: true,
          height: 52,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xs,
          ),
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
              if (transport == LedgerConnectionTransport.usb)
                const AppIcon(AppIcons.usb, size: 20)
              else
                const Icon(Icons.bluetooth, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  transport == LedgerConnectionTransport.usb
                      ? 'USB'
                      : 'Bluetooth',
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
          ),
      ],
    );
  }
}
