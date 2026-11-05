import '../../../core/l10n/l10n.dart';

String swapMinimumReceiveTooltip(AppLocalizations l10n, String receiveSymbol) =>
    l10n.swapActivityTooltipMinimumReceive(receiveSymbol);

String swapGenericMinimumReceiveTooltip(AppLocalizations l10n) =>
    l10n.swapActivityTooltipMinimumReceiveGeneric;

String swapPriceProtectionTooltip(AppLocalizations l10n) =>
    l10n.swapActivityTooltipPriceProtection;

String swapFeeTooltip(AppLocalizations l10n) => l10n.swapActivityTooltipFees;

String swapTotalFeesTooltip(AppLocalizations l10n) => swapFeeTooltip(l10n);

String swapStatusDetailTooltip(AppLocalizations l10n) =>
    l10n.swapActivityTooltipStatusDetail;
