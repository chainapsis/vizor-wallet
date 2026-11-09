import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../services/ledger_app_readiness_service.dart';
import '../services/ledger_signing_progress.dart';
import 'ledger_modal_content.dart';
import 'ledger_procedure.dart';

class DesktopLedgerSigningContent extends StatelessWidget {
  const DesktopLedgerSigningContent({
    required this.stage,
    required this.readiness,
    required this.message,
    required this.failed,
    required this.declined,
    required this.saving,
    required this.finishing,
    required this.broadcasting,
    required this.cancelling,
    required this.preparationComplete,
    required this.failureTitle,
    required this.onCancel,
    required this.onAction,
    this.actionLabel,
    this.onChangeConnection,
    this.identity,
    this.roundNumber = 1,
    this.roundCount = 1,
    this.roundFeeNotice,
    this.cancelLabel,
    super.key,
  });
  final LedgerSigningStage stage;
  final LedgerAppReadinessPhase readiness;
  final String message, failureTitle;
  final String? cancelLabel;
  final bool failed,
      declined,
      saving,
      finishing,
      broadcasting,
      cancelling,
      preparationComplete;
  final VoidCallback? onCancel, onAction, onChangeConnection;
  final String? actionLabel, identity, roundFeeNotice;
  final int roundNumber, roundCount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cancelText = cancelLabel ?? l10n.commonCancel;
    final opening =
        stage == LedgerSigningStage.preparing &&
        readiness == LedgerAppReadinessPhase.confirmOpening;
    final current = saving || finishing
        ? 2
        : preparationComplete ||
              declined ||
              stage != LedgerSigningStage.preparing
        ? 1
        : 0;
    final instruction = declined
        ? l10n.ledgerSigningDeclined
        : saving
        ? l10n.ledgerSigningSaving
        : finishing
        ? l10n.ledgerSigningApprovedFinishing
        : opening
        ? l10n.ledgerConfirmOpeningZcash
        : stage == LedgerSigningStage.sending
        ? l10n.ledgerSigningWaitInstruction
        : stage == LedgerSigningStage.reviewing
        ? l10n.ledgerSigningCheckAmountRecipient
        : stage == LedgerSigningStage.finishing
        ? l10n.ledgerSigningFinishingRequest
        : l10n.ledgerSigningKeepLedgerConnected;
    final note = current == 2
        ? l10n.ledgerSigningKeepVizorOpen
        : opening
        ? l10n.ledgerKeepZcashOpen
        : stage == LedgerSigningStage.reviewing
        ? (roundCount > 1 && roundNumber < roundCount
              ? l10n.ledgerSigningApproveToSignNext
              : l10n.ledgerSigningApproveToSign)
        : stage == LedgerSigningStage.sending
        ? l10n.ledgerSigningKeepLedgerConnected
        : null;
    final useProcedure = !cancelling && !broadcasting && (!failed || declined);
    Widget? footer;
    if (!cancelling) {
      if (failed && actionLabel != null && onCancel != null) {
        footer = AppModalActions(
          onCancel: onCancel,
          cancelLabel: cancelText,
          actionLabel: actionLabel!,
          onAction: onAction,
        );
      } else if (failed && actionLabel != null) {
        footer = AppButton(
          onPressed: onAction,
          size: AppButtonSize.mediumLarge,
          expand: true,
          child: Text(actionLabel!),
        );
      } else if (onCancel != null) {
        footer = Center(
          child: AppButton(
            onPressed: onCancel,
            size: AppButtonSize.mediumLarge,
            variant: AppButtonVariant.ghost,
            minWidth: kAppModalButtonMinWidth,
            child: Text(cancelText),
          ),
        );
      }
    }
    return LedgerModalContent(
      title: cancelling
          ? l10n.ledgerCancellingRequest
          : failed && !declined
          ? failureTitle
          : broadcasting
          ? l10n.ledgerSigningTitleSendingTx
          : l10n.ledgerSigningTitleSign,
      identity: cancelling ? null : identity,
      onBack: cancelling ? null : onChangeConnection,
      backLabel: l10n.ledgerSigningChangeConnection,
      footer: footer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (useProcedure)
            LedgerProcedure(
              topPadding: 0,
              currentStep: current,
              steps: [
                for (var i = 0; i < 3; i++)
                  LedgerStep(
                    [
                      l10n.ledgerSigningStepPrepare,
                      l10n.ledgerSigningStepReview,
                      l10n.ledgerSigningStepFinish,
                    ][i],
                    message: i == current ? instruction : null,
                    note: i == current && !declined ? note : null,
                    detail: i == 1 && roundCount > 1
                        ? l10n.ledgerSigningTransactionProgress(
                            '$roundNumber',
                            '$roundCount',
                          )
                        : null,
                    busy: i == current && !failed,
                    requiresDeviceAction:
                        i == current &&
                        !failed &&
                        (opening || stage == LedgerSigningStage.reviewing),
                  ),
              ],
            )
          else ...[
            Text(
              cancelling ? l10n.ledgerSigningKeepOpenWhileCancelling : message,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
            if (!failed || cancelling)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.s),
                child: Row(
                  children: [
                    const AppIcon(AppIcons.loader, size: 20),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        cancelling
                            ? l10n.commonCancelling
                            : l10n.ledgerSigningKeepVizorOpen,
                        style: AppTypography.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (roundFeeNotice != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s),
              child: Text(
                roundFeeNotice!,
                style: AppTypography.bodySmall.copyWith(
                  color: context.colors.text.secondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
