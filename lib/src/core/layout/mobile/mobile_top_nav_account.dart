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
    // Synced reads fully green: label `sync.text` (GreenPrimitives.p900) +
    // vivid green bar `sync.lightSuccess`. Syncing reads muted: the label is
    // the same green at 65% (`sync.textSyncing`, slightly less saturated) and
    // the shimmer peaks at the full synced green to preview it. The bar uses a
    // neutral grey (`text.muted` = p500, identical in both modes) so it never
    // muddies to olive on a light background the way a 65%-alpha dark green
    // would; it goes vivid green only once synced.
    final (labelColor, indicatorColor, highlightColor) = switch (status.kind) {
      SyncStatusKind.synced => (
        colors.sync.text, // green label
        colors.sync.lightSuccess, // green bar
        colors.sync.text,
      ),
      SyncStatusKind.syncing => (
        colors.sync.textSyncing, // muted green (synced green @ 65%)
        colors.text.muted, // neutral grey bar (both modes)
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
