import 'package:flutter/widgets.dart';

import '../../../../core/config/network_config.dart'
    show kZcashDefaultCurrencyTicker;
import '../../../../core/l10n/l10n.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/mobile/mobile_action_card.dart';

/// The ways to receive that the mobile Home Receive button offers.
enum ReceiveOption { receive, request, redeemGiftCard }

/// Opens the sheet behind the mobile Home Receive button. Resolves to the
/// option picked, or null when the sheet is dismissed; the caller acts on it
/// once the sheet has closed.
Future<ReceiveOption?> showReceiveOptionsSheet(BuildContext context) {
  return showAppMobileSheet<ReceiveOption>(
    context: context,
    builder: (_) => const ReceiveOptionsSheet(),
  );
}

class ReceiveOptionsSheet extends StatelessWidget {
  const ReceiveOptionsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    void pick(ReceiveOption option) => Navigator.of(context).pop(option);

    return MobileModalScaffold(
      title: l10n.homeReceive,
      onClose: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MobileActionCard(
            key: const ValueKey('receive_options_receive'),
            icon: AppIcons.qr,
            title: l10n.receiveTitle(kZcashDefaultCurrencyTicker),
            subtitle: l10n.homeReceiveReceiveSubtitle,
            onTap: () => pick(ReceiveOption.receive),
          ),
          const SizedBox(height: AppSpacing.s),
          MobileActionCard(
            key: const ValueKey('receive_options_request'),
            icon: AppIcons.request,
            title: l10n.receiveRequestButton(kZcashDefaultCurrencyTicker),
            subtitle: l10n.homeReceiveRequestSubtitle,
            onTap: () => pick(ReceiveOption.request),
          ),
          const SizedBox(height: AppSpacing.s),
          MobileActionCard(
            key: const ValueKey('receive_options_redeem_gift_card'),
            icon: AppIcons.giftCard,
            title: l10n.homeReceiveRedeemGiftCard,
            subtitle: l10n.homeReceiveRedeemGiftCardSubtitle,
            onTap: () => pick(ReceiveOption.redeemGiftCard),
          ),
        ],
      ),
    );
  }
}
