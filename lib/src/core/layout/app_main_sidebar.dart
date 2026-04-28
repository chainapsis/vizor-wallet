import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/sync_provider.dart';
import '../profile_pictures.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_button.dart';
import 'app_desktop_shell.dart';

class AppMainSidebar extends ConsumerStatefulWidget {
  const AppMainSidebar({super.key});

  @override
  ConsumerState<AppMainSidebar> createState() => _AppMainSidebarState();
}

class _AppMainSidebarState extends ConsumerState<AppMainSidebar> {
  static const double _selectorHeight = 40;
  static const double _selectorGap = 6;
  static const double _dropdownHeaderHeight = 50;
  static const double _dropdownFooterHeight = 50;
  static const double _accountRowHeight = 40;
  static const double _maxListViewportHeight = 164;

  final ScrollController _accountsScrollController = ScrollController();
  bool _isDropdownOpen = false;
  bool _isSelectorHovered = false;
  bool _isSigningOut = false;

  String get _matchedLocation => GoRouterState.of(context).matchedLocation;

  bool _matches(String routePath) =>
      _matchedLocation == routePath ||
      _matchedLocation.startsWith('$routePath/');

  @override
  void dispose() {
    _accountsScrollController.dispose();
    super.dispose();
  }

  Future<void> _handleAccountSelected(String uuid) async {
    final activeAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
    if (uuid == activeAccountUuid) return;
    await ref.read(accountProvider.notifier).switchAccount(uuid);
    await ref.read(syncProvider.notifier).refreshAfterSend();
    if (!mounted) return;
    setState(() {
      _isDropdownOpen = false;
    });
  }

  void _toggleDropdown() {
    setState(() {
      _isDropdownOpen = !_isDropdownOpen;
    });
  }

  Future<void> _handleSignOut() async {
    if (_isSigningOut) return;
    final syncNotifier = ref.read(syncProvider.notifier);
    final accountNotifier = ref.read(accountProvider.notifier);
    final securityNotifier = ref.read(appSecurityProvider.notifier);

    setState(() {
      _isSigningOut = true;
      _isDropdownOpen = false;
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
        child: TapRegion(
          onTapOutside: (_) {
            if (!_isDropdownOpen) return;
            setState(() {
              _isDropdownOpen = false;
            });
          },
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
                          label: 'Wallet',
                          iconName: AppIcons.wallet,
                          active: _matches('/home'),
                          onTap: _matches('/home')
                              ? null
                              : () => context.go('/home'),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        AppSidebarItem(
                          label: 'Send',
                          iconName: AppIcons.plane,
                          active: _matches('/send'),
                          onTap: _matches('/send')
                              ? null
                              : () => context.go('/send'),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        AppSidebarItem(
                          label: 'Receive',
                          iconName: AppIcons.arrowDownCircle,
                          active: _matches('/receive'),
                          onTap: _matches('/receive')
                              ? null
                              : () => context.go('/receive'),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        AppSidebarItem(
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
                        const AppSidebarItem(
                          label: 'About Vizor',
                          iconName: AppIcons.crystalBall,
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
                child: Column(
                  children: [
                    _SidebarAccountSelectorButton(
                      label: accountName,
                      profilePictureId:
                          activeAccount?.profilePictureId ??
                          kDefaultProfilePictureId,
                      isOpen: _isDropdownOpen,
                      isHovered: _isSelectorHovered,
                      onHoverChanged: (hovered) {
                        if (_isSelectorHovered == hovered) return;
                        setState(() {
                          _isSelectorHovered = hovered;
                        });
                      },
                      onTap: _toggleDropdown,
                    ),
                    if (_isDropdownOpen) ...[
                      const SizedBox(height: _selectorGap),
                      _SidebarAccountDropdown(
                        accounts: accounts,
                        activeAccountUuid: activeAccountUuid,
                        scrollController: _accountsScrollController,
                        headerHeight: _dropdownHeaderHeight,
                        footerHeight: _dropdownFooterHeight,
                        rowHeight: _accountRowHeight,
                        maxListViewportHeight: _maxListViewportHeight,
                        onSelectAccount: _handleAccountSelected,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarAccountSelectorButton extends StatelessWidget {
  const _SidebarAccountSelectorButton({
    required this.label,
    required this.profilePictureId,
    required this.isOpen,
    required this.isHovered,
    required this.onHoverChanged,
    required this.onTap,
  });

  final String label;
  final String profilePictureId;
  final bool isOpen;
  final bool isHovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final backgroundColor = (isOpen || isHovered)
        ? colors.state.selectedOpacity
        : null;
    final textColor = colors.text.accent;
    final iconColor = colors.icon.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: GestureDetector(
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
              AppIcon(
                isOpen ? AppIcons.collapsed : AppIcons.expand,
                size: 20,
                color: iconColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarAccountDropdown extends StatelessWidget {
  const _SidebarAccountDropdown({
    required this.accounts,
    required this.activeAccountUuid,
    required this.scrollController,
    required this.headerHeight,
    required this.footerHeight,
    required this.rowHeight,
    required this.maxListViewportHeight,
    required this.onSelectAccount,
  });

  final List<AccountInfo> accounts;
  final String? activeAccountUuid;
  final ScrollController scrollController;
  final double headerHeight;
  final double footerHeight;
  final double rowHeight;
  final double maxListViewportHeight;
  final Future<void> Function(String uuid) onSelectAccount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final desiredListHeight = accounts.length * rowHeight;
    final listViewportHeight = desiredListHeight <= 0
        ? rowHeight
        : desiredListHeight > maxListViewportHeight
        ? maxListViewportHeight
        : desiredListHeight.toDouble();
    final list = ListView.builder(
      controller: scrollController,
      padding: EdgeInsets.zero,
      itemCount: accounts.length,
      itemBuilder: (context, index) {
        final account = accounts[index];
        final isActive = account.uuid == activeAccountUuid;
        return _SidebarAccountRow(
          account: account,
          isActive: isActive,
          onTap: isActive ? null : () => onSelectAccount(account.uuid),
        );
      },
    );

    return Container(
      height: headerHeight + listViewportHeight + footerHeight,
      decoration: BoxDecoration(
        color: colors.surface.input,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
        boxShadow: [
          BoxShadow(
            color: colors.background.neutralScrim,
            blurRadius: 25,
            spreadRadius: -10,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: headerHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${accounts.length} ${accounts.length == 1 ? 'Account' : 'Accounts'}',
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: listViewportHeight,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xxs),
              child: list,
            ),
          ),
          SizedBox(
            height: footerHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
              child: _SidebarCreateWalletRow(
                onTap: () => context.go('/add-account'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarAccountRow extends StatelessWidget {
  const _SidebarAccountRow({
    required this.account,
    required this.isActive,
    required this.onTap,
  });

  final AccountInfo account;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelColor = colors.text.accent;
    final trailing = isActive
        ? AppIcon(AppIcons.checkCircle, size: 20, color: colors.icon.regular)
        : AppIcon(AppIcons.chevronForward, size: 20, color: colors.icon.accent);

    final row = SizedBox(
      height: 40,
      child: Opacity(
        opacity: isActive ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            right: AppSpacing.s,
          ),
          child: Row(
            children: [
              _SidebarAccountAvatar(profilePictureId: account.profilePictureId),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  account.name,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(color: labelColor),
                ),
              ),
              trailing,
            ],
          ),
        ),
      ),
    );

    return onTap == null
        ? row
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: row,
            ),
          );
  }
}

class _SidebarCreateWalletRow extends StatelessWidget {
  const _SidebarCreateWalletRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: AppButton(
          onPressed: onTap,
          variant: AppButtonVariant.ghost,
          minWidth: constraints.maxWidth,
          leading: const AppIcon(AppIcons.addNew),
          child: const Text('Create New Wallet'),
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
    final option = resolveProfilePictureOption(profilePictureId);

    return ClipOval(
      child: Image.asset(
        option.assetPath,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
      ),
    );
  }
}
