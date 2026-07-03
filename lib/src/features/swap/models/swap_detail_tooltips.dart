import '../../../../l10n/app_localizations.dart';

String swapMinimumReceiveTooltip(AppLocalizations l10n, String receiveSymbol) =>
    l10n.swapMinReceiveTooltip(receiveSymbol);

String swapGenericMinimumReceiveTooltip(AppLocalizations l10n) =>
    l10n.swapGenericMinReceiveTooltip;

String swapFeeTooltip(AppLocalizations l10n) => l10n.swapFeeTooltipText;

String swapTotalFeesTooltip(AppLocalizations l10n) => swapFeeTooltip(l10n);

String swapStatusDetailTooltip(AppLocalizations l10n) =>
    l10n.swapStatusDetailTooltipText;
