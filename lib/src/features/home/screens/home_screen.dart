import 'package:flutter/material.dart'
    show CircularProgressIndicator, Scrollbar, Theme;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _canBackgroundSync = false;
  bool _isBalanceVisible = true;

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

  void _toggleBalanceVisibility() {
    setState(() {
      _isBalanceVisible = !_isBalanceVisible;
    });
  }

  String _groupLabelForTx(rust_sync.TransactionInfo tx) {
    if (tx.minedHeight == BigInt.zero && !tx.expiredUnmined) {
      return 'Today';
    }

    final date = DateTime.fromMillisecondsSinceEpoch(
      tx.blockTime.toInt() * 1000,
    );
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) return 'Today';
    return '${_monthName(date.month)}, ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    final syncAsync = ref.watch(syncProvider);
    final sync = syncAsync.value ?? SyncState();

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
              balanceText: _formatZec(sync.totalBalance),
              formatSignedZec: _formatSignedZec,
              groupLabelForTx: _groupLabelForTx,
              onToggleBalanceVisibility: _toggleBalanceVisibility,
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
    required this.balanceText,
    required this.formatSignedZec,
    required this.groupLabelForTx,
    required this.onToggleBalanceVisibility,
    required this.onSyncInBackground,
    required this.onStopBackgroundSync,
    required this.onRetrySync,
  });

  final SyncState sync;
  final bool canBackgroundSync;
  final bool isBalanceVisible;
  final String balanceText;
  final String Function(BigInt zatoshi) formatSignedZec;
  final String Function(rust_sync.TransactionInfo tx) groupLabelForTx;
  final VoidCallback onToggleBalanceVisibility;
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
    final groups = _activityGroups(context);
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
                          balanceText: widget.balanceText,
                          isBalanceVisible: widget.isBalanceVisible,
                          onToggleBalanceVisibility:
                              widget.onToggleBalanceVisibility,
                        ),
                        if (notice != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          _HomeNoticeCard(data: notice),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        _HomeActivitySection(groups: groups),
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

  List<_HomeActivityGroupData> _activityGroups(BuildContext context) {
    final grouped = <String, List<_HomeActivityRowData>>{};
    final todayRows = <_HomeActivityRowData>[];
    final colors = context.colors;
    final successColor = Theme.of(context).colorScheme.tertiary;

    if (widget.sync.error != null) {
      todayRows.add(
        _HomeActivityRowData(
          title: 'Sync Error',
          leadingIconName: AppIcons.warning,
          leadingBackgroundColor: colors.background.base,
          leadingIconColor: colors.icon.warning,
          amountText: 'Retry',
          amountColor: colors.text.warning,
          onTap: widget.onRetrySync,
        ),
      );
    } else if (widget.sync.isSyncing) {
      final pct = (widget.sync.percentage * 100).toStringAsFixed(0);
      todayRows.add(
        _HomeActivityRowData(
          title: widget.sync.isBackgroundMode
              ? 'Background Syncing...'
              : 'Syncing...',
          leadingIconName: AppIcons.renew,
          leadingBackgroundColor: colors.background.base,
          leadingIconColor: colors.icon.accent,
          subtitle: widget.sync.phase.isEmpty
              ? null
              : '${widget.sync.phase[0].toUpperCase()}${widget.sync.phase.substring(1)}',
          amountText: '$pct%',
          amountColor: colors.text.secondary,
        ),
      );
    } else {
      todayRows.add(
        _HomeActivityRowData(
          title: 'Wallet Synced',
          leadingIconName: AppIcons.check,
          leadingBackgroundColor: successColor.withValues(alpha: 0.16),
          leadingIconColor: successColor,
        ),
      );
    }

    for (final tx in widget.sync.recentTransactions.take(6)) {
      final groupLabel = widget.groupLabelForTx(tx);
      final rows = grouped.putIfAbsent(groupLabel, () => []);
      final isIncoming = tx.accountBalanceDelta >= 0;
      final isPending = tx.minedHeight == BigInt.zero && !tx.expiredUnmined;
      final isExpired = tx.expiredUnmined;
      final subtitle = tx.isTransparent ? 'Transparent' : 'Shielded';
      final subtitleIconName = tx.isTransparent
          ? null
          : AppIcons.shieldKeyholeOutline;
      rows.add(
        _HomeActivityRowData(
          title: isExpired
              ? (isIncoming ? 'Receive Expired' : 'Send Expired')
              : isPending
              ? (isIncoming ? 'Receiving...' : 'Sending...')
              : isIncoming
              ? 'Received'
              : 'Sent',
          subtitle: subtitle,
          subtitleIconName: subtitleIconName,
          leadingIconName: isIncoming
              ? AppIcons.arrowDownCircle
              : AppIcons.plane,
          leadingBackgroundColor: colors.background.base,
          leadingIconColor: isIncoming
              ? colors.icon.accent
              : colors.icon.brandPurple,
          subIconName: isPending ? AppIcons.loader : null,
          subIconBackgroundColor: isPending
              ? colors.background.overlay.withValues(alpha: 0.5)
              : colors.background.brandCyanStrong,
          amountText: widget.formatSignedZec(
            BigInt.from(tx.accountBalanceDelta),
          ),
          amountColor: isExpired
              ? colors.text.muted
              : isIncoming
              ? colors.text.accent
              : colors.text.brandPurple,
        ),
      );
    }

    final results = <_HomeActivityGroupData>[];
    final mergedToday = [
      ...todayRows,
      ...(grouped.remove('Today') ?? const <_HomeActivityRowData>[]),
    ];
    if (mergedToday.isNotEmpty) {
      results.add(_HomeActivityGroupData(label: 'Today', rows: mergedToday));
    }
    grouped.forEach((label, rows) {
      results.add(_HomeActivityGroupData(label: label, rows: rows));
    });
    return results;
  }
}

class _HomeBalanceCard extends StatelessWidget {
  const _HomeBalanceCard({
    required this.balanceText,
    required this.isBalanceVisible,
    required this.onToggleBalanceVisibility,
  });

  final String balanceText;
  final bool isBalanceVisible;
  final VoidCallback onToggleBalanceVisibility;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayedBalance = isBalanceVisible
        ? '$balanceText zec'
        : '•••••• zec';
    final isDark = AppTheme.of(context) == AppThemeData.dark;

    return SizedBox(
      height: 196,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(color: colors.background.base),
              ),
            ),
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
                          height: 196,
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
                                iconColor: colors.icon.brandPurple,
                              ),
                              const SizedBox(width: AppSpacing.xxs),
                              Text(
                                'Shielded Balance',
                                style: AppTypography.labelLarge.copyWith(
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
                      displayedBalance,
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
                                onPressed: () => context.push('/receive'),
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
        borderRadius: BorderRadius.circular(AppRadii.small),
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
  const _HomeActivitySection({required this.groups});

  final List<_HomeActivityGroupData> groups;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => context.push('/history'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Recent Activity',
                    style: AppTypography.headlineSmall.copyWith(
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
        const SizedBox(height: AppSpacing.s),
        for (var i = 0; i < groups.length; i++) ...[
          _HomeActivityGroup(group: groups[i]),
          if (i != groups.length - 1) const SizedBox(height: AppSpacing.s),
        ],
      ],
    );
  }
}

class _HomeActivityGroupData {
  const _HomeActivityGroupData({required this.label, required this.rows});

  final String label;
  final List<_HomeActivityRowData> rows;
}

class _HomeActivityGroup extends StatelessWidget {
  const _HomeActivityGroup({required this.group});

  final _HomeActivityGroupData group;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(
            group.label,
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var i = 0; i < group.rows.length; i++) ...[
          _HomeActivityRow(row: group.rows[i]),
          if (i != group.rows.length - 1) const SizedBox(height: AppSpacing.xs),
        ],
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
    this.subIconName,
    this.subIconBackgroundColor,
    this.amountText,
    this.amountColor,
    this.onTap,
  });

  final String title;
  final String leadingIconName;
  final Color leadingBackgroundColor;
  final Color leadingIconColor;
  final String? subtitle;
  final String? subtitleIconName;
  final String? subIconName;
  final Color? subIconBackgroundColor;
  final String? amountText;
  final Color? amountColor;
  final VoidCallback? onTap;
}

class _HomeActivityRow extends StatelessWidget {
  const _HomeActivityRow({required this.row});

  final _HomeActivityRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Row(
        children: [
          _ActivityAvatar(row: row),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  row.title,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                if (row.subtitle != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        row.subtitle!,
                        style: AppTypography.labelMedium.copyWith(
                          color: row.subtitleIconName == null
                              ? colors.text.secondary
                              : colors.text.brandPurple,
                        ),
                      ),
                      if (row.subtitleIconName != null) ...[
                        const SizedBox(width: AppSpacing.xxs),
                        AppIcon(
                          row.subtitleIconName!,
                          size: 16,
                          color: colors.icon.brandPurple,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          if (row.amountText != null)
            Text(
              row.amountText!,
              style: AppTypography.labelLarge.copyWith(
                color: row.amountColor ?? colors.text.accent,
              ),
            ),
        ],
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
          if (row.subIconName != null && row.subIconBackgroundColor != null)
            Positioned(
              right: -4,
              bottom: -2,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: row.subIconBackgroundColor,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
                child: Center(
                  child: AppIcon(
                    row.subIconName!,
                    size: 12,
                    color: context.colors.icon.accent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
