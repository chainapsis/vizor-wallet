import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_carousel.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../providers/backup_reminder_provider.dart';

final showDesktopHomeSetupCarouselProvider = Provider.autoDispose<bool>(
  (ref) {
    final account = ref.watch(accountProvider).value?.activeAccount;
    if (account == null || ref.watch(appSecurityProvider).requiresUnlock) {
      return false;
    }
    return account.giftEducationPending ||
        (!account.isHardware && ref.watch(showBackupReminderProvider));
  },
  dependencies: [
    accountProvider,
    appSecurityProvider,
    showBackupReminderProvider,
  ],
);

/// Actionable setup reminders using the shared desktop carousel geometry.
class DesktopHomeSetupCarousel extends ConsumerWidget {
  const DesktopHomeSetupCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value?.activeAccount;
    if (account == null || !ref.watch(showDesktopHomeSetupCarouselProvider)) {
      return const SizedBox.shrink();
    }
    final backup = !account.isHardware && ref.watch(showBackupReminderProvider);
    final education = account.giftEducationPending;
    if (!backup && !education) return const SizedBox.shrink();
    return AppCarousel(
      key: ValueKey('desktop_setup_carousel_${account.uuid}'),
      showAdjacentCards: false,
      autoplay: false,
      semanticLabel: 'Wallet setup',
      items: [
        if (backup)
          AppCarouselItem.icon(
            message: 'Back up your wallet. Keep your secret passphrase safe.',
            tileColor: const Color(0xFF00A460),
            icon: AppIcons.key,
            onTap: () => context.push('/setup/backup', extra: account.uuid),
          ),
        if (education)
          AppCarouselItem.icon(
            message:
                'Learn how Zcash protects your privacy and which address to use.',
            tileColor: const Color(0xFF9667E2),
            icon: AppIcons.zcash,
            onTap: () =>
                context.push('/setup/education/intro', extra: account.uuid),
          ),
      ],
    );
  }
}
