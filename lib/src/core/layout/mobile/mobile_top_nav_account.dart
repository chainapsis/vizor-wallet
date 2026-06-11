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
  const MobileTopNavAccount({this.onAccountTap, super.key});

  final VoidCallback? onAccountTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final account = ref.watch(accountProvider).value?.activeAccount;
    final sync = ref.watch(syncProvider).value ?? SyncState();
    final status = SyncStatusLabel.from(sync);

    final (labelColor, indicatorColor) = switch (status.kind) {
      SyncStatusKind.synced => (colors.sync.text, colors.sync.glow),
      SyncStatusKind.syncing => (colors.sync.textSyncing, colors.sync.glow),
      SyncStatusKind.failed => (colors.sync.textError, colors.sync.lightError),
    };

    return MobileTopNav.account(
      accountName: account?.name ?? '',
      avatar: MobileAccountAvatar(
        profilePictureId: account?.profilePictureId ?? kDefaultProfilePictureId,
        size: AppProfilePictureSize.navLarge,
        isHardware: account?.isHardware ?? false,
        badgeRingColor: colors.background.window,
      ),
      syncLabel: status.label,
      syncLabelColor: labelColor,
      syncIndicatorColor: indicatorColor,
      onAccountTap: onAccountTap,
    );
  }
}
