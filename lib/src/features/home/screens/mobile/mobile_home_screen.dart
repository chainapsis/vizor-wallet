import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/formatting/sync_status_label.dart';
import '../../../../core/config/network_config.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/app_mobile_tab_bar.dart';
import '../../../../core/layout/mobile/mobile_top_nav_account.dart';
import '../../../../core/layout/mobile/mobile_top_scroll_fade.dart';
import '../../../../core/privacy/privacy_mask.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/privacy_mode_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../providers/zec_price_change_provider.dart';
import '../../../accounts/widgets/mobile/mobile_accounts_sheet.dart';
import '../../../activity/activity_feed_sections.dart';
import '../../../activity/activity_row_mapper.dart';
import '../../../activity/screens/mobile/mobile_transaction_status_screen.dart';
import '../../../activity/swap_activity_row_items_provider.dart';
import '../../../activity/swap_activity_row_mapper.dart';
import '../../../activity/widgets/activity_feed.dart';
import '../../../swap/models/swap_activity_navigation.dart';
import '../../../swap/widgets/swap_activity_status_auto_refresh.dart';
import '../../services/transparent_shielding_service.dart';
import 'mobile_keystone_shield_screen.dart';

/// Mobile home tab: shielded balance card, send/receive actions, and
/// up to ten recent activity rows — Figma `HOME` section frames
/// `Home Default` (4394:88353), `Home NO Activity NO Balance`
/// (4394:90024), and `Importing` (4394:88886).
class MobileHomeScreen extends ConsumerWidget {
  const MobileHomeScreen({super.key});

  static const _recentActivityLimit = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountState = ref.watch(accountProvider).value;
    final activeAccountUuid = accountState?.activeAccountUuid;
    final sync = (ref.watch(syncProvider).value ?? SyncState()).scopedToAccount(
      activeAccountUuid,
    );
    final privacyModeEnabled = ref.watch(privacyModeProvider);

    final isImporting =
        activeAccountUuid != null &&
        !sync.hasAccountScopedData &&
        sync.failure == null;

    return SwapActivityStatusAutoRefresh(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isImporting) const _ImportingBackground(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Builder(
                  builder: (context) => MobileTopNavAccount(
                    showSyncStatus: !isImporting,
                    onAccountTap: () => showMobileAccountsSheet(context),
                  ),
                ),
                Expanded(
                  // VZR-74: dissolve scrolled content under the top nav
                  // with a soft eased fade instead of a hard clip line.
                  child: MobileTopScrollFade(
                    child: isImporting
                        ? _ImportingView(progress: sync.displayPercentage)
                        : _HomeContent(
                            sync: sync,
                            activeAccountUuid: activeAccountUuid,
                            privacyModeEnabled: privacyModeEnabled,
                            onTogglePrivacyMode: () =>
                                ref.read(privacyModeProvider.notifier).toggle(),
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

const _mobileHomeLabelMStyle = TextStyle(
  fontFamily: 'Geist',
  fontWeight: FontWeight.w400,
  fontSize: 14,
  height: 16 / 14,
  letterSpacing: -0.06,
);

const _mobileHomeBalanceAmountStyle = TextStyle(
  fontFamily: 'Young Serif',
  fontWeight: FontWeight.w400,
  fontSize: 45,
  height: 48 / 45,
  letterSpacing: -1.35,
  fontFeatures: [FontFeature.enable('case')],
);

const _mobileHomeBalanceTickerStyle = TextStyle(
  fontFamily: 'Young Serif',
  fontWeight: FontWeight.w400,
  fontSize: 32,
  height: 33 / 32,
  letterSpacing: -1.35,
  fontFeatures: [FontFeature.enable('case')],
);

const _mobileHomeActionButtonHeight = AppButtonSizing.largeHeight;

class _ImportingBackground extends StatelessWidget {
  const _ImportingBackground();

  @override
  Widget build(BuildContext context) {
    final isDark = context.appTheme == AppThemeData.dark;
    final assetName = isDark
        ? 'assets/illustrations/home_importing_background_dark.png'
        : 'assets/illustrations/home_importing_background_light.png';

    return Positioned.fill(
      child: Align(
        alignment: Alignment.topCenter,
        child: Image.asset(
          assetName,
          key: const ValueKey('mobile_home_importing_background'),
          width: 1080,
          height: 720,
          fit: BoxFit.fill,
        ),
      ),
    );
  }
}

class _HomeContent extends ConsumerStatefulWidget {
  const _HomeContent({
    required this.sync,
    required this.activeAccountUuid,
    required this.privacyModeEnabled,
    required this.onTogglePrivacyMode,
  });

  final SyncState sync;
  final String? activeAccountUuid;
  final bool privacyModeEnabled;
  final VoidCallback onTogglePrivacyMode;

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent> {
  bool _isShieldingBalance = false;

  Future<void> _shieldTransparentBalance() async {
    if (_isShieldingBalance) return;

    late final String accountUuid;
    try {
      accountUuid = activeShieldingAccountUuid(ref);
    } catch (_) {
      _showShieldToast('No active account.');
      return;
    }

    final accountNotifier = ref.read(accountProvider.notifier);
    if (accountNotifier.isHardwareAccount(accountUuid)) {
      final result = await context.push<MobileKeystoneShieldResult>(
        '/home/keystone-shield',
      );
      if (!mounted || result == null) return;
      final message = result.message;
      if (message != null && message.isNotEmpty) {
        _showShieldToast(message);
      } else if (result.succeeded) {
        showAppToast(context, 'Shielding complete');
      }
      return;
    }

    setState(() => _isShieldingBalance = true);
    try {
      final result = await shieldTransparentSoftwareBalance(
        ref: ref,
        accountUuid: accountUuid,
        logContext: 'MobileHome',
      );
      if (!mounted) return;
      final warning = shieldBalanceBroadcastStatusMessage(result);
      if (warning != null) {
        _showShieldToast(warning);
      } else {
        showAppToast(context, 'Shielding complete');
      }
    } catch (e) {
      if (!mounted) return;
      _showShieldToast(friendlyShieldBalanceError(e));
    } finally {
      if (mounted) {
        setState(() => _isShieldingBalance = false);
      }
    }
  }

  void _showShieldToast(String message) {
    showAppToast(context, message, iconName: AppIcons.warning);
  }

  @override
  Widget build(BuildContext context) {
    final sync = widget.sync;
    final activeAccountUuid = widget.activeAccountUuid;
    final privacyModeEnabled = widget.privacyModeEnabled;
    final shieldedBalance =
        sync.saplingBalance +
        sync.orchardBalance +
        sync.saplingPendingBalance +
        sync.orchardPendingBalance;
    final transparentBalance =
        sync.transparentBalance + sync.transparentPendingBalance;
    final hasBalance =
        shieldedBalance > BigInt.zero || transparentBalance > BigInt.zero;
    final zecUsdUnitPrice = ref.watch(zecHomeUsdUnitPriceProvider);
    final fiatBalanceText = fiatTextForZatoshi(
      shieldedBalance,
      zecUsdUnitPrice: zecUsdUnitPrice,
    );
    final shieldedFiatBalanceText =
        privacyModeEnabled && fiatBalanceText != null
        ? fixedPrivacyMask()
        : fiatBalanceText;
    final priceChange24hPct = ref.watch(zecPriceChange24hPctProvider);

    final uuid = activeAccountUuid;
    final swapItems = uuid == null
        ? const <SwapActivityRowItem>[]
        : ref.watch(swapActivityRowItemsProvider(uuid)).value ??
              const <SwapActivityRowItem>[];
    final entries = <ActivityEntry>[
      for (final tx in sync.recentTransactions)
        ActivityEntry(
          timestamp: transactionActivityTimestamp(tx),
          row: buildTransactionActivityRow(
            context: context,
            transaction: tx,
            privacyModeEnabled: privacyModeEnabled,
            dateOnlyTimestamp: true,
            onTap: () => context.push(
              Uri(
                path: '/activity/tx/${tx.txidHex}',
                queryParameters: {'kind': tx.txKind},
              ).toString(),
              extra: MobileTransactionStatusArgs(
                txidHex: tx.txidHex,
                txKind: tx.txKind,
                initialTransaction: tx,
              ),
            ),
          ),
        ),
      for (final item in swapItems)
        ActivityEntry(
          timestamp: item.activityTimestamp,
          row: buildSwapActivityRow(
            context: context,
            item: item,
            privacyModeEnabled: privacyModeEnabled,
            dateOnlyTimestamp: true,
            onTap: () => context.push(
              swapActivityDetailUri(
                intentId: item.intentId,
                returnTarget: SwapActivityReturnTarget.home,
              ).toString(),
            ),
          ),
        ),
    ]..sort(compareActivityEntries);
    final recentRows = [
      for (final entry in entries.take(MobileHomeScreen._recentActivityLimit))
        entry.row,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.s,
        AppSpacing.sm,
        kMobileTabBarHeight + AppSpacing.lg,
      ),
      children: [
        _BalanceCard(
          balanceText: privacyModeEnabled
              ? fixedPrivacyMask()
              : ZecAmount.fromZatoshi(shieldedBalance).balance.amountText,
          fiatBalanceText: shieldedFiatBalanceText,
          priceChange24hPct: priceChange24hPct,
          transparentBalanceText: ZecAmount.fromZatoshi(
            transparentBalance,
          ).balance.amountText,
          hasTransparentBalance: transparentBalance > BigInt.zero,
          canShieldBalance: sync.canShieldTransparentBalance,
          isShieldingBalance: _isShieldingBalance,
          privacyModeEnabled: privacyModeEnabled,
          onTogglePrivacyMode: widget.onTogglePrivacyMode,
          onShieldBalancePressed: () => unawaited(_shieldTransparentBalance()),
        ),
        const SizedBox(height: AppSpacing.s),
        if (hasBalance)
          Row(
            children: [
              Expanded(
                child: AppButton(
                  key: const ValueKey('mobile_home_send'),
                  expand: true,
                  onPressed: () => context.push('/send'),
                  leading: const _ButtonIcon(AppIcons.plane),
                  height: _mobileHomeActionButtonHeight,
                  child: const Text('Send'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton(
                  key: const ValueKey('mobile_home_receive'),
                  expand: true,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => context.push('/receive'),
                  leading: const _ButtonIcon(AppIcons.arrowDownCircle),
                  height: _mobileHomeActionButtonHeight,
                  child: const Text('Receive'),
                ),
              ),
            ],
          )
        else
          AppButton(
            // Same key as the funded-state Receive button — only one of
            // the two renders at a time.
            key: const ValueKey('mobile_home_receive'),
            expand: true,
            constrainContent: true,
            onPressed: () => context.push('/receive'),
            leading: const _ButtonIcon(AppIcons.addNew),
            height: _mobileHomeActionButtonHeight,
            child: const Text(
              'Receive your first ZEC',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        if (recentRows.isEmpty)
          const _EmptyActivity()
        else
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.s,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RecentActivityHeader(onSeeAll: () => context.go('/activity')),
                const SizedBox(height: AppSpacing.md),
                for (var i = 0; i < recentRows.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.s),
                  KeyedSubtree(
                    key: ValueKey('mobile_home_activity_row_$i'),
                    child: ActivityFeedRowGroup(row: recentRows[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// The dark shielded-balance card — Figma `Full Width Card`
/// (4394:88394): 200px tall, home-card surface, chip + privacy eye on
/// top, fiat line and serif ZEC balance at the bottom.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balanceText,
    required this.fiatBalanceText,
    required this.priceChange24hPct,
    required this.transparentBalanceText,
    required this.hasTransparentBalance,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.privacyModeEnabled,
    required this.onTogglePrivacyMode,
    required this.onShieldBalancePressed,
  });

  final String balanceText;
  final String? fiatBalanceText;
  final double? priceChange24hPct;
  final String transparentBalanceText;
  final bool hasTransparentBalance;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final bool privacyModeEnabled;
  final VoidCallback onTogglePrivacyMode;
  final VoidCallback onShieldBalancePressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardText = colors.text.homeCard;
    final cardRadius = BorderRadius.circular(AppRadii.large);
    final roundedPriceChangePct = priceChange24hPct == null
        ? null
        : roundZecPriceChange24hPct(priceChange24hPct!);
    final priceChangeColor = roundedPriceChangePct == null
        ? null
        : roundedPriceChangePct > 0
        ? colors.text.positiveStrong
        : roundedPriceChangePct < 0
        ? colors.text.destructive
        : cardText;

    return Container(
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: cardRadius,
        boxShadow: appSurfaceShadow(colors),
      ),
      child: ClipRRect(
        borderRadius: cardRadius,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 200,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.background.homeCard,
                borderRadius: cardRadius,
                border: Border.all(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.07),
                  width: 1.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppIcon(
                        AppIcons.shieldKeyhole,
                        size: 20,
                        color: cardText,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'Shielded balance',
                          style: _mobileHomeLabelMStyle.copyWith(
                            color: cardText,
                          ),
                        ),
                      ),
                      _PrivacyEyeButton(
                        enabled: privacyModeEnabled,
                        onTap: onTogglePrivacyMode,
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (fiatBalanceText != null) ...[
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            fiatBalanceText!,
                            key: const ValueKey(
                              'mobile_home_balance_fiat_text',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _mobileHomeLabelMStyle.copyWith(
                              color: cardText.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        if (priceChangeColor != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            formatZecPriceChange24hPct(priceChange24hPct!),
                            key: const ValueKey(
                              'mobile_home_balance_price_change_text',
                            ),
                            style: _mobileHomeLabelMStyle.copyWith(
                              color: priceChangeColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  Text.rich(
                    key: const ValueKey('mobile_home_shielded_balance'),
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$balanceText ',
                          style: _mobileHomeBalanceAmountStyle.copyWith(
                            color: cardText,
                          ),
                        ),
                        TextSpan(
                          text: kZcashDefaultCurrencyTicker,
                          style: _mobileHomeBalanceTickerStyle.copyWith(
                            color: cardText,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (hasTransparentBalance)
              _MobileTransparentBalanceStrip(
                key: const ValueKey('mobile_home_transparent_balance_strip'),
                balanceText: transparentBalanceText,
                canShieldBalance: canShieldBalance,
                isShieldingBalance: isShieldingBalance,
                privacyModeEnabled: privacyModeEnabled,
                onShieldBalancePressed: onShieldBalancePressed,
              ),
          ],
        ),
      ),
    );
  }
}

class _MobileTransparentBalanceStrip extends StatelessWidget {
  const _MobileTransparentBalanceStrip({
    required this.balanceText,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.privacyModeEnabled,
    required this.onShieldBalancePressed,
    super.key,
  });

  final String balanceText;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final bool privacyModeEnabled;
  final VoidCallback onShieldBalancePressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayedBalance = hideAmountIfPrivacyMode(
      '$balanceText $kZcashDefaultCurrencyTicker',
      privacyModeEnabled: privacyModeEnabled,
    );

    return SizedBox(
      height: 57,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    AppIcons.transparentBalance,
                    size: 20,
                    color: colors.text.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      'Transparent: $displayedBalance',
                      key: const ValueKey(
                        'mobile_home_transparent_balance_text',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _mobileHomeLabelMStyle.copyWith(
                        color: colors.text.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (canShieldBalance || isShieldingBalance)
              _MobileShieldBalanceButton(
                enabled: canShieldBalance,
                isLoading: isShieldingBalance,
                onPressed: onShieldBalancePressed,
              ),
          ],
        ),
      ),
    );
  }
}

class _MobileShieldBalanceButton extends StatelessWidget {
  const _MobileShieldBalanceButton({
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
    final contentColor = isLoading || enabled
        ? colors.text.accent
        : colors.text.secondary.withValues(alpha: 0.64);

    return Semantics(
      key: const ValueKey('mobile_home_shield_balance_button'),
      button: true,
      enabled: isInteractive,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isInteractive ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxs,
            vertical: AppSpacing.s,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isLoading ? 'Shielding...' : 'Shield',
                style: _mobileHomeLabelMStyle.copyWith(color: contentColor),
              ),
              const SizedBox(width: AppSpacing.xxs),
              AppIcon(
                isLoading ? AppIcons.loader : AppIcons.chevronForward,
                size: 16,
                color: contentColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyEyeButton extends StatelessWidget {
  const _PrivacyEyeButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: enabled ? 'Show balance' : 'Hide balance',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          unawaited(AppHaptics.privacyToggle());
          onTap();
        },
        child: Container(
          key: const ValueKey('mobile_home_privacy_button'),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Center(
            child: AppIcon(
              enabled ? AppIcons.eyeClosed : AppIcons.eye,
              size: 16,
              color: context.colors.text.homeCard,
            ),
          ),
        ),
      ),
    );
  }
}

class _ButtonIcon extends StatelessWidget {
  const _ButtonIcon(this.iconName);

  final String iconName;

  @override
  Widget build(BuildContext context) {
    return AppIcon(iconName, size: 20);
  }
}

class _RecentActivityHeader extends StatelessWidget {
  const _RecentActivityHeader({required this.onSeeAll});

  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Recent activity',
            style: AppTypography.labelLarge.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSeeAll,
            child: SizedBox(
              height: 24,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See all',
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.button.ghost.label,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    AppIcon(
                      AppIcons.chevronForward,
                      size: AppIconSize.medium,
                      color: colors.button.ghost.label,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
        Text(
          'No activity, yet...',
          style: AppTypography.headlineSmall.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          'How about running your\nfirst ZEC tx?',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const _MobileRestImage(),
      ],
    );
  }
}

class _MobileRestImage extends StatelessWidget {
  const _MobileRestImage();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('mobile_home_rest_canvas'),
      width: 340,
      height: 220,
      child: Stack(
        children: [
          Positioned(
            left: 47,
            top: 28,
            child: Image.asset(
              'assets/illustrations/home_rest_character.png',
              key: const ValueKey('mobile_home_rest_image'),
              width: 246,
              height: 192,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-tab importing state — Figma `Importing` (4394:88886).
class _ImportingView extends StatelessWidget {
  const _ImportingView({required this.progress});

  static const _horizontalPadding = AppSpacing.sm;
  static const _topGap = AppSpacing.sm;
  static const _contentToRestGap = AppSpacing.lg;

  // AppMobileShell floats the 64px nav over the body with a 16px bottom gap.
  // Figma then leaves 16px between content and nav plus 12px inside the
  // importing panel, so the Rest illustration clears the nav instead of
  // sitting underneath it.
  static const _bottomClearance =
      kMobileTabBarHeight + AppSpacing.sm + AppSpacing.sm + AppSpacing.s;

  static const _titleStyle = TextStyle(
    fontFamily: 'Young Serif',
    fontWeight: FontWeight.w400,
    fontSize: 24,
    height: 28 / 24,
    letterSpacing: -0.4,
    fontFeatures: [FontFeature.liningFigures()],
  );

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${formatSyncStatusPercentage(progress)}%',
          style: AppTypography.displayLarge.copyWith(color: colors.text.accent),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 246,
          child: Text(
            "We're importing your wallet...",
            textAlign: TextAlign.center,
            style: _titleStyle.copyWith(color: colors.text.accent),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 247,
          child: Text(
            'Hang tight ... It might take some time. Keep Vizor open & running.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
        const SizedBox(height: _contentToRestGap),
        const _MobileRestImage(),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _horizontalPadding,
        _topGap,
        _horizontalPadding,
        _bottomClearance,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Align(alignment: Alignment.bottomCenter, child: content),
            ),
          );
        },
      ),
    );
  }
}
