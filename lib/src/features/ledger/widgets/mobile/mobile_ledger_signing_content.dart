import 'package:flutter/widgets.dart';

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
    if (cancelling) {
      return const MobileLedgerSheetContent(
        title: 'Cancelling request',
        onClose: null,
        children: [
          MobileLedgerMessage(
            'Keep Vizor open while the Ledger request is cancelled.',
          ),
          MobileLedgerStatus('Cancelling…'),
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
        ? 'Signing was declined on Ledger. Try again when you’re ready.'
        : saving
        ? 'Saving the signed transaction.'
        : finishing
        ? 'Approved on Ledger. Vizor is finishing the transaction.'
        : stage == LedgerSigningStage.preparing
        ? opening
              ? 'Confirm opening Zcash on Ledger.'
              : 'Keep Ledger connected.'
        : stage == LedgerSigningStage.sending
        ? kLedgerSigningWaitInstruction
        : stage == LedgerSigningStage.reviewing
        ? 'When prompted, check the amount and recipient on Ledger.'
        : stage == LedgerSigningStage.finishing
        ? 'Finishing the Ledger request.'
        : message;
    final reviewNote = [
      if (opening)
        'Keep Zcash open.'
      else if (stage == LedgerSigningStage.reviewing)
        'Approve to sign, or reject to cancel.'
      else if (stage != LedgerSigningStage.preparing)
        'Keep Ledger connected.',
      if (roundCount > 1 && roundNumber < roundCount)
        'You will approve the next transaction separately.',
    ].join('\n\n');
    return MobileLedgerSheetContent(
      title: declined
          ? 'Request declined'
          : failed
          ? title
          : broadcasting
          ? 'Sending transaction'
          : 'Sign transaction',
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
                'Prepare transaction',
                message: current == 0 ? currentMessage : null,
                note: current == 0 && opening ? 'Keep Zcash open.' : null,
                busy: current == 0 && active,
                requiresDeviceAction: opening && active,
              ),
              LedgerStep(
                'Review on Ledger',
                message: current == 1 ? currentMessage : null,
                detail: roundCount > 1
                    ? 'Transaction $roundNumber of $roundCount'
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
                'Finish transaction',
                message: current == 2 ? currentMessage : null,
                note: current == 2 ? 'Keep Vizor open.' : null,
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
        if (failed && status != 'Action needed') ...[
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
          const MobileLedgerMessage('Keep Vizor open.'),
        ],
      ],
    );
  }
}
