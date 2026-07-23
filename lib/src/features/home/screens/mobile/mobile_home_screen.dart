import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/swap_feature_config.dart';
import '../../../../core/feedback/app_haptics.dart';
import '../../../../core/formatting/sync_status_label.dart';
import '../../../../core/config/network_config.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../../core/layout/mobile/app_mobile_tab_bar.dart';
import '../../../../core/layout/mobile/mobile_top_nav_account.dart';
import '../../../../core/layout/mobile/mobile_top_scroll_fade.dart';
import '../../../../core/privacy/privacy_mask.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/primitives.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/privacy_mode_provider.dart';
import '../../../../providers/sync_keep_awake_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../providers/zec_price_change_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../accounts/widgets/mobile/mobile_accounts_sheet.dart';
import '../../../activity/activity_feed_sections.dart';
import '../../../activity/activity_row_mapper.dart';
import '../../../activity/screens/mobile/mobile_transaction_status_screen.dart';
import '../../../activity/swap_activity_row_items_provider.dart';
import '../../../activity/swap_activity_row_mapper.dart';
import '../../../activity/widgets/activity_feed.dart';
import '../../../migration/providers/ironwood_migration_announcement_provider.dart';
import '../../../migration/widgets/mobile/mobile_ironwood_migration_announcement_sheet.dart';
import '../../../migration/widgets/mobile/mobile_ironwood_migration_complete_sheet.dart';
import '../../../swap/models/swap_activity_navigation.dart';
import '../../../swap/providers/swap_state_provider.dart';
import '../../../swap/widgets/swap_activity_status_auto_refresh.dart';
import '../../services/pay_introduction_badge_store.dart';
import '../../services/transparent_shielding_service.dart';
import '../../widgets/pay_floating_badge.dart';
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
    final ironwoodMigrationCta = ref.watch(
      ironwoodHomeMigrationPresentationProvider,
    );

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
                const SizedBox(height: AppSpacing.s),
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
                            ironwoodMigrationCta: ironwoodMigrationCta,
                            onTogglePrivacyMode: () =>
                                ref.read(privacyModeProvider.notifier).toggle(),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const _SyncKeepAwakePromptHost(),
          const _IronwoodMigrationAnnouncementHost(),
          const _IronwoodMigrationCompletionHost(),
        ],
      ),
    );
  }
}

enum _IronwoodAnnouncementAction { startMigration }

class _IronwoodMigrationAnnouncementHost extends ConsumerStatefulWidget {
  const _IronwoodMigrationAnnouncementHost();

  @override
  ConsumerState<_IronwoodMigrationAnnouncementHost> createState() =>
      _IronwoodMigrationAnnouncementHostState();
}

class _IronwoodMigrationAnnouncementHostState
    extends ConsumerState<_IronwoodMigrationAnnouncementHost> {
  bool _showing = false;
  String? _shownFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _evaluate(ref.read(ironwoodMigrationAnnouncementProvider).value);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ironwoodMigrationAnnouncementProvider, (_, next) {
      _evaluate(next.value);
    });
    return const SizedBox.shrink();
  }

  void _evaluate(IronwoodMigrationAnnouncementState? announcement) {
    if (announcement == null || !announcement.visible || _showing) return;
    final network = announcement.network;
    final accountUuid = announcement.accountUuid;
    if (network == null || accountUuid == null) return;
    final key = '$network:$accountUuid';
    if (_shownFor == key) return;
    _shownFor = key;
    unawaited(_show(announcement));
  }

  Future<void> _show(IronwoodMigrationAnnouncementState announcement) async {
    _showing = true;
    try {
      final action = await showAppMobileSheet<_IronwoodAnnouncementAction>(
        context: context,
        builder: (sheetContext) => MobileIronwoodMigrationAnnouncementSheet(
          onStartMigration: () => Navigator.of(
            sheetContext,
          ).pop(_IronwoodAnnouncementAction.startMigration),
          onOpenReleaseNotes: () => unawaited(_openReleaseNotes()),
        ),
      );
      if (!mounted) return;
      if (action == _IronwoodAnnouncementAction.startMigration) {
        context.push('/migration/intro');
      }
      await _markSeen(announcement);
    } finally {
      _showing = false;
    }
  }

  Future<void> _markSeen(
    IronwoodMigrationAnnouncementState announcement,
  ) async {
    final network = announcement.network;
    final accountUuid = announcement.accountUuid;
    if (network == null || accountUuid == null) return;
    try {
      await ref
          .read(ironwoodMigrationAnnouncementStoreProvider)
          .markSeen(network: network, accountUuid: accountUuid);
    } catch (_) {
      return;
    }
    if (mounted) ref.invalidate(ironwoodMigrationAnnouncementProvider);
  }

  Future<void> _openReleaseNotes() async {
    final uri = Uri.parse(kIronwoodMigrationReleaseNotesUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // The announcement remains open so the user can retry.
    }
  }
}

class _IronwoodMigrationCompletionHost extends ConsumerStatefulWidget {
  const _IronwoodMigrationCompletionHost();

  @override
  ConsumerState<_IronwoodMigrationCompletionHost> createState() =>
      _IronwoodMigrationCompletionHostState();
}

class _IronwoodMigrationCompletionHostState
    extends ConsumerState<_IronwoodMigrationCompletionHost> {
  bool _showing = false;
  String? _shownFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _evaluate(ref.read(ironwoodMigrationCompletionProvider).value);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ironwoodMigrationCompletionProvider, (_, next) {
      _evaluate(next.value);
    });
    return const SizedBox.shrink();
  }

  void _evaluate(IronwoodMigrationCompletionState? completion) {
    if (completion == null || !completion.visible || _showing) return;
    final network = completion.network;
    final accountUuid = completion.accountUuid;
    final completionId = completion.completionId;
    final transferredZatoshi = completion.transferredZatoshi;
    if (network == null ||
        accountUuid == null ||
        completionId == null ||
        transferredZatoshi == null) {
      return;
    }
    final key = '$network:$accountUuid:$completionId';
    if (_shownFor == key) return;
    _shownFor = key;
    unawaited(_show(completion, transferredZatoshi));
  }

  Future<void> _show(
    IronwoodMigrationCompletionState completion,
    BigInt transferredZatoshi,
  ) async {
    _showing = true;
    try {
      final acknowledged = await showAppMobileSheet<bool>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        builder: (sheetContext) => MobileIronwoodMigrationCompleteSheet(
          transferredZatoshi: transferredZatoshi,
          onDone: () => Navigator.of(sheetContext).pop(true),
        ),
      );
      if (!mounted || acknowledged != true) return;
      await _markSeen(completion);
    } finally {
      _showing = false;
    }
  }

  Future<void> _markSeen(IronwoodMigrationCompletionState completion) async {
    final network = completion.network;
    final accountUuid = completion.accountUuid;
    final completionId = completion.completionId;
    if (network == null || accountUuid == null || completionId == null) return;
    try {
      await ref
          .read(ironwoodMigrationCompletionStoreProvider)
          .markSeen(
            network: network,
            accountUuid: accountUuid,
            completionId: completionId,
          );
    } catch (_) {
      return;
    }
    if (mounted) ref.invalidate(ironwoodMigrationCompletionProvider);
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

class _SyncKeepAwakePromptHost extends ConsumerStatefulWidget {
  const _SyncKeepAwakePromptHost();

  @override
  ConsumerState<_SyncKeepAwakePromptHost> createState() =>
      _SyncKeepAwakePromptHostState();
}

class _SyncKeepAwakePromptHostState
    extends ConsumerState<_SyncKeepAwakePromptHost> {
  SyncKeepAwakeEtaSample? _etaSample;
  DateTime? _promptRequestedForRun;
  var _showingPrompt = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _evaluateCurrentSync();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(syncProvider, (_, next) {
      final sync = next.asData?.value;
      if (sync != null) _evaluateSync(sync);
    });
    ref.listen(syncKeepAwakeProvider, (previous, next) {
      _evaluateCurrentSync();
    });

    return const SizedBox.shrink();
  }

  void _evaluateCurrentSync() {
    final sync = ref.read(syncProvider).value;
    if (sync != null) _evaluateSync(sync);
  }

  void _evaluateSync(SyncState sync) {
    if (!sync.isSyncing ||
        sync.lastSyncStartedAt != _etaSample?.syncStartedAt) {
      _etaSample = null;
    }

    final estimate = estimateSyncKeepAwakeEta(
      sync,
      now: DateTime.now(),
      previousSample: _etaSample,
    );
    if (estimate.sample != null) {
      _etaSample = estimate.sample;
    }

    final startedAt = sync.lastSyncStartedAt;
    if (_showingPrompt ||
        startedAt == null ||
        _promptRequestedForRun == startedAt) {
      return;
    }
    final settings = ref.read(syncKeepAwakeProvider);
    if (settings.enabled ||
        settings.promptSeen ||
        estimate.remaining == null ||
        estimate.remaining! < kSyncKeepAwakePromptEtaThreshold) {
      return;
    }

    _promptRequestedForRun = startedAt;
    unawaited(_showPrompt());
  }

  Future<void> _showPrompt() async {
    _showingPrompt = true;
    try {
      await ref.read(syncKeepAwakeProvider.notifier).markPromptSeen();
      if (!mounted) return;
      final enableKeepAwake = await showAppMobileSheet<bool>(
        context: context,
        builder: (sheetContext) => _SyncKeepAwakePromptSheet(
          onKeepAwake: () => Navigator.of(sheetContext).pop(true),
          onMaybeLater: () => Navigator.of(sheetContext).pop(false),
        ),
      );
      if (!mounted || enableKeepAwake != true) return;
      await ref
          .read(syncKeepAwakeProvider.notifier)
          .setEnabled(true, markPromptSeen: false);
    } finally {
      if (mounted) {
        setState(() => _showingPrompt = false);
      } else {
        _showingPrompt = false;
      }
    }
  }
}

class _SyncKeepAwakePromptSheet extends StatelessWidget {
  const _SyncKeepAwakePromptSheet({
    required this.onKeepAwake,
    required this.onMaybeLater,
  });

  final VoidCallback onKeepAwake;
  final VoidCallback onMaybeLater;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bodyStyle = AppTypography.bodyMedium.copyWith(
      color: colors.text.accent,
    );

    return MobileModalScaffold(
      key: const ValueKey('mobile_sync_keep_awake_prompt_sheet'),
      title: 'Stay awake to sync?',
      onClose: onMaybeLater,
      bodyGap: AppSpacing.xxs,
      bottomPadding: AppSpacing.base,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your phone pauses syncing when screen is off. This allows sync '
            'to finish faster.',
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SyncKeepAwakePromptBullet(
                iconName: AppIcons.lock,
                text:
                    'The app locks after 1 minute of inactivity. Syncing '
                    'continues behind the lock.',
                textStyle: bodyStyle,
              ),
              const SizedBox(height: AppSpacing.xs),
              _SyncKeepAwakePromptBullet(
                iconName: AppIcons.cog,
                text: 'You can change this anytime in the Settings.',
                textStyle: bodyStyle.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            key: const ValueKey('mobile_sync_keep_awake_prompt_enable'),
            expand: true,
            constrainContent: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
            ),
            leading: const AppIcon(AppIcons.day),
            onPressed: onKeepAwake,
            child: const Text(
              'Keep screen awake',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          AppButton(
            key: const ValueKey('mobile_sync_keep_awake_prompt_later'),
            variant: AppButtonVariant.ghost,
            expand: true,
            constrainContent: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
            ),
            onPressed: onMaybeLater,
            child: const Text(
              'Maybe later',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncKeepAwakePromptBullet extends StatelessWidget {
  const _SyncKeepAwakePromptBullet({
    required this.iconName,
    required this.text,
    required this.textStyle,
  });

  final String iconName;
  final String text;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 32,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Center(
              child: AppIcon(
                iconName,
                size: 20,
                color: context.colors.icon.accent,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(child: Text(text, style: textStyle)),
      ],
    );
  }
}

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
    required this.ironwoodMigrationCta,
    required this.onTogglePrivacyMode,
  });

  final SyncState sync;
  final String? activeAccountUuid;
  final bool privacyModeEnabled;
  final IronwoodHomeMigrationCtaState ironwoodMigrationCta;
  final VoidCallback onTogglePrivacyMode;

  @override
  ConsumerState<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends ConsumerState<_HomeContent> {
  bool _isShieldingBalance = false;

  Future<void> _openPay() async {
    final accountUuid = ref
        .read(accountProvider)
        .value
        ?.activeAccountUuid
        ?.trim();
    if (accountUuid == null || accountUuid.isEmpty) return;

    final router = GoRouter.of(context);
    final swapNotifier = ref.read(swapStateProvider.notifier);
    final selectedAssetFuture = swapNotifier.resolvePaySelectedAssetForEntry(
      accountUuid: accountUuid,
    );
    ref.read(payIntroductionBadgeClickedProvider.notifier).markClicked();

    final selectedAsset = await selectedAssetFuture;
    if (!mounted ||
        selectedAsset == null ||
        router.routerDelegate.currentConfiguration.uri.path != '/home') {
      return;
    }
    final prepared = swapNotifier.preparePayFromShieldedZec(
      preferredAsset: selectedAsset,
      expectedAccountUuid: accountUuid,
    );
    if (!prepared) return;
    router.push(
      '/pay',
      extra: const PayComposerNavigationArgs(preservePreparedComposer: true),
    );
  }

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
    final migrationRequired =
        widget.ironwoodMigrationCta.mode == IronwoodHomeMigrationCtaMode.start;
    final migrationInProgress =
        widget.ironwoodMigrationCta.mode == IronwoodHomeMigrationCtaMode.resume;
    final shieldedBalance = migrationRequired
        ? sync.orchardBalance + sync.orchardPendingBalance
        : migrationInProgress
        ? sync.ironwoodBalance
        : sync.saplingBalance +
              sync.orchardBalance +
              sync.ironwoodBalance +
              sync.saplingPendingBalance +
              sync.orchardPendingBalance +
              sync.ironwoodPendingBalance;
    final transparentBalance =
        sync.transparentBalance + sync.transparentPendingBalance;
    final hasBalance =
        shieldedBalance > BigInt.zero || transparentBalance > BigInt.zero;
    final zecUsdUnitPrice = ref.watch(zecHomeUsdUnitPriceProvider);
    final fiatBalanceText = _mobileHomeFiatTextForZatoshi(
      shieldedBalance,
      zecUsdUnitPrice: zecUsdUnitPrice,
    );
    final shieldedFiatBalanceText =
        privacyModeEnabled && fiatBalanceText != null
        ? fixedPrivacyMask()
        : fiatBalanceText;
    final priceChange24hPct = ref.watch(zecPriceChange24hPctProvider);
    final payEnabled = ref.watch(swapFeatureEnabledProvider);
    final payIntroductionClicked = ref
        .watch(payIntroductionBadgeClickedProvider)
        .value;
    final showPayIntroduction = payEnabled && payIntroductionClicked == false;

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
        AppSpacing.sm,
        AppSpacing.sm,
        kMobileTabBarHeight + AppSpacing.lg,
      ),
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                _BalanceCard(
                  balanceText: privacyModeEnabled
                      ? fixedPrivacyMask()
                      : ZecAmount.fromZatoshi(
                          shieldedBalance,
                        ).compactBalance.amountText,
                  fiatBalanceText: shieldedFiatBalanceText,
                  priceChange24hPct: priceChange24hPct,
                  transparentBalanceText: ZecAmount.fromZatoshi(
                    transparentBalance,
                  ).compactBalance.amountText,
                  hasTransparentBalance: transparentBalance > BigInt.zero,
                  canShieldBalance: sync.canShieldTransparentBalance,
                  isShieldingBalance: _isShieldingBalance,
                  privacyModeEnabled: privacyModeEnabled,
                  ironwoodMigrationCta: widget.ironwoodMigrationCta,
                  balanceDisabled: migrationRequired,
                  onTogglePrivacyMode: widget.onTogglePrivacyMode,
                  onIronwoodMigrationTap: () {
                    final target = switch (widget.ironwoodMigrationCta.mode) {
                      IronwoodHomeMigrationCtaMode.start => '/migration/intro',
                      IronwoodHomeMigrationCtaMode.resume =>
                        '/migration/private/status',
                      IronwoodHomeMigrationCtaMode.hidden => null,
                    };
                    if (target != null) context.push(target);
                  },
                  onShieldBalancePressed: () =>
                      unawaited(_shieldTransparentBalance()),
                ),
                const SizedBox(height: AppSpacing.s),
                if (hasBalance)
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          key: const ValueKey('mobile_home_send'),
                          expand: true,
                          constrainContent: true,
                          onPressed: migrationRequired
                              ? null
                              : () => context.push('/send'),
                          leading: const _ButtonIcon(AppIcons.plane),
                          height: _mobileHomeActionButtonHeight,
                          child: const Text(
                            'Send',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: AppButton(
                          key: const ValueKey('mobile_home_receive'),
                          expand: true,
                          constrainContent: true,
                          variant: AppButtonVariant.secondary,
                          onPressed: () => context.push('/receive'),
                          leading: const _ButtonIcon(AppIcons.arrowDownCircle),
                          height: _mobileHomeActionButtonHeight,
                          child: const Text(
                            'Receive',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      // The Pay entry follows the swap feature flag: pay
                      // rides the swap engine, so a server-side swap disable
                      // hides the button and its callout, mirroring desktop's
                      // `onPay == null` gating.
                      if (payEnabled && !migrationRequired) ...[
                        const SizedBox(width: AppSpacing.xs),
                        DecoratedBox(
                          key: const ValueKey('mobile_home_pay_glow'),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: showPayIntroduction
                                ? const [
                                    BoxShadow(
                                      color: Color(0xFF1C7ADE),
                                      blurRadius: 60,
                                      spreadRadius: 20,
                                    ),
                                    BoxShadow(
                                      color: Color(0xFF1C7ADE),
                                      blurRadius: 100,
                                    ),
                                  ]
                                : null,
                          ),
                          child: SizedBox(
                            width: _mobileHomeActionButtonHeight,
                            height: _mobileHomeActionButtonHeight,
                            child: Semantics(
                              button: true,
                              label: 'Pay',
                              child: AppButton(
                                key: const ValueKey('mobile_home_pay'),
                                minWidth: _mobileHomeActionButtonHeight,
                                height: _mobileHomeActionButtonHeight,
                                contentPadding: EdgeInsets.zero,
                                variant: AppButtonVariant.secondary,
                                onPressed: _openPay,
                                child: const _ButtonIcon(AppIcons.paid),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  )
                else
                  AppButton(
                    // Same key as the funded-state Receive button — only one
                    // of the two renders at a time.
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
                if (widget.ironwoodMigrationCta.visible) ...[
                  const SizedBox(height: AppSpacing.s),
                  _MobileIronwoodMigrationBanner(
                    inProgress: migrationInProgress,
                    actionNeeded: _mobileIronwoodMigrationNeedsAttention(
                      widget.ironwoodMigrationCta.status,
                      currentHeight: sync.chainTipHeight,
                    ),
                    remainingText: _mobileIronwoodRemainingAmountText(
                      widget.ironwoodMigrationCta.status,
                    ),
                    onTap: () {
                      final target = migrationRequired
                          ? '/migration/intro'
                          : '/migration/private/status';
                      context.push(target);
                    },
                  ),
                ],
              ],
            ),
            if (hasBalance && showPayIntroduction && !migrationRequired) ...[
              Positioned(
                right: 41,
                top: 172,
                width: 118,
                height: 65,
                child: const IgnorePointer(child: _MobilePayBadges()),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Stack(
          clipBehavior: Clip.none,
          children: [
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
                    _RecentActivityHeader(
                      onSeeAll: () => context.go('/activity'),
                    ),
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
            if (hasBalance && showPayIntroduction)
              Positioned(
                right: 43,
                top: -35,
                width: 80,
                height: 80,
                child: IgnorePointer(
                  child: PayCoinFloatMotion(
                    animate: ref.watch(
                      payIntroductionBadgeMotionEnabledProvider,
                    ),
                    child: Image.asset(
                      'assets/illustrations/pay_coin.png',
                      key: const ValueKey('mobile_home_pay_coin'),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

String? _mobileHomeFiatTextForZatoshi(
  BigInt zatoshi, {
  required double? zecUsdUnitPrice,
}) {
  final compactText = fiatTextForZatoshi(
    zatoshi,
    zecUsdUnitPrice: zecUsdUnitPrice,
  );
  if (compactText == null || zecUsdUnitPrice == null) return compactText;

  final zec = zatoshi.toDouble() / zatoshiPerZec.toDouble();
  final value = zec * zecUsdUnitPrice;
  if (!value.isFinite || value >= 1000000) return compactText;

  final parts = value.toStringAsFixed(2).split('.');
  final whole = parts.first;
  final grouped = StringBuffer();
  for (var index = 0; index < whole.length; index++) {
    if (index > 0 && (whole.length - index) % 3 == 0) grouped.write(',');
    grouped.write(whole[index]);
  }
  return '\$$grouped.${parts.last}';
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
    required this.ironwoodMigrationCta,
    required this.balanceDisabled,
    required this.onTogglePrivacyMode,
    required this.onIronwoodMigrationTap,
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
  final IronwoodHomeMigrationCtaState ironwoodMigrationCta;
  final bool balanceDisabled;
  final VoidCallback onTogglePrivacyMode;
  final VoidCallback onIronwoodMigrationTap;
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
              decoration: BoxDecoration(
                color: colors.background.homeCard,
                borderRadius: cardRadius,
                border: Border.all(
                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.07),
                  width: 1.5,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (ironwoodMigrationCta.mode ==
                                IronwoodHomeMigrationCtaMode.start)
                              Expanded(
                                child: _MobileIronwoodMigrationPill(
                                  onTap: onIronwoodMigrationTap,
                                ),
                              )
                            else ...[
                              AppIcon(
                                AppIcons.shieldKeyhole,
                                size: 20,
                                color: cardText,
                              ),
                              const SizedBox(width: AppSpacing.s),
                              Expanded(
                                child: Text(
                                  'Shielded balance',
                                  style: _mobileHomeLabelMStyle.copyWith(
                                    color: cardText,
                                  ),
                                ),
                              ),
                            ],
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
                                    color: cardText.withValues(
                                      alpha: balanceDisabled ? 0.4 : 0.8,
                                    ),
                                  ),
                                ),
                              ),
                              if (priceChangeColor != null) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  formatZecPriceChange24hPct(
                                    priceChange24hPct!,
                                  ),
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
                                  color: cardText.withValues(
                                    alpha: balanceDisabled ? 0.4 : 1,
                                  ),
                                ),
                              ),
                              TextSpan(
                                text: kZcashDefaultCurrencyTicker,
                                style: _mobileHomeBalanceTickerStyle.copyWith(
                                  color: cardText.withValues(
                                    alpha: balanceDisabled ? 0.4 : 1,
                                  ),
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
                ],
              ),
            ),
            _AnimatedMobileTransparentBalanceStrip(
              visible: hasTransparentBalance,
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

String? _mobileIronwoodRemainingAmountText(rust_sync.MigrationStatus? status) {
  if (status == null) return null;
  final broadcasts = status.scheduledBroadcasts;
  if (broadcasts.isEmpty) return null;
  final remaining = broadcasts
      .where((item) => item.status.toLowerCase() != 'confirmed')
      .fold<BigInt>(BigInt.zero, (sum, item) => sum + item.valueZatoshi);
  if (remaining == BigInt.zero) return null;
  return ZecAmount.fromZatoshi(remaining).compactBalance.amountText;
}

bool _mobileIronwoodMigrationNeedsAttention(
  rust_sync.MigrationStatus? status, {
  required int currentHeight,
}) {
  if (status == null || currentHeight <= 0) return false;
  return status.scheduledBroadcasts.any(
    (item) =>
        item.status.toLowerCase() == 'scheduled' &&
        item.scheduledHeight > 0 &&
        currentHeight >=
            item.scheduledHeight + kIronwoodMigrationLateGraceBlocks,
  );
}

class _MobileIronwoodMigrationBanner extends StatefulWidget {
  const _MobileIronwoodMigrationBanner({
    required this.inProgress,
    required this.actionNeeded,
    required this.remainingText,
    required this.onTap,
  });

  final bool inProgress;
  final bool actionNeeded;
  final String? remainingText;
  final VoidCallback onTap;

  @override
  State<_MobileIronwoodMigrationBanner> createState() =>
      _MobileIronwoodMigrationBannerState();
}

class _MobileIronwoodMigrationBannerState
    extends State<_MobileIronwoodMigrationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _MobileIronwoodMigrationBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inProgress != widget.inProgress ||
        oldWidget.actionNeeded != widget.actionNeeded) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    final animate =
        !widget.inProgress &&
        !widget.actionNeeded &&
        !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    if (animate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = widget.actionNeeded
        ? 'Migration needs attention'
        : widget.inProgress
        ? widget.remainingText == null
              ? 'Migration in progress'
              : '${widget.remainingText} ZEC still migrating'
        : 'Migrate to Ironwood';
    final contentColor = colors.text.homeCard;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        key: const ValueKey('mobile_home_ironwood_migration_banner'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 52,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.background.homeCard,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            border: Border.all(
              color: const Color(0xFFFFFFFF).withValues(alpha: 0.07),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: ShaderMask(
                  key: const ValueKey(
                    'mobile_home_ironwood_migration_banner_image_mask',
                  ),
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0x0DFFFFFF), Color(0x8CFFFFFF)],
                  ).createShader(bounds),
                  child: Image.asset(
                    'assets/illustrations/'
                    'ironwood_migration_home_card_background.png',
                    key: const ValueKey(
                      'mobile_home_ironwood_migration_banner_background',
                    ),
                    fit: BoxFit.fill,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    if (widget.actionNeeded)
                      AppIcon(
                        AppIcons.warning,
                        key: const ValueKey(
                          'mobile_home_ironwood_migration_attention',
                        ),
                        size: 20,
                        color: colors.icon.warning,
                      )
                    else if (widget.inProgress)
                      AppIcon(
                        AppIcons.loader,
                        key: const ValueKey(
                          'mobile_home_ironwood_migration_loader',
                        ),
                        size: 20,
                        color: contentColor,
                      )
                    else
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, _) {
                          final timeline = _controller.value;
                          final rippleProgress = timeline <= 0.1
                              ? 0.0
                              : timeline >= 0.7
                              ? 1.0
                              : Curves.easeInOut.transform(
                                  (timeline - 0.1) / 0.6,
                                );
                          final rippleSize = lerpDouble(8, 56, rippleProgress)!;
                          return SizedBox(
                            key: const ValueKey(
                              'mobile_home_ironwood_migration_blink',
                            ),
                            width: 16,
                            height: 16,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  left: (16 - rippleSize) / 2,
                                  top: (16 - rippleSize) / 2,
                                  child: Opacity(
                                    key: const ValueKey(
                                      'mobile_home_ironwood_migration_blink_ripple',
                                    ),
                                    opacity: 1 - rippleProgress,
                                    child: SizedBox(
                                      width: rippleSize,
                                      height: rippleSize,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: GreenPrimitives.p200Dark,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const Positioned(
                                  left: 3,
                                  top: 3,
                                  width: 10,
                                  height: 10,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        colors: [
                                          GreenPrimitives.p200Light,
                                          GreenPrimitives.p300Dark,
                                        ],
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: GreenPrimitives.p300Dark,
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    SizedBox(
                      width: widget.inProgress || widget.actionNeeded
                          ? AppSpacing.xxs
                          : AppSpacing.sm,
                    ),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: contentColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AppIcon(
                      AppIcons.chevronForward,
                      size: 20,
                      color: contentColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileIronwoodMigrationPill extends StatelessWidget {
  const _MobileIronwoodMigrationPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final contentColor = context.colors.text.homeCard;
    return Semantics(
      button: true,
      label: 'Migration required',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          key: const ValueKey('mobile_home_ironwood_migration_required_pill'),
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(AppIcons.lock, size: 20, color: contentColor),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Migration required',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mobileHomeLabelMStyle.copyWith(color: contentColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _mobileTransparentBalanceStripHeight = 57.0;
const _mobileTransparentBalanceMotionDuration = Duration(milliseconds: 280);
const _mobileTransparentBalanceMotionReverseDuration = Duration(
  milliseconds: 240,
);

class _AnimatedMobileTransparentBalanceStrip extends StatefulWidget {
  const _AnimatedMobileTransparentBalanceStrip({
    required this.visible,
    required this.balanceText,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.privacyModeEnabled,
    required this.onShieldBalancePressed,
  });

  final bool visible;
  final String balanceText;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final bool privacyModeEnabled;
  final VoidCallback onShieldBalancePressed;

  @override
  State<_AnimatedMobileTransparentBalanceStrip> createState() =>
      _AnimatedMobileTransparentBalanceStripState();
}

class _AnimatedMobileTransparentBalanceStripState
    extends State<_AnimatedMobileTransparentBalanceStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sizeFactor;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  late String _balanceText;
  late bool _canShieldBalance;
  late bool _isShieldingBalance;
  late bool _privacyModeEnabled;
  late VoidCallback _onShieldBalancePressed;
  var _hasCachedStrip = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _mobileTransparentBalanceMotionDuration,
      reverseDuration: _mobileTransparentBalanceMotionReverseDuration,
      value: widget.visible ? 1.0 : 0.0,
    )..addStatusListener(_handleAnimationStatus);
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _sizeFactor = curve;
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, -0.14),
      end: Offset.zero,
    ).animate(curve);
    if (widget.visible) {
      _cacheVisibleStrip();
      _hasCachedStrip = true;
    }
  }

  @override
  void didUpdateWidget(
    covariant _AnimatedMobileTransparentBalanceStrip oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) {
      setState(() {
        _cacheVisibleStrip();
        _hasCachedStrip = true;
      });
      unawaited(_controller.forward());
      return;
    }

    if (oldWidget.visible && !widget.visible) {
      unawaited(_controller.reverse());
    }
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  void _cacheVisibleStrip() {
    _balanceText = widget.balanceText;
    _canShieldBalance = widget.canShieldBalance;
    _isShieldingBalance = widget.isShieldingBalance;
    _privacyModeEnabled = widget.privacyModeEnabled;
    _onShieldBalancePressed = widget.onShieldBalancePressed;
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed ||
        widget.visible ||
        !_hasCachedStrip) {
      return;
    }
    setState(() => _hasCachedStrip = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasCachedStrip && !widget.visible && _controller.isDismissed) {
      return const SizedBox.shrink();
    }

    return ClipRect(
      key: const ValueKey('mobile_home_transparent_balance_strip'),
      child: SizeTransition(
        sizeFactor: _sizeFactor,
        axisAlignment: -1,
        child: FadeTransition(
          opacity: _opacity,
          child: SlideTransition(
            position: _offset,
            child: IgnorePointer(
              ignoring: !widget.visible,
              child: _MobileTransparentBalanceStrip(
                balanceText: _balanceText,
                canShieldBalance: _canShieldBalance,
                isShieldingBalance: _isShieldingBalance,
                privacyModeEnabled: _privacyModeEnabled,
                onShieldBalancePressed: _onShieldBalancePressed,
              ),
            ),
          ),
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
      height: _mobileTransparentBalanceStripHeight,
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

/// The Pay introduction callout — Figma `PAY Floating Badge`
/// (6261:126485). Like desktop, the whole treatment remains until the first
/// Pay activation; mobile has no hover state for bringing it back afterwards.
class _MobilePayBadges extends StatelessWidget {
  const _MobilePayBadges();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'New: Pay in USDC',
      container: true,
      child: ExcludeSemantics(
        child: SizedBox(
          key: const ValueKey('mobile_home_pay_badges'),
          width: 118,
          height: 65,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: 118,
                height: 34,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C7ADE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Positioned(
                left: 14,
                top: 8,
                child: Text(
                  'Pay in USDC',
                  style: AppTypography.labelLarge.copyWith(
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ),
              Positioned(
                left: 40,
                top: 36,
                width: 55,
                height: 29,
                child: SvgPicture.asset(
                  'assets/illustrations/pay_floating_new.svg',
                ),
              ),
              Positioned(
                left: 49,
                top: 42,
                child: Text(
                  'NEW',
                  style: AppTypography.labelLarge.copyWith(
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
