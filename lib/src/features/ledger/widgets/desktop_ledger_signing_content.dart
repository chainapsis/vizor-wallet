import 'package:flutter/widgets.dart';

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
    this.cancelLabel = 'Cancel',
    super.key,
  });
  final LedgerSigningStage stage;
  final LedgerAppReadinessPhase readiness;
  final String message, failureTitle, cancelLabel;
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
        ? 'Signing was declined on Ledger. Try again when you’re ready.'
        : saving
        ? 'Saving the signed transaction.'
        : finishing
        ? 'Approved on Ledger. Vizor is finishing the transaction.'
        : opening
        ? 'Confirm opening Zcash on Ledger.'
        : stage == LedgerSigningStage.sending
        ? kLedgerSigningWaitInstruction
        : stage == LedgerSigningStage.reviewing
        ? 'When prompted, check the amount and recipient on Ledger.'
        : stage == LedgerSigningStage.finishing
        ? 'Finishing the Ledger request.'
        : 'Keep Ledger connected.';
    final note = current == 2
        ? 'Keep Vizor open.'
        : opening
        ? 'Keep Zcash open.'
        : stage == LedgerSigningStage.reviewing
        ? 'Approve to sign.${roundCount > 1 && roundNumber < roundCount ? '\n\nYou will approve the next transaction separately.' : ''}'
        : stage == LedgerSigningStage.sending
        ? 'Keep Ledger connected.'
        : null;
    final useProcedure = !cancelling && !broadcasting && (!failed || declined);
    Widget? footer;
    if (!cancelling) {
      if (failed && actionLabel != null && onCancel != null) {
        footer = AppModalActions(
          onCancel: onCancel,
          cancelLabel: cancelLabel,
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
            child: Text(cancelLabel),
          ),
        );
      }
    }
    return LedgerModalContent(
      title: cancelling
          ? 'Cancelling request'
          : failed && !declined
          ? failureTitle
          : broadcasting
          ? 'Sending transaction'
          : 'Sign transaction',
      identity: cancelling ? null : identity,
      onBack: cancelling ? null : onChangeConnection,
      backLabel: 'Change connection',
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
                    const [
                      'Prepare transaction',
                      'Review on Ledger',
                      'Finish transaction',
                    ][i],
                    message: i == current ? instruction : null,
                    note: i == current && !declined ? note : null,
                    detail: i == 1 && roundCount > 1
                        ? 'Transaction $roundNumber of $roundCount'
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
              cancelling
                  ? 'Keep Vizor open while the Ledger request is cancelled.'
                  : message,
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
                        cancelling ? 'Cancelling…' : 'Keep Vizor open.',
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
