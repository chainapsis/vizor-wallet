import '../../../core/layout/app_form_factor.dart';
import 'mobile/mobile_ledger_signing_content.dart';

import 'package:flutter/widgets.dart';

import 'ledger_access_recovery_modal.dart';
import '../services/ledger_device_selection.dart';
import '../services/ledger_mobile_ble_service.dart';
import '../services/ledger_bluetooth_access.dart';
import '../../../core/navigation/payment_uri_busy_surface_hold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../ledger_capability.dart';
import '../services/ledger_app_readiness_service.dart';
import '../services/ledger_signing_progress.dart';
import 'ledger_device_app_prompt.dart';

enum LedgerSigningModalPhase {
  preparing,
  awaitingDevice,
  saving,
  broadcasting,
  failed,
}

class LedgerSigningFailurePresentation {
  const LedgerSigningFailurePresentation({
    required this.title,
    required this.statusLabel,
    required this.message,
    required this.showDeviceAppPrompt,
    this.actionLabel,
    this.isError = true,
    this.showConnectionPicker = true,
    this.bluetoothRecovery = false,
    this.pairingRecovery = false,
    this.pairingInvalid = false,
  });

  final String title;
  final String statusLabel;
  final String message;
  final bool showDeviceAppPrompt;
  final String? actionLabel;
  final bool isError;
  final bool showConnectionPicker;
  final bool bluetoothRecovery;
  final bool pairingRecovery;
  final bool pairingInvalid;
}

class LedgerSigningModal extends ConsumerWidget {
  const LedgerSigningModal({
    required this.phase,
    required this.failure,
    required this.onCancel,
    required this.onFailureAction,
    this.cancelLabel = 'Cancel',
    this.accountUuid,
    this.connectionScope,
    this.signingStage,
    this.roundFeeNotice,
    this.roundNumber = 1,
    this.roundCount = 1,
    super.key,
  }) : assert(roundNumber > 0 && roundNumber <= roundCount),
       assert(roundCount > 0),
       assert(
         phase == LedgerSigningModalPhase.failed || failure == null,
         'Failure presentation is only valid for the failed phase.',
       ),
       assert(
         phase != LedgerSigningModalPhase.failed || failure != null,
         'The failed phase requires an explicit presentation.',
       );

  final LedgerSigningModalPhase phase;
  final LedgerSigningFailurePresentation? failure;
  final VoidCallback? onCancel;
  final VoidCallback? onFailureAction;
  final String cancelLabel;
  final String? accountUuid;
  final LedgerConnectionScope? connectionScope;
  final LedgerSigningStage? signingStage;
  final String? roundFeeNotice;
  final int roundNumber;
  final int roundCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PaymentUriBusySurfaceHold(child: _buildContent(context, ref));

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final networkName = ref.watch(
      rpcEndpointProvider.select((endpoint) => endpoint.networkName),
    );
    final appName = ledgerZcashAppName(networkName);
    final readiness = ref.watch(ledgerAppReadinessStateProvider);
    final account = _ledgerAccount(ref, accountUuid);
    final selection = ref.watch(ledgerDeviceSelectionProvider);
    if (selection != null &&
        selection.accountUuid == accountUuid &&
        account != null) {
      return LedgerAccessRecoveryModal(
        key: ObjectKey(selection),
        account: account,
        selectionRequest: selection,
        onRetry: null,
        onClose: onCancel,
      );
    }
    final failed = phase == LedgerSigningModalPhase.failed;
    final failure = this.failure;
    final canChangeConnection =
        failed &&
        failure!.showConnectionPicker &&
        onFailureAction != null &&
        connectionScope != null &&
        ref.watch(ledgerTargetPlatformProvider) == TargetPlatform.macOS;
    void changeConnection() {
      connectionScope!.changeConnection();
      onFailureAction?.call();
    }

    if (failed &&
        (failure!.bluetoothRecovery ||
            (failure.pairingRecovery && account != null)) &&
        ref.watch(ledgerMobileBleServiceProvider) is LedgerBluetoothAccess) {
      return LedgerAccessRecoveryModal(
        key: ValueKey(accountUuid),
        account: account,
        pairingRecovery: failure.pairingRecovery,
        pairingInvalid: failure.pairingInvalid,
        retrySelectsDevice: true,
        onChangeConnection: canChangeConnection ? changeConnection : null,
        onRetry: onFailureAction,
        onClose: onCancel,
      );
    }
    final error = failed && failure!.isError;
    final progress = ref.watch(ledgerSigningProgressProvider);
    final stage = switch (phase) {
      LedgerSigningModalPhase.preparing => LedgerSigningStage.preparing,
      LedgerSigningModalPhase.awaitingDevice =>
        signingStage ??
            (progress?.accountUuid == accountUuid ? progress?.stage : null) ??
            LedgerSigningStage.preparing,
      LedgerSigningModalPhase.saving ||
      LedgerSigningModalPhase.broadcasting => LedgerSigningStage.finishing,
      LedgerSigningModalPhase.failed => LedgerSigningStage.preparing,
    };
    var title = failed ? failure!.title : stage.title;
    var message = failed
        ? failure!.message
        : stage.messageForDevice(
            progress?.accountUuid == accountUuid ? progress?.deviceModel : null,
          );
    var statusLabel = failed ? failure!.statusLabel : stage.status;
    if (roundCount > 1) {
      final progress = 'Transaction $roundNumber of $roundCount';
      if (!failed) statusLabel = progress;
    }
    if ((phase == LedgerSigningModalPhase.awaitingDevice ||
            phase == LedgerSigningModalPhase.preparing) &&
        stage == LedgerSigningStage.preparing) {
      switch (readiness.phase) {
        case LedgerAppReadinessPhase.checkingDevice:
          title = 'Checking your Ledger';
          statusLabel = 'Checking device';
          message = 'Vizor is checking whether the Zcash app is ready.';
        case LedgerAppReadinessPhase.confirmOpening:
          title = 'Confirm opening Zcash';
          statusLabel = 'Opening Zcash';
          message =
              'Confirm the request on your Ledger. Vizor will reconnect automatically.';
        case LedgerAppReadinessPhase.idle ||
            LedgerAppReadinessPhase.ready ||
            LedgerAppReadinessPhase.failed:
          break;
      }
    }
    if (!failed && roundFeeNotice != null) {
      message = '$message ${roundFeeNotice!}';
    }
    final actionLabel = failed ? failure!.actionLabel : null;
    final showDeviceAppPrompt = switch (phase) {
      LedgerSigningModalPhase.saving ||
      LedgerSigningModalPhase.broadcasting => false,
      LedgerSigningModalPhase.failed => failure!.showDeviceAppPrompt,
      LedgerSigningModalPhase.preparing ||
      LedgerSigningModalPhase.awaitingDevice => true,
    };

    if (kAppFormFactor == AppFormFactor.mobile) {
      return MobileLedgerSigningContent(
        title: !failed && stage == LedgerSigningStage.reviewing
            ? 'Confirm on your Ledger'
            : title,
        message: message,
        status:
            !failed && stage == LedgerSigningStage.reviewing && roundCount == 1
            ? 'Waiting for your approval'
            : statusLabel,
        active:
            stage != LedgerSigningStage.reviewing &&
            readiness.phase != LedgerAppReadinessPhase.confirmOpening,
        failed: failed,
        account: account,
        onClose: onCancel,
        actionLabel: actionLabel,
        onAction: onFailureAction,
      );
    }
    return AppModalCard(
      width: 328,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (canChangeConnection) ...[
                AppButton(
                  onPressed: changeConnection,
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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.background.neutralSubtleOpacity,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                  border: Border.all(color: colors.border.subtle),
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.ledger,
                    size: 22,
                    color: colors.icon.regular,
                    semanticLabel: 'Ledger',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.bodyLarge.copyWith(
                        color: colors.text.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '$appName · Ledger',
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showDeviceAppPrompt) ...[
            const SizedBox(height: AppSpacing.md),
            LedgerDeviceAppPrompt(networkName: networkName),
          ],
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.s),
            decoration: BoxDecoration(
              color: colors.background.neutralSubtleOpacity,
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: AppIcon(
                      failed
                          ? AppIcons.warningCircle
                          : stage == LedgerSigningStage.reviewing
                          ? AppIcons.ledger
                          : AppIcons.loader,
                      size: failed ? 24 : 20,
                      color: error
                          ? colors.icon.destructive
                          : colors.icon.regular,
                      animated: !failed,
                      semanticLabel: statusLabel,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusLabel,
                        style: AppTypography.bodyMedium.copyWith(
                          color: error
                              ? colors.text.destructive
                              : colors.text.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        message,
                        style: AppTypography.bodySmall.copyWith(
                          color: error
                              ? colors.text.destructive
                              : colors.text.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (actionLabel == null && onCancel == null)
            const SizedBox.shrink()
          else if (actionLabel == null)
            AppButton(
              onPressed: onCancel,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.mediumLarge,
              minWidth: 280,
              constrainContent: true,
              child: Text(
                cancelLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else if (onCancel == null)
            AppButton(
              onPressed: failed ? onFailureAction : null,
              variant: AppButtonVariant.primary,
              size: AppButtonSize.mediumLarge,
              minWidth: 280,
              constrainContent: true,
              child: Text(
                actionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            AppModalActions(
              onCancel: onCancel,
              cancelLabel: cancelLabel,
              actionLabel: actionLabel,
              onAction: failed ? onFailureAction : null,
            ),
        ],
      ),
    );
  }

  static AccountInfo? _ledgerAccount(WidgetRef ref, String? uuid) {
    if (uuid == null) return null;
    final accounts = ref.watch(accountProvider).value?.accounts ?? const [];
    for (final account in accounts) {
      if (account.uuid == uuid && account.isLedger) return account;
    }
    return null;
  }
}
