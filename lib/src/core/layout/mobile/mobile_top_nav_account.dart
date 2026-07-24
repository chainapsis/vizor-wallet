import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../formatting/sync_status_label.dart';
import '../../profile_pictures.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_profile_picture.dart';
import '../../widgets/mobile/mobile_account_avatar.dart';
import 'mobile_top_nav.dart';

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
    final colors = context.colors;
    final account = ref.watch(accountProvider).value?.activeAccount;
    final sync = ref.watch(syncProvider).value ?? SyncState();
    final status = SyncStatusLabel.from(sync);

    final isSyncing = status.kind == SyncStatusKind.syncing;
    // Synced reads green: label `sync.text` + vivid green bar
    // `sync.lightSuccess`. Syncing follows the Figma nav sync widget: neutral
    // grey label and bar, with a white shimmer sweep.
    final (labelColor, indicatorColor, highlightColor) = switch (status.kind) {
      SyncStatusKind.synced => (
        colors.sync.text, // green label
        colors.sync.lightSuccess, // green bar
        colors.sync.text,
      ),
      SyncStatusKind.syncing => (
        colors.sync.textSyncing, // neutral grey resting label
        colors.sync.lightSyncing, // neutral grey bar
        colors.sync.textSyncingHighlight, // white shimmer peak
      ),
      SyncStatusKind.failed => (
        colors.sync.textError,
        colors.sync.lightError,
        colors.sync.textError,
      ),
    };

    return MobileTopNav.account(
      accountName: account?.name ?? '',
      avatar: MobileAccountAvatar(
        profilePictureId: account?.profilePictureId ?? kDefaultProfilePictureId,
        size: AppProfilePictureSize.navLarge,
        isHardware: account?.isHardware ?? false,
        badgeRingColor: colors.background.window,
      ),
      syncLabel: showSyncStatus ? status.label : null,
      syncLabelColor: labelColor,
      syncIndicatorColor: indicatorColor,
      syncAnimated: showSyncStatus && isSyncing,
      syncHighlightColor: highlightColor,
      onAccountTap: onAccountTap,
    );
  }
}
