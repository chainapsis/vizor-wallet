import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../models/swap_prototype_models.dart';
import 'swap_copy_feedback.dart';

class RedactedReceiptDrawer extends StatelessWidget {
  const RedactedReceiptDrawer({
    required this.rows,
    required this.intent,
    super.key,
  });

  final List<SwapPrototypeField> rows;
  final SwapPrototypeIntent intent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final supportRows = _supportRows(rows);
    final receiptText = redactedReceiptText(supportRows);
    final recoveryBundleCopyText = recoveryBundleText(intent);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Receipt',
            style: AppTypography.headlineSmall.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final row in supportRows) _ReceiptRow(row: row),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppButton(
                key: const ValueKey('swap_copy_redacted_receipt_button'),
                onPressed:
                    receiptText.isEmpty
                        ? null
                        : () {
                          copySwapText(
                            context,
                            text: receiptText,
                            toastMessage: 'Receipt Copied',
                          );
                        },
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                leading: const AppIcon(AppIcons.copy),
                child: const Text('Copy redacted receipt'),
              ),
              AppButton(
                key: const ValueKey('swap_copy_recovery_bundle_button'),
                onPressed:
                    recoveryBundleCopyText.isEmpty
                        ? null
                        : () {
                          copySwapText(
                            context,
                            text: recoveryBundleCopyText,
                            toastMessage: 'Recovery Bundle Copied',
                          );
                        },
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                leading: const AppIcon(AppIcons.scroll),
                child: const Text('Copy recovery'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String redactedReceiptText(List<SwapPrototypeField> rows) {
  final fields = _supportRows(rows)
      .where((row) => row.value.trim().isNotEmpty)
      .map((row) => '${row.label}: ${row.value}');
  if (fields.isEmpty) return '';
  return ['Receipt scope: redacted status evidence', ...fields].join('\n');
}

String recoveryBundleText(SwapPrototypeIntent intent) {
  final fields = <SwapPrototypeField>[
    SwapPrototypeField(label: 'Swap service', value: intent.provider),
    SwapPrototypeField(label: 'Pair', value: intent.pair),
    SwapPrototypeField(label: 'Status', value: intent.statusLabel),
    SwapPrototypeField(label: 'Next action', value: intent.nextAction),
    if (intent.depositAddress != null)
      SwapPrototypeField(
        label: 'Deposit address',
        value: intent.depositAddress!,
      ),
    if (intent.depositMemo != null)
      SwapPrototypeField(label: 'Deposit memo', value: intent.depositMemo!),
    if (intent.depositTxHash != null)
      SwapPrototypeField(label: 'Deposit tx', value: intent.depositTxHash!),
    if (intent.providerQuoteId != null)
      SwapPrototypeField(
        label: 'Provider quote',
        value: intent.providerQuoteId!,
      ),
    if (intent.oneClickRecipient != null)
      SwapPrototypeField(label: 'Recipient', value: intent.oneClickRecipient!),
    if (intent.oneClickRefundTo != null)
      SwapPrototypeField(
        label: 'Refund address',
        value: intent.oneClickRefundTo!,
      ),
  ];

  final lines = fields
      .where((field) => field.value.trim().isNotEmpty)
      .map((field) => '${field.label}: ${field.value}');
  if (lines.isEmpty) return '';
  return ['Recovery scope: local support bundle', ...lines].join('\n');
}

List<SwapPrototypeField> _supportRows(List<SwapPrototypeField> rows) {
  return [
    for (final row in rows)
      if (!_isNoisySupportRow(row)) row,
  ];
}

bool _isNoisySupportRow(SwapPrototypeField row) {
  final label = row.label.trim().toLowerCase();
  return label == 'swap id' || label == 'shared fields';
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.row});

  final SwapPrototypeField row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              row.label,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              row.value,
              style: AppTypography.bodySmall.copyWith(
                color: colors.text.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
