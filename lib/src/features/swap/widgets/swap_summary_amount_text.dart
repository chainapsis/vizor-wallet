import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/swap_contract.dart';

class SwapSummaryAmountText extends StatelessWidget {
  const SwapSummaryAmountText({
    required this.amountText,
    required this.asset,
    required this.style,
    this.keyPrefix,
    super.key,
  });

  final String amountText;
  final SwapAsset asset;
  final TextStyle style;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final parts = splitSwapSummaryAmountText(amountText, asset);
    return Semantics(
      label: amountText,
      child: ExcludeSemantics(
        child: Row(
          key: keyPrefix == null ? null : ValueKey(keyPrefix),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (parts.amount.isNotEmpty)
              Flexible(
                fit: FlexFit.loose,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    parts.amount,
                    key: keyPrefix == null
                        ? null
                        : ValueKey('${keyPrefix}_number'),
                    maxLines: 1,
                    softWrap: false,
                    style: style,
                  ),
                ),
              ),
            if (parts.amount.isNotEmpty && parts.symbol.isNotEmpty)
              const SizedBox(width: AppSpacing.xxs),
            if (parts.symbol.isNotEmpty)
              Text(
                parts.symbol,
                key: keyPrefix == null ? null : ValueKey('${keyPrefix}_symbol'),
                maxLines: 1,
                softWrap: false,
                style: style,
              ),
          ],
        ),
      ),
    );
  }
}

class SwapSummaryAmountParts {
  const SwapSummaryAmountParts({required this.amount, required this.symbol});

  final String amount;
  final String symbol;
}

SwapSummaryAmountParts splitSwapSummaryAmountText(
  String text,
  SwapAsset asset,
) {
  final trimmed = text.trim();
  final symbol = asset.symbol.trim();
  if (trimmed.isEmpty) {
    return const SwapSummaryAmountParts(amount: '', symbol: '');
  }
  if (symbol.isNotEmpty) {
    final suffix = ' $symbol';
    if (trimmed.endsWith(suffix)) {
      return SwapSummaryAmountParts(
        amount: trimmed.substring(0, trimmed.length - suffix.length).trim(),
        symbol: symbol,
      );
    }
    if (trimmed == symbol) {
      return SwapSummaryAmountParts(amount: '', symbol: symbol);
    }
  }

  final fallback = RegExp(r'^(.+?)\s+(\S+)$').firstMatch(trimmed);
  if (fallback != null) {
    return SwapSummaryAmountParts(
      amount: fallback[1]!.trim(),
      symbol: fallback[2]!.trim(),
    );
  }
  return SwapSummaryAmountParts(amount: trimmed, symbol: '');
}
