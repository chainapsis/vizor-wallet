import 'dart:async';

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
  bool _isSigningOut = false;
  bool _isCopyingAddress = false;

  String get _matchedLocation => GoRouterState.of(context).matchedLocation;

  bool _matches(String routePath) =>
      _matchedLocation == routePath ||
      _matchedLocation.startsWith('$routePath/');

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
    _navigateTo('/accounts');
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
    final balanceText =
        '${ZecAmount.fromZatoshi(accountSync.totalBalance).balance.amountText} '
        '$kZcashDefaultCurrencyTicker';
    final balanceLabel = hideAmountIfPrivacyMode(
      balanceText,
      privacyModeEnabled: ref.watch(privacyModeProvider),
    );
    final swapFeatureEnabled = ref.watch(swapFeatureEnabledProvider);
    final accountsActive = _matches('/accounts');

    return AppDesktopSidebarSurface(
      glass: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 640;
          final topPadding = compact ? AppSpacing.s : 40.0;
          final primaryVerticalPadding = compact ? 0.0 : AppSpacing.xs;
          final headerNavGap = compact ? AppSpacing.xs : AppSpacing.md;
          final bottomPadding = compact ? AppSpacing.xs : AppSpacing.md;
          final bottomSyncGap = compact ? AppSpacing.xs : AppSpacing.md;

          return Padding(
            padding: EdgeInsets.only(
              top: topPadding,
              left: AppSpacing.xs,
              right: AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: primaryVerticalPadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SidebarAccountHeader(
                            key: const ValueKey('sidebar_accounts_button'),
                            accountName: accountName,
                            profilePictureId:
                                activeAccount?.profilePictureId ??
                                kDefaultProfilePictureId,
                            balanceLabel: balanceLabel,
                            onCopyAddress:
                                activeAccountUuid == null || _isCopyingAddress
                                ? null
                                : () => unawaited(_copyShieldedAddress()),
                            onTap: accountsActive ? null : _openAccounts,
                          ),
                          SizedBox(height: headerNavGap),
                          AppSidebarItem(
                            key: const ValueKey('sidebar_wallet_button'),
                            label: 'Wallet',
                            iconName: AppIcons.wallet,
                            active: _matches('/home'),
                            inactiveOpacity: 0.5,
                            onTap: _matches('/home')
                                ? null
                                : () => _navigateTo('/home'),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          AppSidebarItem(
                            key: const ValueKey('sidebar_send_button'),
                            label: 'Send',
                            iconName: AppIcons.plane,
                            active: _matches('/send'),
                            inactiveOpacity: 0.5,
                            onTap: _matches('/send')
                                ? null
                                : () => _navigateTo('/send'),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          AppSidebarItem(
                            key: const ValueKey('sidebar_receive_button'),
                            label: 'Receive',
                            iconName: AppIcons.arrowDownCircle,
                            active: _matches('/receive'),
                            inactiveOpacity: 0.5,
                            onTap: _matches('/receive')
                                ? null
                                : () => _navigateTo('/receive'),
                          ),
                          if (swapFeatureEnabled) ...[
                            const SizedBox(height: AppSpacing.xs),
                            AppSidebarItem(
                              key: const ValueKey('sidebar_swap_button'),
                              label: 'Swap',
                              iconName: AppIcons.swapArrows,
                              active: _matches('/swap'),
                              inactiveOpacity: 0.5,
                              onTap: _matches('/swap')
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
                            inactiveOpacity: 0.5,
                            onTap: () => _navigateTo('/voting'),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          AppSidebarItem(
                            key: const ValueKey('sidebar_address_book_button'),
                            label: 'Address book',
                            iconName: AppIcons.users,
                            active: _matches('/address-book'),
                            inactiveOpacity: 0.5,
                            onTap: _matches('/address-book')
                                ? null
                                : () => _navigateTo('/address-book'),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          AppSidebarItem(
                            key: const ValueKey('sidebar_activity_button'),
                            label: 'Activity',
                            iconName: AppIcons.history,
                            active: _matches('/activity'),
                            inactiveOpacity: 0.5,
                            onTap: _matches('/activity')
                                ? null
                                : () => _navigateTo('/activity'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    left: AppSpacing.xs,
                    right: AppSpacing.xs,
                    top: AppSpacing.xs,
                    bottom: bottomPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppSidebarItem(
                        label: 'Settings',
                        iconName: AppIcons.cog,
                        active: _matches('/settings'),
                        onTap: _matches('/settings')
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
            ),
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
    this.onCopyAddress,
    this.onTap,
    super.key,
  });

  final String accountName;
  final String profilePictureId;
  final String balanceLabel;
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
            _SidebarAccountAvatar(profilePictureId: profilePictureId),
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
                  Text(
                    balanceLabel,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary,
                    ),
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
  const _SidebarAccountAvatar({required this.profilePictureId});

  final String profilePictureId;

  @override
  Widget build(BuildContext context) {
    return AppProfilePicture(
      profilePictureId: profilePictureId,
      size: AppProfilePictureSize.navLarge,
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
