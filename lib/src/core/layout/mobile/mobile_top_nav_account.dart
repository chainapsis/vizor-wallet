import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/network_privacy_provider.dart';
import '../../../providers/sync_display_progress_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../formatting/sync_status_label.dart';
import '../../profile_pictures.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_profile_picture.dart';
import '../../widgets/mobile/mobile_account_avatar.dart';
import 'mobile_top_nav.dart';
import 'mobile_sync_status.dart';

/// [MobileTopNav.account] bound to live state: the active account's
/// name and profile picture from [accountProvider], and the sync status
/// label/edge indicator from [syncProvider] (same derivation as the
/// desktop sidebar status row).
class MobileTopNavAccount extends ConsumerWidget {
  const MobileTopNavAccount({
    this.onAccountTap,
    this.showSyncStatus = true,
    super.key,
  });

  final VoidCallback? onAccountTap;
  final bool showSyncStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value?.activeAccount;
    final sync = ref.watch(syncProvider).value ?? SyncState();
    final status = SyncStatusLabel.from(
      sync,
      displayWholePercentage: ref.watch(syncDisplayWholePercentageProvider),
      networkPrivacy: ref.watch(networkPrivacyProvider),
    );

    final isSyncing = status.kind == SyncStatusKind.syncing;
    final syncColors = MobileSyncStatus.colorsFor(context, status.kind);

    return MobileTopNav.account(
      accountName: account?.name ?? '',
      avatar: MobileAccountAvatar(
        profilePictureId: account?.profilePictureId ?? kDefaultProfilePictureId,
        size: AppProfilePictureSize.navLarge,
        hardwareSignerKind: account?.hardwareSignerKind,
        badgeRingColor: context.colors.background.window,
      ),
      syncLabel: showSyncStatus ? status.label : null,
      syncLabelColor: syncColors.label,
      syncIndicatorColor: syncColors.indicator,
      syncAnimated: showSyncStatus && isSyncing,
      syncHighlightColor: syncColors.highlight,
      onAccountTap: onAccountTap,
    );
  }
}
