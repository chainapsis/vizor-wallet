import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../models/swap_prototype_models.dart';

typedef SwapSupportCopyText =
    void Function({required String text, required String toastMessage});

class RedactedReceiptDrawer extends StatelessWidget {
  const RedactedReceiptDrawer({
    required this.rows,
    required this.intent,
    required this.onCopyText,
    super.key,
  });

  final List<SwapPrototypeField> rows;
  final SwapPrototypeIntent intent;
  final SwapSupportCopyText onCopyText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final detailRows = _supportDetailRows(rows, intent);
    final summaryRows = _safeSupportSummaryRows(detailRows);
    final detailsText = supportDetailsText(detailRows);
    return Container(
      key: const ValueKey('swap_support_safe_summary_panel'),
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
            'Safe support summary',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Raw address values, memos, transaction hashes, and quote ids are shown below because you opened Support details.',
            style: AppTypography.bodyExtraSmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final row in summaryRows) _SafeSummaryRow(row: row),
          const SizedBox(height: AppSpacing.sm),
          Container(
            key: const ValueKey('swap_support_bundle_panel'),
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: colors.background.raised,
              border: Border.all(color: colors.border.subtle),
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Details for support',
                        style: AppTypography.labelMedium.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                    ),
                    AppButton(
                      key: const ValueKey('swap_copy_support_details_button'),
                      onPressed: detailsText.isEmpty
                          ? null
                          : () => onCopyText(
                              text: detailsText,
                              toastMessage: 'Support Details Copied',
                            ),
                      variant: AppButtonVariant.secondary,
                      size: AppButtonSize.small,
                      leading: const AppIcon(AppIcons.copy),
                      child: const Text('Copy details'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final row in detailRows)
                  _ReceiptRow(row: row, onCopyText: onCopyText),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String supportDetailsText(List<SwapPrototypeField> rows) {
  final fields = rows
      .where((row) => row.value.trim().isNotEmpty)
      .map((row) => '${row.label}: ${row.value}');
  if (fields.isEmpty) return '';
  return ['Support details', ...fields].join('\n');
}

String redactedReceiptText(List<SwapPrototypeField> rows) {
  final fields = _supportRows(rows)
      .where((row) => row.value.trim().isNotEmpty)
      .map((row) => '${row.label}: ${row.value}');
  if (fields.isEmpty) return '';
  return ['Receipt scope: redacted status evidence', ...fields].join('\n');
}

List<SwapPrototypeField> _supportRows(List<SwapPrototypeField> rows) {
  return [
    for (final row in rows)
      if (!_isNoisySupportRow(row)) row,
  ];
}

List<SwapPrototypeField> _supportDetailRows(
  List<SwapPrototypeField> rows,
  SwapPrototypeIntent intent,
) {
  final fields = <SwapPrototypeField>[];
  final receiptRows = _supportRows(rows);

  void add(String label, String? rawValue) {
    final value = rawValue?.trim();
    if (value == null || value.isEmpty) return;
    final candidate = SwapPrototypeField(label: label, value: value);
    if (_isNoisySupportRow(candidate)) return;
    if (_hasSupportField(fields, candidate)) return;
    fields.add(candidate);
  }

  String? receiptValue(String label) {
    final normalized = label.trim().toLowerCase();
    for (final row in receiptRows) {
      if (row.label.trim().toLowerCase() == normalized) {
        return row.value;
      }
    }
    return null;
  }

  final showShieldStagingAddress = switch (intent.status) {
    SwapIntentStatus.shieldingPending ||
    SwapIntentStatus.shieldingConfirming ||
    SwapIntentStatus.shieldingFailed => true,
    _ => false,
  };

  add(
    'Provider quote',
    intent.providerQuoteId ?? receiptValue('Provider quote'),
  );
  if (intent.direction == SwapDirection.zecToExternal) {
    final symbol = intent.externalAsset?.symbol ?? 'External';
    add(
      '$symbol recipient',
      intent.oneClickRecipient ?? receiptValue('$symbol recipient'),
    );
  }
  add('Deposit address', intent.depositAddress);
  add('Deposit memo', intent.depositMemo ?? receiptValue('Memo'));
  add('Deposit tx', intent.depositTxHash ?? receiptValue('Deposit tx'));
  if (showShieldStagingAddress) {
    add(
      'Shield staging address',
      intent.oneClickRecipient ?? receiptValue('Receive address'),
    );
  }
  add('Shield tx', intent.shieldTxHash ?? receiptValue('Shield tx'));
  add('Shield fee', receiptValue('Shield fee'));
  add('Intent hash', intent.nearIntentHash);

  return fields;
}

bool _hasSupportField(
  List<SwapPrototypeField> rows,
  SwapPrototypeField candidate,
) {
  final label = candidate.label.trim().toLowerCase();
  final value = candidate.value.trim();
  return rows.any((row) {
    final rowLabel = row.label.trim().toLowerCase();
    final rowValue = row.value.trim();
    return rowLabel == label || (value.length > 8 && rowValue == value);
  });
}

bool _isNoisySupportRow(SwapPrototypeField row) {
  final label = row.label.trim().toLowerCase();
  return label == 'swap id' || label == 'shared fields';
}

List<SwapPrototypeField> _safeSupportSummaryRows(
  List<SwapPrototypeField> rows,
) {
  final fields = <SwapPrototypeField>[];

  bool hasLabel(String needle) {
    final lowerNeedle = needle.toLowerCase();
    return rows.any((row) => row.label.toLowerCase().contains(lowerNeedle));
  }

  void add(String label, String value) {
    fields.add(SwapPrototypeField(label: label, value: value));
  }

  if (hasLabel('provider') || hasLabel('intent')) {
    add('Provider', 'Reference ids available for support');
  }
  if (hasLabel('deposit')) {
    final parts = <String>[];
    if (hasLabel('deposit address')) parts.add('address');
    if (hasLabel('deposit memo')) parts.add('memo');
    if (hasLabel('deposit tx')) parts.add('transaction');
    add(
      'Deposit',
      parts.isEmpty
          ? 'Tracking fields available'
          : '${parts.join(', ')} recorded',
    );
  }
  if (hasLabel('shield')) {
    final parts = <String>[];
    if (hasLabel('shield staging')) parts.add('staging address');
    if (hasLabel('shield tx')) parts.add('transaction');
    if (hasLabel('shield fee')) parts.add('fee');
    add(
      'Shielding',
      parts.isEmpty
          ? 'Wallet shielding fields available'
          : '${parts.join(', ')} recorded',
    );
  }
  if (fields.isEmpty) {
    add('Support', 'No support fields recorded yet');
  }

  return fields;
}

class _SafeSummaryRow extends StatelessWidget {
  const _SafeSummaryRow({required this.row});

  final SwapPrototypeField row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.background.raised,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              row.label,
              style: AppTypography.labelMedium.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              row.value,
              style: AppTypography.bodyExtraSmall.copyWith(
                color: colors.text.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.row, required this.onCopyText});

  final SwapPrototypeField row;
  final SwapSupportCopyText onCopyText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emphasized = _isHighSignalSupportRow(row);
    final copyable = _isCopyableSupportRow(row);
    final technical = _isTechnicalSupportRow(row);
    final valueStyle =
        (technical ? AppTypography.codeSmall : AppTypography.bodySmall)
            .copyWith(color: colors.text.primary);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: emphasized ? colors.background.raised : colors.background.base,
        border: emphasized ? Border.all(color: colors.border.subtle) : null,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              row.label,
              style: AppTypography.labelMedium.copyWith(
                color: emphasized ? colors.text.accent : colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(row.value, style: valueStyle)),
          if (copyable) ...[
            const SizedBox(width: AppSpacing.xs),
            _ReceiptCopyButton(row: row, onCopyText: onCopyText),
          ],
        ],
      ),
    );
  }
}

class _ReceiptCopyButton extends StatelessWidget {
  const _ReceiptCopyButton({required this.row, required this.onCopyText});

  final SwapPrototypeField row;
  final SwapSupportCopyText onCopyText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Copy ${row.label}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('swap_copy_detail_${_supportRowKey(row.label)}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onCopyText(
            text: row.value,
            toastMessage: _copyDetailToastMessage(row.label),
          ),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.background.base,
              border: Border.all(color: colors.border.subtle),
              borderRadius: BorderRadius.circular(AppRadii.xSmall),
            ),
            child: AppIcon(AppIcons.copy, size: 14, color: colors.icon.muted),
          ),
        ),
      ),
    );
  }
}

bool _isCopyableSupportRow(SwapPrototypeField row) {
  final label = row.label.trim().toLowerCase();
  final value = row.value.trim();
  if (value.isEmpty) return false;
  return label.contains('address') ||
      label.contains('memo') ||
      label.contains('tx') ||
      label.contains('quote') ||
      label.contains('recipient') ||
      label.contains('refund') ||
      label.contains('deposit') ||
      label.contains('explorer') ||
      value.startsWith('http://') ||
      value.startsWith('https://');
}

bool _isHighSignalSupportRow(SwapPrototypeField row) {
  final label = row.label.trim().toLowerCase();
  return label.contains('address') ||
      label.contains('recipient') ||
      label.contains('refund') ||
      label.contains('tx') ||
      label.contains('explorer');
}

bool _isTechnicalSupportRow(SwapPrototypeField row) {
  final label = row.label.trim().toLowerCase();
  final value = row.value.trim();
  return label.contains('address') ||
      label.contains('memo') ||
      label.contains('tx') ||
      label.contains('quote') ||
      label.contains('explorer') ||
      value.startsWith('http://') ||
      value.startsWith('https://');
}

String _supportRowKey(String label) {
  return label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

String _copyDetailToastMessage(String label) {
  final lower = label.trim().toLowerCase();
  if (lower.contains('explorer')) return 'Explorer Link Copied';
  if (lower.contains('tx')) return 'Transaction Copied';
  if (lower.contains('quote')) return 'Quote Copied';
  if (lower.contains('memo')) return 'Memo Copied';
  if (lower.contains('address') ||
      lower.contains('recipient') ||
      lower.contains('refund') ||
      lower.contains('deposit')) {
    return 'Address Copied';
  }
  return 'Copied to Clipboard';
}
