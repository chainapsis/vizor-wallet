import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../about/about_content.dart' show launchAboutUrl;
import '../ledger_capability.dart';
import '../ledger_app_instructions.dart' show ledgerZcashAppName;

/// A preparation hint, not evidence that a compatible app is installed or
/// publicly available. Connection readiness still enforces the version gate.
class LedgerConnectionGuide extends StatelessWidget {
  const LedgerConnectionGuide({
    required this.networkName,
    this.awaitingAccountApproval = false,
    this.connectionAction,
    super.key,
  });

  final String networkName;
  final bool awaitingAccountApproval;
  final Widget? connectionAction;

  static const updateGuideUrl =
      'https://support.ledger.com/article/4404382258961-zd';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      key: const ValueKey('ledger_connection_guide'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeading(
            icon: AppIcons.importWallet,
            title: '1. Check the Zcash app version',
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Use Zcash app $kMinimumLedgerZcashAppVersion or newer on your Ledger.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'This is the device app version, not Ledger Wallet or firmware.',
            style: AppTypography.bodySmall.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            link: true,
            child: AppButton(
              key: const ValueKey('ledger_app_update_guide'),
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              contentPadding: EdgeInsets.zero,
              trailing: const AppIcon(AppIcons.link),
              onPressed: awaitingAccountApproval
                  ? null
                  : () => unawaited(launchAboutUrl(updateGuideUrl)),
              child: const Text('App update guide'),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(height: 1, color: colors.border.subtle),
          const SizedBox(height: AppSpacing.sm),
          const _StepHeading(
            icon: AppIcons.ledger,
            title: '2. Prepare to connect',
          ),
          const SizedBox(height: AppSpacing.xs),
          if (connectionAction case final action?) ...[
            action,
            const SizedBox(height: AppSpacing.sm),
          ],
          IndexedStack(
            key: const ValueKey('ledger_connection_preparation'),
            index: awaitingAccountApproval ? 1 : 0,
            children: [
              for (final awaiting in [false, true])
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      awaiting
                          ? 'Check your Ledger'
                          : 'Unlock your Ledger and open the ${ledgerZcashAppName(networkName)} app.',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Approve sharing the viewing key when prompted.',
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepHeading extends StatelessWidget {
  const _StepHeading({required this.icon, required this.title});

  final String icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppIcon(icon, size: 20, color: context.colors.icon.regular),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text(
          title,
          style: AppTypography.bodyMedium.copyWith(
            color: context.colors.text.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}
