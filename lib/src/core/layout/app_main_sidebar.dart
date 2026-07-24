import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../main.dart' show log;
import '../../providers/account_provider.dart';
import '../../providers/app_security_provider.dart';
import '../../providers/privacy_mode_provider.dart';
import '../../providers/receive_address_provider.dart';
import '../../providers/sync_provider.dart';
import '../../providers/voting/voting_rounds_provider.dart';
import '../../providers/voting/voting_submission_guard_provider.dart';
import '../../rust/api/sync.dart' as rust_sync;
import '../../features/migration/providers/ironwood_migration_announcement_provider.dart';
import '../../features/migration/providers/ironwood_migration_coordinator_provider.dart';
import '../config/network_config.dart';
import '../config/swap_feature_config.dart';
import '../formatting/zec_amount.dart';
import '../privacy/privacy_mask.dart';
import '../profile_pictures.dart';
import '../formatting/sync_status_label.dart';
import '../theme/app_theme.dart';
import '../widgets/app_copy_feedback.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_profile_picture.dart';
import '../widgets/app_tappable.dart';
import '../widgets/app_toast.dart';
import 'app_desktop_shell.dart';
import 'desktop_sidebar_spacing.dart';

class AppMainSidebar extends ConsumerStatefulWidget {
  const AppMainSidebar({this.disabledRoutePaths = const {}, super.key});

  final Set<String> disabledRoutePaths;

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

  bool get _homeShouldBeActive =>
      _isHomeRoute ||
      _matches('/send') ||
      _matches('/receive') ||
      _matches('/migration');

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
    if (widget.disabledRoutePaths.contains(routePath)) return;
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

  void _openActivity() {
    if (_matchedLocation == '/activity') return;
    context.go('/activity');
  }

  void _openSettings() {
    if (_matchedLocation == '/settings') return;
    context.go('/settings');
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
      builder: (_) => AppTheme(
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
                onCopyAccountAddress: (account) =>
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
    final activeAccountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid;
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

      if (!mounted) return;
      copyTextWithToast(context, text: address, toastMessage: 'Address copied');
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

      if (!mounted) return;
      copyTextWithToast(
        context,
        text: address,
        toastMessage: 'Shielded address copied',
      );
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
    final ironwoodHomeMigrationPresentation = ref.watch(
      ironwoodHomeMigrationPresentationProvider,
    );
    final ironwoodPostMigrationState = ref
        .watch(ironwoodPostMigrationStateProvider)
        .value;
    final ironwoodMigrationNavigationLocked =
        ironwoodPostMigrationState?.locksNavigation ??
        (ironwoodHomeMigrationPresentation.mode ==
            IronwoodHomeMigrationCtaMode.start);
    final migrationCoordinator = ref.watch(
      ironwoodMigrationCoordinatorProvider,
    );
    final migrationStatus = activeAccountUuid == null
        ? null
        : migrationCoordinator.statuses[activeAccountUuid];

    return AppDesktopSidebarSurface(
      glass: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 640;
          final topPadding = mainSidebarTopPadding(compact: compact);
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
                        onTogglePrivacyMode: () =>
                            ref.read(privacyModeProvider.notifier).toggle(),
                        onCopyAddress:
                            activeAccountUuid == null || _isCopyingAddress
                            ? null
                            : () => unawaited(_copyShieldedAddress()),
                        onTap: accounts.isEmpty
                            ? null
                            : () => _toggleAccountMenu(
                                accounts: accounts,
                                activeAccountUuid: activeAccountUuid,
                              ),
                      ),
                    ),
                    SizedBox(height: headerNavGap),
                    if (migrationStatus?.activeRunId != null &&
                        migrationStatus?.phase !=
                            kIronwoodMigrationWaitingDenomConfirmationsPhase)
                      _SidebarMigrationHomeSection(
                        status: migrationStatus!,
                        isHardware: activeAccount?.isHardware ?? false,
                        orchardBalance:
                            accountSync.orchardBalance +
                            accountSync.orchardPendingBalance,
                        ironwoodBalance:
                            accountSync.ironwoodBalance +
                            accountSync.ironwoodPendingBalance,
                        privacyModeEnabled: privacyModeEnabled,
                        active: _homeShouldBeActive,
                        onHome: () => _navigateTo('/home'),
                        onMigration: () =>
                            _navigateTo('/migration/private/status'),
                      )
                    else
                      AppSidebarItem(
                        key: const ValueKey('sidebar_home_button'),
                        label: isImporting ? 'Importing...' : 'Home',
                        iconName: isImporting ? AppIcons.loader : AppIcons.home,
                        iconAnimated: !isImporting,
                        active: _homeShouldBeActive,
                        onTap: isImporting ? null : () => _navigateTo('/home'),
                      ),
                    if (swapFeatureEnabled) ...[
                      const SizedBox(height: AppSpacing.xs),
                      AppSidebarItem(
                        key: const ValueKey('sidebar_swap_button'),
                        label: 'Swap',
                        iconName: AppIcons.swapArrows,
                        active: _matches('/swap'),
                        onTap:
                            isImporting ||
                                widget.disabledRoutePaths.contains('/swap') ||
                                ironwoodMigrationNavigationLocked
                            ? null
                            : () => _navigateTo('/swap'),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    AppSidebarItem(
                      key: const ValueKey('sidebar_voting_button'),
                      label: 'Vote',
                      iconName: AppIcons.scroll,
                      active: _matches('/voting'),
                      // Stays tappable while active: _navigateTo requests a
                      // poll-list refresh when re-tapped on /voting.
                      onTap:
                          isImporting ||
                              widget.disabledRoutePaths.contains('/voting') ||
                              ironwoodMigrationNavigationLocked
                          ? null
                          : () => _navigateTo('/voting'),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppSidebarItem(
                      key: const ValueKey('sidebar_activity_button'),
                      label: 'Activity',
                      iconName: AppIcons.history,
                      active: _matches('/activity'),
                      // Stays tappable on detail subroutes (tx/swap status)
                      // as a way back to the main activity feed.
                      onTap: isImporting ? null : _openActivity,
                    ),
                    const Spacer(),
                    AppSidebarItem(
                      label: 'Settings',
                      iconName: AppIcons.cog,
                      active: _matches('/settings'),
                      onTap: _openSettings,
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

class _SidebarMigrationHomeSection extends StatelessWidget {
  const _SidebarMigrationHomeSection({
    required this.status,
    required this.isHardware,
    required this.orchardBalance,
    required this.ironwoodBalance,
    required this.privacyModeEnabled,
    required this.active,
    required this.onHome,
    required this.onMigration,
  });

  final rust_sync.MigrationStatus status;
  final bool isHardware;
  final BigInt orchardBalance;
  final BigInt ironwoodBalance;
  final bool privacyModeEnabled;
  final bool active;
  final VoidCallback onHome;
  final VoidCallback onMigration;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final needsInput = isHardware && status.phase == 'ready_to_migrate';
    final orchardLabel = hideAmountIfPrivacyMode(
      '${ZecAmount.fromZatoshi(orchardBalance).balance.amountText} ZEC',
      privacyModeEnabled: privacyModeEnabled,
    );
    final ironwoodLabel = hideAmountIfPrivacyMode(
      '${ZecAmount.fromZatoshi(ironwoodBalance).balance.amountText} ZEC',
      privacyModeEnabled: privacyModeEnabled,
    );

    return SizedBox(
      height: 120,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: AppSidebarItem(
              key: ValueKey('sidebar_orchard_home_row'),
              label: 'Home',
              iconName: AppIcons.home,
              onTap: onHome,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    orchardLabel,
                    key: ValueKey('sidebar_orchard_balance'),
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary.withValues(alpha: 0.5),
                    ),
                  ),
                  SizedBox(width: AppSpacing.xxs),
                  AppIcon(
                    AppIcons.lock,
                    size: 16,
                    color: colors.icon.regular.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: _SidebarMigrationGlow.left,
            top: _SidebarMigrationGlow.top,
            child: _SidebarMigrationGlow(),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 40,
            child: AppSidebarItem(
              key: ValueKey('sidebar_migration_progress_button'),
              label: needsInput ? 'Needs input' : 'Migrating...',
              leading: SizedBox(
                width: _SidebarMigrationGlow.visualWidth,
                height: _SidebarMigrationGlow.visualHeight,
              ),
              leadingGap: AppSpacing.sm,
              inactiveOpacity: 0.64,
              onTap: onMigration,
              trailing: AppIcon(
                needsInput ? AppIcons.warning : AppIcons.loader,
                size: 20,
                color: needsInput ? colors.icon.warning : colors.icon.regular,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 80,
            child: AppSidebarItem(
              key: ValueKey('sidebar_home_button'),
              label: 'Ironwood',
              iconName: AppIcons.home,
              active: active,
              onTap: onHome,
              trailing: Text(
                ironwoodLabel,
                key: ValueKey('sidebar_ironwood_balance'),
                style: AppTypography.labelLarge.copyWith(
                  color: active
                      ? colors.navPanel.activeLabel.withValues(alpha: 0.8)
                      : colors.text.secondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarMigrationGlow extends StatefulWidget {
  const _SidebarMigrationGlow();

  static const visualWidth = 20.0;
  static const visualHeight = 32.0;
  static const left = 14.0;
  static const top = 6.0;
  static const _outerWidth = 24.0;
  static const _outerHeight = 108.0;
  static const _innerWidth = 14.0;
  static const _innerHeight = 92.0;
  static const _radius = 13.0;
  static const _midAlpha = 0.15;
  static const _glowColor = Color(0xFF00A460);
  static const _flowBandHeight = 34.0;
  static const _flowPeriod = Duration(milliseconds: 1800);

  @override
  State<_SidebarMigrationGlow> createState() => _SidebarMigrationGlowState();
}

class _SidebarMigrationGlowState extends State<_SidebarMigrationGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _SidebarMigrationGlow._flowPeriod,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animate = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
    }

    return SizedBox(
      width: _SidebarMigrationGlow._outerWidth,
      height: _SidebarMigrationGlow._outerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          const _SidebarMigrationGlowPill(
            width: _SidebarMigrationGlow._outerWidth,
            height: _SidebarMigrationGlow._outerHeight,
          ),
          const _SidebarMigrationGlowPill(
            width: _SidebarMigrationGlow._innerWidth,
            height: _SidebarMigrationGlow._innerHeight,
          ),
          if (animate)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return _SidebarMigrationFlowHighlight(t: _controller.value);
              },
            ),
        ],
      ),
    );
  }
}

class _SidebarMigrationFlowHighlight extends StatelessWidget {
  const _SidebarMigrationFlowHighlight({required this.t});

  final double t;

  @override
  Widget build(BuildContext context) {
    final bandHeight = _SidebarMigrationGlow._flowBandHeight;
    final travel = _SidebarMigrationGlow._outerHeight + (bandHeight * 2);
    final y = -bandHeight + (travel * t);

    return ClipRRect(
      borderRadius: BorderRadius.circular(_SidebarMigrationGlow._radius),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00FFFFFF),
            Color(0xFFFFFFFF),
            Color(0xFFFFFFFF),
            Color(0x00FFFFFF),
          ],
          stops: [0, 0.22, 0.78, 1],
        ).createShader(bounds),
        child: SizedBox(
          width: _SidebarMigrationGlow._outerWidth,
          height: _SidebarMigrationGlow._outerHeight,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: y,
                child: const _SidebarMigrationFlowBand(
                  width: _SidebarMigrationGlow._outerWidth,
                  height: _SidebarMigrationGlow._flowBandHeight,
                  alpha: 0.13,
                ),
              ),
              Positioned(
                top: y + 5,
                child: const _SidebarMigrationFlowBand(
                  width: _SidebarMigrationGlow._innerWidth,
                  height: _SidebarMigrationGlow._flowBandHeight,
                  alpha: 0.26,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarMigrationFlowBand extends StatelessWidget {
  const _SidebarMigrationFlowBand({
    required this.width,
    required this.height,
    required this.alpha,
  });

  final double width;
  final double height;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_SidebarMigrationGlow._radius),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _SidebarMigrationGlow._glowColor.withValues(alpha: 0),
              _SidebarMigrationGlow._glowColor.withValues(alpha: alpha),
              _SidebarMigrationGlow._glowColor.withValues(alpha: alpha * 0.72),
              _SidebarMigrationGlow._glowColor.withValues(alpha: 0),
            ],
            stops: const [0, 0.42, 0.62, 1],
          ),
        ),
      ),
    );
  }
}

class _SidebarMigrationGlowPill extends StatelessWidget {
  const _SidebarMigrationGlowPill({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_SidebarMigrationGlow._radius),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _SidebarMigrationGlow._glowColor.withValues(alpha: 0),
              _SidebarMigrationGlow._glowColor.withValues(
                alpha: _SidebarMigrationGlow._midAlpha,
              ),
              _SidebarMigrationGlow._glowColor.withValues(alpha: 0),
            ],
            stops: const [0, 0.5, 1],
          ),
        ),
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
      height: 44,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          children: [
            _SidebarAccountAvatar(
              profilePictureId: profilePictureId,
              showsKeystone: showsKeystone,
            ),
            const SizedBox(width: AppSpacing.sm),
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
                            fontWeight: FontWeight.w400,
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
            size: AppProfilePictureSize.large,
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
                  // The ring sits OUTSIDE the 16px badge like the Figma
                  // stroke, leaving the full box to the 14px logo.
                  border: Border.all(
                    color: colors.background.ground,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
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
            height: 16,
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
            height: 16,
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
              // Figma's dropdown shadow stack (no stroke): 0/14/28 @ 8%,
              // 0/-6/12 @ 3%, 0/2/8 @ 6%.
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 12,
                  offset: Offset(0, -6),
                ),
                BoxShadow(
                  color: Color(0x0F000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
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
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.muted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  key: const ValueKey('sidebar_accounts_list'),
                  height: 153,
                  child: RawScrollbar(
                    key: const ValueKey('sidebar_accounts_scrollbar'),
                    controller: _scrollController,
                    thumbVisibility: showScrollbar,
                    radius: const Radius.circular(AppRadii.full),
                    thickness: 6,
                    mainAxisMargin: 6,
                    crossAxisMargin: 6,
                    thumbColor: colors.surface.scrollbarThumb,
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
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: AppSpacing.xxs),
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
                                  : () => widget.onCopyAccountAddress(account),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const _SidebarAccountsActionsDivider(),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      _SidebarPopoverHoverTarget(
                        onTap: widget.onManageAccounts,
                        builder: (context, hovered) => Container(
                          key: const ValueKey('sidebar_accounts_manage'),
                          width: 153,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: hovered
                                ? colors.button.secondary.bgHover
                                : colors.button.secondary.bg,
                            borderRadius: BorderRadius.circular(AppRadii.full),
                          ),
                          child: Text(
                            'Manage',
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.button.secondary.label,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      _SidebarPopoverHoverTarget(
                        onTap: widget.onAddAccount,
                        builder: (context, hovered) => Container(
                          key: const ValueKey('sidebar_accounts_add'),
                          width: 48,
                          height: 32,
                          decoration: BoxDecoration(
                            color: hovered
                                ? colors.button.primary.bgHover
                                : colors.button.primary.bg,
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
    return AppTappable(
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
                  style: AppTypography.labelLarge.copyWith(
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

/// Click target that also tracks hover, for the popover's pill buttons.
class _SidebarPopoverHoverTarget extends StatefulWidget {
  const _SidebarPopoverHoverTarget({
    required this.onTap,
    required this.builder,
  });

  final VoidCallback onTap;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_SidebarPopoverHoverTarget> createState() =>
      _SidebarPopoverHoverTargetState();
}

class _SidebarPopoverHoverTargetState
    extends State<_SidebarPopoverHoverTarget> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: widget.builder(context, _hovered),
        ),
      ),
    );
  }
}

/// Sidebar sync status row. While syncing (and reduced-motion is off) a slow
/// shimmer band sweeps the muted-green label up to the full synced green and a
/// breathing glow pulses the indicator bar, so the row reads as "actively
/// working". Synced / failed / reduced-motion render static.
///
/// The desktop color policy is preserved: the indicator stays the sync-success
/// green while syncing (only failed differs); only the motion + glow are
/// added. (The mobile top-nav has the same effect with its own colors; the
/// small shimmer/motion helpers are intentionally duplicated rather than
/// shared so the two surfaces ship as independent changes.)
class _SidebarSyncStatus extends StatefulWidget {
  const _SidebarSyncStatus({required this.sync});

  final SyncState sync;

  @override
  State<_SidebarSyncStatus> createState() => _SidebarSyncStatusState();
}

class _SidebarSyncStatusState extends State<_SidebarSyncStatus>
    with SingleTickerProviderStateMixin {
  static const _width = 176.0;
  static const _height = 32.0;
  static const _indicatorWidth = 5.0;
  static const _indicatorHeight = 32.0;
  static const _indicatorLeft = -AppSpacing.sm;
  static const _textLeft = AppSpacing.xs;

  AnimationController? _controller;

  AnimationController get _activeController {
    return _controller ??= AnimationController(
      vsync: this,
      duration: _SidebarSyncMotion.period,
    );
  }

  bool get _isSyncing =>
      SyncStatusLabel.from(widget.sync).kind == SyncStatusKind.syncing;

  bool get _shouldAnimate {
    if (!_isSyncing) {
      return false;
    }
    return !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _SidebarSyncStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_shouldAnimate) {
      if (!_activeController.isAnimating) {
        _activeController.repeat();
      }
    } else {
      final controller = _controller;
      if (controller != null) {
        controller
          ..stop()
          ..value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final status = SyncStatusLabel.from(widget.sync);
    final textColor = switch (status.kind) {
      SyncStatusKind.syncing => colors.sync.textSyncing,
      SyncStatusKind.failed => colors.sync.textError,
      SyncStatusKind.synced => colors.sync.text,
    };
    final indicatorColor = switch (status.kind) {
      SyncStatusKind.syncing => colors.text.muted,
      SyncStatusKind.failed => colors.sync.lightError,
      SyncStatusKind.synced => colors.sync.lightSuccess,
    };

    final Widget body = _shouldAnimate
        ? AnimatedBuilder(
            animation: _activeController,
            builder: (context, _) {
              final t = _activeController.value;
              return _row(
                indicatorColor: indicatorColor,
                glow: _SidebarSyncMotion.glowFor(t),
                text: _SidebarSyncShimmerLabel(
                  key: const ValueKey('sidebar_sync_text'),
                  label: status.label,
                  baseColor: textColor,
                  highlightColor: colors.sync.lightSuccess,
                  progress: t,
                ),
              );
            },
          )
        : _row(
            indicatorColor: indicatorColor,
            glow: _SidebarSyncMotion.staticGlow,
            text: Text(
              status.label,
              key: const ValueKey('sidebar_sync_text'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                color: textColor,
                fontWeight: FontWeight.w400,
              ),
            ),
          );

    return SizedBox(
      width: _width,
      height: _height,
      child: Semantics(label: status.semanticsLabel, child: body),
    );
  }

  Widget _row({
    required Color indicatorColor,
    required ({double blur, double alpha})? glow,
    required Widget text,
  }) {
    return Stack(
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
              boxShadow: glow == null
                  ? null
                  : [
                      BoxShadow(
                        color: indicatorColor.withValues(alpha: glow.alpha),
                        blurRadius: glow.blur,
                      ),
                    ],
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
          child: Align(alignment: Alignment.centerLeft, child: text),
        ),
      ],
    );
  }
}

/// Subtle/slow motion constants for the sidebar syncing affordance. One full
/// glow breath and one shimmer sweep per [period]. (Mirrors the mobile
/// top-nav values; duplicated to keep the two surfaces independent.)
abstract final class _SidebarSyncMotion {
  static const period = Duration(milliseconds: 1400);

  /// Half-width of the shimmer highlight band as a gradient-stop fraction.
  static const _bandHalf = 0.18;

  /// Indicator glow breathing range (shadow blur radius + alpha). Kept gentle
  /// so the syncing glow stays calm rather than vibrant.
  static const _minGlowBlur = 8.0;
  static const _maxGlowBlur = 13.0;
  static const _minGlowAlpha = 0.2;
  static const _maxGlowAlpha = 0.45;

  /// Static indicator glow used for synced, failed, and reduced-motion states.
  static const staticGlow = (blur: 12.0, alpha: 0.6);

  /// 0 to 1 to 0 once per [period].
  static double _breath(double t) => (1 - math.cos(2 * math.pi * t)) / 2;

  static ({double blur, double alpha}) glowFor(double t) {
    final e = _breath(t);
    return (
      blur: _lerp(_minGlowBlur, _maxGlowBlur, e),
      alpha: _lerp(_minGlowAlpha, _maxGlowAlpha, e),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// The sidebar sync label with a highlight band sweeping across it. A
/// [ShaderMask] (`srcIn`) replaces the glyph pixels with a horizontal
/// `base / highlight / base` gradient; sliding the gradient's mapping rect by
/// [progress] travels the band left to right. The band fully exits both edges
/// (pure [baseColor]) at the loop ends, so the repeat is seamless.
class _SidebarSyncShimmerLabel extends StatelessWidget {
  const _SidebarSyncShimmerLabel({
    required this.label,
    required this.baseColor,
    required this.highlightColor,
    required this.progress,
    super.key,
  });

  final String label;
  final Color baseColor;
  final Color highlightColor;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        final shift = (progress * 2 - 1) * bounds.width;
        final rect = Rect.fromLTWH(
          bounds.left + shift,
          bounds.top,
          bounds.width,
          bounds.height,
        );
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [baseColor, highlightColor, baseColor],
          stops: const [
            0.5 - _SidebarSyncMotion._bandHalf,
            0.5,
            0.5 + _SidebarSyncMotion._bandHalf,
          ],
          tileMode: TileMode.clamp,
        ).createShader(rect);
      },
      // Solid color so `srcIn` keeps the gradient over the full glyph.
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelLarge.copyWith(
          color: const Color(0xFFFFFFFF),
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
