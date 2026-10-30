import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../providers/account_provider.dart';
import '../../ledger_capability.dart';
import '../../ledger_device_label.dart';
import '../../services/ledger_bluetooth_access.dart';
import '../../services/ledger_device_selection.dart';
import '../../services/ledger_pairing_recovery_service.dart';
import 'mobile_ledger_bluetooth_content.dart';
import '../ledger_pairing_session.dart';
import 'mobile_ledger_sheet_content.dart';
import 'mobile_ledger_connection_help.dart';

class MobileLedgerAccessContent extends ConsumerStatefulWidget {
  const MobileLedgerAccessContent({
    required this.account,
    required this.onRetry,
    required this.onClose,
    this.pairingRecovery = false,
    this.pairingInvalid = false,
    this.selectionRequest,
    this.retrySelectsDevice = false,
    super.key,
  });
  final AccountInfo? account;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  final bool pairingRecovery;
  final bool pairingInvalid;
  final LedgerDeviceSelectionRequest? selectionRequest;
  final bool retrySelectsDevice;

  @override
  ConsumerState<MobileLedgerAccessContent> createState() =>
      _MobileLedgerAccessContentState();
}

class _MobileLedgerAccessContentState
    extends ConsumerState<MobileLedgerAccessContent> {
  bool _help = false;

  Future<void> _openHelp(LedgerPairingSessionState session) async {
    if (!await session.pauseForHelp() || !mounted) return;
    setState(() => _help = true);
  }

  void _search(LedgerPairingSessionState session) {
    setState(() => _help = false);
    session.scan();
  }

  Widget _bluetooth({VoidCallback? retry, String retryLabel = 'Reconnect'}) =>
      MobileLedgerBluetoothContent(
        onRetry: retry ?? widget.onRetry,
        onClose: widget.onClose,
        retryLabel: retryLabel,
      );

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    if ((!widget.pairingRecovery && widget.selectionRequest == null) ||
        account == null) {
      return _bluetooth();
    }
    final platform = ref.watch(ledgerTargetPlatformProvider);
    return LedgerPairingSession(
      accountUuid: account.uuid,
      pairingInvalid: widget.pairingInvalid,
      onRetry: widget.onRetry,
      onClose: widget.onClose,
      selectionRequest: widget.selectionRequest,
      retrySelectsDevice: widget.retrySelectsDevice,
      onBusyChanged: (_) {},
      builder: (context, c) {
        if (c.accessRecovery) {
          return _bluetooth(
            retry: () => _search(c),
            retryLabel: 'Find my Ledger',
          );
        }
        if (_help && !c.invalidated) {
          return MobileLedgerConnectionHelp(
            platform: platform,
            initialModel: LedgerHelpModel.fromSavedModel(
              account.ledgerDeviceModel,
            ),
            pairingInvalid: c.pairingInvalid,
            busy: c.busy,
            error: c.error,
            onBack: () => setState(() => _help = false),
            onClose: widget.onClose,
            onSearch: () => _search(c),
            onSettings: c.service is LedgerBluetoothPairingSettings
                ? c.settings
                : null,
          );
        }
        final choosing =
            c.stage == LedgerPairingStage.scanning ||
            c.stage == LedgerPairingStage.devices;
        final helpAvailable =
            (c.stage == LedgerPairingStage.devices && c.devices.isEmpty) ||
            (c.stage == LedgerPairingStage.failed && c.pairingInvalid);
        final title = switch (c.stage) {
          LedgerPairingStage.scanning || LedgerPairingStage.devices =>
            c.devices.isNotEmpty
                ? 'Select your Ledger'
                : c.stage == LedgerPairingStage.scanning
                ? 'Finding your Ledger'
                : 'No Ledger devices found',
          LedgerPairingStage.verifying =>
            c.sameSavedDevice
                ? 'Connecting to your Ledger'
                : 'Check your Ledger',
          LedgerPairingStage.saving => 'Saving your connection',
          LedgerPairingStage.saved => 'Ledger saved',
          LedgerPairingStage.ready => 'Your Ledger is connected',
          LedgerPairingStage.mismatch => 'This Ledger doesn’t match',
          LedgerPairingStage.failed =>
            c.pairingInvalid
                ? 'Pair your Ledger again'
                : c.requestFailure.title,
        };
        final message = switch (c.stage) {
          LedgerPairingStage.scanning || LedgerPairingStage.devices =>
            c.devices.isEmpty
                ? 'Keep your Ledger nearby and unlocked, with Bluetooth turned on.'
                : 'Choose a device to continue.',
          LedgerPairingStage.verifying =>
            c.sameSavedDevice
                ? 'Unlock your Ledger and open the Zcash app. Approve opening it if prompted.'
                : 'Complete pairing if prompted, then open the Zcash app and approve sharing the viewing key.',
          LedgerPairingStage.saving =>
            'Your account matches. Saving the verified connection.',
          LedgerPairingStage.saved =>
            'This Ledger matches your account and is now saved. Find it again to continue.',
          LedgerPairingStage.ready =>
            'Continue when you’re ready to review the transaction on your Ledger.',
          LedgerPairingStage.mismatch =>
            'Choose the Ledger that holds this account. Your saved connection hasn’t changed.',
          LedgerPairingStage.failed =>
            c.pairingInvalid
                ? 'Your Ledger no longer recognizes this Bluetooth pairing.'
                : c.failureMessage,
        };
        return MobileLedgerSheetContent(
          title: title,
          onClose: widget.onClose,
          action: c.busy
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MobileLedgerAction(
                      switch (c.stage) {
                        LedgerPairingStage.ready => 'Continue signing',
                        LedgerPairingStage.mismatch => 'Choose another Ledger',
                        LedgerPairingStage.devices => 'Search again',
                        LedgerPairingStage.failed when !c.pairingInvalid =>
                          c.failureRetryable
                              ? 'Try again'
                              : 'Choose another Ledger',
                        _ => 'Find my Ledger',
                      },
                      onPressed: c.invalidated
                          ? null
                          : c.stage == LedgerPairingStage.ready
                          ? c.continueSigning
                          : c.scan,
                    ),
                    if (helpAvailable)
                      AppButton(
                        variant: AppButtonVariant.ghost,
                        expand: true,
                        constrainContent: true,
                        growWithContent: true,
                        onPressed: c.invalidated ? null : () => _openHelp(c),
                        child: Text(
                          c.pairingInvalid
                              ? 'Reset Bluetooth pairing'
                              : 'Connection help',
                        ),
                      ),
                  ],
                ),
          children: [
            MobileLedgerMessage(message),
            if (choosing && c.devices.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              for (final device in c.devices)
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: context.colors.border.subtle),
                    ),
                  ),
                  child: AppButton(
                    variant: AppButtonVariant.ghost,
                    expand: true,
                    constrainContent: true,
                    growWithContent: true,
                    height: 72,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    onPressed: c.invalidated ? null : () => c.select(device),
                    child: Row(
                      children: [
                        const AppIcon(AppIcons.ledger, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ledgerDeviceLabel(device),
                                style: AppTypography.bodyMediumStrong,
                              ),
                              if (ledgerDeviceDiffersFromSavedConnection(
                                account.ledgerDeviceId,
                                device.id,
                              )) ...[
                                const SizedBox(height: AppSpacing.xxs),
                                Text(
                                  'Different from saved connection',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: context.colors.text.secondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const AppIcon(AppIcons.chevronForward, size: 16),
                      ],
                    ),
                  ),
                ),
            ],
            if (!choosing && c.selectedDevice != null)
              MobileLedgerIdentity(ledgerDeviceLabel(c.selectedDevice!)),
            if (c.error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              MobileLedgerMessage(c.error!),
            ],
            if (c.busy && !(choosing && c.devices.isNotEmpty))
              MobileLedgerStatus(
                c.preparingHelp
                    ? 'Opening connection help…'
                    : switch (c.stage) {
                        LedgerPairingStage.scanning =>
                          c.devices.isEmpty
                              ? 'Searching nearby…'
                              : 'Still searching nearby…',
                        LedgerPairingStage.verifying =>
                          c.sameSavedDevice
                              ? 'Connecting…'
                              : 'Follow the prompts on your Ledger',
                        LedgerPairingStage.saving => 'Saving connection…',
                        _ => 'Opening Bluetooth settings…',
                      },
              ),
          ],
        );
      },
    );
  }
}
