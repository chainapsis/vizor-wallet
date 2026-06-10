import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../main.dart' show log;
import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/privacy_mode_provider.dart';
import '../../providers/receive_address_provider.dart';
import '../../providers/sync_failure.dart';
import '../../providers/sync_provider.dart';
import '../../providers/voting/voting_rounds_provider.dart';
import '../../providers/voting/voting_submission_guard_provider.dart';
import '../config/network_config.dart';
import '../config/swap_feature_config.dart';
import '../formatting/zec_amount.dart';
import '../privacy/privacy_mask.dart';
import '../profile_pictures.dart';
import '../theme/app_theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_profile_picture.dart';
import '../widgets/app_toast.dart';
import 'app_desktop_shell.dart';

class AppMainSidebar extends ConsumerStatefulWidget {
  const AppMainSidebar({super.key});

  @override
  ConsumerState<AppMainSidebar> createState() => _AppMainSidebarState();
}

class _AppMainSidebarState extends ConsumerState<AppMainSidebar> {
  final LayerLink _accountMenuLink = LayerLink();

  bool _isSigningOut = false;
  bool _isCopyingAddress = false;
  OverlayEntry? _accountMenuEntry;

  String get _matchedLocation => GoRouterState.of(context).matchedLocation;

  bool _matches(String routePath) =>
      _matchedLocation == routePath ||
      _matchedLocation.startsWith('$routePath/');

  bool get _isHomeRoute => _matches('/home');

  bool get _homeShouldBeActive => _isHomeRoute || _matches('/send');

  bool get _isAccountMenuOpen => _accountMenuEntry != null;

  @override
  void dispose() {
    _closeAccountMenu(rebuild: false);
    super.dispose();
  }

  bool _blockIfVotingSubmissionInProgress() {
    final guards = ref.read(votingSubmissionGuardProvider);
    if (guards.isEmpty) return false;
    showAppToast(context, guards.first.message);
    return true;
  }

  void _navigateTo(String routePath) {
    if (_matches(routePath)) {
      if (routePath == '/voting') {
        ref.read(votingPollListRefreshRequestProvider.notifier).request();
      }
      return;
    }
    context.go(routePath);
  }

  void _openAccounts() {
    _closeAccountMenu();
    _navigateTo('/accounts');
  }

  void _openAddAccount() {
    _closeAccountMenu();
    context.go('/add-account');
  }

  void _toggleAccountMenu({
    required List<AccountInfo> accounts,
    required String? activeAccountUuid,
  }) {
    if (_isAccountMenuOpen) {
      _closeAccountMenu();
    } else {
      _openAccountMenu(
        accounts: accounts,
        activeAccountUuid: activeAccountUuid,
      );
    }
  }

  void _openAccountMenu({
    required List<AccountInfo> accounts,
    required String? activeAccountUuid,
  }) {
    final overlay = Overlay.of(context);
    final appTheme = AppTheme.of(context);
    _accountMenuEntry = OverlayEntry(
      builder:
          (_) => AppTheme(
            data: appTheme,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('sidebar_accounts_popover_backdrop'),
                    behavior: HitTestBehavior.translucent,
                    onTap: _closeAccountMenu,
                  ),
                ),
                CompositedTransformFollower(
                  link: _accountMenuLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.topLeft,
                  followerAnchor: Alignment.topLeft,
                  offset: const Offset(0, 48),
                  child: _SidebarAccountsPopover(
                    accounts: accounts,
                    activeAccountUuid: activeAccountUuid,
                    onSelectAccount: (uuid) => unawaited(_switchAccount(uuid)),
                    onCopyAccountAddress:
                        (account) =>
                            unawaited(_copyShieldedAddressForAccount(account)),
                    onManageAccounts: _openAccounts,
                    onAddAccount: _openAddAccount,
                  ),
                ),
              ],
            ),
          ),
    );
    overlay.insert(_accountMenuEntry!);
    setState(() {});
  }

  void _closeAccountMenu({bool rebuild = true}) {
    final entry = _accountMenuEntry;
    if (entry == null) return;
    _accountMenuEntry = null;
    entry.remove();
    if (rebuild && mounted) setState(() {});
  }

  Future<void> _switchAccount(String uuid) async {
    final activeAccountUuid =
        ref.read(accountProvider).value?.activeAccountUuid;
    _closeAccountMenu();
    if (uuid == activeAccountUuid) return;

    final accountNotifier = ref.read(accountProvider.notifier);
    final syncNotifier = ref.read(syncProvider.notifier);
    await accountNotifier.switchAccount(uuid);
    if (mounted) {
      context.go('/home');
    }
    unawaited(_refreshAfterAccountSwitch(syncNotifier));
  }

  Future<void> _refreshAfterAccountSwitch(SyncNotifier syncNotifier) async {
    try {
      await syncNotifier.refreshAfterSend();
    } catch (e) {
      log('AppMainSidebar: refresh after account switch failed: $e');
    }
  }

  Future<void> _copyShieldedAddress() async {
    if (_isCopyingAddress) return;

    final accountState = ref.read(accountProvider).value;
    final accountUuid = accountState?.activeAccountUuid;
    if (accountUuid == null) {
      showAppToast(context, "Address couldn't be copied");
      return;
    }

    setState(() {
      _isCopyingAddress = true;
    });

    try {
      final address = await ref
          .read(receiveAddressServiceProvider)
          .loadShieldedAddress(
            accountUuid: accountUuid,
            currentShieldedAddress: accountState?.activeAddress,
          );
      if (!mounted) return;
      if (ref.read(accountProvider).value?.activeAccountUuid != accountUuid) {
        return;
      }
      if (address.trim().isEmpty) {
        showAppToast(context, "Address couldn't be copied");
        return;
      }

      await Clipboard.setData(ClipboardData(text: address));
      if (!mounted) return;
      showAppToast(context, 'Address copied');
    } catch (e) {
      log('AppMainSidebar: ERROR copying shielded address: $e');
      if (!mounted) return;
      showAppToast(context, "Address couldn't be copied");
    } finally {
      if (mounted) {
        setState(() {
          _isCopyingAddress = false;
        });
      }
    }
  }

  Future<void> _copyShieldedAddressForAccount(AccountInfo account) async {
    if (_isCopyingAddress) return;
    setState(() => _isCopyingAddress = true);

    try {
      final accountState = ref.read(accountProvider).value;
      final currentShieldedAddress =
          accountState?.activeAccountUuid == account.uuid
              ? accountState?.activeAddress
              : null;
      final address = await ref
          .read(receiveAddressServiceProvider)
          .loadShieldedAddress(
            accountUuid: account.uuid,
            currentShieldedAddress: currentShieldedAddress,
          );
      if (!mounted) return;
      if (address.trim().isEmpty) {
        showAppToast(context, "Address couldn't be copied");
        return;
      }

      await Clipboard.setData(ClipboardData(text: address));
      if (!mounted) return;
      showAppToast(context, 'Shielded address copied');
    } catch (e) {
      log('AppMainSidebar: ERROR copying account shielded address: $e');
      if (!mounted) return;
      showAppToast(context, "Address couldn't be copied");
    } finally {
      if (mounted) {
        setState(() => _isCopyingAddress = false);
      }
    }
  }

  Future<void> _handleSignOut() async {
    if (_isSigningOut) return;
    if (_blockIfVotingSubmissionInProgress()) return;
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
    final accountSync = sync.scopedToAccount(activeAccountUuid);
    final isImporting =
        activeAccountUuid != null &&
        !accountSync.hasAccountScopedData &&
        accountSync.failure == null;
    final balanceText =
        '${ZecAmount.fromZatoshi(accountSync.totalBalance).balance.amountText} '
        '$kZcashDefaultCurrencyTicker';
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final balanceLabel = hideAmountIfPrivacyMode(
      balanceText,
      privacyModeEnabled: privacyModeEnabled,
    );
    final swapFeatureEnabled = ref.watch(swapFeatureEnabledProvider);

    return AppDesktopSidebarSurface(
      glass: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 640;
          final topPadding = compact ? AppSpacing.s : 40.0;
          final headerNavGap = compact ? AppSpacing.xs : AppSpacing.md;
          final bottomPadding = compact ? AppSpacing.xs : AppSpacing.md;
          final bottomSyncGap = compact ? AppSpacing.xs : AppSpacing.md;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  top: topPadding,
                  left: AppSpacing.sm,
                  right: AppSpacing.sm,
                  bottom: bottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CompositedTransformTarget(
                      link: _accountMenuLink,
                      child: _SidebarAccountHeader(
                        key: const ValueKey('sidebar_accounts_button'),
                        accountName: accountName,
                        profilePictureId:
                            activeAccount?.profilePictureId ??
                            kDefaultProfilePictureId,
                        balanceLabel: balanceLabel,
                        showsKeystone: activeAccount?.isHardware ?? false,
                        privacyModeEnabled: privacyModeEnabled,
                        onTogglePrivacyMode:
                            () =>
                                ref.read(privacyModeProvider.notifier).toggle(),
                        onCopyAddress:
                            activeAccountUuid == null || _isCopyingAddress
                                ? null
                                : () => unawaited(_copyShieldedAddress()),
                        onTap:
                            accounts.isEmpty
                                ? null
                                : () => _toggleAccountMenu(
                                  accounts: accounts,
                                  activeAccountUuid: activeAccountUuid,
                                ),
                      ),
                    ),
                    SizedBox(height: headerNavGap),
                    AppSidebarItem(
                      key: const ValueKey('sidebar_home_button'),
                      label: isImporting ? 'Importing...' : 'Home',
                      iconName: isImporting ? AppIcons.loader : AppIcons.home,
                      iconAnimated: !isImporting,
                      active: _homeShouldBeActive,
                      inactiveOpacity: 0.5,
                      onTap:
                          isImporting || _isHomeRoute
                              ? null
                              : () => _navigateTo('/home'),
                    ),
                    if (swapFeatureEnabled) ...[
                      const SizedBox(height: AppSpacing.xs),
                      AppSidebarItem(
                        key: const ValueKey('sidebar_swap_button'),
                        label: 'Swap',
                        iconName: AppIcons.swapArrows,
                        active: _matches('/swap'),
                        inactiveOpacity: 0.5,
                        onTap:
                            isImporting || _matches('/swap')
                                ? null
                                : () => _navigateTo('/swap'),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    AppSidebarItem(
                      key: const ValueKey('sidebar_activity_button'),
                      label: 'Activity',
                      iconName: AppIcons.history,
                      active: _matches('/activity'),
                      inactiveOpacity: 0.5,
                      onTap:
                          isImporting || _matches('/activity')
                              ? null
                              : () => _navigateTo('/activity'),
                    ),
                    const Spacer(),
                    AppSidebarItem(
                      label: 'Settings',
                      iconName: AppIcons.cog,
                      active: _matches('/settings'),
                      onTap:
                          _matches('/settings')
                              ? null
                              : () => _navigateTo('/settings'),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppSidebarItem(
                      label: 'Sign out',
                      iconName: AppIcons.logOut,
                      onTap: _isSigningOut ? null : _handleSignOut,
                    ),
                    SizedBox(height: bottomSyncGap),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _SidebarSyncStatus(sync: sync),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SidebarAccountHeader extends StatelessWidget {
  const _SidebarAccountHeader({
    required this.accountName,
    required this.profilePictureId,
    required this.balanceLabel,
    required this.showsKeystone,
    required this.privacyModeEnabled,
    required this.onTogglePrivacyMode,
    this.onCopyAddress,
    this.onTap,
    super.key,
  });

  final String accountName;
  final String profilePictureId;
  final String balanceLabel;
  final bool showsKeystone;
  final bool privacyModeEnabled;
  final VoidCallback onTogglePrivacyMode;
  final VoidCallback? onCopyAddress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          children: [
            _SidebarAccountAvatar(
              profilePictureId: profilePictureId,
              showsKeystone: showsKeystone,
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          accountName,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      _SidebarCopyAddressButton(onTap: onCopyAddress),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text(
                          balanceLabel,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      _SidebarHideBalanceButton(
                        enabled: true,
                        privacyModeEnabled: privacyModeEnabled,
                        onTap: onTogglePrivacyMode,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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

class _SidebarAccountAvatar extends StatelessWidget {
  const _SidebarAccountAvatar({
    required this.profilePictureId,
    required this.showsKeystone,
  });

  final String profilePictureId;
  final bool showsKeystone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AppProfilePicture(
            profilePictureId: profilePictureId,
            size: AppProfilePictureSize.navLarge,
          ),
          if (showsKeystone)
            Positioned(
              right: -5,
              bottom: 0,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: colors.background.inverse,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.background.ground, width: 2),
                ),
                child: Center(
                  child: AppIcon(
                    AppIcons.keystone,
                    size: 14,
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

class _SidebarHideBalanceButton extends StatelessWidget {
  const _SidebarHideBalanceButton({
    required this.enabled,
    required this.privacyModeEnabled,
    required this.onTap,
  });

  final bool enabled;
  final bool privacyModeEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: enabled,
      label: privacyModeEnabled ? 'Show balance' : 'Hide balance',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 16,
            height: 18,
            child: Center(
              child: AppIcon(
                privacyModeEnabled ? AppIcons.eyeClosed : AppIcons.eye,
                size: 16,
                color: colors.icon.regular.withValues(
                  alpha: enabled ? 0.72 : 0.38,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarCopyAddressButton extends StatelessWidget {
  const _SidebarCopyAddressButton({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    final iconColor = colors.icon.regular.withValues(
      alpha: enabled ? 0.72 : 0.38,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Copy shielded address',
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 16,
            height: 18,
            child: Center(
              child: AppIcon(AppIcons.copy, size: 16, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarAccountsPopover extends StatefulWidget {
  const _SidebarAccountsPopover({
    required this.accounts,
    required this.activeAccountUuid,
    required this.onSelectAccount,
    required this.onCopyAccountAddress,
    required this.onManageAccounts,
    required this.onAddAccount,
  });

  final List<AccountInfo> accounts;
  final String? activeAccountUuid;
  final ValueChanged<String> onSelectAccount;
  final ValueChanged<AccountInfo> onCopyAccountAddress;
  final VoidCallback onManageAccounts;
  final VoidCallback onAddAccount;

  @override
  State<_SidebarAccountsPopover> createState() =>
      _SidebarAccountsPopoverState();
}

class _SidebarAccountsPopoverState extends State<_SidebarAccountsPopover> {
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
    final showScrollbar = widget.accounts.length > 3;
    return DefaultTextStyle.merge(
      style: const TextStyle(decoration: TextDecoration.none),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 17.5, sigmaY: 17.5),
          child: Container(
            key: const ValueKey('sidebar_accounts_popover'),
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
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.muted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  key: const ValueKey('sidebar_accounts_list'),
                  height: 161,
                  child: RawScrollbar(
                    key: const ValueKey('sidebar_accounts_scrollbar'),
                    controller: _scrollController,
                    thumbVisibility: showScrollbar,
                    radius: const Radius.circular(AppRadii.full),
                    thickness: 6,
                    mainAxisMargin: 6,
                    crossAxisMargin: 6,
                    thumbColor: colors.background.neutralStrongOpacity,
                    child: Padding(
                      key: const ValueKey('sidebar_accounts_list_gutter'),
                      padding: const EdgeInsets.only(right: 18),
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(
                          context,
                        ).copyWith(scrollbars: false),
                        child: ListView.separated(
                          controller: _scrollController,
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          itemCount: widget.accounts.length,
                          separatorBuilder:
                              (_, _) => const SizedBox(height: AppSpacing.xxs),
                          itemBuilder: (context, index) {
                            final account = widget.accounts[index];
                            return _SidebarAccountPopoverRow(
                              key: ValueKey(
                                'sidebar_account_popover_row_${account.uuid}',
                              ),
                              account: account,
                              selected:
                                  account.uuid == widget.activeAccountUuid,
                              onTap: () => widget.onSelectAccount(account.uuid),
                              onCopyAddress:
                                  account.uuid == widget.activeAccountUuid
                                      ? null
                                      : () =>
                                          widget.onCopyAccountAddress(account),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const _SidebarAccountsActionsDivider(),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      _SidebarPopoverClickTarget(
                        onTap: widget.onManageAccounts,
                        child: Container(
                          key: const ValueKey('sidebar_accounts_manage'),
                          width: 153,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.button.secondary.bg,
                            borderRadius: BorderRadius.circular(AppRadii.full),
                          ),
                          child: Text(
                            'Manage',
                            style: AppTypography.labelMedium.copyWith(
                              color: colors.button.secondary.label,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      _SidebarPopoverClickTarget(
                        onTap: widget.onAddAccount,
                        child: Container(
                          key: const ValueKey('sidebar_accounts_add'),
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
          ),
        ),
      ),
    );
  }
}

class _SidebarAccountsActionsDivider extends StatelessWidget {
  const _SidebarAccountsActionsDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('sidebar_accounts_actions_divider'),
      height: 1,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(color: context.colors.border.subtle),
      ),
    );
  }
}

class _SidebarAccountPopoverRow extends StatelessWidget {
  const _SidebarAccountPopoverRow({
    super.key,
    required this.account,
    required this.selected,
    required this.onTap,
    this.onCopyAddress,
  });

  final AccountInfo account;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onCopyAddress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _SidebarPopoverClickTarget(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: selected ? colors.state.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.small),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Row(
            children: [
              _SidebarAccountAvatar(
                profilePictureId: account.profilePictureId,
                showsKeystone: account.isHardware,
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
              if (onCopyAddress != null)
                _SidebarCopyAddressButton(onTap: onCopyAddress)
              else if (selected)
                AppIcon(AppIcons.check, size: 16, color: colors.icon.regular),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarPopoverClickTarget extends StatelessWidget {
  const _SidebarPopoverClickTarget({required this.onTap, required this.child});

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

class _SidebarSyncStatus extends StatelessWidget {
  const _SidebarSyncStatus({required this.sync});

  final SyncState sync;

  static const _width = 176.0;
  static const _height = 34.0;
  static const _indicatorWidth = 5.0;
  static const _indicatorHeight = 32.0;
  static const _indicatorLeft = -AppSpacing.sm;
  static const _textLeft = AppSpacing.xs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
      width: _width,
      height: _height,
      child: Semantics(
        label: status.semanticsLabel,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _indicatorLeft,
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
        label: 'Syncing failed. $reason...',
        semanticsLabel: 'Syncing failed. $reason',
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
