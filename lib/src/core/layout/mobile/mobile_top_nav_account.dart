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

    final isSyncing = status.kind == SyncStatusKind.syncing;
    // Per Vizor's Figma sync tokens: synced is the full green
    // (`sync.text` = GreenPrimitives.p900), syncing is the SAME green at
    // 65% (`sync.textSyncing`) — i.e. slightly less saturated, reading as a
    // muted grey-green. The shimmer peaks at the synced green to preview it.
    final (labelColor, indicatorColor, highlightColor) = switch (status.kind) {
      SyncStatusKind.synced => (
        colors.sync.text, // green label
        colors.sync.lightSuccess, // green bar
        colors.sync.text,
      ),
      SyncStatusKind.syncing => (
        colors.sync.textSyncing, // muted green (synced green @ 65%)
        colors.sync.textSyncing, // muted green bar
        colors.sync.text, // shimmer peak = the synced green
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
      syncLabel: status.label,
      syncLabelColor: labelColor,
      syncIndicatorColor: indicatorColor,
      syncAnimated: isSyncing,
      syncHighlightColor: highlightColor,
      onAccountTap: onAccountTap,
    );
  }
}
