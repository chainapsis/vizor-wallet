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
import '../../../../providers/account_provider.dart';
import '../../../../providers/privacy_mode_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../accounts/widgets/mobile/mobile_accounts_sheet.dart';
import '../../../activity/activity_feed_sections.dart';
import '../../../activity/activity_row_mapper.dart';
import '../../../activity/screens/mobile/mobile_transaction_status_screen.dart';
import '../../../activity/swap_activity_row_items_provider.dart';
import '../../../activity/swap_activity_row_mapper.dart';
import '../../../activity/widgets/activity_feed.dart';
import '../../../swap/models/swap_activity_navigation.dart';
import '../../../swap/widgets/swap_activity_status_auto_refresh.dart';

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
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Builder(
              builder: (context) => MobileTopNavAccount(
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
    );
  }
}

class _HomeContent extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final shieldedBalance =
        sync.saplingBalance +
        sync.orchardBalance +
        sync.saplingPendingBalance +
        sync.orchardPendingBalance;
    final hasBalance = shieldedBalance > BigInt.zero;

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
          privacyModeEnabled: privacyModeEnabled,
          onTogglePrivacyMode: onTogglePrivacyMode,
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
            variant: AppButtonVariant.secondary,
            onPressed: () => context.push('/receive'),
            leading: const _ButtonIcon(AppIcons.addNew),
            child: const Text('Receive your first ZEC'),
          ),
        const SizedBox(height: AppSpacing.md),
        if (recentRows.isEmpty)
          const _EmptyActivity()
        else
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
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
    required this.privacyModeEnabled,
    required this.onTogglePrivacyMode,
  });

  final String balanceText;
  final bool privacyModeEnabled;
  final VoidCallback onTogglePrivacyMode;

  // TODO(pricing): live fiat value and 24h change need a price feed
  // that desktop doesn't have yet either; design-literal placeholder
  // until that lands as separate work.
  static const _fiatPlaceholder = '\$1,200.12';
  static const _changePlaceholder = ' + 13.12% (24h)';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardText = colors.text.homeCard;

    return Container(
      height: 200,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background.homeCard,
        borderRadius: BorderRadius.circular(AppRadii.large),
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
              AppIcon(AppIcons.shieldKeyhole, size: 20, color: cardText),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Shielded balance',
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
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
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _fiatPlaceholder,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: cardText.withValues(alpha: 0.8),
                  ),
                ),
                TextSpan(
                  text: _changePlaceholder,
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.text.positiveStrong,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text.rich(
            key: const ValueKey('mobile_home_shielded_balance'),
            TextSpan(
              children: [
                TextSpan(
                  text: '$balanceText ',
                  style: AppTypography.displayLarge.copyWith(color: cardText),
                ),
                TextSpan(
                  text: kZcashDefaultCurrencyTicker,
                  style: AppTypography.headlineLarge.copyWith(color: cardText),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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
          // 40 px disc, a step lighter than the card (#393C3C on
          // #2E3232), per the Figma privacy toggle.
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.06),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: AppIcon(
              AppIcons.eye,
              size: 18,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Recent activity',
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSeeAll,
            child: Row(
              children: [
                Text(
                  'See all',
                  style: AppTypography.labelMedium.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                AppIcon(
                  AppIcons.chevronForward,
                  size: AppIconSize.medium,
                  color: colors.icon.muted,
                ),
              ],
            ),
          ),
        ],
      ),
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
        const SizedBox(height: AppSpacing.base),
        Text(
          'No activity, yet...',
          style: AppTypography.headlineSmall.copyWith(
            color: colors.text.accent,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'How about running your\nfirst ZEC tx?',
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Image.asset(
          'assets/illustrations/home_rest_character.png',
          width: 280,
          fit: BoxFit.contain,
        ),
      ],
    );
  }
}

/// Full-tab importing state — Figma `Importing` (4394:88886).
class _ImportingView extends StatelessWidget {
  const _ImportingView({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        children: [
          const Spacer(),
          Text(
            '${formatSyncStatusPercentage(progress)}%',
            style: AppTypography.displayLarge.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            "We're importing\nyour wallet...",
            textAlign: TextAlign.center,
            style: AppTypography.headlineMedium.copyWith(
              color: colors.text.accent,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Hang tight ... It might take some\ntime. Keep Vizor open & running.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Image.asset(
            'assets/illustrations/home_rest_character.png',
            width: 240,
            fit: BoxFit.contain,
          ),
          const Spacer(),
          const SizedBox(height: kMobileTabBarHeight),
        ],
      ),
    );
  }
}
