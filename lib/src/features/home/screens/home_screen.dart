import 'dart:async';

import 'package:flutter/material.dart'
    show CircularProgressIndicator, Scrollbar;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../app_bootstrap.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;
import '../../activity/activity_row_mapper.dart';
import '../../activity/models/activity_row_data.dart';
import '../../activity/screens/activity_transaction_status_screen.dart';
import '../../activity/widgets/activity_table.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _canBackgroundSync = false;
  bool _isShieldingBalance = false;
  String? _shieldBalanceError;

  @override
  void initState() {
    super.initState();
    _checkBackgroundSyncAvailability();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
    });
  }

  Future<void> _checkBackgroundSyncAvailability() async {
    final available = await SyncNotifier.isBackgroundSyncAvailable();
    log('[zcash] BackgroundSync available: $available');
    if (mounted) {
      setState(() {
        _canBackgroundSync = available;
      });
    }
  }

  String _formatZec(BigInt zatoshi) {
    return ZecAmount.fromZatoshi(zatoshi).balance.amountText;
  }

  void _dismissShieldBalanceError() {
    setState(() {
      _shieldBalanceError = null;
    });
  }

  Future<void> _shieldTransparentBalance() async {
    if (_isShieldingBalance) return;

    setState(() {
      _isShieldingBalance = true;
      _shieldBalanceError = null;
    });

    try {
      final wallet = ref.read(walletProvider).value;
      final accountUuid = wallet?.activeAccountUuid;
      if (accountUuid == null) {
        throw Exception('No active account.');
      }

      final accountNotifier = ref.read(accountProvider.notifier);
      if (accountNotifier.isHardwareAccount(accountUuid)) {
        throw Exception(
          'Shielding transparent balance is only available for software accounts.',
        );
      }

      final sync = ref.read(syncProvider).value ?? SyncState();
      if (!sync.canShieldTransparentBalance) {
        throw Exception(
          'Transparent balance is too small to shield after fees.',
        );
      }

      final mnemonic = await accountNotifier.getMnemonicForAccount(accountUuid);
      if (mnemonic == null) {
        throw Exception('Mnemonic not found for the active account.');
      }

      final seedBytes = await rust_wallet.deriveSeed(mnemonic: mnemonic);
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final result = await rust_sync.shieldTransparentBalance(
        dbPath: dbPath,
        lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        seed: seedBytes,
      );
      log(
        'HomeScreen: shielded transparent balance txids=${result.txids} '
        'fee=${result.feeZatoshi} shielded=${result.shieldedZatoshi}',
      );

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('HomeScreen: refreshAfterSend after shielding failed: $e');
      }
    } catch (e, st) {
      log('HomeScreen: shield transparent balance failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _shieldBalanceError = _friendlyShieldBalanceError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isShieldingBalance = false;
        });
      }
    }
  }

  String _friendlyShieldBalanceError(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();
    if (lower.contains('hardware')) {
      return 'Shield balance is only available for software accounts.';
    }
    if (lower.contains('mnemonic')) {
      return 'Mnemonic not found for the active account.';
    }
    if (lower.contains('sync')) {
      return 'Sync the wallet before shielding transparent balance.';
    }
    if (lower.contains('insufficient') ||
        lower.contains('threshold') ||
        lower.contains('too small') ||
        lower.contains('no transparent funds')) {
      return 'Transparent balance is too small to shield after fees.';
    }
    if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
      return 'Shield transaction could not be broadcast.';
    }
    return 'Shield balance failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    final bootstrap = ref.watch(appBootstrapProvider);
    final syncAsync = ref.watch(syncProvider);
    final sync = syncAsync.value ?? SyncState();
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final shieldedBalance =
        sync.saplingBalance +
        sync.orchardBalance +
        sync.saplingPendingBalance +
        sync.orchardPendingBalance;
    final transparentBalance =
        sync.transparentBalance + sync.transparentPendingBalance;
    final canShieldTransparentBalance = sync.canShieldTransparentBalance;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, 0, 0),
        child: SizedBox.expand(
          child: walletAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text(
                'Error: $err',
                style: AppTypography.bodyMedium.copyWith(
                  color: context.colors.text.warning,
                ),
              ),
            ),
            data: (_) => _HomePane(
              sync: sync,
              passwordRotationRecoveryFailed:
                  bootstrap.passwordRotationRecoveryFailed,
              canBackgroundSync: _canBackgroundSync,
              privacyModeEnabled: privacyModeEnabled,
              shieldedBalanceText: _formatZec(shieldedBalance),
              transparentBalanceText: _formatZec(transparentBalance),
              hasTransparentBalance: transparentBalance > BigInt.zero,
              canShieldBalance: canShieldTransparentBalance,
              isShieldingBalance: _isShieldingBalance,
              shieldBalanceError: _shieldBalanceError,
              onTogglePrivacyMode: () =>
                  ref.read(privacyModeProvider.notifier).toggle(),
              onShieldBalancePressed: () =>
                  unawaited(_shieldTransparentBalance()),
              onDismissShieldBalanceError: _dismissShieldBalanceError,
              onSyncInBackground: () =>
                  ref.read(syncProvider.notifier).enableBackgroundSync(),
              onStopBackgroundSync: () =>
                  ref.read(syncProvider.notifier).disableBackgroundSync(),
              onRetrySync: () => ref.read(syncProvider.notifier).startSync(),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomePane extends ConsumerStatefulWidget {
  const _HomePane({
    required this.sync,
    required this.passwordRotationRecoveryFailed,
    required this.canBackgroundSync,
    required this.privacyModeEnabled,
    required this.shieldedBalanceText,
    required this.transparentBalanceText,
    required this.hasTransparentBalance,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.shieldBalanceError,
    required this.onTogglePrivacyMode,
    required this.onShieldBalancePressed,
    required this.onDismissShieldBalanceError,
    required this.onSyncInBackground,
    required this.onStopBackgroundSync,
    required this.onRetrySync,
  });

  final SyncState sync;
  final bool passwordRotationRecoveryFailed;
  final bool canBackgroundSync;
  final bool privacyModeEnabled;
  final String shieldedBalanceText;
  final String transparentBalanceText;
  final bool hasTransparentBalance;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final String? shieldBalanceError;
  final VoidCallback onTogglePrivacyMode;
  final VoidCallback onShieldBalancePressed;
  final VoidCallback onDismissShieldBalanceError;
  final VoidCallback onSyncInBackground;
  final VoidCallback onStopBackgroundSync;
  final VoidCallback onRetrySync;

  @override
  ConsumerState<_HomePane> createState() => _HomePaneState();
}

class _HomePaneState extends ConsumerState<_HomePane> {
  final ScrollController _scrollController = ScrollController();
  bool _isHovered = false;
  bool _canScroll = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateCanScroll();
    });
  }

  @override
  void didUpdateWidget(covariant _HomePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateCanScroll();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _updateCanScroll() {
    if (!_scrollController.hasClients) return;
    final canScroll = _scrollController.position.maxScrollExtent > 0;
    if (canScroll == _canScroll) return;
    setState(() {
      _canScroll = canScroll;
    });
  }

  @override
  Widget build(BuildContext context) {
    final notice = _noticeData();
    final rows = _activityRows(context);
    final showHoverScrollbar = isDesktopLayoutPlatform;

    return LayoutBuilder(
      builder: (context, constraints) {
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _updateCanScroll();
            });
            return false;
          },
          child: MouseRegion(
            onEnter: (_) {
              if (!_isHovered) {
                setState(() {
                  _isHovered = true;
                });
              }
            },
            onExit: (_) {
              if (_isHovered) {
                setState(() {
                  _isHovered = false;
                });
              }
            },
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: showHoverScrollbar && _isHovered && _canScroll,
              child: SingleChildScrollView(
                controller: _scrollController,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: AppSpacing.sm),
                        _HomeBalanceCard(
                          shieldedBalanceText: widget.shieldedBalanceText,
                          transparentBalanceText: widget.transparentBalanceText,
                          hasTransparentBalance: widget.hasTransparentBalance,
                          canShieldBalance: widget.canShieldBalance,
                          isShieldingBalance: widget.isShieldingBalance,
                          privacyModeEnabled: widget.privacyModeEnabled,
                          onTogglePrivacyMode: widget.onTogglePrivacyMode,
                          onShieldBalancePressed: widget.onShieldBalancePressed,
                        ),
                        if (notice != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          _HomeNoticeCard(data: notice),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                          ),
                          child: ActivityTable(
                            rows: rows,
                            title: 'Recent Activity',
                            onTitleTap: () => context.push('/activity'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  _HomeNoticeData? _noticeData() {
    if (widget.passwordRotationRecoveryFailed) {
      return _HomeNoticeData(
        iconName: AppIcons.warning,
        message: "We couldn't verify the previous password change.",
        actionLabel: 'Settings',
        onTap: () => context.push('/settings'),
      );
    }
    if (widget.shieldBalanceError != null) {
      return _HomeNoticeData(
        iconName: AppIcons.warning,
        message: widget.shieldBalanceError!,
        actionLabel: 'Dismiss',
        onTap: widget.onDismissShieldBalanceError,
      );
    }
    if (widget.sync.error != null) {
      return _HomeNoticeData(
        iconName: AppIcons.warning,
        message: 'Sync error',
        actionLabel: 'Retry',
        onTap: widget.onRetrySync,
      );
    }
    if (widget.sync.isBackgroundMode) {
      return _HomeNoticeData(
        iconName: AppIcons.renew,
        message: 'Background sync is running.',
        actionLabel: 'Stop sync',
        onTap: widget.onStopBackgroundSync,
      );
    }
    if (widget.canBackgroundSync && widget.sync.isSyncing) {
      return _HomeNoticeData(
        iconName: AppIcons.loader,
        message: 'Continue syncing in the background.',
        actionLabel: 'Sync in background',
        onTap: widget.onSyncInBackground,
      );
    }
    return null;
  }

  List<ActivityRowData> _activityRows(BuildContext context) {
    return buildActivityRows(
      context: context,
      sync: widget.sync,
      transactions: widget.sync.recentTransactions.take(9),
      privacyModeEnabled: widget.privacyModeEnabled,
      onRetrySync: widget.onRetrySync,
      onTransactionTap: _openTransactionStatus,
    );
  }

  void _openTransactionStatus(rust_sync.TransactionInfo transaction) {
    unawaited(_pushTransactionStatus(transaction));
  }

  Future<void> _pushTransactionStatus(
    rust_sync.TransactionInfo transaction,
  ) async {
    final detail = await _loadTransactionDetail(transaction);
    if (!mounted) return;
    context.push(
      Uri(
        path: '/activity/tx/${transaction.txidHex}',
        queryParameters: {'kind': transaction.txKind},
      ).toString(),
      extra: ActivityTransactionStatusArgs(
        txidHex: transaction.txidHex,
        txKind: transaction.txKind,
        initialTransaction: transaction,
        initialDetail: detail,
      ),
    );
  }

  Future<rust_sync.TransactionDetail?> _loadTransactionDetail(
    rust_sync.TransactionInfo transaction,
  ) async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == null) return null;

    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      if (!mounted ||
          accountUuid != ref.read(accountProvider).value?.activeAccountUuid) {
        return null;
      }
      return rust_sync.getTransactionDetail(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
        txidHex: transaction.txidHex,
        txKind: transaction.txKind,
      );
    } catch (e, st) {
      log('HomeScreen: transaction detail load failed: $e\n$st');
      return null;
    }
  }
}

class _HomeBalanceCard extends StatefulWidget {
  const _HomeBalanceCard({
    required this.shieldedBalanceText,
    required this.transparentBalanceText,
    required this.hasTransparentBalance,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.privacyModeEnabled,
    required this.onTogglePrivacyMode,
    required this.onShieldBalancePressed,
  });

  final String shieldedBalanceText;
  final String transparentBalanceText;
  final bool hasTransparentBalance;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final bool privacyModeEnabled;
  final VoidCallback onTogglePrivacyMode;
  final VoidCallback onShieldBalancePressed;

  @override
  State<_HomeBalanceCard> createState() => _HomeBalanceCardState();
}

class _HomeBalanceCardState extends State<_HomeBalanceCard> {
  bool _isShieldBalanceHovered = false;

  static const _shieldedCardHeight = 216.0;
  static const _transparentStripHeight = 56.0;
  static const _shieldedCardBorderWidth = 1.5;
  static const _shieldedCardBorderColor = Color(0x12FFFFFF);
  static const _outerCardPadding = 2.0;
  static const _outerCardRadius = 18.0;
  static const _actionButtonMinWidth = 196.0;

  @override
  void didUpdateWidget(covariant _HomeBalanceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isShieldBalanceHovered &&
        (!widget.hasTransparentBalance ||
            !widget.canShieldBalance ||
            widget.isShieldingBalance)) {
      _isShieldBalanceHovered = false;
    }
  }

  void _handleShieldBalanceHoverChanged(bool hovered) {
    if (_isShieldBalanceHovered == hovered) return;
    setState(() {
      _isShieldBalanceHovered = hovered;
    });
  }

  BoxDecoration _homeCardDecoration({
    required AppColors colors,
    required BorderRadius borderRadius,
  }) {
    return BoxDecoration(
      color: colors.background.homeCard,
      borderRadius: borderRadius,
    );
  }

  BoxDecoration _shieldBalanceHoverDecoration(AppColors colors) {
    return BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(0.86, 0.80),
        radius: 1.45,
        colors: [
          colors.button.primary.bg,
          colors.button.primary.bg.withValues(alpha: 0),
        ],
        stops: const [0.19, 1.0],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayedShieldedBalance = hideIfPrivacyMode(
      '${widget.shieldedBalanceText} zec',
      privacyModeEnabled: widget.privacyModeEnabled,
      suffix: ' zec',
    );
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final targetStripHeight = widget.hasTransparentBalance
        ? _transparentStripHeight
        : 0.0;
    final isShieldBalanceHoverActive =
        widget.canShieldBalance &&
        !widget.isShieldingBalance &&
        _isShieldBalanceHovered;
    final shieldBalanceContentColor = isShieldBalanceHoverActive
        ? colors.button.primary.label
        : widget.canShieldBalance
        ? colors.text.homeCard
        : colors.text.secondary.withValues(alpha: 0.64);
    final shieldBalanceChevronColor = isShieldBalanceHoverActive
        ? colors.background.utilitySuccessStrong
        : shieldBalanceContentColor;
    final transparentStrip = widget.hasTransparentBalance
        ? _HomeTransparentBalanceStrip(
            key: const ValueKey('transparent-balance-strip'),
            balanceText: widget.transparentBalanceText,
            canShieldBalance: widget.canShieldBalance,
            isShieldingBalance: widget.isShieldingBalance,
            privacyModeEnabled: widget.privacyModeEnabled,
            shieldBalanceContentColor: shieldBalanceContentColor,
            shieldBalanceChevronColor: shieldBalanceChevronColor,
            onShieldBalancePressed: widget.onShieldBalancePressed,
            onShieldBalanceHoverChanged: _handleShieldBalanceHoverChanged,
          )
        : const SizedBox.shrink(key: ValueKey('transparent-balance-empty'));

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: targetStripHeight, end: targetStripHeight),
      builder: (context, stripHeight, _) {
        final cardHeight = _shieldedCardHeight + stripHeight;
        final revealProgress = (stripHeight / _transparentStripHeight).clamp(
          0.0,
          1.0,
        );
        final shieldedCardRadius = BorderRadius.circular(
          stripHeight > 0 ? AppRadii.medium : 0.0,
        );
        final shieldedCardBorderColor = Color.lerp(
          const Color(0x00FFFFFF),
          _shieldedCardBorderColor,
          revealProgress,
        )!;
        final outerCardBorderRadius = BorderRadius.circular(_outerCardRadius);
        final innerCardBorderRadius = BorderRadius.circular(
          _outerCardRadius - _outerCardPadding,
        );

        return ClipRRect(
          borderRadius: outerCardBorderRadius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            decoration: _homeCardDecoration(
              colors: colors,
              borderRadius: outerCardBorderRadius,
            ),
            child: Padding(
              padding: const EdgeInsets.all(_outerCardPadding),
              child: ClipRRect(
                borderRadius: innerCardBorderRadius,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  decoration: _homeCardDecoration(
                    colors: colors,
                    borderRadius: innerCardBorderRadius,
                  ),
                  child: SizedBox(
                    height: cardHeight,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOut,
                              opacity: isShieldBalanceHoverActive ? 1.0 : 0.0,
                              child: DecoratedBox(
                                decoration: _shieldBalanceHoverDecoration(
                                  colors,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          right: 0,
                          height: _shieldedCardHeight,
                          child: ClipRRect(
                            borderRadius: shieldedCardRadius,
                            child: DecoratedBox(
                              position: DecorationPosition.foreground,
                              decoration: BoxDecoration(
                                borderRadius: shieldedCardRadius,
                                border: Border.all(
                                  color: shieldedCardBorderColor,
                                  width: _shieldedCardBorderWidth,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.centerLeft,
                                                  end: Alignment.centerRight,
                                                  colors: isDark
                                                      ? [
                                                          colors
                                                              .background
                                                              .homeCard
                                                              .withValues(
                                                                alpha: 0.90,
                                                              ),
                                                          colors
                                                              .background
                                                              .homeCard
                                                              .withValues(
                                                                alpha: 0.82,
                                                              ),
                                                          colors
                                                              .background
                                                              .homeCard
                                                              .withValues(
                                                                alpha: 0.48,
                                                              ),
                                                          colors
                                                              .background
                                                              .homeCard
                                                              .withValues(
                                                                alpha: 0.00,
                                                              ),
                                                        ]
                                                      : [
                                                          colors
                                                              .background
                                                              .homeCard
                                                              .withValues(
                                                                alpha: 0.98,
                                                              ),
                                                          colors
                                                              .background
                                                              .homeCard
                                                              .withValues(
                                                                alpha: 0.95,
                                                              ),
                                                          colors
                                                              .background
                                                              .homeCard
                                                              .withValues(
                                                                alpha: 0.70,
                                                              ),
                                                          colors
                                                              .background
                                                              .homeCard
                                                              .withValues(
                                                                alpha: 0.00,
                                                              ),
                                                        ],
                                                  stops: const [
                                                    0.0,
                                                    0.28,
                                                    0.56,
                                                    0.86,
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned.fill(
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: Image.asset(
                                                isDark
                                                    ? 'assets/illustrations/home_balance_card_bg_dark.png'
                                                    : 'assets/illustrations/home_balance_card_bg_light.png',
                                                fit: BoxFit.cover,
                                                width: 604,
                                                height: _shieldedCardHeight,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.sm,
                                        AppSpacing.md,
                                        AppSpacing.sm,
                                        AppSpacing.md,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(
                                                  AppSpacing.xxs,
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    _HomeBalanceShieldIcon(
                                                      isDark: isDark,
                                                      iconColor: colors
                                                          .icon
                                                          .brandCrimson,
                                                    ),
                                                    const SizedBox(
                                                      width: AppSpacing.xs,
                                                    ),
                                                    Text(
                                                      'Shielded Balance',
                                                      style: AppTypography
                                                          .labelLarge
                                                          .copyWith(
                                                            color: colors
                                                                .text
                                                                .homeCard,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const Spacer(),
                                              _IconPillButton(
                                                iconName:
                                                    widget.privacyModeEnabled
                                                    ? AppIcons.eyeClosed
                                                    : AppIcons.eye,
                                                onPressed:
                                                    widget.onTogglePrivacyMode,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: AppSpacing.xs),
                                          Text(
                                            displayedShieldedBalance,
                                            style: AppTypography.displayMedium
                                                .copyWith(
                                                  color: colors.text.homeCard,
                                                ),
                                          ),
                                          const Spacer(),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              AppButton(
                                                onPressed: () =>
                                                    context.push('/send'),
                                                variant:
                                                    AppButtonVariant.primary,
                                                minWidth: _actionButtonMinWidth,
                                                leading: const AppIcon(
                                                  AppIcons.plane,
                                                ),
                                                child: const Text('Send'),
                                              ),
                                              const SizedBox(
                                                width: AppSpacing.xs,
                                              ),
                                              AppButton(
                                                onPressed: () =>
                                                    context.push('/receive'),
                                                variant:
                                                    AppButtonVariant.secondary,
                                                minWidth: _actionButtonMinWidth,
                                                focusRingColor: isDark
                                                    ? null
                                                    : colors
                                                          .button
                                                          .secondary
                                                          .bg,
                                                leading: const AppIcon(
                                                  AppIcons.arrowDownCircle,
                                                ),
                                                child: const Text('Receive'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: _shieldedCardHeight,
                          right: 0,
                          height: stripHeight,
                          child: SizedBox(
                            height: stripHeight,
                            child: ClipRect(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) {
                                  final curved = CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                    reverseCurve: Curves.easeInCubic,
                                  );
                                  return ClipRect(
                                    child: SizeTransition(
                                      sizeFactor: curved,
                                      axisAlignment: -1,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0, -0.85),
                                          end: Offset.zero,
                                        ).animate(curved),
                                        child: child,
                                      ),
                                    ),
                                  );
                                },
                                child: transparentStrip,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeTransparentBalanceStrip extends StatelessWidget {
  const _HomeTransparentBalanceStrip({
    required this.balanceText,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.privacyModeEnabled,
    required this.shieldBalanceContentColor,
    required this.shieldBalanceChevronColor,
    required this.onShieldBalancePressed,
    required this.onShieldBalanceHoverChanged,
    super.key,
  });

  final String balanceText;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final bool privacyModeEnabled;
  final Color shieldBalanceContentColor;
  final Color shieldBalanceChevronColor;
  final VoidCallback onShieldBalancePressed;
  final ValueChanged<bool> onShieldBalanceHoverChanged;

  static const _itemGap = 10.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayedBalance = hideAmountIfPrivacyMode(
      '$balanceText ZEC',
      privacyModeEnabled: privacyModeEnabled,
    );
    final canHoverShieldBalance = canShieldBalance && !isShieldingBalance;

    return SizedBox(
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
                        'Transparent balance: $displayedBalance',
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
            if (canShieldBalance || isShieldingBalance) ...[
              const SizedBox(width: _itemGap),
              MouseRegion(
                cursor: canHoverShieldBalance
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                onEnter: canHoverShieldBalance
                    ? (_) => onShieldBalanceHoverChanged(true)
                    : null,
                onExit: canHoverShieldBalance
                    ? (_) => onShieldBalanceHoverChanged(false)
                    : null,
                child: _HomeShieldBalanceButton(
                  enabled: canShieldBalance,
                  isLoading: isShieldingBalance,
                  contentColor: shieldBalanceContentColor,
                  chevronColor: shieldBalanceChevronColor,
                  onPressed: onShieldBalancePressed,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeShieldBalanceButton extends StatelessWidget {
  const _HomeShieldBalanceButton({
    required this.enabled,
    required this.isLoading,
    required this.contentColor,
    required this.chevronColor,
    required this.onPressed,
  });

  final bool enabled;
  final bool isLoading;
  final Color contentColor;
  final Color chevronColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isInteractive = enabled && !isLoading;

    return Semantics(
      button: true,
      enabled: isInteractive,
      child: MouseRegion(
        cursor: isInteractive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isInteractive ? onPressed : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 96, minHeight: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoading)
                    AppIcon(AppIcons.loader, size: 16, color: contentColor),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                    ),
                    child: Text(
                      'Shield Balance',
                      style: AppTypography.labelLarge.copyWith(
                        color: contentColor,
                      ),
                    ),
                  ),
                  if (!isLoading)
                    AppIcon(
                      AppIcons.chevronForward,
                      size: 16,
                      color: chevronColor,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeBalanceShieldIcon extends StatelessWidget {
  const _HomeBalanceShieldIcon({required this.isDark, required this.iconColor});

  final bool isDark;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    const patternWidth = 896.0;
    const patternHeight = 1007.0;

    return SizedBox(
      width: 20,
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: OverflowBox(
              minWidth: 0,
              minHeight: 0,
              maxWidth: patternWidth,
              maxHeight: patternHeight,
              alignment: Alignment.center,
              child: Opacity(
                opacity: 0.10,
                child: Image.asset(
                  isDark
                      ? 'assets/illustrations/home_balance_card_pattern_dark.png'
                      : 'assets/illustrations/home_balance_card_pattern_light.png',
                  width: patternWidth,
                  height: patternHeight,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          AppIcon(AppIcons.shieldKeyhole, size: 20, color: iconColor),
        ],
      ),
    );
  }
}

class _IconPillButton extends StatelessWidget {
  const _IconPillButton({required this.iconName, required this.onPressed});

  final String iconName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          width: 32,
          height: 32,
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: colors.button.secondary.bg,
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: AppIcon(
            iconName,
            size: 16,
            color: colors.button.secondary.label,
          ),
        ),
      ),
    );
  }
}

class _HomeNoticeData {
  const _HomeNoticeData({
    required this.iconName,
    required this.message,
    required this.actionLabel,
    required this.onTap,
  });

  final String iconName;
  final String message;
  final String actionLabel;
  final VoidCallback onTap;
}

class _HomeNoticeCard extends StatelessWidget {
  const _HomeNoticeCard({required this.data});

  final _HomeNoticeData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: Row(
        children: [
          AppIcon(data.iconName, size: 16, color: colors.icon.warning),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              data.message,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          AppButton(
            onPressed: data.onTap,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            trailing: const AppIcon(AppIcons.chevronForward),
            child: Text(data.actionLabel),
          ),
        ],
      ),
    );
  }
}
