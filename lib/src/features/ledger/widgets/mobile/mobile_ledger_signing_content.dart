import 'package:flutter/widgets.dart';

import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../providers/account_provider.dart';
import '../../ledger_device_label.dart';
import '../../services/ledger_mobile_ble_service.dart';
import '../../services/ledger_app_readiness_service.dart';
import '../../services/ledger_signing_progress.dart';
import '../ledger_procedure.dart';
import 'mobile_ledger_sheet_content.dart';

/// Mobile presentation of the shared operation status, independent of the
/// desktop signing card and its nested status/prompt panels.
class MobileLedgerSigningContent extends StatelessWidget {
  const MobileLedgerSigningContent({
    required this.title,
    required this.message,
    required this.status,
    required this.active,
    required this.failed,
    required this.showFailureStatus,
    required this.onClose,
    required this.onAction,
    this.actionLabel,
    this.account,
    required this.stage,
    required this.readiness,
    required this.saving,
    required this.finishing,
    required this.broadcasting,
    required this.declined,
    required this.roundNumber,
    required this.roundCount,
    this.roundFeeNotice,
    this.cancelling = false,
    this.resumingApproval = false,
    super.key,
  });
  final String title;
  final String message;
  final String status;
  final bool active;
  final bool failed;
  final bool showFailureStatus;
  final AccountInfo? account;
  final String? actionLabel;
  final VoidCallback? onClose;
  final VoidCallback? onAction;
  final LedgerSigningStage stage;
  final LedgerAppReadinessPhase readiness;
  final bool saving;
  final bool finishing;
  final bool broadcasting;
  final bool declined;
  final int roundNumber;
  final int roundCount;
  final String? roundFeeNotice;
  final bool cancelling;
  final bool resumingApproval;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (cancelling) {
      return MobileLedgerSheetContent(
        title: l10n.ledgerCancellingRequest,
        onClose: null,
        children: [
          MobileLedgerMessage(l10n.ledgerSigningKeepOpenWhileCancelling),
          MobileLedgerStatus(l10n.commonCancelling),
        ],
      );
    }
    final procedure = !broadcasting && (!failed || declined);
    final current = saving || finishing
        ? 2
        : (resumingApproval ||
              declined ||
              stage != LedgerSigningStage.preparing)
        ? 1
        : 0;
    final opening =
        stage == LedgerSigningStage.preparing &&
        readiness == LedgerAppReadinessPhase.confirmOpening;
    final currentMessage = declined
        ? l10n.ledgerSigningDeclined
        : saving
        ? l10n.ledgerSigningSaving
        : finishing
        ? l10n.ledgerSigningApprovedFinishing
        : stage == LedgerSigningStage.preparing
        ? opening
              ? l10n.ledgerConfirmOpeningZcash
              : l10n.ledgerSigningKeepLedgerConnected
        : stage == LedgerSigningStage.sending
        ? l10n.ledgerSigningWaitInstruction
        : stage == LedgerSigningStage.reviewing
        ? l10n.ledgerSigningCheckAmountRecipient
        : stage == LedgerSigningStage.finishing
        ? l10n.ledgerSigningFinishingRequest
        : message;
    final reviewNote = [
      if (opening)
        l10n.ledgerKeepZcashOpen
      else if (stage == LedgerSigningStage.reviewing)
        l10n.ledgerSigningApproveOrReject
      else if (stage != LedgerSigningStage.preparing)
        l10n.ledgerSigningKeepLedgerConnected,
      if (roundCount > 1 && roundNumber < roundCount)
        l10n.ledgerSigningApproveNextSeparately,
    ].join('\n\n');
    return MobileLedgerSheetContent(
      title: declined
          ? l10n.ledgerSheetDeclinedTitle
          : failed
          ? title
          : broadcasting
          ? l10n.ledgerSigningTitleSendingTx
          : l10n.ledgerSigningTitleSign,
      onClose: onClose,
      action: failed && actionLabel != null
          ? MobileLedgerAction(actionLabel!, onPressed: onAction)
          : null,
      children: [
        if ((!failed || declined) && account?.ledgerDeviceId != null)
          MobileLedgerIdentity(
            ledgerDeviceLabel(
              LedgerBleDevice(
                id: account!.ledgerDeviceId!,
                name: account!.ledgerDeviceName ?? '',
                model: account!.ledgerDeviceModel ?? '',
              ),
            ),
            topPadding: 0,
          ),
        if (procedure)
          LedgerProcedure(
            currentStep: current,
            steps: [
              LedgerStep(
                l10n.ledgerSigningStepPrepare,
                message: current == 0 ? currentMessage : null,
                note: current == 0 && opening ? l10n.ledgerKeepZcashOpen : null,
                busy: current == 0 && active,
                requiresDeviceAction: opening && active,
              ),
              LedgerStep(
                l10n.ledgerSigningStepReview,
                message: current == 1 ? currentMessage : null,
                detail: roundCount > 1
                    ? l10n.ledgerSigningTransactionProgress(
                        '$roundNumber',
                        '$roundCount',
                      )
                    : null,
                note: current == 1 && !declined && reviewNote.isNotEmpty
                    ? reviewNote
                    : null,
                busy: current == 1 && !declined && active,
                requiresDeviceAction:
                    (stage == LedgerSigningStage.reviewing || opening) &&
                    !declined &&
                    active,
              ),
              LedgerStep(
                l10n.ledgerSigningStepFinish,
                message: current == 2 ? currentMessage : null,
                note: current == 2 ? l10n.ledgerSigningKeepVizorOpen : null,
                busy: current == 2 && active,
              ),
            ],
          )
        else ...[
          if (!failed && account?.ledgerDeviceId != null)
            const SizedBox(height: AppSpacing.md),
          MobileLedgerMessage(message),
          if (!failed) MobileLedgerStatus(status, active: active),
        ],
        if (roundFeeNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s),
            child: MobileLedgerMessage(roundFeeNotice!),
          ),
        if (failed && showFailureStatus) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            status,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ],
        if (failed && actionLabel == null && onClose == null) ...[
          const SizedBox(height: AppSpacing.sm),
          MobileLedgerMessage(l10n.ledgerSigningKeepVizorOpen),
        ],
      ],
    );
  }
}
