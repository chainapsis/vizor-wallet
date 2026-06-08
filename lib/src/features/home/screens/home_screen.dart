import 'dart:async';

import 'package:flutter/material.dart' show CircularProgressIndicator, Colors;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../app_bootstrap.dart';
import '../../../core/config/network_config.dart';
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
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../activity/activity_row_mapper.dart';
import '../../activity/models/activity_row_data.dart';
import '../../activity/screens/activity_transaction_status_screen.dart';

const _homeContentMaxWidth = 420.0;
const _homeContentTopInset = 48.0;
const _homeContentHorizontalPadding = AppSpacing.s;
const _homeContentVerticalPadding = AppSpacing.sm;
const _homeSectionGap = AppSpacing.md;
const _homeActivityActivationShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
};
const shieldBalancePendingBroadcastMessage =
    'Shielding queued for retry. Check Activity.';

String? shieldBalanceBroadcastStatusMessage(
  rust_sync.ShieldTransparentResult result,
) {
  if (result.status == 'broadcasted') return null;
  return shieldBalancePendingBroadcastMessage;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _canBackgroundSync = false;

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

  @override
  Widget build(BuildContext context) {
    final walletAsync = ref.watch(walletProvider);
    final bootstrap = ref.watch(appBootstrapProvider);
    final syncAsync = ref.watch(syncProvider);
    final activeAccountUuid = ref.watch(
      accountProvider.select((value) => value.value?.activeAccountUuid),
    );
    final syncState = syncAsync.value;
    final sync = (syncState ?? SyncState()).scopedToAccount(activeAccountUuid);
    final hasActivitySyncData =
        syncState?.hasDataForAccount(activeAccountUuid) ?? false;
    final isActivityLoading =
        activeAccountUuid != null &&
        !hasActivitySyncData &&
        sync.failure == null;
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final shieldedBalance =
        sync.saplingBalance +
        sync.orchardBalance +
        sync.saplingPendingBalance +
        sync.orchardPendingBalance;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SizedBox.expand(
              child: walletAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Text(
                    'Something went wrong. Try again in a moment.\n\n'
                    'Details: $err',
                    style: AppTypography.bodyMedium.copyWith(
                      color: context.colors.text.warning,
                    ),
                  ),
                ),
                data: (_) => _HomePane(
                  sync: sync,
                  hasActivitySyncData: hasActivitySyncData,
                  isActivityLoading: isActivityLoading,
                  passwordRotationRecoveryFailed:
                      bootstrap.passwordRotationRecoveryFailed,
                  canBackgroundSync: _canBackgroundSync,
                  privacyModeEnabled: privacyModeEnabled,
                  shieldedBalanceText: _formatZec(shieldedBalance),
                  hasShieldedBalance: shieldedBalance > BigInt.zero,
                  onTogglePrivacyMode: () =>
                      ref.read(privacyModeProvider.notifier).toggle(),
                  onSyncInBackground: () =>
                      ref.read(syncProvider.notifier).enableBackgroundSync(),
                  onStopBackgroundSync: () =>
                      ref.read(syncProvider.notifier).disableBackgroundSync(),
                  onRetrySync: () =>
                      ref.read(syncProvider.notifier).startSync(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePane extends ConsumerStatefulWidget {
  const _HomePane({
    required this.sync,
    required this.hasActivitySyncData,
    required this.isActivityLoading,
    required this.passwordRotationRecoveryFailed,
    required this.canBackgroundSync,
    required this.privacyModeEnabled,
    required this.shieldedBalanceText,
    required this.hasShieldedBalance,
    required this.onTogglePrivacyMode,
    required this.onSyncInBackground,
    required this.onStopBackgroundSync,
    required this.onRetrySync,
  });

  final SyncState sync;
  final bool hasActivitySyncData;
  final bool isActivityLoading;
  final bool passwordRotationRecoveryFailed;
  final bool canBackgroundSync;
  final bool privacyModeEnabled;
  final String shieldedBalanceText;
  final bool hasShieldedBalance;
  final VoidCallback onTogglePrivacyMode;
  final VoidCallback onSyncInBackground;
  final VoidCallback onStopBackgroundSync;
  final VoidCallback onRetrySync;

  @override
  ConsumerState<_HomePane> createState() => _HomePaneState();
}

class _HomePaneState extends ConsumerState<_HomePane> {
  static const _recentActivityLimit = 10;

  @override
  Widget build(BuildContext context) {
    final notice = _noticeData();
    final rows = _activityRows(context);
    final showEmptyActivity = !widget.isActivityLoading && rows.isEmpty;

    return AppPaneScrollableFill(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: _homeContentTopInset),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _homeContentMaxWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _homeContentHorizontalPadding,
                vertical: _homeContentVerticalPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HomeBalanceCard(
                    shieldedBalanceText: widget.shieldedBalanceText,
                    hasShieldedBalance: widget.hasShieldedBalance,
                    privacyModeEnabled: widget.privacyModeEnabled,
                    onTogglePrivacyMode: widget.onTogglePrivacyMode,
                  ),
                  if (notice != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    _HomeNoticeCard(data: notice),
                  ],
                  const SizedBox(height: _homeSectionGap),
                  if (showEmptyActivity)
                    const Expanded(child: _HomeEmptyActivityState())
                  else
                    _HomeRecentActivityCard(
                      rows: rows,
                      isLoading: widget.isActivityLoading,
                      onTitleTap: () => context.push('/activity'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  _HomeNoticeData? _noticeData() {
    if (widget.passwordRotationRecoveryFailed) {
      return _HomeNoticeData(
        iconName: AppIcons.warning,
        message:
            "We couldn't verify the previous password change. Try again or restart Vizor.",
        actionLabel: 'Settings',
        onTap: () => context.push('/settings'),
      );
    }
    final syncFailure = widget.sync.failure;
    if (syncFailure != null) {
      return _HomeNoticeData(
        iconName: AppIcons.warning,
        message: syncFailure.userMessage,
        actionLabel: syncFailure.actionLabel,
        onTap: syncFailure.showSettingsAction
            ? () => context.push('/settings/endpoint')
            : widget.onRetrySync,
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
    if (!widget.hasActivitySyncData) {
      return const [];
    }
    return buildActivityRows(
      context: context,
      transactions: widget.sync.recentTransactions.take(_recentActivityLimit),
      privacyModeEnabled: widget.privacyModeEnabled,
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
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
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

class _HomeBalanceCard extends StatelessWidget {
  const _HomeBalanceCard({
    required this.shieldedBalanceText,
    required this.hasShieldedBalance,
    required this.privacyModeEnabled,
    required this.onTogglePrivacyMode,
  });

  final String shieldedBalanceText;
  final bool hasShieldedBalance;
  final bool privacyModeEnabled;
  final VoidCallback onTogglePrivacyMode;

  static const _cardHeight = 200.0;
  static const _cardBorderWidth = 1.5;
  static const _cardBorderColor = Color(0x12FFFFFF);
  static const _cardRadius = AppRadii.large;
  static const _actionButtonGap = AppSpacing.xs;
  static const _actionButtonHeight = 44.0;
  static const _cardActionsGap = AppSpacing.s;
  static const _fiatValuePlaceholder = r'$1,200.12';
  static const _fiatChangePlaceholder = '+13.12% (24h)';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final currencyTicker = kZcashDefaultCurrencyTicker;
    final displayedShieldedBalance = hideIfPrivacyMode(
      '$shieldedBalanceText $currencyTicker',
      privacyModeEnabled: privacyModeEnabled,
      suffix: ' $currencyTicker',
    );
    final isDark = AppTheme.of(context) == AppThemeData.dark;
    final displayedFiatValue = hideIfPrivacyMode(
      _fiatValuePlaceholder,
      privacyModeEnabled: privacyModeEnabled,
      maskLength: 3,
    );
    final displayedFiatChange = privacyModeEnabled
        ? fixedPrivacyMask(length: 3)
        : _fiatChangePlaceholder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: _cardHeight,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.background.homeCard,
            borderRadius: BorderRadius.circular(_cardRadius),
            border: Border.all(
              color: _cardBorderColor,
              width: _cardBorderWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.xxs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            AppIcons.shieldKeyhole,
                            size: 20,
                            color: colors.text.homeCard,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Shielded Balance',
                            style: AppTypography.labelLarge.copyWith(
                              color: colors.text.homeCard,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _IconPillButton(
                      iconName: privacyModeEnabled
                          ? AppIcons.eyeClosed
                          : AppIcons.eye,
                      onPressed: onTogglePrivacyMode,
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Text(
                    displayedFiatValue,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.homeCard,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    displayedFiatChange,
                    style: AppTypography.labelMedium.copyWith(
                      color: colors.text.positiveStrong,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                displayedShieldedBalance,
                key: const ValueKey('home_shielded_balance_text'),
                style: AppTypography.displayMedium.copyWith(
                  color: colors.text.homeCard,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: _cardActionsGap),
        _HomeBalanceActions(
          showSend: hasShieldedBalance,
          receiveFocusRingColor: isDark ? null : colors.button.secondary.bg,
        ),
      ],
    );
  }
}

class _HomeBalanceActions extends StatelessWidget {
  const _HomeBalanceActions({
    required this.showSend,
    required this.receiveFocusRingColor,
  });

  final bool showSend;
  final Color? receiveFocusRingColor;

  @override
  Widget build(BuildContext context) {
    if (!showSend) {
      return SizedBox(
        height: _HomeBalanceCard._actionButtonHeight,
        child: _HomeActionButton(
          onPressed: () => context.push('/receive'),
          variant: AppButtonVariant.primary,
          iconName: AppIcons.arrowDownCircle,
          label: 'Receive your first ZEC',
        ),
      );
    }

    return SizedBox(
      height: _HomeBalanceCard._actionButtonHeight,
      child: Row(
        children: [
          Expanded(
            child: _HomeActionButton(
              onPressed: () => context.push('/send'),
              variant: AppButtonVariant.primary,
              iconName: AppIcons.plane,
              label: 'Send',
            ),
          ),
          const SizedBox(width: _HomeBalanceCard._actionButtonGap),
          Expanded(
            child: _HomeActionButton(
              onPressed: () => context.push('/receive'),
              variant: AppButtonVariant.secondary,
              focusRingColor: receiveFocusRingColor,
              iconName: AppIcons.arrowDownCircle,
              label: 'Receive',
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeActionButton extends StatefulWidget {
  const _HomeActionButton({
    required this.onPressed,
    required this.variant,
    required this.iconName,
    required this.label,
    this.focusRingColor,
  });

  final VoidCallback onPressed;
  final AppButtonVariant variant;
  final String iconName;
  final String label;
  final Color? focusRingColor;

  @override
  State<_HomeActionButton> createState() => _HomeActionButtonState();
}

class _HomeActionButtonState extends State<_HomeActionButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() {
      _hovered = value;
    });
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() {
      _pressed = value;
    });
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() {
      _focused = value;
    });
  }

  Color _backgroundColor(AppColors colors) {
    return switch (widget.variant) {
      AppButtonVariant.primary =>
        _pressed
            ? colors.button.primary.bgPressed
            : _hovered
            ? colors.button.primary.bgHover
            : colors.button.primary.bg,
      AppButtonVariant.secondary =>
        _pressed
            ? colors.button.secondary.bgPressed
            : _hovered
            ? colors.button.secondary.bgHover
            : colors.button.secondary.bg,
      _ => colors.button.secondary.bg,
    };
  }

  Color _labelColor(AppColors colors) {
    return switch (widget.variant) {
      AppButtonVariant.primary =>
        _pressed || _hovered
            ? colors.button.primary.labelHover
            : colors.button.primary.label,
      AppButtonVariant.secondary => colors.button.secondary.label,
      _ => colors.button.secondary.label,
    };
  }

  BorderSide _borderSide(AppColors colors) {
    if (widget.variant != AppButtonVariant.primary) {
      return BorderSide.none;
    }
    final color = _pressed
        ? colors.button.primary.borderPressed
        : _hovered
        ? colors.button.primary.borderHover
        : colors.button.primary.border;
    return BorderSide(color: color, width: 1.5);
  }

  Color _focusRingColor(AppColors colors) {
    if (widget.focusRingColor != null) return widget.focusRingColor!;
    if (widget.variant == AppButtonVariant.primary) {
      return _hovered
          ? colors.button.primary.bgHover
          : colors.button.primary.bg;
    }
    return colors.state.focusRing;
  }

  void _activate() {
    _setPressed(false);
    widget.onPressed();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isActivate =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space;
    if (!isActivate) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      _setPressed(true);
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final labelColor = _labelColor(colors);
    final focusRingOutset = widget.variant == AppButtonVariant.primary
        ? 3.5
        : 2.0;

    return Focus(
      onFocusChange: _setFocused,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) {
          _setHovered(false);
          _setPressed(false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _activate(),
          onTapCancel: () => _setPressed(false),
          child: SizedBox.expand(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    decoration: ShapeDecoration(
                      color: _backgroundColor(colors),
                      shape: StadiumBorder(side: _borderSide(colors)),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(widget.iconName, size: 20, color: labelColor),
                        const SizedBox(width: AppSpacing.xxs),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xxs,
                          ),
                          child: Text(
                            widget.label,
                            style: AppTypography.labelLarge.copyWith(
                              color: labelColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: -focusRingOutset,
                  top: -focusRingOutset,
                  right: -focusRingOutset,
                  bottom: -focusRingOutset,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOut,
                      opacity: _focused ? 1 : 0,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          shape: StadiumBorder(
                            side: BorderSide(
                              color: _focusRingColor(colors),
                              width: 2,
                              strokeAlign: BorderSide.strokeAlignOutside,
                            ),
                          ),
                        ),
                      ),
                    ),
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
            color: const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: AppIcon(iconName, size: 16, color: colors.text.homeCard),
        ),
      ),
    );
  }
}

class _HomeRecentActivityCard extends StatelessWidget {
  const _HomeRecentActivityCard({
    required this.rows,
    required this.isLoading,
    required this.onTitleTap,
  });

  final List<ActivityRowData> rows;
  final bool isLoading;
  final VoidCallback onTitleTap;

  static const _cardRadius = AppRadii.medium;
  static const _cardPadding = AppSpacing.sm;
  static const _sectionGap = AppSpacing.s;
  static const _headerHeight = 24.0;
  static const _dividerHeight = 1.0;
  static const _listTitleHeight = 24.0;
  static const _listTitleInset = AppSpacing.xxs;
  static const _rowHeight = 44.0;
  static const _rowRadius = AppRadii.small;
  static const _rowHorizontalPadding = AppSpacing.xxs;
  static const _rowIconGap = AppSpacing.xs;
  static const _rowContentGap = AppSpacing.s;
  static const _rowTrailingMaxWidth = 132.0;
  static const _rowAvatarSize = 32.0;
  static const _rowIconSize = 16.0;
  static const _focusRingOutset = 2.0;
  static const _focusRingWidth = 2.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background.base,
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: [
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: colors.shadows.subtle,
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
          BoxShadow(color: colors.shadows.subtle, blurRadius: 1),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HomeRecentActivityTitle(onTap: onTitleTap),
            const SizedBox(height: _sectionGap),
            Container(height: _dividerHeight, color: colors.border.subtle),
            const SizedBox(height: _sectionGap),
            const _HomeRecentActivityListTitle(),
            const SizedBox(height: _sectionGap),
            if (isLoading && rows.isEmpty)
              const _HomeRecentActivityMessage(text: 'Loading activity...')
            else if (rows.isEmpty)
              const _HomeRecentActivityMessage(text: 'No activity yet')
            else
              for (var i = 0; i < rows.length; i++) ...[
                _HomeActivityCompactRow(
                  key: ValueKey('home_recent_activity_row_$i'),
                  row: rows[i],
                ),
                if (i != rows.length - 1) const SizedBox(height: _sectionGap),
              ],
          ],
        ),
      ),
    );
  }
}

class _HomeEmptyActivityState extends StatelessWidget {
  const _HomeEmptyActivityState();

  static const _textBlockWidth = 256.0;
  static const _textBlockHeight = 137.0;
  static const _bodyWidth = 188.0;
  static const _illustrationFrameWidth = 230.0;
  static const _illustrationFrameHeight = 155.0;
  static const _illustrationWidth = 266.0;
  static const _illustrationHeight = 207.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = AppTheme.of(context) == AppThemeData.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _textBlockWidth,
            height: _textBlockHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'No activity, yet...',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                SizedBox(
                  width: _bodyWidth,
                  child: Text(
                    'How about running your first ZEC tx?',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          SizedBox(
            width: _illustrationFrameWidth,
            height: _illustrationFrameHeight,
            child: ClipRect(
              child: OverflowBox(
                minWidth: 0,
                minHeight: 0,
                maxWidth: _illustrationWidth,
                maxHeight: _illustrationHeight,
                alignment: Alignment.center,
                child: Image.asset(
                  isDark
                      ? 'assets/illustrations/home_empty_activity_dark.png'
                      : 'assets/illustrations/home_empty_activity_light.png',
                  width: _illustrationWidth,
                  height: _illustrationHeight,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeRecentActivityTitle extends StatelessWidget {
  const _HomeRecentActivityTitle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: _HomeRecentActivityCard._headerHeight,
      child: Row(
        children: [
          Text(
            'Recent Activity',
            style: AppTypography.labelLarge.copyWith(color: colors.text.accent),
          ),
          const Spacer(),
          AppButton(
            onPressed: onTap,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            trailing: const AppIcon(AppIcons.chevronForward),
            child: const Text('See all'),
          ),
        ],
      ),
    );
  }
}

class _HomeRecentActivityListTitle extends StatelessWidget {
  const _HomeRecentActivityListTitle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _HomeRecentActivityCard._listTitleHeight,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(
            left: _HomeRecentActivityCard._listTitleInset,
          ),
          child: Text(
            'This week',
            style: AppTypography.labelMedium.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeActivityCompactRow extends StatefulWidget {
  const _HomeActivityCompactRow({required this.row, super.key});

  final ActivityRowData row;

  @override
  State<_HomeActivityCompactRow> createState() =>
      _HomeActivityCompactRowState();
}

class _HomeActivityCompactRowState extends State<_HomeActivityCompactRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  void didUpdateWidget(covariant _HomeActivityCompactRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.title != widget.row.title ||
        oldWidget.row.amountText != widget.row.amountText ||
        oldWidget.row.timestampText != widget.row.timestampText) {
      _hovered = false;
      _focused = false;
    }
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() {
      _hovered = value;
    });
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() {
      _focused = value;
    });
  }

  void _activate() {
    _setHovered(false);
    widget.row.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final row = widget.row;
    final isInteractive = row.onTap != null;
    final isInProgress = row.statusText == 'In progress';
    final title = isInProgress ? '${row.title} ...' : row.title;
    final content = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          height: _HomeRecentActivityCard._rowHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: _HomeRecentActivityCard._rowHorizontalPadding,
          ),
          decoration: BoxDecoration(
            color: isInteractive && _hovered ? colors.state.hover : null,
            borderRadius: BorderRadius.circular(
              _HomeRecentActivityCard._rowRadius,
            ),
          ),
          child: Row(
            children: [
              _HomeActivityAvatar(row: row, showLoader: isInProgress),
              const SizedBox(width: _HomeRecentActivityCard._rowIconGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.accent,
                      ),
                    ),
                    if (row.subtitle != null)
                      Row(
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
                                color: colors.text.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: _HomeRecentActivityCard._rowContentGap),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: _HomeRecentActivityCard._rowTrailingMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _HomeActivityAmountLabel(row: row),
                    Text(
                      row.timestampText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (isInteractive && _focused)
          Positioned(
            left: -_HomeRecentActivityCard._focusRingOutset,
            top: -_HomeRecentActivityCard._focusRingOutset,
            right: -_HomeRecentActivityCard._focusRingOutset,
            bottom: -_HomeRecentActivityCard._focusRingOutset,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: colors.state.focusRing,
                    width: _HomeRecentActivityCard._focusRingWidth,
                  ),
                  borderRadius: BorderRadius.circular(
                    _HomeRecentActivityCard._rowRadius +
                        (_HomeRecentActivityCard._focusRingWidth / 2),
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    if (!isInteractive) return content;
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: _setFocused,
          shortcuts: _homeActivityActivationShortcuts,
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
            child: content,
          ),
        ),
      ),
    );
  }
}

class _HomeActivityAmountLabel extends StatelessWidget {
  const _HomeActivityAmountLabel({required this.row});

  final ActivityRowData row;

  @override
  Widget build(BuildContext context) {
    final color = _homeActivityAmountColor(context, row);
    final text = Text(
      row.amountText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.end,
      style: AppTypography.labelLarge.copyWith(color: color),
    );
    final iconName = row.amountIconName;
    if (iconName == null) return text;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(iconName, size: 16, color: row.amountIconColor ?? color),
        const SizedBox(width: AppSpacing.xxs),
        Flexible(child: text),
      ],
    );
  }
}

class _HomeActivityAvatar extends StatelessWidget {
  const _HomeActivityAvatar({required this.row, required this.showLoader});

  final ActivityRowData row;
  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    final iconName = showLoader ? AppIcons.loader : row.leadingIconName;
    return SizedBox(
      width: _HomeRecentActivityCard._rowAvatarSize,
      height: _HomeRecentActivityCard._rowAvatarSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: row.leadingBackgroundColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: AppIcon(
            iconName,
            size: _HomeRecentActivityCard._rowIconSize,
            color: row.leadingIconColor,
          ),
        ),
      ),
    );
  }
}

class _HomeRecentActivityMessage extends StatelessWidget {
  const _HomeRecentActivityMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(
          text,
          style: AppTypography.labelLarge.copyWith(
            color: context.colors.text.secondary,
          ),
        ),
      ),
    );
  }
}

Color _homeActivityAmountColor(BuildContext context, ActivityRowData row) {
  final colors = context.colors;
  if (row.statusText == 'Failed') return colors.text.destructive;
  if (row.statusText == 'In progress' &&
      row.title != 'Receiving' &&
      row.title != 'Received') {
    return colors.text.primary;
  }
  if (row.amountText.trimLeft().startsWith('+')) {
    return colors.text.positiveStrong;
  }
  return colors.text.primary;
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
