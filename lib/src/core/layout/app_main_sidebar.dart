import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/sync_provider.dart';
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
                    key: const ValueKey('sidebar_wallet_button'),
                    label: 'Wallet',
                    iconName: AppIcons.wallet,
                    active: _matches('/home'),
                    onTap: _matches('/home') ? null : () => context.go('/home'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    key: const ValueKey('sidebar_send_button'),
                    label: 'Send',
                    iconName: AppIcons.plane,
                    active: _matches('/send'),
                    onTap: _matches('/send') ? null : () => context.go('/send'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppSidebarItem(
                    key: const ValueKey('sidebar_receive_button'),
                    label: 'Receive',
                    iconName: AppIcons.arrowDownCircle,
                    active: _matches('/receive'),
                    onTap: _matches('/receive')
                        ? null
                        : () => context.go('/receive'),
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
                    label: 'Sign Out',
                    iconName: AppIcons.logOut,
                    onTap: _isSigningOut ? null : _handleSignOut,
                  ),
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
