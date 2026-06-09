import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/profile_pictures.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_icon.dart';

const _homePreviewActivationShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};

enum HomeDesktopPreviewState {
  importing,
  noBalance,
  noActivity,
  activity,
  keystone,
  accounts,
}

enum HomeDesktopPreviewNotice {
  none,
  passwordRecovery,
  shieldQueued,
  syncFailure,
}

class HomeDesktopPreview extends StatefulWidget {
  const HomeDesktopPreview({
    super.key,
    required this.state,
    this.notice = HomeDesktopPreviewNotice.none,
    this.accountCount = 4,
    this.onAccountSelected,
    this.onManageAccounts,
    this.onAddAccount,
  });

  final HomeDesktopPreviewState state;
  final HomeDesktopPreviewNotice notice;
  final int accountCount;
  final ValueChanged<int>? onAccountSelected;
  final VoidCallback? onManageAccounts;
  final VoidCallback? onAddAccount;

  static const size = Size(1080, 720);

  @override
  State<HomeDesktopPreview> createState() => _HomeDesktopPreviewState();
}

class _HomeDesktopPreviewState extends State<HomeDesktopPreview> {
  late bool _isAccountMenuOpen;
  var _selectedAccountIndex = 0;

  bool get _hasBalance =>
      widget.state != HomeDesktopPreviewState.importing &&
      widget.state != HomeDesktopPreviewState.noBalance;

  bool get _hasActivity =>
      widget.state == HomeDesktopPreviewState.activity ||
      widget.state == HomeDesktopPreviewState.keystone ||
      widget.state == HomeDesktopPreviewState.accounts;

  bool get _showsKeystone =>
      widget.state == HomeDesktopPreviewState.keystone ||
      widget.state == HomeDesktopPreviewState.accounts;

  String get _accountName =>
      _selectedAccountIndex == 0
          ? 'Username'
          : 'Account ${_selectedAccountIndex + 1}';

  @override
  void initState() {
    super.initState();
    _isAccountMenuOpen = widget.state == HomeDesktopPreviewState.accounts;
  }

  @override
  void didUpdateWidget(HomeDesktopPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _isAccountMenuOpen = widget.state == HomeDesktopPreviewState.accounts;
    }
  }

  void _toggleAccountMenu() {
    setState(() => _isAccountMenuOpen = !_isAccountMenuOpen);
  }

  void _selectAccount(int index) {
    setState(() {
      _selectedAccountIndex = index;
      _isAccountMenuOpen = false;
    });
    widget.onAccountSelected?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.of(context) == AppThemeData.dark;

    return SizedBox.fromSize(
      size: HomeDesktopPreview.size,
      child: _WindowShell(
        isDark: isDark,
        state: widget.state,
        accountName: _accountName,
        hasBalance: _hasBalance,
        hasActivity: _hasActivity,
        showsAccountMenu: _isAccountMenuOpen,
        showsKeystone: _showsKeystone,
        notice: widget.notice,
        accountCount: widget.accountCount,
        onAccountHeaderTap: _toggleAccountMenu,
        onAccountSelected: _selectAccount,
        onManageAccounts: widget.onManageAccounts,
        onAddAccount: widget.onAddAccount,
      ),
    );
  }
}

const _homeDisplayXl = TextStyle(
  fontFamily: 'Libre Caslon Text',
  fontWeight: FontWeight.w400,
  fontSize: 45,
  height: 48 / 45,
  letterSpacing: -1.35,
);

const _homeHeadlineMedium = TextStyle(
  fontFamily: 'Libre Caslon Text',
  fontWeight: FontWeight.w400,
  fontSize: 28,
  height: 30 / 28,
  letterSpacing: -0.28,
);

const _homeLabelMRegular = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w400,
  fontSize: 14,
  height: 16 / 14,
  letterSpacing: -0.06,
);

const _homeLabelMMedium = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w500,
  fontSize: 14,
  height: 16 / 14,
  letterSpacing: -0.06,
);

const _homeLabelMSemiBold = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w600,
  fontSize: 14,
  height: 16 / 14,
  letterSpacing: -0.06,
);

const _homeLabelSRegular = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w400,
  fontSize: 13,
  height: 14 / 13,
  letterSpacing: 0,
);

Color _positiveStrongColor(BuildContext context) {
  return context.colors.text.positiveStrong;
}

class _WindowShell extends StatelessWidget {
  const _WindowShell({
    required this.isDark,
    required this.state,
    required this.accountName,
    required this.hasBalance,
    required this.hasActivity,
    required this.showsAccountMenu,
    required this.showsKeystone,
    required this.notice,
    required this.accountCount,
    required this.onAccountHeaderTap,
    required this.onAccountSelected,
    this.onManageAccounts,
    this.onAddAccount,
  });

  final bool isDark;
  final HomeDesktopPreviewState state;
  final String accountName;
  final bool hasBalance;
  final bool hasActivity;
  final bool showsAccountMenu;
  final bool showsKeystone;
  final HomeDesktopPreviewNotice notice;
  final int accountCount;
  final VoidCallback onAccountHeaderTap;
  final ValueChanged<int> onAccountSelected;
  final VoidCallback? onManageAccounts;
  final VoidCallback? onAddAccount;

  @override
  Widget build(BuildContext context) {
    final windowColor =
        isDark ? const Color(0xFF0D0F0F) : const Color(0xFFF7F7F7);

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 17.5, sigmaY: 17.5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: windowColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: (isDark
                      ? const Color(0xFFFFFFFF)
                      : const Color(0xFF000000))
                  .withValues(alpha: isDark ? 0.10 : 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.35),
                blurRadius: 48,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Stack(
            children: [
              _FullPageBackground(
                isDark: isDark,
                isImporting: state == HomeDesktopPreviewState.importing,
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Row(
                    children: [
                      _Sidebar(
                        isDark: isDark,
                        state: state,
                        accountName: accountName,
                        hasBalance: hasBalance,
                        hasActivity: hasActivity,
                        showsAccountMenu: showsAccountMenu,
                        showsKeystone: showsKeystone,
                        accountCount: accountCount,
                        onAccountHeaderTap: onAccountHeaderTap,
                        onAccountSelected: onAccountSelected,
                        onManageAccounts: onManageAccounts,
                        onAddAccount: onAddAccount,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: _TrailingPane(
                          state: state,
                          hasBalance: hasBalance,
                          hasActivity: hasActivity,
                          notice: notice,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(left: 20, top: 20, child: _WindowControls()),
            ],
          ),
        ),
      ),
    );
  }
}

class _FullPageBackground extends StatelessWidget {
  const _FullPageBackground({required this.isDark, required this.isImporting});

  final bool isDark;
  final bool isImporting;

  @override
  Widget build(BuildContext context) {
    final variant = isImporting ? 'importing' : 'default';
    final theme = isDark ? 'dark' : 'light';
    return Positioned(
      left: 0,
      top: 0,
      width: 1080,
      height: 720,
      child: Image.asset(
        'assets/illustrations/home_${variant}_background_$theme.png',
        key: const ValueKey('home_preview_full_page_background'),
        width: 1080,
        height: 720,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
      ),
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _WindowControl(color: Color(0xFFFF736A)),
        SizedBox(width: 9),
        _WindowControl(color: Color(0xFFFEBC2E)),
        SizedBox(width: 9),
        _WindowControl(color: Color(0xFFB8B8B8)),
      ],
    );
  }
}

class _WindowControl extends StatelessWidget {
  const _WindowControl({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF000000).withValues(alpha: 0.10),
          width: 0.5,
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.isDark,
    required this.state,
    required this.accountName,
    required this.hasBalance,
    required this.hasActivity,
    required this.showsAccountMenu,
    required this.showsKeystone,
    required this.accountCount,
    required this.onAccountHeaderTap,
    required this.onAccountSelected,
    this.onManageAccounts,
    this.onAddAccount,
  });

  final bool isDark;
  final HomeDesktopPreviewState state;
  final String accountName;
  final bool hasBalance;
  final bool hasActivity;
  final bool showsAccountMenu;
  final bool showsKeystone;
  final int accountCount;
  final VoidCallback onAccountHeaderTap;
  final ValueChanged<int> onAccountSelected;
  final VoidCallback? onManageAccounts;
  final VoidCallback? onAddAccount;

  bool get _isImporting => state == HomeDesktopPreviewState.importing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final sidebarColor =
        isDark
            ? const Color(0xFF050606).withValues(alpha: 0.42)
            : const Color(0xFFFFFFFF).withValues(alpha: 0.30);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 17.5, sigmaY: 17.5),
        child: Container(
          width: 256,
          height: 704,
          decoration: BoxDecoration(
            color: sidebarColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: (isDark ? colors.border.subtle : const Color(0xFFFFFFFF))
                  .withValues(alpha: isDark ? 0.7 : 0.65),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.12),
                blurRadius: 44,
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AccountHeader(
                        accountName: accountName,
                        hasBalance: hasBalance,
                        showsKeystone: showsKeystone,
                        onTap: onAccountHeaderTap,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _NavItem(
                        icon: _isImporting ? AppIcons.loader : AppIcons.home,
                        label: _isImporting ? 'Importing...' : 'Home',
                        active: true,
                        animated: _isImporting,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _NavItem(
                        icon: AppIcons.swapArrows,
                        label: 'Swap',
                        enabled: !_isImporting,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _NavItem(
                        icon: AppIcons.history,
                        label: 'Activity',
                        badge: hasActivity,
                        enabled: !_isImporting,
                      ),
                      const Spacer(),
                      const _NavItem(icon: AppIcons.cog, label: 'Settings'),
                      const SizedBox(height: AppSpacing.xs),
                      const _NavItem(icon: AppIcons.logOut, label: 'Sign out'),
                      if (!_isImporting) ...[
                        const SizedBox(height: AppSpacing.md),
                        const _SyncStatus(),
                      ],
                    ],
                  ),
                ),
              ),
              if (showsAccountMenu)
                Positioned(
                  left: 16,
                  top: 96,
                  child: _AccountsPopover(
                    accountCount: accountCount,
                    onAccountSelected: onAccountSelected,
                    onManageAccounts: onManageAccounts,
                    onAddAccount: onAddAccount,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.accountName,
    required this.hasBalance,
    required this.showsKeystone,
    required this.onTap,
  });

  final String accountName;
  final bool hasBalance;
  final bool showsKeystone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          _ProfileImage(size: 32, showsKeystone: showsKeystone),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  accountName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _homeLabelMSemiBold.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                if (hasBalance) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '142.23 ZEC',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _homeLabelMRegular.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ),
                      if (showsKeystone) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        AppIcon(
                          AppIcons.eye,
                          size: 16,
                          color: colors.text.secondary,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          AppIcon(AppIcons.copy, size: 16, color: colors.icon.regular),
        ],
      ),
    );
  }
}

class _ProfileImage extends StatelessWidget {
  const _ProfileImage({required this.size, this.showsKeystone = false});

  final double size;
  final bool showsKeystone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final badgeSize = size >= 32 ? 16.0 : 12.0;
    final badgeIconSize = size >= 32 ? 14.0 : 12.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipOval(
            child: Image.asset(
              kKnightProfilePictureAsset,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          ),
          if (showsKeystone)
            Positioned(
              right: size >= 32 ? -5 : -4,
              bottom: 0,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: colors.background.inverse,
                  borderRadius: BorderRadius.circular(size >= 32 ? 4 : 3),
                  border: Border.all(color: colors.background.ground, width: 2),
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.keystone,
                    size: badgeIconSize,
                    color: colors.text.inverse,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountsPopover extends StatefulWidget {
  const _AccountsPopover({
    required this.accountCount,
    required this.onAccountSelected,
    this.onManageAccounts,
    this.onAddAccount,
  });

  final int accountCount;
  final ValueChanged<int> onAccountSelected;
  final VoidCallback? onManageAccounts;
  final VoidCallback? onAddAccount;

  @override
  State<_AccountsPopover> createState() => _AccountsPopoverState();
}

class _AccountsPopoverState extends State<_AccountsPopover> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accountCount = widget.accountCount.clamp(1, 12).toInt();
    final accounts = [
      for (var index = 0; index < accountCount; index++) 'Account ${index + 1}',
    ];
    final showScrollbar = accounts.length > 3;
    return Container(
      key: const ValueKey('home_accounts_popover'),
      width: 221,
      height: 254,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surface.nav,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colors.border.subtle,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.shadows.regular,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              'My accounts',
              style: _homeLabelMRegular.copyWith(color: colors.text.muted),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            key: const ValueKey('home_accounts_list'),
            height: 161,
            child: RawScrollbar(
              key: const ValueKey('home_accounts_scrollbar'),
              controller: _scrollController,
              thumbVisibility: showScrollbar,
              radius: const Radius.circular(AppRadii.full),
              thickness: 6,
              mainAxisMargin: 6,
              crossAxisMargin: 6,
              thumbColor: colors.background.neutralStrongOpacity,
              child: Padding(
                key: const ValueKey('home_accounts_list_gutter'),
                padding: const EdgeInsets.only(right: 18),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: ListView.separated(
                    controller: _scrollController,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    itemCount: accounts.length,
                    separatorBuilder:
                        (_, _) => const SizedBox(height: AppSpacing.xxs),
                    itemBuilder: (context, index) {
                      return _AccountPopoverRow(
                        key: ValueKey('home_account_row_$index'),
                        label: accounts[index],
                        showsKeystone: index == 1 || index == 2,
                        showsCopy: index > 0,
                        onTap: () => widget.onAccountSelected(index),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const _AccountsPopoverActionsDivider(),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            key: const ValueKey('home_accounts_buttons'),
            height: 36,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _AccountsPopoverClickTarget(
                  onTap: widget.onManageAccounts ?? () {},
                  child: Container(
                    key: const ValueKey('home_accounts_manage'),
                    width: 153,
                    height: 36,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: colors.button.secondary.bg,
                      borderRadius: BorderRadius.circular(AppRadii.full),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs,
                      ),
                      child: Text(
                        'Manage',
                        style: AppTypography.labelMedium.copyWith(
                          color: colors.button.secondary.label,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                _AccountsPopoverClickTarget(
                  onTap: widget.onAddAccount ?? () {},
                  child: Container(
                    key: const ValueKey('home_accounts_add'),
                    width: 48,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.button.primary.bg,
                      borderRadius: BorderRadius.circular(AppRadii.full),
                      border: Border.all(
                        color: colors.border.subtleOpacity,
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                    ),
                    child: Center(
                      child: AppIcon(
                        AppIcons.addNew,
                        size: 16,
                        color: colors.button.primary.label,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountsPopoverActionsDivider extends StatelessWidget {
  const _AccountsPopoverActionsDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('home_accounts_actions_divider'),
      height: 1,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(color: context.colors.border.subtle),
      ),
    );
  }
}

class _AccountPopoverRow extends StatelessWidget {
  const _AccountPopoverRow({
    super.key,
    required this.label,
    required this.showsKeystone,
    required this.showsCopy,
    required this.onTap,
  });

  final String label;
  final bool showsKeystone;
  final bool showsCopy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _AccountsPopoverClickTarget(
      onTap: onTap,
      child: SizedBox(
        height: 40,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Row(
            children: [
              _ProfileImage(size: 32, showsKeystone: showsKeystone),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _homeLabelMMedium.copyWith(color: colors.text.accent),
                ),
              ),
              if (showsCopy)
                AppIcon(AppIcons.copy, size: 16, color: colors.icon.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountsPopoverClickTarget extends StatelessWidget {
  const _AccountsPopoverClickTarget({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.badge = false,
    this.animated = false,
    this.enabled = true,
  });

  final String icon;
  final String label;
  final bool active;
  final bool badge;
  final bool animated;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelColor =
        active ? colors.navPanel.activeLabel : colors.text.accent;
    final iconColor = active ? colors.navPanel.activeIcon : colors.icon.regular;

    final item = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: active ? colors.navPanel.activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Row(
        children: [
          AppIcon(icon, size: 20, color: iconColor, animated: animated),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _homeLabelMSemiBold.copyWith(color: labelColor),
            ),
          ),
          if (badge)
            Container(
              width: 24,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.navPanel.badgeBg,
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
              child: Text(
                '1',
                style: AppTypography.labelSmall.copyWith(
                  color: colors.navPanel.badgeLabel,
                ),
              ),
            ),
        ],
      ),
    );
    return enabled ? item : Opacity(opacity: 0.5, child: item);
  }
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Container(
            width: 5,
            height: 32,
            decoration: BoxDecoration(
              color: colors.sync.lightSuccess,
              borderRadius: BorderRadius.circular(AppRadii.full),
              boxShadow: [
                BoxShadow(
                  color: colors.sync.lightSuccess.withValues(alpha: 0.35),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s),
          Text(
            '34% Syncing...',
            style: _homeLabelMRegular.copyWith(color: colors.sync.textSyncing),
          ),
        ],
      ),
    );
  }
}

class _TrailingPane extends StatelessWidget {
  const _TrailingPane({
    required this.state,
    required this.hasBalance,
    required this.hasActivity,
    required this.notice,
  });

  final HomeDesktopPreviewState state;
  final bool hasBalance;
  final bool hasActivity;
  final HomeDesktopPreviewNotice notice;

  bool get _isImporting => state == HomeDesktopPreviewState.importing;
  bool get _isNoBalance => state == HomeDesktopPreviewState.noBalance;

  static const _referencePaneHeight = 704.0;
  static const _referenceTop = 48.0;

  double _contentTop(double paneHeight) {
    return math.max(
      0.0,
      _referenceTop + ((paneHeight - _referencePaneHeight) / 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentTop = _contentTop(constraints.maxHeight);
        if (!_isImporting) {
          return CustomScrollView(
            key: const ValueKey('home_preview_scroll_view'),
            clipBehavior: Clip.none,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(top: contentTop),
                sliver: _HomePreviewCenteredSliver(
                  contentKey: const ValueKey('home_preview_content'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s,
                    AppSpacing.sm,
                    AppSpacing.s,
                    0,
                  ),
                  child: _HomeCard(
                    hasBalance: hasBalance,
                    isNoBalance: _isNoBalance,
                  ),
                ),
              ),
              if (notice != HomeDesktopPreviewNotice.none) ...[
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xs),
                ),
                _HomePreviewCenteredSliver(
                  child: _PreviewNoticeCard(notice: notice),
                ),
              ],
              SliverPadding(
                padding: EdgeInsets.only(
                  top: hasBalance ? AppSpacing.s : AppSpacing.md,
                ),
                sliver:
                    hasActivity
                        ? const _HomePreviewCenteredSliver(
                          padding: EdgeInsets.fromLTRB(
                            AppSpacing.s,
                            0,
                            AppSpacing.s,
                            AppSpacing.sm,
                          ),
                          child: _RecentActivityCard(),
                        )
                        : const _EmptyActivitySliver(),
              ),
            ],
          );
        }

        return Stack(
          children: [
            Positioned.fill(
              top: contentTop,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  key: const ValueKey('home_preview_content'),
                  width: 420,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s,
                      vertical: AppSpacing.sm,
                    ),
                    child: const _ImportingContent(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HomePreviewCenteredSliver extends StatelessWidget {
  const _HomePreviewCenteredSliver({
    required this.child,
    this.contentKey,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.s),
  });

  final Widget child;
  final Key? contentKey;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          key: contentKey,
          width: 420,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _ImportingContent extends StatelessWidget {
  const _ImportingContent();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 396,
      height: 624,
      child: Stack(
        children: [
          Positioned(
            left: 28,
            top: 105,
            width: 340,
            height: 414,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: 340,
                  height: 48,
                  child: Text(
                    '32%',
                    textAlign: TextAlign.center,
                    style: _homeDisplayXl.copyWith(color: colors.text.accent),
                  ),
                ),
                Positioned(
                  left: 47,
                  top: 60,
                  width: 246,
                  height: 60,
                  child: Text(
                    "We're importing\nyour wallet...",
                    textAlign: TextAlign.center,
                    style: _homeHeadlineMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Positioned(
                  left: 76,
                  top: 136,
                  width: 188,
                  height: 42,
                  child: Text(
                    'It might take some time.\nKeep Vizor open & running.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
                const Positioned(
                  left: 0,
                  top: 194,
                  width: 340,
                  height: 220,
                  child: _RestIllustration(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RestIllustration extends StatelessWidget {
  const _RestIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 340,
      height: 220,
      child: Stack(
        children: [
          Positioned(
            left: 47,
            top: 28,
            width: 246,
            height: 192,
            child: Image.asset(
              'assets/illustrations/home_rest_character.png',
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.hasBalance, required this.isNoBalance});

  final bool hasBalance;
  final bool isNoBalance;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 396,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BalanceCard(hasBalance: hasBalance),
          const SizedBox(height: AppSpacing.s),
          if (isNoBalance)
            const _HomeActionButton(
              icon: AppIcons.arrowDownCircle,
              label: 'Receive your first ZEC',
              minWidth: 396,
            )
          else
            Row(
              children: [
                const Expanded(
                  child: _HomeActionButton(
                    icon: AppIcons.plane,
                    label: 'Send',
                    minWidth: 196,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Expanded(
                  child: _HomeActionButton(
                    icon: AppIcons.arrowDownCircle,
                    label: 'Receive',
                    minWidth: 196,
                    primary: false,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PreviewNoticeCard extends StatelessWidget {
  const _PreviewNoticeCard({required this.notice});

  final HomeDesktopPreviewNotice notice;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (String icon, String message, String actionLabel) = switch (notice) {
      HomeDesktopPreviewNotice.passwordRecovery => (
        AppIcons.warning,
        "We couldn't verify the previous password change. Try again or restart Vizor.",
        'Settings',
      ),
      HomeDesktopPreviewNotice.shieldQueued => (
        AppIcons.warning,
        'Shielding queued for retry. Check Activity.',
        'Dismiss',
      ),
      HomeDesktopPreviewNotice.syncFailure => (
        AppIcons.warning,
        'Network connection lost.',
        'Retry',
      ),
      HomeDesktopPreviewNotice.none => (AppIcons.warning, '', ''),
    };

    return Container(
      key: const ValueKey('home_preview_notice_card'),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        children: [
          AppIcon(icon, size: 16, color: colors.icon.warning),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _homeLabelMRegular.copyWith(color: colors.text.accent),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            actionLabel,
            style: _homeLabelMMedium.copyWith(color: colors.text.accent),
          ),
          const SizedBox(width: AppSpacing.xxs),
          AppIcon(
            AppIcons.chevronForward,
            size: 16,
            color: colors.icon.regular,
          ),
        ],
      ),
    );
  }
}

class _HomeActionButton extends StatelessWidget {
  const _HomeActionButton({
    required this.icon,
    required this.label,
    required this.minWidth,
    this.primary = true,
  });

  final String icon;
  final String label;
  final double minWidth;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg =
        primary ? colors.button.primary.label : colors.button.secondary.label;

    return _HomePreviewInteractiveTarget(
      semanticsLabel: label,
      onTap: () {},
      builder: (context, hovered, focused) {
        final bg =
            primary
                ? hovered
                    ? colors.button.primary.bgHover
                    : colors.button.primary.bg
                : hovered
                ? colors.button.secondary.bgHover
                : colors.button.secondary.bg;
        final focusRingColor =
            primary
                ? hovered
                    ? colors.button.primary.bgHover
                    : colors.button.primary.bg
                : colors.state.focusRing;

        return SizedBox(
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                height: 44,
                constraints: BoxConstraints(minWidth: minWidth),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: bg,
                  shape: const StadiumBorder(),
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: fg, size: 16),
                  child: DefaultTextStyle.merge(
                    style: _homeLabelMRegular.copyWith(color: fg),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(icon, size: 16, color: fg),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(label),
                      ],
                    ),
                  ),
                ),
              ),
              if (focused)
                Positioned(
                  left: -2,
                  top: -2,
                  right: -2,
                  bottom: -2,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: StadiumBorder(
                          side: BorderSide(color: focusRingColor, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HomePreviewInteractiveTarget extends StatefulWidget {
  const _HomePreviewInteractiveTarget({
    required this.onTap,
    required this.builder,
    this.semanticsLabel,
  });

  final VoidCallback onTap;
  final String? semanticsLabel;
  final Widget Function(BuildContext context, bool hovered, bool focused)
  builder;

  @override
  State<_HomePreviewInteractiveTarget> createState() =>
      _HomePreviewInteractiveTargetState();
}

class _HomePreviewInteractiveTargetState
    extends State<_HomePreviewInteractiveTarget> {
  bool _hovered = false;
  bool _focused = false;

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused != value) setState(() => _focused = value);
  }

  void _activate() {
    _setHovered(false);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: _setFocused,
          shortcuts: _homePreviewActivationShortcuts,
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<Intent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _activate,
            child: widget.builder(context, _hovered, _focused),
          ),
        ),
      ),
    );
  }
}

class _EmptyActivitySliver extends StatelessWidget {
  const _EmptyActivitySliver();

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final remainingHeight =
            constraints.viewportMainAxisExtent -
            constraints.precedingScrollExtent;
        final height = math.max(160.0, remainingHeight - AppSpacing.sm);

        return SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 420,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s,
                  0,
                  AppSpacing.s,
                  AppSpacing.sm,
                ),
                child: SizedBox(height: height, child: const _EmptyActivity()),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.hasBalance});

  final bool hasBalance;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardRadius = BorderRadius.circular(AppRadii.large);
    final shieldedCardRadius =
        hasBalance
            ? const BorderRadius.vertical(
              top: Radius.circular(AppRadii.large),
              bottom: Radius.circular(AppRadii.medium),
            )
            : cardRadius;
    return ClipRRect(
      borderRadius: cardRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background.homeCard,
          borderRadius: cardRadius,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 396,
              height: 200,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.background.homeCard,
                borderRadius: shieldedCardRadius,
                border: Border.all(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.07),
                  width: 1.5,
                ),
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AppIcon(
                            AppIcons.shieldKeyhole,
                            size: 20,
                            color: colors.icon.brandCrimson,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Shielded balance',
                            style: _homeLabelMRegular.copyWith(
                              color: colors.text.homeCard,
                            ),
                          ),
                          const Spacer(),
                          _HomePreviewInteractiveTarget(
                            semanticsLabel: 'Hide balance',
                            onTap: () {},
                            builder: (context, hovered, focused) {
                              return SizedBox(
                                key: const ValueKey(
                                  'home_preview_privacy_button',
                                ),
                                width: 32,
                                height: 32,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  alignment: Alignment.center,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 120,
                                      ),
                                      curve: Curves.easeOut,
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFFFFFFF,
                                        ).withValues(
                                          alpha: hovered ? 0.10 : 0.05,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: AppIcon(
                                          AppIcons.eye,
                                          size: 16,
                                          color: colors.text.homeCard,
                                        ),
                                      ),
                                    ),
                                    if (focused)
                                      Positioned(
                                        left: -2,
                                        top: -2,
                                        right: -2,
                                        bottom: -2,
                                        child: IgnorePointer(
                                          child: DecoratedBox(
                                            decoration: ShapeDecoration(
                                              shape: CircleBorder(
                                                side: BorderSide(
                                                  color: colors.state.focusRing,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (hasBalance) ...[
                        Text(
                          r'$1,200.12  +13.12% (24h)',
                          key: const ValueKey('home_preview_balance_fiat_text'),
                          style: _homeLabelMRegular.copyWith(
                            color: _positiveStrongColor(context),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            hasBalance ? '143.12' : '0',
                            style: _homeDisplayXl.copyWith(
                              color: colors.text.homeCard,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              'ZEC',
                              style: _homeHeadlineMedium.copyWith(
                                color: colors.text.homeCard,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (hasBalance) const _PreviewTransparentBalanceStrip(),
          ],
        ),
      ),
    );
  }
}

class _PreviewTransparentBalanceStrip extends StatelessWidget {
  const _PreviewTransparentBalanceStrip();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      key: const ValueKey('home_preview_transparent_balance_strip'),
      height: 56,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      AppIcons.transparentBalance,
                      size: 16,
                      color: colors.text.homeCard,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Flexible(
                      child: Text(
                        'Transparent balance: 2.42 ZEC',
                        key: const ValueKey(
                          'home_preview_transparent_balance_text',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.homeCard,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _HomePreviewInteractiveTarget(
              semanticsLabel: 'Shield balance',
              onTap: () {},
              builder: (context, hovered, focused) {
                final contentColor =
                    hovered
                        ? colors.button.primary.label
                        : colors.text.homeCard;
                final chevronColor =
                    hovered
                        ? colors.background.utilitySuccessStrong
                        : colors.text.homeCard;
                return ConstrainedBox(
                  key: const ValueKey('home_preview_shield_balance_button'),
                  constraints: const BoxConstraints(
                    minWidth: 96,
                    minHeight: 32,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xxs,
                              ),
                              child: Text(
                                'Shield balance',
                                style: AppTypography.labelLarge.copyWith(
                                  color: contentColor,
                                ),
                              ),
                            ),
                            AppIcon(
                              AppIcons.chevronForward,
                              size: 16,
                              color: chevronColor,
                            ),
                          ],
                        ),
                      ),
                      if (focused)
                        Positioned(
                          left: -2,
                          top: -2,
                          right: -2,
                          bottom: -2,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: ShapeDecoration(
                                shape: StadiumBorder(
                                  side: BorderSide(
                                    color: colors.state.focusRing,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 160) {
          return Center(
            child: Text(
              'No activity, yet...',
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
          );
        }
        final compact = constraints.maxHeight < 300;
        final verticalOffset = compact ? 0.0 : 32.0;
        final availableIllustrationHeight =
            constraints.maxHeight - (compact ? 116.0 : 92.0);
        final illustrationHeight =
            math
                .min(
                  192.0,
                  math.max(compact ? 64.0 : 96.0, availableIllustrationHeight),
                )
                .toDouble();
        final illustrationWidth = illustrationHeight * (246 / 192);

        return Center(
          child: Transform.translate(
            offset: Offset(0, verticalOffset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No activity, yet...',
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                SizedBox(
                  width: 188,
                  child: Text(
                    'How about running your first ZEC tx?',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Image.asset(
                  'assets/illustrations/home_rest_character.png',
                  width: illustrationWidth,
                  height: illustrationHeight,
                  fit: BoxFit.contain,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    return Container(
      width: 396,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? colors.surface.card : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Recent activity',
                style: _homeLabelMSemiBold.copyWith(color: colors.text.accent),
              ),
              const Spacer(),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Row(
                    key: const ValueKey('home_preview_activity_see_all_button'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'See all',
                        style: _homeLabelMRegular.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      AppIcon(
                        AppIcons.chevronForward,
                        size: 16,
                        color: colors.icon.regular,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const _ActivityRow(
            icon: AppIcons.loader,
            title: 'Receiving ...',
            subtitleIcon: AppIcons.shieldKeyholeOutline,
            subtitle: 'Shielded',
            amount: '+31.10 ZEC',
            positive: true,
            animated: false,
          ),
          const SizedBox(height: AppSpacing.xxs),
          const _ActivityRow(
            icon: AppIcons.swapArrows,
            title: 'Swapping ...',
            subtitleIcon: AppIcons.shieldKeyholeOutline,
            subtitle: 'Shielded',
            amount: '+31.10 ZEC',
            progress: true,
          ),
          const SizedBox(height: AppSpacing.xxs),
          const _ActivityRow(
            icon: AppIcons.arrowDownCircle,
            title: 'Received',
            subtitleIcon: AppIcons.shieldKeyholeOutline,
            subtitle: 'Shielded',
            amount: '+31.10 ZEC',
            positive: true,
            highlighted: true,
          ),
          const SizedBox(height: AppSpacing.xxs),
          const _ActivityRow(
            icon: AppIcons.plane,
            title: 'Sent',
            subtitleIcon: AppIcons.transparentBalance,
            subtitle: 'Transparent',
            amount: '-14.123 ZEC',
            focused: true,
          ),
          const SizedBox(height: AppSpacing.xxs),
          const _ActivityRow(
            icon: AppIcons.arrowDownCircle,
            title: 'Received',
            subtitleIcon: AppIcons.shieldKeyholeOutline,
            subtitle: 'Shielded',
            amount: '+31.10 ZEC',
            positive: true,
          ),
        ],
      ),
    );
  }
}

class _ActivityGlyph extends StatelessWidget {
  const _ActivityGlyph({required this.icon, required this.animated});

  final String icon;
  final bool animated;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: AppIcon(
          icon,
          size: 16,
          color: colors.icon.regular,
          animated: animated,
        ),
      ),
    );
  }
}

class _SwappingActivityIcon extends StatelessWidget {
  const _SwappingActivityIcon();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 32,
      height: 32,
      child: OverflowBox(
        maxWidth: 37,
        maxHeight: 37,
        child: SizedBox(
          width: 37,
          height: 37,
          child: CustomPaint(
            painter: _SwappingRingPainter(
              trackColor: const Color(0xFFD4D4D4),
              progressColor: const Color(0xFFC2546A),
              innerFillColor: const Color(0x339A9A9A),
              progress: 0.5,
            ),
            child: Center(
              child: AppIcon(
                AppIcons.swapArrows,
                size: 16,
                color: colors.icon.regular,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwappingRingPainter extends CustomPainter {
  const _SwappingRingPainter({
    required this.trackColor,
    required this.progressColor,
    required this.innerFillColor,
    required this.progress,
  });

  final Color trackColor;
  final Color progressColor;
  final Color innerFillColor;
  final double progress;

  static const _segmentCount = 4;
  static const _viewBoxSize = 37.0;
  static const _center = Offset(18.1836, 18.1842);
  static const _ringRadius = 17.0;
  static const _ringStrokeWidth = 2.5;
  static const _segmentGapAngle = 0.32;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _viewBoxSize, size.height / _viewBoxSize);
    _paintProgressRing(canvas);
    _paintInnerCircle(canvas);
    canvas.restore();
  }

  void _paintProgressRing(Canvas canvas) {
    final trackPaint =
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ringStrokeWidth
          ..strokeCap = StrokeCap.round;
    final progressPaint =
        Paint()
          ..color = progressColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _ringStrokeWidth
          ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: _center, radius: _ringRadius);
    const segmentStep = math.pi * 2 / _segmentCount;
    const segmentSweep = segmentStep - _segmentGapAngle;
    const firstStartAngle = -math.pi + (_segmentGapAngle / 2);
    final normalizedProgress = progress.clamp(0.0, 1.0);
    final filledSegments =
        normalizedProgress <= 0
            ? 0
            : math.max(
              1,
              math.min(
                _segmentCount,
                (normalizedProgress * _segmentCount).ceil(),
              ),
            );

    for (var index = 0; index < _segmentCount; index++) {
      final startAngle = firstStartAngle + (segmentStep * index);
      canvas.drawArc(rect, startAngle, segmentSweep, false, trackPaint);
    }
    for (var index = 0; index < filledSegments; index++) {
      final startAngle = firstStartAngle + (segmentStep * index);
      canvas.drawArc(rect, startAngle, segmentSweep, false, progressPaint);
    }
  }

  void _paintInnerCircle(Canvas canvas) {
    final fillPaint =
        Paint()
          ..color = innerFillColor
          ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(18.1836, 18.1841), 13, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _SwappingRingPainter oldDelegate) {
    return oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.innerFillColor != innerFillColor ||
        oldDelegate.progress != progress;
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.title,
    required this.subtitleIcon,
    required this.subtitle,
    required this.amount,
    this.positive = false,
    this.highlighted = false,
    this.focused = false,
    this.animated = true,
    this.progress = false,
  });

  final String icon;
  final String title;
  final String subtitleIcon;
  final String subtitle;
  final String amount;
  final bool positive;
  final bool highlighted;
  final bool focused;
  final bool animated;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _HomePreviewInteractiveTarget(
      semanticsLabel: title,
      onTap: () {},
      builder: (context, hovered, focusedByKeyboard) {
        final showHover = highlighted || hovered;
        final showFocus = focused || focusedByKeyboard;
        return SizedBox(
          key: ValueKey(
            'home_preview_activity_row_${title}_${subtitle}_'
            '${amount}_${highlighted}_$focused',
          ),
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                decoration: BoxDecoration(
                  color:
                      showHover
                          ? colors.state.hoverOpacity
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
                child: Row(
                  children: [
                    progress
                        ? const _SwappingActivityIcon()
                        : _ActivityGlyph(icon: icon, animated: animated),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _homeLabelMMedium.copyWith(
                              color: colors.text.accent,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Row(
                            children: [
                              AppIcon(
                                subtitleIcon,
                                size: 16,
                                color: colors.text.brandCrimson,
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                              Flexible(
                                child: Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _homeLabelMRegular.copyWith(
                                    color: colors.text.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          amount,
                          style: _homeLabelMSemiBold.copyWith(
                            color:
                                positive
                                    ? _positiveStrongColor(context)
                                    : colors.text.primary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'May 29, 13:40',
                          style: _homeLabelSRegular.copyWith(
                            color: colors.text.muted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showFocus)
                Positioned(
                  left: -2,
                  top: -2,
                  right: -2,
                  bottom: -2,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: colors.state.focusRing,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
