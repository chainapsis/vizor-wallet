import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/l10n.dart';
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

  Widget _bluetooth({VoidCallback? retry, String? retryLabel}) =>
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
            retryLabel: context.l10n.ledgerFindMyLedger,
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
        final l10n = context.l10n;
        final choosing =
            c.stage == LedgerPairingStage.scanning ||
            c.stage == LedgerPairingStage.devices;
        final helpAvailable =
            (c.stage == LedgerPairingStage.devices && c.devices.isEmpty) ||
            (c.stage == LedgerPairingStage.failed && c.pairingInvalid);
        final title = switch (c.stage) {
          LedgerPairingStage.scanning || LedgerPairingStage.devices =>
            c.devices.isNotEmpty
                ? l10n.ledgerTitleSelectYourLedger
                : c.stage == LedgerPairingStage.scanning
                ? l10n.ledgerTitleFindingLedger
                : l10n.ledgerNoDevicesFound,
          LedgerPairingStage.verifying =>
            c.sameSavedDevice
                ? l10n.ledgerTitleConnectingToLedger
                : l10n.ledgerSigningTitleReviewing,
          LedgerPairingStage.saving => l10n.ledgerTitleSavingConnection,
          LedgerPairingStage.saved => l10n.ledgerTitleLedgerSaved,
          LedgerPairingStage.ready => l10n.ledgerTitleLedgerConnected,
          LedgerPairingStage.mismatch => l10n.ledgerTitleMismatch,
          LedgerPairingStage.failed =>
            c.pairingInvalid
                ? l10n.ledgerTitlePairAgain
                : c.requestFailure.title(l10n),
        };
        final message = switch (c.stage) {
          LedgerPairingStage.scanning || LedgerPairingStage.devices =>
            c.devices.isEmpty
                ? l10n.ledgerKeepNearbyUnlocked
                : l10n.ledgerChooseDevice,
          LedgerPairingStage.verifying =>
            c.sameSavedDevice
                ? l10n.ledgerUnlockOpenZcashApprove
                : l10n.ledgerCompletePairingOpenZcash,
          LedgerPairingStage.saving => l10n.ledgerSavingVerified,
          LedgerPairingStage.saved => l10n.ledgerSavedMatchesFindAgain,
          LedgerPairingStage.ready => l10n.ledgerReadyReviewOnLedger,
          LedgerPairingStage.mismatch => l10n.ledgerMismatchChooseHolder,
          LedgerPairingStage.failed =>
            c.pairingInvalid
                ? l10n.ledgerPairingNoLongerRecognized
                : c.failureMessage(l10n),
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
                        LedgerPairingStage.ready => l10n.ledgerContinueSigning,
                        LedgerPairingStage.mismatch => l10n.ledgerChooseAnother,
                        LedgerPairingStage.devices => l10n.ledgerSearchAgain,
                        LedgerPairingStage.failed when !c.pairingInvalid =>
                          c.failureRetryable
                              ? l10n.commonTryAgain
                              : l10n.ledgerChooseAnother,
                        _ => l10n.ledgerFindMyLedger,
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
                              ? l10n.ledgerResetBluetoothPairing
                              : l10n.ledgerConnectionHelp,
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
                                  l10n.ledgerDifferentFromSaved,
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
                    ? l10n.ledgerOpeningConnectionHelp
                    : switch (c.stage) {
                        LedgerPairingStage.scanning =>
                          c.devices.isEmpty
                              ? l10n.ledgerStatusSearchingNearby
                              : l10n.ledgerStatusStillSearching,
                        LedgerPairingStage.verifying =>
                          c.sameSavedDevice
                              ? l10n.ledgerStatusConnecting
                              : l10n.ledgerStatusFollowPrompts,
                        LedgerPairingStage.saving =>
                          l10n.ledgerStatusSavingConnection,
                        _ => l10n.ledgerStatusOpeningBluetoothSettings,
                      },
              ),
          ],
        );
      },
    );
  }
}
