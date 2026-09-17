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

class MobileLedgerAccessContent extends ConsumerWidget {
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

  Widget _bluetooth({VoidCallback? retry, String retryLabel = 'Reconnect'}) =>
      MobileLedgerBluetoothContent(
        onRetry: retry ?? onRetry,
        onClose: onClose,
        retryLabel: retryLabel,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if ((!pairingRecovery && selectionRequest == null) || account == null) {
      return _bluetooth();
    }
    final platform = ref.watch(ledgerTargetPlatformProvider);
    return LedgerPairingSession(
      accountUuid: account!.uuid,
      pairingInvalid: pairingInvalid,
      onRetry: onRetry,
      onClose: onClose,
      selectionRequest: selectionRequest,
      retrySelectsDevice: retrySelectsDevice,
      onBusyChanged: (_) {},
      builder: (context, c) {
        if (c.accessRecovery) {
          return _bluetooth(retry: c.scan, retryLabel: 'Find my Ledger');
        }
        final choosing =
            c.stage == LedgerPairingStage.scanning ||
            c.stage == LedgerPairingStage.devices;
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
          LedgerPairingStage.ready =>
            c.connectionUpdated
                ? 'This Ledger matches your account. Your saved connection has been updated.'
                : 'Continue when you’re ready to review the transaction on your Ledger.',
          LedgerPairingStage.mismatch =>
            'Choose the Ledger that holds this account. Your saved connection hasn’t changed.',
          LedgerPairingStage.failed =>
            c.pairingInvalid
                ? 'Your Ledger no longer recognizes this Bluetooth pairing.'
                : c.requestFailure.message,
        };
        return MobileLedgerSheetContent(
          title: title,
          onClose: onClose,
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
                                account?.ledgerDeviceId,
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
            if (c.stage == LedgerPairingStage.failed && c.pairingInvalid) ...[
              const SizedBox(height: AppSpacing.sm),
              MobileLedgerMessage(
                platform == TargetPlatform.iOS
                    ? 'Open Settings > Bluetooth. If your Ledger is listed, tap its info button and forget the device. Then come back and find your Ledger again.'
                    : 'Open Bluetooth settings and remove your Ledger’s saved pairing. Then come back and find your Ledger again.',
              ),
              if (platform != TargetPlatform.iOS &&
                  c.service is LedgerBluetoothPairingSettings)
                AppButton(
                  variant: AppButtonVariant.ghost,
                  onPressed: c.busy ? null : c.settings,
                  child: const Text('Open settings'),
                ),
            ],
            if (c.error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              MobileLedgerMessage(c.error!),
            ],
            if (c.busy)
              MobileLedgerStatus(switch (c.stage) {
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
              })
            else
              MobileLedgerAction(
                switch (c.stage) {
                  LedgerPairingStage.ready => 'Continue signing',
                  LedgerPairingStage.mismatch => 'Choose another Ledger',
                  LedgerPairingStage.devices => 'Search again',
                  LedgerPairingStage.failed when !c.pairingInvalid =>
                    'Try again',
                  _ => 'Find my Ledger',
                },
                onPressed: c.invalidated
                    ? null
                    : c.stage == LedgerPairingStage.ready
                    ? c.continueSigning
                    : c.scan,
              ),
          ],
        );
      },
    );
  }
}
