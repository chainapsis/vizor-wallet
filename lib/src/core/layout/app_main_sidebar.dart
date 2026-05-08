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
  static const double _selectorHeight = 40;

  bool _isSelectorHovered = false;
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: _selectorHeight + AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Column(
                    children: [
                      AppSidebarItem(
                        key: const ValueKey('sidebar_wallet_button'),
                        label: 'Wallet',
                        iconName: AppIcons.wallet,
                        active: _matches('/home'),
                        onTap: _matches('/home')
                            ? null
                            : () => context.go('/home'),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      AppSidebarItem(
                        key: const ValueKey('sidebar_send_button'),
                        label: 'Send',
                        iconName: AppIcons.plane,
                        active: _matches('/send'),
                        onTap: _matches('/send')
                            ? null
                            : () => context.go('/send'),
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
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _SidebarAccountSelectorButton(
                label: accountName,
                profilePictureId:
                    activeAccount?.profilePictureId ?? kDefaultProfilePictureId,
                active: _matches('/accounts'),
                isHovered: _isSelectorHovered,
                onHoverChanged: (hovered) {
                  if (_isSelectorHovered == hovered) return;
                  setState(() {
                    _isSelectorHovered = hovered;
                  });
                },
                onTap: _openAccounts,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarAccountSelectorButton extends StatelessWidget {
  const _SidebarAccountSelectorButton({
    required this.label,
    required this.profilePictureId,
    required this.active,
    required this.isHovered,
    required this.onHoverChanged,
    required this.onTap,
  });

  final String label;
  final String profilePictureId;
  final bool active;
  final bool isHovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final backgroundColor = (active || isHovered)
        ? colors.state.selectedOpacity
        : null;
    final textColor = colors.text.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
        key: const ValueKey('sidebar_account_selector_button'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppRadii.xSmall),
          ),
          child: Row(
            children: [
              _SidebarAccountAvatar(profilePictureId: profilePictureId),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(color: textColor),
                ),
              ),
            ],
          ),
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
