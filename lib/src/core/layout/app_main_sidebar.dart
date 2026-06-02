import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/sync_failure.dart';
import '../../providers/sync_provider.dart';
import '../config/swap_feature_config.dart';
import '../profile_pictures.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_profile_picture.dart';
import 'app_desktop_shell.dart';

class AppMainSidebar extends ConsumerStatefulWidget {
  const AppMainSidebar({super.key});

  @override
  ConsumerState<AppMainSidebar> createState() => _AppMainSidebarState();
}

class _AppMainSidebarState extends ConsumerState<AppMainSidebar> {
  bool _isSigningOut = false;

  String get _matchedLocation => GoRouterState.of(context).matchedLocation;

  bool _matches(String routePath) =>
      _matchedLocation == routePath ||
      _matchedLocation.startsWith('$routePath/');

  void _openAccounts() {
    if (!_matches('/accounts')) {
      context.go('/accounts');
    }
  }

  Future<void> _handleSignOut() async {
    if (_isSigningOut) return;
    final syncNotifier = ref.read(syncProvider.notifier);
    final accountNotifier = ref.read(accountProvider.notifier);
    final securityNotifier = ref.read(appSecurityProvider.notifier);

    setState(() {
      _isSigningOut = true;
    });

    try {
      securityNotifier.lock();
      accountNotifier.clearSensitiveStateForLock();
      if (mounted) {
        context.go('/unlock');
      }
      await syncNotifier.clearSensitiveStateForLock();
    } finally {
      if (mounted) {
        setState(() {
          _isSigningOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(accountProvider);
    final accounts = [
      ...(accountAsync.value?.accounts ?? const <AccountInfo>[]),
    ];
    accounts.sort((a, b) => a.order.compareTo(b.order));
    final activeAccountUuid = accountAsync.value?.activeAccountUuid;
    AccountInfo? activeAccount;
    if (activeAccountUuid != null) {
      for (final account in accounts) {
        if (account.uuid == activeAccountUuid) {
          activeAccount = account;
          break;
        }
      }
    }
    final accountName = activeAccount?.name ?? 'Username';
    final sync = ref.watch(syncProvider).value ?? SyncState();
    final swapFeatureEnabled = ref.watch(swapFeatureEnabledProvider);

    return AppDesktopSidebarSurface(
      clipBehavior: Clip.none,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                right: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  AppSidebarItem(
                    key: const ValueKey('sidebar_accounts_button'),
                    label: accountName,
                    leading: _SidebarAccountAvatar(
                      profilePictureId:
                          activeAccount?.profilePictureId ??
                          kDefaultProfilePictureId,
                    ),
                    leadingGap: AppSpacing.xs,
                    active: _matches('/accounts'),
                    onTap: _matches('/accounts') ? null : _openAccounts,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    key: const ValueKey('sidebar_home_button'),
                    label: 'Home',
                    iconName: AppIcons.home,
                    active: _matches('/home'),
                    onTap: _matches('/home') ? null : () => context.go('/home'),
                  ),
                  if (swapFeatureEnabled) ...[
                    const SizedBox(height: AppSpacing.xs),
                    AppSidebarItem(
                      key: const ValueKey('sidebar_swap_button'),
                      label: 'Swap',
                      iconName: AppIcons.swapArrows,
                      active: _matches('/swap'),
                      onTap: _matches('/swap')
                          ? null
                          : () => context.go('/swap'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    key: const ValueKey('sidebar_address_book_button'),
                    label: 'Address book',
                    iconName: AppIcons.users,
                    active: _matches('/address-book'),
                    onTap: _matches('/address-book')
                        ? null
                        : () => context.go('/address-book'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    key: const ValueKey('sidebar_activity_button'),
                    label: 'Activity',
                    iconName: AppIcons.history,
                    active: _matches('/activity'),
                    onTap: _matches('/activity')
                        ? null
                        : () => context.go('/activity'),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSidebarItem(
                    label: 'Settings',
                    iconName: AppIcons.cog,
                    active: _matches('/settings'),
                    onTap: _matches('/settings')
                        ? null
                        : () => context.go('/settings'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'About Vizor',
                    iconName: AppIcons.vizor,
                    active: _matches('/about'),
                    onTap: _matches('/about')
                        ? null
                        : () => context.go('/about'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    label: 'Sign out',
                    iconName: AppIcons.logOut,
                    onTap: _isSigningOut ? null : _handleSignOut,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _SidebarSyncStatus(sync: sync),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarAccountAvatar extends StatelessWidget {
  const _SidebarAccountAvatar({required this.profilePictureId});

  final String profilePictureId;

  @override
  Widget build(BuildContext context) {
    return AppProfilePicture(
      profilePictureId: profilePictureId,
      size: AppProfilePictureSize.medium,
    );
  }
}

class _SidebarSyncStatus extends StatelessWidget {
  const _SidebarSyncStatus({required this.sync});

  final SyncState sync;

  static const _height = 34.0;
  static const _indicatorWidth = 5.0;
  static const _indicatorHeight = 32.0;
  static const _indicatorLeft = -AppSpacing.md;
  static const _textLeft = AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final indicatorLeft =
        AppSidebarLayoutScope.syncIndicatorLeftOffsetOf(context) ??
        _indicatorLeft;
    final status = _SidebarSyncStatusData.from(sync);
    final textColor = switch (status.kind) {
      _SidebarSyncStatusKind.syncing => colors.sync.textSyncing,
      _SidebarSyncStatusKind.failed => colors.sync.textError,
      _SidebarSyncStatusKind.synced => colors.sync.text,
    };
    final indicatorColor = switch (status.kind) {
      _SidebarSyncStatusKind.failed => colors.sync.lightError,
      _ => colors.sync.lightSuccess,
    };

    return SizedBox(
      height: _height,
      child: Semantics(
        label: status.semanticsLabel,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: indicatorLeft,
              top: (_height - _indicatorHeight) / 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: indicatorColor,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(AppRadii.full),
                  ),
                ),
                child: const SizedBox(
                  key: ValueKey('sidebar_sync_indicator'),
                  width: _indicatorWidth,
                  height: _indicatorHeight,
                ),
              ),
            ),
            Positioned(
              left: _textLeft,
              right: AppSpacing.xxs,
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  status.label,
                  key: const ValueKey('sidebar_sync_text'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(color: textColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SidebarSyncStatusKind { syncing, failed, synced }

class _SidebarSyncStatusData {
  const _SidebarSyncStatusData({
    required this.kind,
    required this.label,
    required this.semanticsLabel,
  });

  final _SidebarSyncStatusKind kind;
  final String label;
  final String semanticsLabel;

  factory _SidebarSyncStatusData.from(SyncState sync) {
    final failure = sync.failure;
    if (failure != null) {
      final reason = _syncFailureReason(failure.kind);
      return _SidebarSyncStatusData(
        kind: _SidebarSyncStatusKind.failed,
        label: 'Syncing failed: $reason',
        semanticsLabel: 'Syncing failed: $reason',
      );
    }

    final complete =
        !sync.isSyncing &&
        (sync.percentage >= 1.0 ||
            (sync.chainTipHeight > 0 &&
                sync.scannedHeight >= sync.chainTipHeight));
    if (!complete && (sync.isSyncing || sync.isBackgroundMode)) {
      final pct = formatSidebarSyncPercentage(sync.displayPercentage);
      return _SidebarSyncStatusData(
        kind: _SidebarSyncStatusKind.syncing,
        label: '$pct% Syncing...',
        semanticsLabel: 'Syncing $pct percent',
      );
    }

    return const _SidebarSyncStatusData(
      kind: _SidebarSyncStatusKind.synced,
      label: 'Vizor is synced',
      semanticsLabel: 'Vizor is synced',
    );
  }
}

String _syncFailureReason(SyncFailureKind kind) {
  return switch (kind) {
    SyncFailureKind.network => 'Network error',
    SyncFailureKind.endpoint => 'Endpoint error',
    SyncFailureKind.databaseBusy => 'Wallet data busy',
    SyncFailureKind.databaseFatal => 'Wallet data error',
    SyncFailureKind.chainRecovery => 'Chain recovery',
    SyncFailureKind.parseFatal => 'Data error',
    SyncFailureKind.unknown => 'Unknown error',
  };
}

@visibleForTesting
String formatSidebarSyncPercentage(double progress) {
  final pct = (progress.clamp(0.0, 1.0) * 100).toDouble();
  return pct.clamp(0.0, 99.0).toStringAsFixed(0);
}
