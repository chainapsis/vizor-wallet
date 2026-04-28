import 'dart:async';

import 'package:flutter/material.dart'
    show CircularProgressIndicator, Scrollbar;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/config/network_config.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../../rust/api/wallet.dart' as rust_wallet;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _canBackgroundSync = false;
  bool _isBalanceVisible = true;
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
    if (zatoshi == BigInt.zero) return '0.00';
    final whole = zatoshi ~/ BigInt.from(100000000);
    final frac = (zatoshi % BigInt.from(100000000)).toString().padLeft(8, '0');
    if (whole == BigInt.zero && int.parse(frac) < 1000000) {
      return '0.$frac';
    }
    return '$whole.${frac.substring(0, 2)}';
  }

  String _formatSignedZec(BigInt zatoshi) {
    final isPositive = zatoshi >= BigInt.zero;
    final abs = zatoshi.abs();
    final whole = abs ~/ BigInt.from(100000000);
    final frac = (abs % BigInt.from(100000000)).toString().padLeft(8, '0');
    final digits = whole == BigInt.zero && int.parse(frac) < 1000000
        ? frac
        : frac.substring(0, 2);
    final sign = isPositive ? '+' : '-';
    return '$sign$whole.$digits ZEC';
  }

  String _formatZecWithUnit(BigInt zatoshi) => '${_formatZec(zatoshi)} ZEC';

  void _toggleBalanceVisibility() {
    setState(() {
      _isBalanceVisible = !_isBalanceVisible;
    });
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
      final result = await rust_sync.shieldTransparentBalance(
        dbPath: dbPath,
        lightwalletdUrl: ZcashNetwork.mainnet.lightwalletdUrl,
        network: ZcashNetwork.mainnet.name,
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
    final syncAsync = ref.watch(syncProvider);
    final sync = syncAsync.value ?? SyncState();
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
              canBackgroundSync: _canBackgroundSync,
              isBalanceVisible: _isBalanceVisible,
              shieldedBalanceText: _formatZec(shieldedBalance),
              transparentBalanceText: _formatZec(transparentBalance),
              hasTransparentBalance: transparentBalance > BigInt.zero,
              canShieldBalance: canShieldTransparentBalance,
              isShieldingBalance: _isShieldingBalance,
              shieldBalanceError: _shieldBalanceError,
              formatZec: _formatZecWithUnit,
              formatSignedZec: _formatSignedZec,
              onToggleBalanceVisibility: _toggleBalanceVisibility,
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

  static String _monthName(int month) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month];
  }
}

class _HomePane extends StatefulWidget {
  const _HomePane({
    required this.sync,
    required this.canBackgroundSync,
    required this.isBalanceVisible,
    required this.shieldedBalanceText,
    required this.transparentBalanceText,
    required this.hasTransparentBalance,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.shieldBalanceError,
    required this.formatZec,
    required this.formatSignedZec,
    required this.onToggleBalanceVisibility,
    required this.onShieldBalancePressed,
    required this.onDismissShieldBalanceError,
    required this.onSyncInBackground,
    required this.onStopBackgroundSync,
    required this.onRetrySync,
  });

  final SyncState sync;
  final bool canBackgroundSync;
  final bool isBalanceVisible;
  final String shieldedBalanceText;
  final String transparentBalanceText;
  final bool hasTransparentBalance;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final String? shieldBalanceError;
  final String Function(BigInt zatoshi) formatZec;
  final String Function(BigInt zatoshi) formatSignedZec;
  final VoidCallback onToggleBalanceVisibility;
  final VoidCallback onShieldBalancePressed;
  final VoidCallback onDismissShieldBalanceError;
  final VoidCallback onSyncInBackground;
  final VoidCallback onStopBackgroundSync;
  final VoidCallback onRetrySync;

  @override
  State<_HomePane> createState() => _HomePaneState();
}

class _HomePaneState extends State<_HomePane> {
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
                          isBalanceVisible: widget.isBalanceVisible,
                          onToggleBalanceVisibility:
                              widget.onToggleBalanceVisibility,
                          onShieldBalancePressed: widget.onShieldBalancePressed,
                        ),
                        if (notice != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          _HomeNoticeCard(data: notice),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        _HomeActivitySection(rows: rows),
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

  List<_HomeActivityRowData> _activityRows(BuildContext context) {
    return [
      _syncActivityRow(context),
      ...widget.sync.recentTransactions
          .take(6)
          .map((tx) => _transactionActivityRow(context, tx)),
    ];
  }

  _HomeActivityRowData _syncActivityRow(BuildContext context) {
    final colors = context.colors;

    if (widget.sync.error != null) {
      return _HomeActivityRowData(
        title: 'Wallet Synced',
        leadingIconName: AppIcons.sync,
        leadingBackgroundColor: colors.background.neutralSubtleOpacity,
        leadingIconColor: colors.icon.regular,
        amountText: 'Retry',
        amountColor: colors.text.warning,
        statusText: 'Failed',
        statusIconName: AppIcons.skull,
        statusColor: colors.text.destructive,
        timestampText: _formatTimestamp(widget.sync.lastSyncFailedAt),
        onTap: widget.onRetrySync,
      );
    }

    if (widget.sync.isSyncing) {
      final pct = (widget.sync.percentage * 100).toStringAsFixed(0);
      return _HomeActivityRowData(
        title: 'Wallet Synced',
        leadingIconName: AppIcons.sync,
        leadingBackgroundColor: colors.background.neutralSubtleOpacity,
        leadingIconColor: colors.icon.regular,
        subtitle: widget.sync.phase.isEmpty
            ? null
            : _capitalize(widget.sync.phase),
        amountText: '$pct%',
        amountColor: colors.text.secondary,
        statusText: 'In progress',
        statusIconName: AppIcons.loader,
        statusColor: colors.text.secondary,
        timestampText: _formatTimestamp(widget.sync.lastSyncStartedAt),
      );
    }

    return _HomeActivityRowData(
      title: 'Wallet Synced',
      leadingIconName: AppIcons.sync,
      leadingBackgroundColor: colors.background.neutralSubtleOpacity,
      leadingIconColor: colors.icon.regular,
      amountText: widget.formatZec(widget.sync.totalBalance),
      amountColor: colors.text.accent,
      statusText: 'Completed',
      statusColor: colors.text.secondary,
      timestampText: _formatTimestamp(widget.sync.lastSyncCompletedAt),
    );
  }

  _HomeActivityRowData _transactionActivityRow(
    BuildContext context,
    rust_sync.TransactionInfo tx,
  ) {
    final colors = context.colors;
    final isPending = tx.minedHeight == BigInt.zero && !tx.expiredUnmined;
    final isFailed = tx.expiredUnmined;
    final kind = tx.txKind;
    final amount = tx.displayAmount;
    final isReceived = kind == 'received';
    final isSent = kind == 'sent';
    final isShielded = kind == 'shielded';
    final signedAmount = isSent ? -amount : amount;
    final subtitle = isReceived || isSent ? _poolLabel(tx.displayPool) : null;

    return _HomeActivityRowData(
      title: _txTitle(kind),
      leadingIconName: _txIcon(kind),
      leadingBackgroundColor: colors.background.neutralSubtleOpacity,
      leadingIconColor: colors.icon.regular,
      subtitle: subtitle,
      subtitleIconName: tx.displayPool == 'shielded'
          ? AppIcons.shieldKeyholeOutline
          : null,
      amountText: amount == BigInt.zero
          ? '--'
          : isShielded || kind == 'internal'
          ? widget.formatZec(amount)
          : widget.formatSignedZec(signedAmount),
      amountColor: isFailed
          ? colors.text.muted
          : isReceived
          ? colors.text.brandCrimson
          : colors.text.accent,
      statusText: isFailed
          ? 'Failed'
          : isPending
          ? 'In progress'
          : 'Completed',
      statusIconName: isFailed
          ? AppIcons.skull
          : isPending
          ? AppIcons.loader
          : null,
      statusColor: isFailed ? colors.text.destructive : colors.text.secondary,
      timestampText: _formatTimestamp(_txTimestamp(tx)),
    );
  }

  String _txTitle(String kind) {
    return switch (kind) {
      'received' => 'Received',
      'sent' => 'Sent',
      'shielded' => 'Shielded',
      'internal' => 'Internal',
      _ => 'Transaction',
    };
  }

  String _txIcon(String kind) {
    return switch (kind) {
      'received' => AppIcons.arrowDownCircle,
      'sent' => AppIcons.plane,
      'shielded' => AppIcons.shieldAsset,
      'internal' => AppIcons.sync,
      _ => AppIcons.history,
    };
  }

  String? _poolLabel(String pool) {
    return switch (pool) {
      'transparent' => 'Transparent',
      'shielded' => 'Shielded',
      'mixed' => 'Mixed',
      _ => null,
    };
  }

  DateTime? _txTimestamp(rust_sync.TransactionInfo tx) {
    final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
    if (seconds <= BigInt.zero) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '--';
    final now = DateTime.now();
    final local = timestamp.toLocal();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(local.year, local.month, local.day);
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    if (date == today) return 'Today, $time';
    if (date == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, $time';
    }
    return '${_HomeScreenState._monthName(local.month)} ${local.day}, $time';
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}

class _HomeBalanceCard extends StatelessWidget {
  const _HomeBalanceCard({
    required this.shieldedBalanceText,
    required this.transparentBalanceText,
    required this.hasTransparentBalance,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.isBalanceVisible,
    required this.onToggleBalanceVisibility,
    required this.onShieldBalancePressed,
  });

  final String shieldedBalanceText;
  final String transparentBalanceText;
  final bool hasTransparentBalance;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final bool isBalanceVisible;
  final VoidCallback onToggleBalanceVisibility;
  final VoidCallback onShieldBalancePressed;

  static const _shieldedCardHeight = 196.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayedShieldedBalance = isBalanceVisible
        ? '$shieldedBalanceText zec'
        : '•••••• zec';
    final isDark = AppTheme.of(context) == AppThemeData.dark;

    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: DecoratedBox(
          decoration: BoxDecoration(color: colors.background.base),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: _shieldedCardHeight,
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
                                            colors.background.base.withValues(
                                              alpha: 0.90,
                                            ),
                                            colors.background.base.withValues(
                                              alpha: 0.82,
                                            ),
                                            colors.background.base.withValues(
                                              alpha: 0.48,
                                            ),
                                            colors.background.base.withValues(
                                              alpha: 0.00,
                                            ),
                                          ]
                                        : [
                                            colors.background.base.withValues(
                                              alpha: 0.98,
                                            ),
                                            colors.background.base.withValues(
                                              alpha: 0.95,
                                            ),
                                            colors.background.base.withValues(
                                              alpha: 0.70,
                                            ),
                                            colors.background.base.withValues(
                                              alpha: 0.00,
                                            ),
                                          ],
                                    stops: const [0.0, 0.28, 0.56, 0.86],
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.xxs),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _HomeBalanceShieldIcon(
                                        isDark: isDark,
                                        iconColor: colors.icon.brandCrimson,
                                      ),
                                      const SizedBox(width: AppSpacing.xxs),
                                      Text(
                                        'Shielded Balance',
                                        style: AppTypography.labelLarge
                                            .copyWith(
                                              color: colors.text.accent,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                _IconPillButton(
                                  iconName: isBalanceVisible
                                      ? AppIcons.eye
                                      : AppIcons.eyeClosed,
                                  onPressed: onToggleBalanceVisibility,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              displayedShieldedBalance,
                              style: AppTypography.displayMedium.copyWith(
                                color: colors.text.accent,
                              ),
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      return AppButton(
                                        onPressed: () => context.push('/send'),
                                        variant: AppButtonVariant.primary,
                                        minWidth: constraints.maxWidth,
                                        leading: const AppIcon(AppIcons.plane),
                                        child: const Text('Send'),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      return AppButton(
                                        onPressed: () =>
                                            context.push('/receive'),
                                        variant: AppButtonVariant.secondary,
                                        minWidth: constraints.maxWidth,
                                        leading: const AppIcon(
                                          AppIcons.arrowDownCircle,
                                        ),
                                        child: const Text('Receive'),
                                      );
                                    },
                                  ),
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
              AnimatedSwitcher(
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
                child: hasTransparentBalance
                    ? _HomeTransparentBalanceStrip(
                        key: const ValueKey('transparent-balance-strip'),
                        balanceText: transparentBalanceText,
                        canShieldBalance: canShieldBalance,
                        isShieldingBalance: isShieldingBalance,
                        isBalanceVisible: isBalanceVisible,
                        onShieldBalancePressed: onShieldBalancePressed,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('transparent-balance-empty'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeTransparentBalanceStrip extends StatelessWidget {
  const _HomeTransparentBalanceStrip({
    required this.balanceText,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.isBalanceVisible,
    required this.onShieldBalancePressed,
    super.key,
  });

  final String balanceText;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final bool isBalanceVisible;
  final VoidCallback onShieldBalancePressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayedBalance = isBalanceVisible
        ? '$balanceText ZEC'
        : '•••••• ZEC';

    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s),
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.transparentBalance,
                    size: 16,
                    color: colors.text.accent,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Flexible(
                    child: Text(
                      'Transparent balance: $displayedBalance',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (canShieldBalance || isShieldingBalance) ...[
              const SizedBox(width: AppSpacing.xs),
              _HomeShieldBalanceButton(
                enabled: canShieldBalance,
                isLoading: isShieldingBalance,
                onPressed: onShieldBalancePressed,
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
    required this.onPressed,
  });

  final bool enabled;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isInteractive = enabled && !isLoading;
    final contentColor = enabled
        ? colors.text.accent
        : colors.text.secondary.withValues(alpha: 0.64);

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
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: contentColor,
                      ),
                    )
                  else
                    AppIcon(
                      AppIcons.shieldKeyholeOutline,
                      size: 16,
                      color: contentColor,
                    ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    'Shield Balance',
                    style: AppTypography.labelLarge.copyWith(
                      color: contentColor,
                    ),
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
      width: 16,
      height: 16,
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
                opacity: 0.15,
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
          AppIcon(AppIcons.shieldKeyhole, size: 16, color: iconColor),
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
          width: 24,
          height: 24,
          padding: const EdgeInsets.all(AppSpacing.xxs),
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

class _HomeActivitySection extends StatelessWidget {
  const _HomeActivitySection({required this.rows});

  final List<_HomeActivityRowData> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.push('/history'),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Recent Activity',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    AppIcon(
                      AppIcons.chevronForward,
                      size: 16,
                      color: colors.icon.accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const _HomeActivityTableHeader(),
          const SizedBox(height: AppSpacing.s),
          for (var i = 0; i < rows.length; i++) ...[
            _HomeActivityRow(row: rows[i]),
            if (i != rows.length - 1) ...[
              const SizedBox(height: AppSpacing.xs),
              const _HomeActivityDivider(),
              const SizedBox(height: AppSpacing.xs),
            ],
          ],
        ],
      ),
    );
  }
}

class _HomeActivityTableHeader extends StatelessWidget {
  const _HomeActivityTableHeader();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = AppTypography.labelMedium.copyWith(color: colors.text.muted);
    return SizedBox(
      height: 32,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        child: _HomeActivityColumnLayout(
          txType: Text('Tx Type', style: style),
          amount: Text('Amount', style: style),
          status: Text('Status', style: style),
          timestamp: Text('Time Stamp', textAlign: TextAlign.end, style: style),
        ),
      ),
    );
  }
}

const double _homeActivityLeftCellWidth = 190;
const double _homeActivityMiddleCellWidth = 160;
const double _homeActivityRightCellWidth = 140;
const double _homeActivityFixedColumnsWidth =
    _homeActivityLeftCellWidth +
    (_homeActivityMiddleCellWidth * 2) +
    _homeActivityRightCellWidth;

class _HomeActivityDivider extends StatelessWidget {
  const _HomeActivityDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: context.colors.border.subtle);
  }
}

class _HomeActivityColumnLayout extends StatelessWidget {
  const _HomeActivityColumnLayout({
    required this.txType,
    required this.amount,
    required this.status,
    required this.timestamp,
  });

  final Widget txType;
  final Widget amount;
  final Widget status;
  final Widget timestamp;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useFixedColumns =
            constraints.maxWidth >= _homeActivityFixedColumnsWidth;
        if (useFixedColumns) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _HomeActivityCell(
                width: _homeActivityLeftCellWidth,
                child: txType,
              ),
              _HomeActivityCell(
                width: _homeActivityMiddleCellWidth,
                child: amount,
              ),
              _HomeActivityCell(
                width: _homeActivityMiddleCellWidth,
                child: status,
              ),
              _HomeActivityCell(
                width: _homeActivityRightCellWidth,
                alignEnd: true,
                child: timestamp,
              ),
            ],
          );
        }

        return Row(
          children: [
            _HomeActivityCell(flex: 190, child: txType),
            _HomeActivityCell(flex: 160, child: amount),
            _HomeActivityCell(flex: 160, child: status),
            _HomeActivityCell(flex: 140, alignEnd: true, child: timestamp),
          ],
        );
      },
    );
  }
}

class _HomeActivityCell extends StatelessWidget {
  const _HomeActivityCell({
    required this.child,
    this.width,
    this.flex,
    this.alignEnd = false,
  });

  final Widget child;
  final double? width;
  final int? flex;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final content = Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
    final width = this.width;
    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return Expanded(flex: flex ?? 1, child: content);
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.row});

  final _HomeActivityRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (row.statusIconName != null) ...[
          AppIcon(
            row.statusIconName!,
            size: 16,
            color: row.statusColor ?? colors.text.secondary,
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
        Text(
          row.statusText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelMedium.copyWith(
            color: row.statusColor ?? colors.text.secondary,
          ),
        ),
      ],
    );
  }
}

class _HomeActivityRowData {
  const _HomeActivityRowData({
    required this.title,
    required this.leadingIconName,
    required this.leadingBackgroundColor,
    required this.leadingIconColor,
    this.subtitle,
    this.subtitleIconName,
    required this.amountText,
    this.amountColor,
    required this.statusText,
    required this.timestampText,
    this.statusIconName,
    this.statusColor,
    this.onTap,
  });

  final String title;
  final String leadingIconName;
  final Color leadingBackgroundColor;
  final Color leadingIconColor;
  final String? subtitle;
  final String? subtitleIconName;
  final String amountText;
  final Color? amountColor;
  final String statusText;
  final String timestampText;
  final String? statusIconName;
  final Color? statusColor;
  final VoidCallback? onTap;
}

class _HomeActivityRow extends StatelessWidget {
  const _HomeActivityRow({required this.row});

  final _HomeActivityRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Container(
      height: 48,
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xSmall),
      ),
      child: _HomeActivityColumnLayout(
        txType: Row(
          children: [
            _ActivityAvatar(row: row),
            const SizedBox(width: AppSpacing.s),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                  if (row.subtitle != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (row.subtitleIconName != null) ...[
                          AppIcon(
                            row.subtitleIconName!,
                            size: 16,
                            color: colors.icon.brandCrimson,
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                        ],
                        Flexible(
                          child: Text(
                            row.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.labelMedium.copyWith(
                              color: row.subtitleIconName == null
                                  ? colors.text.secondary
                                  : colors.text.brandCrimson,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
        amount: Text(
          row.amountText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.labelMedium.copyWith(
            color: row.amountColor ?? colors.text.accent,
          ),
        ),
        status: _StatusLabel(row: row),
        timestamp: Text(
          row.timestampText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: AppTypography.labelMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
      ),
    );

    if (row.onTap == null) return content;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: row.onTap,
        child: content,
      ),
    );
  }
}

class _ActivityAvatar extends StatelessWidget {
  const _ActivityAvatar({required this.row});

  final _HomeActivityRowData row;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: row.leadingBackgroundColor,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: AppIcon(
                  row.leadingIconName,
                  size: 16,
                  color: row.leadingIconColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
