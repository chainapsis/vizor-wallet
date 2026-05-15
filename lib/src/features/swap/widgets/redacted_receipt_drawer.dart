import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../models/swap_prototype_models.dart';

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
    final receiptText = redactedReceiptText(rows);
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
          const _ReceiptScopePanel(),
          const SizedBox(height: AppSpacing.sm),
          for (final row in rows) _ReceiptRow(row: row),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              AppButton(
                key: const ValueKey('swap_copy_redacted_receipt_button'),
                onPressed: receiptText.isEmpty
                    ? null
                    : () {
                        unawaited(
                          Clipboard.setData(ClipboardData(text: receiptText)),
                        );
                      },
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.medium,
                leading: const AppIcon(AppIcons.copy),
                child: const Text('Copy redacted receipt'),
              ),
              AppButton(
                key: const ValueKey('swap_copy_recovery_bundle_button'),
                onPressed: recoveryBundleCopyText.isEmpty
                    ? null
                    : () {
                        unawaited(
                          Clipboard.setData(
                            ClipboardData(text: recoveryBundleCopyText),
                          ),
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
  final fields = rows
      .where((row) => row.value.trim().isNotEmpty)
      .map((row) => '${row.label}: ${row.value}');
  if (fields.isEmpty) return '';
  return ['Receipt scope: redacted status evidence', ...fields].join('\n');
}

String recoveryBundleText(SwapPrototypeIntent intent) {
  final fields = <SwapPrototypeField>[
    SwapPrototypeField(label: 'Swap service', value: intent.provider),
    SwapPrototypeField(label: 'Swap id', value: intent.id),
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
      SwapPrototypeField(label: 'Quote id', value: intent.providerQuoteId!),
    if (intent.providerSignature != null)
      SwapPrototypeField(
        label: 'Quote signature',
        value: intent.providerSignature!,
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

class _ReceiptScopePanel extends StatelessWidget {
  const _ReceiptScopePanel();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('swap_receipt_scope_panel'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: const [
          _ReceiptScopeChip(
            key: ValueKey('swap_redacted_receipt_scope'),
            iconName: AppIcons.eyeClosed,
            label: 'Redacted receipt',
            value: 'txid + status only',
          ),
          _ReceiptScopeChip(
            key: ValueKey('swap_recovery_bundle_scope'),
            iconName: AppIcons.scroll,
            label: 'Recovery bundle',
            value: 'local support fields',
          ),
        ],
      ),
    );
  }
}

class _ReceiptScopeChip extends StatelessWidget {
  const _ReceiptScopeChip({
    required this.iconName,
    required this.label,
    required this.value,
    super.key,
  });

  final String iconName;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.background.base,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(iconName, size: 14, color: colors.icon.regular),
          const SizedBox(width: AppSpacing.xxs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
              Text(
                value,
                style: AppTypography.bodyExtraSmall.copyWith(
                  color: colors.text.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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
