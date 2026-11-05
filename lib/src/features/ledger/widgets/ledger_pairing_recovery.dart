import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../ledger_device_label.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/account_provider.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../ledger_capability.dart';
import '../services/ledger_bluetooth_access.dart';
import '../services/ledger_device_selection.dart';
import '../services/ledger_pairing_recovery_service.dart';
import 'ledger_bluetooth_recovery.dart';
import 'ledger_progress_status.dart';

import 'ledger_pairing_session.dart';

class LedgerPairingRecovery extends ConsumerWidget {
  const LedgerPairingRecovery({
    required this.accountUuid,
    required this.onRetry,
    required this.onClose,
    required this.onBusyChanged,
    this.onCanChangeConnectionChanged,
    this.enabled = true,
    this.pairingInvalid = false,
    this.selectionRequest,
    this.retrySelectsDevice = false,
    super.key,
  });
  final String accountUuid;
  final VoidCallback? onRetry;
  final VoidCallback? onClose;
  final ValueChanged<bool> onBusyChanged;
  final ValueChanged<bool>? onCanChangeConnectionChanged;
  final bool enabled;
  final bool pairingInvalid;
  final LedgerDeviceSelectionRequest? selectionRequest;
  final bool retrySelectsDevice;

  @override
  Widget build(BuildContext context, WidgetRef ref) => LedgerPairingSession(
    accountUuid: accountUuid,
    pairingInvalid: pairingInvalid,
    onRetry: onRetry,
    onClose: onClose,
    onBusyChanged: onBusyChanged,
    onCanChangeConnectionChanged: onCanChangeConnectionChanged,
    enabled: enabled,
    selectionRequest: selectionRequest,
    retrySelectsDevice: retrySelectsDevice,
    builder: (context, session) => _buildContent(context, ref, session),
  );

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    LedgerPairingSessionState c,
  ) {
    if (c.accessRecovery) {
      return LedgerBluetoothRecovery(
        service: c.service,
        onRetry: c.scan,
        onClose: onClose,
        retryLabel: context.l10n.ledgerFindMyLedger,
        enabled: enabled,
        onBusyChanged: onBusyChanged,
      );
    }
    final savedId = ref
        .watch(accountProvider)
        .value
        ?.accounts
        .where((account) => account.uuid == accountUuid)
        .firstOrNull
        ?.ledgerDeviceId;
    final platform = ref.watch(ledgerTargetPlatformProvider);
    final settingsLink =
        platform != TargetPlatform.iOS &&
        c.service is LedgerBluetoothPairingSettings;
    final l10n = context.l10n;
    final title = switch (c.stage) {
      LedgerPairingStage.failed =>
        c.pairingInvalid
            ? l10n.ledgerTitlePairAgain
            : c.requestFailure.title(l10n),
      LedgerPairingStage.scanning || LedgerPairingStage.devices =>
        c.devices.isEmpty
            ? (c.stage == LedgerPairingStage.scanning
                  ? l10n.ledgerTitleFindingLedger
                  : l10n.ledgerNoDevicesFound)
            : l10n.ledgerTitleSelectYourLedger,
      LedgerPairingStage.verifying =>
        c.sameSavedDevice
            ? l10n.ledgerTitleConnectingToLedger
            : l10n.ledgerSigningTitleReviewing,
      LedgerPairingStage.saving => l10n.ledgerTitleSavingConnection,
      LedgerPairingStage.saved => l10n.ledgerTitleLedgerSaved,
      LedgerPairingStage.ready => l10n.ledgerTitleLedgerConnected,
      LedgerPairingStage.mismatch => l10n.ledgerTitleMismatch,
    };
    final message = switch (c.stage) {
      LedgerPairingStage.failed =>
        c.pairingInvalid
            ? l10n.ledgerPairingNoLongerRecognizedRemove
            : c.failureMessage(l10n),
      LedgerPairingStage.scanning || LedgerPairingStage.devices =>
        c.devices.isEmpty
            ? l10n.ledgerKeepNearbyUnlockedShort
            : l10n.ledgerChooseLedgerForAccount,
      LedgerPairingStage.verifying =>
        c.sameSavedDevice
            ? l10n.ledgerUnlockOpenZcashApprove
            : l10n.ledgerCompletePairingOpenZcash,
      LedgerPairingStage.saving => l10n.ledgerSavingVerified,
      LedgerPairingStage.saved => l10n.ledgerSavedMatchesFindAgain,
      LedgerPairingStage.ready => l10n.ledgerReadyReviewOnLedger,
      LedgerPairingStage.mismatch => l10n.ledgerMismatchConnectHolder,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            style: AppTypography.headlineSmall.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          message,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
        if ((c.stage == LedgerPairingStage.saved ||
                (c.stage == LedgerPairingStage.failed && !c.pairingInvalid)) &&
            c.selectedDevice != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              AppIcon(
                AppIcons.ledger,
                size: 20,
                color: context.colors.icon.regular,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  ledgerDeviceLabel(c.selectedDevice!),
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (c.stage == LedgerPairingStage.failed && c.pairingInvalid) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: context.colors.background.neutralSubtleOpacity,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: AppSpacing.sm,
                    bottom: AppSpacing.sm,
                  ),
                  child: Column(
                    children: [
                      _step(
                        context,
                        '1',
                        l10n.ledgerRemoveOldPairing,
                        platform == TargetPlatform.iOS
                            ? l10n.ledgerRemovePairingIos
                            : platform == TargetPlatform.macOS
                            ? l10n.ledgerRemovePairingMacos
                            : l10n.ledgerRemovePairingOther,
                        settingsLink
                            ? AppButton(
                                variant: AppButtonVariant.ghost,
                                size: AppButtonSize.small,
                                height: 44,
                                contentPadding: EdgeInsets.zero,
                                trailing: const AppIcon(
                                  AppIcons.arrowTopRight,
                                  size: 14,
                                ),
                                onPressed: enabled && !c.busy
                                    ? c.settings
                                    : null,
                                child: Text(
                                  l10n.commonOpenSettings,
                                  style: AppTypography.bodySmall.copyWith(
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _step(
                        context,
                        '2',
                        l10n.ledgerComeBackReconnect,
                        l10n.ledgerComeBackFindMyLedger,
                        null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        if (c.error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              c.error!,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
        if (c.stage == LedgerPairingStage.devices ||
            c.stage == LedgerPairingStage.scanning)
          ...c.devices.map(
            (device) => Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: context.colors.background.neutralSubtleOpacity,
                  ),
                ),
              ),
              child: AppButton(
                expand: true,
                constrainContent: true,
                variant: AppButtonVariant.ghost,
                height: 64,
                borderRadius: BorderRadius.circular(AppRadii.small),
                growWithContent: true,
                contentPadding: EdgeInsets.zero,
                onPressed: enabled && !c.invalidated
                    ? () => c.select(device)
                    : null,
                child: Row(
                  children: [
                    const AppIcon(AppIcons.ledger, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ledgerDeviceLabel(device)),
                          if (ledgerDeviceDiffersFromSavedConnection(
                            savedId,
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
                    const AppIcon(AppIcons.chevronForward, size: 16),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        if (c.busy)
          LedgerProgressStatus(
            label: switch (c.stage) {
              LedgerPairingStage.scanning =>
                c.devices.isEmpty
                    ? l10n.ledgerStatusSearchingNearby
                    : l10n.ledgerStatusStillSearching,
              LedgerPairingStage.verifying =>
                c.sameSavedDevice
                    ? l10n.commonConnecting
                    : l10n.ledgerStatusFollowPrompts,
              LedgerPairingStage.saving => l10n.ledgerStatusSavingConnection,
              _ => l10n.ledgerStatusOpeningBluetoothSettings,
            },
          )
        else
          AppButton(
            expand: true,
            constrainContent: true,
            size: AppButtonSize.large,
            onPressed: c.busy || !enabled || c.invalidated
                ? null
                : c.stage == LedgerPairingStage.ready
                ? c.continueSigning
                : c.scan,
            child: Text(switch (c.stage) {
              LedgerPairingStage.scanning => l10n.ledgerButtonSearching,
              LedgerPairingStage.verifying =>
                c.sameSavedDevice
                    ? l10n.ledgerButtonConnecting
                    : l10n.ledgerButtonCheckingAccount,
              LedgerPairingStage.saving => l10n.commonSaving,
              LedgerPairingStage.ready => l10n.ledgerContinueSigning,
              LedgerPairingStage.mismatch => l10n.ledgerChooseAnother,
              LedgerPairingStage.devices => l10n.ledgerSearchAgain,
              LedgerPairingStage.failed when !c.pairingInvalid =>
                c.failureRetryable
                    ? l10n.commonTryAgain
                    : l10n.ledgerChooseAnother,
              _ => l10n.ledgerFindMyLedger,
            }),
          ),
      ],
    );
  }

  Widget _step(
    BuildContext context,
    String number,
    String title,
    String body,
    Widget? action,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: context.colors.background.neutralSubtleOpacity,
          ),
        ),
        child: Text(
          number,
          style: AppTypography.bodySmall.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.bodySmall),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              body,
              style: AppTypography.bodySmall.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            ?action,
          ],
        ),
      ),
    ],
  );
}
