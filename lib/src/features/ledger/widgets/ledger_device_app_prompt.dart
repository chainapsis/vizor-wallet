import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

String ledgerZcashAppName(String networkName) =>
    'Zcash'; // l10n-ignore: product name

String ledgerZcashAppOpenInstruction(
  AppLocalizations l10n,
  String networkName,
) {
  return l10n.ledgerOpenAppInstruction(ledgerZcashAppName(networkName));
}

String ledgerZcashAppOpenErrorInstruction(
  AppLocalizations l10n,
  String networkName,
) {
  return l10n.ledgerOpenAppOnLedger(ledgerZcashAppName(networkName));
}

class LedgerDeviceAppPrompt extends StatelessWidget {
  const LedgerDeviceAppPrompt({required this.networkName, super.key});

  final String networkName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final appName = ledgerZcashAppName(networkName);

    return Container(
      key: const ValueKey('ledger_device_app_prompt_mainnet'),
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        border: Border.all(color: colors.border.subtle),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.background.base,
              borderRadius: BorderRadius.circular(AppRadii.medium),
              border: Border.all(color: colors.border.subtle),
            ),
            child: Center(
              child: AppIcon(
                AppIcons.zcash,
                size: 24,
                color: colors.icon.regular,
                semanticLabel: context.l10n.ledgerAppSemanticsLabel(appName),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ledgerZcashAppOpenInstruction(context.l10n, networkName),
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.text.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  context.l10n.ledgerKeepItOpen,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppIcon(
            AppIcons.ledger,
            size: 20,
            color: colors.icon.muted,
            semanticLabel: 'Ledger', // l10n-ignore: product name
          ),
        ],
      ),
    );
  }
}
