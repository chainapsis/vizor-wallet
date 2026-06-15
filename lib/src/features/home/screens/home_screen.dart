// ignore_for_file: unused_element, unused_field

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show CircularProgressIndicator, Colors, Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../main.dart' show log;
import '../../../app_bootstrap.dart';
import '../../../core/config/rpc_endpoint_config.dart';
import '../../../core/config/swap_feature_config.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_desktop_backdrop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../providers/zec_price_change_provider.dart';
import '../../../providers/zec_usd_price_provider.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/app_security_provider.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/rpc_endpoint_failover_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../providers/wallet_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../activity/activity_row_mapper.dart';
import '../../activity/models/activity_row_data.dart';
import '../../activity/screens/activity_transaction_status_screen.dart';
import '../../activity/swap_activity_row_items_provider.dart';
import '../../activity/swap_activity_row_mapper.dart';
import '../../swap/models/swap_activity_navigation.dart';
import '../../swap/models/swap_fiat_value_formatting.dart';
import '../../swap/providers/swap_activity_tracker.dart';
import '../widgets/keystone_shield_signing_overlay.dart';

const _shieldErrorTooltipIconSize = 14.0;
const _shieldErrorTooltipGap = AppSpacing.xxs;
const _homeDesktopActivationShortcuts = <ShortcutActivator, Intent>{
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
  bool _isShieldingBalance = false;
  bool _showKeystoneShieldSigning = false;
  String? _shieldBalanceError;
  String? _shieldBalanceErrorDetail;

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

  String? _formatFiatBalance(
    BigInt zatoshi, {
    required double? zecUsdUnitPrice,
    required bool privacyModeEnabled,
  }) {
    if (zatoshi <= BigInt.zero ||
        zecUsdUnitPrice == null ||
        !zecUsdUnitPrice.isFinite ||
        zecUsdUnitPrice <= 0) {
      return null;
    }
    if (privacyModeEnabled) return fixedPrivacyMask();

    final zec = zatoshi.toDouble() / zatoshiPerZec.toDouble();
    if (!zec.isFinite || zec <= 0) return null;
    return swapFormatCompactFiatValue(zec * zecUsdUnitPrice);
  }

  void _dismissShieldBalanceError() {
    setState(() {
      _shieldBalanceError = null;
      _shieldBalanceErrorDetail = null;
    });
  }

  Future<void> _shieldTransparentBalance() async {
    if (_isShieldingBalance) return;

    final wallet = ref.read(walletProvider).value;
    final accountUuid = wallet?.activeAccountUuid;
    if (accountUuid == null) {
      setState(() {
        _shieldBalanceError = 'No active account.';
      });
      return;
    }

    final accountNotifier = ref.read(accountProvider.notifier);
    if (accountNotifier.isHardwareAccount(accountUuid)) {
      setState(() {
        _showKeystoneShieldSigning = true;
        _shieldBalanceError = null;
        _shieldBalanceErrorDetail = null;
      });
      return;
    }

    setState(() {
      _isShieldingBalance = true;
      _shieldBalanceError = null;
      _shieldBalanceErrorDetail = null;
    });

    RpcEndpointConfig? attemptedEndpoint;
    try {
      final sync = (ref.read(syncProvider).value ?? SyncState())
          .scopedToAccount(accountUuid);
      if (!sync.canShieldTransparentBalance) {
        throw Exception(
          'Transparent balance is too small to shield after fees.',
        );
      }

      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointFailoverProvider).current;
      attemptedEndpoint = endpoint;

      late final rust_sync.ShieldTransparentResult result;
      late final Future<rust_sync.ShieldTransparentResult> resultFuture;

      if (Platform.isMacOS) {
        final password = ref
            .read(appSecurityProvider.notifier)
            .requireSessionPasswordForNativeSecretUse();
        resultFuture = rust_sync
            .shieldTransparentBalanceWithMacosStoredMnemonic(
              dbPath: dbPath,
              lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
              network: endpoint.networkName,
              accountUuid: accountUuid,
              password: password,
            );
      } else {
        final mnemonicBytes = await accountNotifier.getMnemonicBytesForAccount(
          accountUuid,
        );
        if (mnemonicBytes == null || mnemonicBytes.isEmpty) {
          throw Exception('Mnemonic not found for the active account.');
        }

        try {
          resultFuture = rust_sync.shieldTransparentBalance(
            dbPath: dbPath,
            lightwalletdUrl: endpoint.normalizedLightwalletdUrl,
            network: endpoint.networkName,
            accountUuid: accountUuid,
            mnemonicBytes: mnemonicBytes,
          );
        } finally {
          mnemonicBytes.fillRange(0, mnemonicBytes.length, 0);
        }
      }
      result = await resultFuture;
      log(
        'HomeScreen: shielded transparent balance txids=${result.txids} '
        'status=${result.status} '
        'broadcasted=${result.broadcastedCount}/${result.totalCount} '
        'fee=${result.feeZatoshi} shielded=${result.shieldedZatoshi}',
      );

      final broadcastStatusMessage = shieldBalanceBroadcastStatusMessage(
        result,
      );
      final broadcastDetailMessage = result.message?.trim();
      if (broadcastStatusMessage != null &&
          broadcastDetailMessage != null &&
          broadcastDetailMessage.isNotEmpty) {
        final switched = await ref
            .read(rpcEndpointFailoverProvider.notifier)
            .switchToFallbackFor(
              broadcastDetailMessage,
              endpoint: attemptedEndpoint,
              operation: 'shield transparent balance broadcast',
            );
        if (switched) {
          unawaited(ref.read(syncProvider.notifier).restartSync());
        }
      }

      try {
        await ref.read(syncProvider.notifier).refreshAfterSend();
      } catch (e) {
        log('HomeScreen: refreshAfterSend after shielding failed: $e');
      }

      if (broadcastStatusMessage != null) {
        if (!mounted) return;
        setState(() {
          _shieldBalanceError = broadcastStatusMessage;
          _shieldBalanceErrorDetail = null;
        });
      }
    } catch (e, st) {
      log('HomeScreen: shield transparent balance failed: $e\n$st');
      final switched = await ref
          .read(rpcEndpointFailoverProvider.notifier)
          .switchToFallbackFor(
            e,
            endpoint: attemptedEndpoint,
            operation: 'shield transparent balance',
          );
      if (switched) {
        unawaited(ref.read(syncProvider.notifier).restartSync());
      }
      if (!mounted) return;
      setState(() {
        _shieldBalanceError = _friendlyShieldBalanceError(e);
        _shieldBalanceErrorDetail = _shieldBalanceErrorDetails(e);
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
    if (lower.contains('mnemonic')) {
      return "Secret Passphrase isn't available for this account.";
    }
    if (lower.contains('sync')) {
      return 'Wait for sync to finish, then shield.';
    }
    if (lower.contains('insufficient') ||
        lower.contains('threshold') ||
        lower.contains('too small') ||
        lower.contains('no transparent funds')) {
      return 'Transparent balance is too small to shield after fees.';
    }
    if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
      return "Couldn't broadcast your shielding transaction. Try again.";
    }
    return "Couldn't shield your balance. Try again.";
  }

  String? _shieldBalanceErrorDetails(Object error) {
    final message = error.toString().trim();
    final lower = message.toLowerCase();
    if (lower.contains('broadcast') || lower.contains('sendtransaction')) {
      return null;
    }
    return message.isEmpty ? null : message;
  }

  void _closeKeystoneShieldSigning() {
    setState(() {
      _showKeystoneShieldSigning = false;
    });
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
    final zecUsdUnitPrice = ref.watch(zecUsdUnitPriceProvider).asData?.value;
    final shieldedFiatBalanceText = _formatFiatBalance(
      shieldedBalance,
      zecUsdUnitPrice: zecUsdUnitPrice,
      privacyModeEnabled: privacyModeEnabled,
    );
    final priceChange24hPct = ref.watch(zecPriceChange24hPctProvider);
    final transparentBalance =
        sync.transparentBalance + sync.transparentPendingBalance;
    final canShieldTransparentBalance = sync.canShieldTransparentBalance;
    final isImportingForBackground =
        activeAccountUuid != null &&
        !sync.hasAccountScopedData &&
        sync.failure == null;
    final isDark = context.appTheme == AppThemeData.dark;
    final backgroundVariant = isImportingForBackground
        ? 'importing'
        : 'default';
    final backgroundTheme = isDark ? 'dark' : 'light';

    return AppDesktopBackdropShell(
      background: _HomeFullPageBackground(
        assetName:
            'assets/illustrations/home_${backgroundVariant}_background_$backgroundTheme.png',
      ),
      sidebar: const AppMainSidebar(),
      pane: Stack(
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
                shieldedFiatBalanceText: shieldedFiatBalanceText,
                priceChange24hPct: priceChange24hPct,
                transparentBalanceText: _formatZec(transparentBalance),
                hasTransparentBalance: transparentBalance > BigInt.zero,
                canShieldBalance: canShieldTransparentBalance,
                isShieldingBalance: _isShieldingBalance,
                shieldBalanceError: _shieldBalanceError,
                shieldBalanceErrorDetail: _shieldBalanceErrorDetail,
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
          if (_showKeystoneShieldSigning)
            KeystoneShieldSigningOverlay(
              onCancel: _closeKeystoneShieldSigning,
              onComplete: _closeKeystoneShieldSigning,
            ),
        ],
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
    required this.shieldedFiatBalanceText,
    required this.priceChange24hPct,
    required this.transparentBalanceText,
    required this.hasTransparentBalance,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.shieldBalanceError,
    required this.shieldBalanceErrorDetail,
    required this.onTogglePrivacyMode,
    required this.onShieldBalancePressed,
    required this.onDismissShieldBalanceError,
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
  final String? shieldedFiatBalanceText;
  final double? priceChange24hPct;
  final String transparentBalanceText;
  final bool hasTransparentBalance;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final String? shieldBalanceError;
  final String? shieldBalanceErrorDetail;
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
  static const _recentActivityLimit = 5;

  Timer? _swapActivityRefreshTimer;
  String? _swapActivityRefreshAccountUuid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSwapActivityStatusRefresh();
    });
  }

  @override
  void dispose() {
    _swapActivityRefreshTimer?.cancel();
    super.dispose();
  }

  void _syncSwapActivityStatusRefresh() {
    if (!ref.read(swapFeatureEnabledProvider)) {
      _swapActivityRefreshTimer?.cancel();
      _swapActivityRefreshAccountUuid = null;
      return;
    }
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    if (accountUuid == _swapActivityRefreshAccountUuid &&
        _swapActivityRefreshTimer?.isActive == true) {
      return;
    }
    _swapActivityRefreshTimer?.cancel();
    _swapActivityRefreshAccountUuid = accountUuid;
    if (accountUuid == null || accountUuid.trim().isEmpty) return;

    unawaited(_refreshSwapActivityStatus(accountUuid));
    _swapActivityRefreshTimer = Timer.periodic(
      swapActivityStatusRefreshInterval,
      (_) => unawaited(_refreshSwapActivityStatus(accountUuid)),
    );
  }

  Future<void> _refreshSwapActivityStatus(
    String accountUuid, {
    bool force = false,
  }) {
    return ref
        .read(swapActivityStatusRefresherProvider)
        .refreshOpenActivities(accountUuid: accountUuid, force: force);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AccountState>>(accountProvider, (previous, next) {
      if (previous?.value?.activeAccountUuid != next.value?.activeAccountUuid) {
        _syncSwapActivityStatusRefresh();
      }
    });

    final notice = _noticeData();
    final rows = _activityRows(context);
    final accountState = ref.watch(accountProvider).value;
    final activeAccountUuid = accountState?.activeAccountUuid;
    String? activeAccountName;
    if (activeAccountUuid != null) {
      for (final account in accountState?.accounts ?? const <AccountInfo>[]) {
        if (account.uuid == activeAccountUuid) {
          activeAccountName = account.name;
          break;
        }
      }
    }
    final isImporting =
        !widget.sync.hasAccountScopedData && widget.sync.failure == null;
    final hasBalance = widget.sync.totalBalance > BigInt.zero;

    return _HomeDesktopPane(
      isImporting: isImporting,
      importProgress: widget.sync.displayPercentage,
      importingAccountName: activeAccountName,
      hasBalance: hasBalance,
      shieldedBalanceText: widget.shieldedBalanceText,
      shieldedFiatBalanceText: widget.shieldedFiatBalanceText,
      priceChange24hPct: widget.priceChange24hPct,
      transparentBalanceText: widget.transparentBalanceText,
      hasTransparentBalance: widget.hasTransparentBalance,
      canShieldBalance: widget.canShieldBalance,
      isShieldingBalance: widget.isShieldingBalance,
      privacyModeEnabled: widget.privacyModeEnabled,
      activityRows: rows,
      isActivityLoading: widget.isActivityLoading,
      notice: notice,
      onTogglePrivacyMode: widget.onTogglePrivacyMode,
      onShieldBalancePressed: widget.onShieldBalancePressed,
      onSend: () => context.push('/send'),
      onReceive: () => context.push('/receive'),
      onActivity: () => context.push('/activity'),
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
    if (widget.shieldBalanceError != null) {
      return _HomeNoticeData(
        iconName: AppIcons.warning,
        message: widget.shieldBalanceError!,
        detailMessage: widget.shieldBalanceErrorDetail,
        actionLabel: 'Dismiss',
        onTap: widget.onDismissShieldBalanceError,
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
    final accountUuid = ref.watch(accountProvider).value?.activeAccountUuid;
    final swapFeatureEnabled = ref.watch(swapFeatureEnabledProvider);
    final swapItems = accountUuid == null || !swapFeatureEnabled
        ? const <SwapActivityRowItem>[]
        : ref.watch(swapActivityRowItemsProvider(accountUuid)).value ??
              const <SwapActivityRowItem>[];
    // Suppress standalone tx rows that a swap row already represents, with
    // the same matching the Activity screen uses. Home's compact rows render
    // no children, so only the suppression set is consumed here.
    final absorption = !widget.hasActivitySyncData
        ? SwapActivityLegAbsorption.empty
        : matchSwapActivityLegAbsorption(
            swapItems: swapItems,
            transactions: widget.sync.recentTransactions,
          );
    final entries = <_HomeActivityEntry>[
      if (widget.hasActivitySyncData)
        for (final tx in widget.sync.recentTransactions)
          if (!absorption.absorbs(tx))
            _HomeActivityEntry(
              timestamp: _transactionActivityTimestamp(tx),
              row: buildTransactionActivityRow(
                context: context,
                transaction: tx,
                privacyModeEnabled: widget.privacyModeEnabled,
                onTap: () => _openTransactionStatus(tx),
              ),
            ),
      for (final item in swapItems)
        _HomeActivityEntry(
          timestamp: item.activityTimestamp,
          row: buildSwapActivityRow(
            context: context,
            item: item,
            privacyModeEnabled: widget.privacyModeEnabled,
            onTap: () => _openSwapStatus(item.intentId),
          ),
        ),
    ]..sort(_compareHomeActivityEntries);
    return entries
        .take(_recentActivityLimit)
        .map((entry) => entry.row)
        .toList(growable: false);
  }

  void _openTransactionStatus(rust_sync.TransactionInfo transaction) {
    unawaited(_pushTransactionStatus(transaction));
  }

  void _openSwapStatus(String intentId) {
    context.push(
      swapActivityDetailUri(
        intentId: intentId,
        returnTarget: SwapActivityReturnTarget.home,
      ).toString(),
    );
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

class _HomeActivityEntry {
  const _HomeActivityEntry({required this.timestamp, required this.row});

  final DateTime? timestamp;
  final ActivityRowData row;
}

class _HomeFullPageBackground extends StatelessWidget {
  const _HomeFullPageBackground({required this.assetName});

  final String assetName;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetName,
      key: const ValueKey('home_full_page_background'),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
    );
  }
}

int _compareHomeActivityEntries(_HomeActivityEntry a, _HomeActivityEntry b) {
  final aTime = a.timestamp;
  final bTime = b.timestamp;
  if (aTime == null && bTime == null) return 0;
  if (aTime == null) return 1;
  if (bTime == null) return -1;
  return bTime.compareTo(aTime);
}

DateTime? _transactionActivityTimestamp(rust_sync.TransactionInfo tx) {
  final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
  if (seconds <= BigInt.zero) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
}

class _HomeTransparentBalanceStrip extends StatelessWidget {
  const _HomeTransparentBalanceStrip({
    required this.balanceText,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.privacyModeEnabled,
    required this.shieldBalanceContentColor,
    required this.shieldBalanceHovered,
    required this.onShieldBalancePressed,
    required this.onShieldBalanceHoverChanged,
    super.key,
  });

  final String balanceText;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final bool privacyModeEnabled;
  final Color shieldBalanceContentColor;
  final bool shieldBalanceHovered;
  final VoidCallback onShieldBalancePressed;
  final ValueChanged<bool> onShieldBalanceHoverChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final displayedBalance = hideAmountIfPrivacyMode(
      '$balanceText $kZcashDefaultCurrencyTicker',
      privacyModeEnabled: privacyModeEnabled,
    );
    final canHoverShieldBalance = canShieldBalance && !isShieldingBalance;

    // Figma "Home Shield Balance" (4731:64262/64704): a 46px tray exposed on
    // the card's ground shelf — 16/8 padding, muted primary text on the left,
    // space-between to the shield action.
    return SizedBox(
      height: 46,
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
                      key: const ValueKey('home_transparent_balance_text'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colors.text.primary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (canShieldBalance || isShieldingBalance) ...[
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
                  hovered: shieldBalanceHovered,
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
    required this.hovered,
    required this.onPressed,
  });

  final bool enabled;
  final bool isLoading;
  final Color contentColor;
  final bool hovered;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isInteractive = enabled && !isLoading;

    return Semantics(
      key: const ValueKey('home_shield_balance_button'),
      button: true,
      enabled: isInteractive,
      child: MouseRegion(
        cursor: isInteractive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isInteractive ? onPressed : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Standard ghost-button hover fill; the design draws no hover
              // state for the tray action.
              color: hovered && isInteractive
                  ? colors.button.ghost.bgHover
                  : const Color(0x00000000),
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 30),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs,
                      ),
                      child: Text(
                        isLoading ? 'Shielding...' : 'Shield now',
                        style: AppTypography.labelLarge.copyWith(
                          color: contentColor,
                        ),
                      ),
                    ),
                    AppIcon(
                      isLoading ? AppIcons.loader : AppIcons.chevronForward,
                      size: 16,
                      color: contentColor,
                    ),
                  ],
                ),
              ),
            ),
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
    this.detailMessage,
    required this.actionLabel,
    required this.onTap,
  });

  final String iconName;
  final String message;
  final String? detailMessage;
  final String actionLabel;
  final VoidCallback onTap;
}

class _HomeNoticeCard extends StatelessWidget {
  const _HomeNoticeCard({required this.data});

  final _HomeNoticeData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    final detailMessage = data.detailMessage;
    return Container(
      key: const ValueKey('home_notice_card'),
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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    data.message,
                    style: AppTypography.labelLarge.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                if (detailMessage != null) ...[
                  const SizedBox(width: AppSpacing.xxs),
                  Tooltip(
                    message: detailMessage,
                    waitDuration: const Duration(milliseconds: 350),
                    showDuration: const Duration(seconds: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s,
                      vertical: AppSpacing.xs,
                    ),
                    margin: EdgeInsets.zero,
                    preferBelow: false,
                    positionDelegate: _positionShieldErrorTooltip,
                    decoration: BoxDecoration(
                      color: isDark
                          ? colors.surface.tooltip
                          : colors.background.inverse,
                      borderRadius: BorderRadius.circular(AppRadii.xSmall),
                      border: isDark
                          ? Border.all(color: colors.border.regular)
                          : null,
                    ),
                    textStyle: AppTypography.bodySmall.copyWith(
                      color: isDark ? colors.text.accent : colors.text.inverse,
                      letterSpacing: 0,
                    ),
                    child: AppIcon(
                      AppIcons.help,
                      size: _shieldErrorTooltipIconSize,
                      color: colors.text.accent,
                    ),
                  ),
                ],
              ],
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

Offset _positionShieldErrorTooltip(TooltipPositionContext context) {
  const edgeMargin = AppSpacing.md;
  final targetTop = context.target.dy - (context.targetSize.height / 2);
  final y = (targetTop - _shieldErrorTooltipGap - context.tooltipSize.height)
      .clamp(
        edgeMargin,
        context.overlaySize.height - context.tooltipSize.height - edgeMargin,
      )
      .toDouble();

  final flexibleSpace = context.overlaySize.width - context.tooltipSize.width;
  final x = flexibleSpace <= edgeMargin * 2
      ? flexibleSpace / 2
      : (context.target.dx - (context.tooltipSize.width / 2))
            .clamp(edgeMargin, flexibleSpace - edgeMargin)
            .toDouble();

  return Offset(x, y);
}

class _HomeDesktopPane extends StatelessWidget {
  const _HomeDesktopPane({
    required this.isImporting,
    required this.importProgress,
    required this.importingAccountName,
    required this.hasBalance,
    required this.shieldedBalanceText,
    required this.shieldedFiatBalanceText,
    required this.priceChange24hPct,
    required this.transparentBalanceText,
    required this.hasTransparentBalance,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.privacyModeEnabled,
    required this.activityRows,
    required this.isActivityLoading,
    required this.notice,
    required this.onTogglePrivacyMode,
    required this.onShieldBalancePressed,
    required this.onSend,
    required this.onReceive,
    required this.onActivity,
  });

  final bool isImporting;
  final double importProgress;
  final String? importingAccountName;
  final bool hasBalance;
  final String shieldedBalanceText;
  final String? shieldedFiatBalanceText;
  final double? priceChange24hPct;
  final String transparentBalanceText;
  final bool hasTransparentBalance;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final bool privacyModeEnabled;
  final List<ActivityRowData> activityRows;
  final bool isActivityLoading;
  final _HomeNoticeData? notice;
  final VoidCallback onTogglePrivacyMode;
  final VoidCallback onShieldBalancePressed;
  final VoidCallback onSend;
  final VoidCallback onReceive;
  final VoidCallback onActivity;

  static const _referencePaneHeight = 704.0;
  static const _referenceTop = 48.0;

  double _contentTop(double paneHeight) {
    return math
        .max(0, _referenceTop + ((paneHeight - _referencePaneHeight) / 2))
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentTop = _contentTop(constraints.maxHeight);
        if (!isImporting) {
          return AppPaneScrollbar(
            builder: (context, controller) => CustomScrollView(
              key: const ValueKey('home_desktop_scroll_view'),
              controller: controller,
              clipBehavior: Clip.none,
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.only(top: contentTop),
                  sliver: _HomeDesktopCenteredSliver(
                    contentKey: const ValueKey('home_desktop_content'),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s,
                      AppSpacing.sm,
                      AppSpacing.s,
                      0,
                    ),
                    child: _HomeDesktopBalanceCard(
                      hasBalance: hasBalance,
                      shieldedBalanceText: shieldedBalanceText,
                      shieldedFiatBalanceText: shieldedFiatBalanceText,
                      priceChange24hPct: priceChange24hPct,
                      transparentBalanceText: transparentBalanceText,
                      hasTransparentBalance: hasTransparentBalance,
                      canShieldBalance: canShieldBalance,
                      isShieldingBalance: isShieldingBalance,
                      privacyModeEnabled: privacyModeEnabled,
                      onTogglePrivacyMode: onTogglePrivacyMode,
                      onShieldBalancePressed: onShieldBalancePressed,
                      onSend: onSend,
                      onReceive: onReceive,
                    ),
                  ),
                ),
                if (notice != null) ...[
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.xs),
                  ),
                  _HomeDesktopCenteredSliver(
                    child: _HomeNoticeCard(data: notice!),
                  ),
                ],
                SliverPadding(
                  padding: EdgeInsets.only(
                    top: hasTransparentBalance ? AppSpacing.s : AppSpacing.md,
                  ),
                  sliver: activityRows.isEmpty
                      ? _HomeDesktopEmptyActivitySliver(
                          isLoading: isActivityLoading,
                        )
                      : _HomeDesktopCenteredSliver(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.s,
                            0,
                            AppSpacing.s,
                            AppSpacing.sm,
                          ),
                          child: _HomeDesktopActivityCard(
                            rows: activityRows.take(5).toList(),
                            onSeeAll: onActivity,
                          ),
                        ),
                ),
              ],
            ),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              top: contentTop,
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  key: const ValueKey('home_desktop_content'),
                  width: 420,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s,
                      vertical: AppSpacing.sm,
                    ),
                    child: _HomeImportingContent(
                      progress: importProgress,
                      accountName: importingAccountName,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HomeDesktopCenteredSliver extends StatelessWidget {
  const _HomeDesktopCenteredSliver({
    required this.child,
    this.contentKey,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.s),
  });

  final Widget child;
  final Key? contentKey;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          key: contentKey,
          width: 420,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _HomeImportingContent extends StatelessWidget {
  const _HomeImportingContent({required this.progress, this.accountName});

  final double progress;
  final String? accountName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pct = (progress.clamp(0.0, 0.99) * 100).round();
    final normalizedAccountName = accountName?.trim();
    final detailText =
        normalizedAccountName != null && normalizedAccountName.isNotEmpty
        ? 'Importing $normalizedAccountName\nKeep Vizor open & running.'
        : 'It might take some time.\nKeep Vizor open & running.';
    return SizedBox(
      width: 396,
      height: 624,
      child: Stack(
        children: [
          Positioned(
            left: 28,
            top: 105,
            width: 340,
            height: 414,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: 340,
                  height: 48,
                  child: Text(
                    '$pct%',
                    textAlign: TextAlign.center,
                    style: AppTypography.displayMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Positioned(
                  left: 47,
                  top: 60,
                  width: 246,
                  height: 60,
                  child: Text(
                    "We're importing\nyour wallet...",
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineMedium.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
                Positioned(
                  left: 40,
                  top: 136,
                  width: 260,
                  height: 44,
                  child: Text(
                    detailText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
                Positioned(
                  left: 47,
                  top: 222,
                  width: 246,
                  height: 192,
                  child: Image.asset(
                    'assets/illustrations/home_rest_character.png',
                    fit: BoxFit.contain,
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

class _HomeDesktopBalanceCard extends StatefulWidget {
  const _HomeDesktopBalanceCard({
    required this.hasBalance,
    required this.shieldedBalanceText,
    required this.shieldedFiatBalanceText,
    required this.priceChange24hPct,
    required this.transparentBalanceText,
    required this.hasTransparentBalance,
    required this.canShieldBalance,
    required this.isShieldingBalance,
    required this.privacyModeEnabled,
    required this.onTogglePrivacyMode,
    required this.onShieldBalancePressed,
    required this.onSend,
    required this.onReceive,
  });

  final bool hasBalance;
  final String shieldedBalanceText;
  final String? shieldedFiatBalanceText;
  final double? priceChange24hPct;
  final String transparentBalanceText;
  final bool hasTransparentBalance;
  final bool canShieldBalance;
  final bool isShieldingBalance;
  final bool privacyModeEnabled;
  final VoidCallback onTogglePrivacyMode;
  final VoidCallback onShieldBalancePressed;
  final VoidCallback onSend;
  final VoidCallback onReceive;

  @override
  State<_HomeDesktopBalanceCard> createState() =>
      _HomeDesktopBalanceCardState();
}

class _HomeDesktopBalanceCardState extends State<_HomeDesktopBalanceCard> {
  bool _isShieldBalanceHovered = false;

  void _handleShieldBalanceHoverChanged(bool hovered) {
    if (_isShieldBalanceHovered == hovered) return;
    setState(() {
      _isShieldBalanceHovered = hovered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final visibleBalance = hideIfPrivacyMode(
      widget.shieldedBalanceText,
      privacyModeEnabled: widget.privacyModeEnabled,
    );
    final isShieldBalanceHoverActive =
        widget.canShieldBalance &&
        !widget.isShieldingBalance &&
        _isShieldBalanceHovered;
    // The tray sits on the card's ground shelf (Figma 4731:64262/64704), so
    // the action rests on the accent text token. The design draws no hover
    // state; hover uses the standard ghost-button fill instead of inventing
    // a color (the old gold chevron borrowed a background utility token).
    final shieldBalanceContentColor =
        widget.isShieldingBalance || widget.canShieldBalance
        ? colors.text.accent
        : colors.text.secondary.withValues(alpha: 0.64);
    final roundedPriceChangePct = widget.priceChange24hPct == null
        ? null
        : roundZecPriceChange24hPct(widget.priceChange24hPct!);
    // Color follows the rounded (displayed) value so a -0.004% never shows
    // as a red "0.00%". Null hides the badge entirely.
    final priceChangeColor = roundedPriceChangePct == null
        ? null
        : roundedPriceChangePct > 0
        ? colors.text.positiveStrong
        : roundedPriceChangePct < 0
        ? colors.text.destructive
        : colors.text.homeCard;
    final cardRadius = BorderRadius.circular(AppRadii.large);

    return SizedBox(
      width: 396,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: cardRadius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Figma: the outer card is a ground shelf; only the balance
                // block itself carries the dark homeCard fill, leaving the
                // shield tray exposed on the bright surface.
                color: colors.background.ground,
                borderRadius: cardRadius,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 396,
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
                              key: const ValueKey(
                                'home_desktop_shielded_balance_icon',
                              ),
                              size: 20,
                              color: colors.text.homeCard,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'Shielded balance',
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.homeCard,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const Spacer(),
                            _HomeDesktopPrivacyButton(
                              privacyModeEnabled: widget.privacyModeEnabled,
                              onTap: widget.onTogglePrivacyMode,
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (widget.hasBalance &&
                            widget.shieldedFiatBalanceText != null) ...[
                          Row(
                            children: [
                              Text(
                                widget.shieldedFiatBalanceText!,
                                key: const ValueKey(
                                  'home_desktop_balance_fiat_text',
                                ),
                                // Label M per Figma (Home Card / Balance
                                // Performance): Geist Regular 14/16.
                                style: AppTypography.labelLarge.copyWith(
                                  color: colors.text.homeCard,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              // Figma separates the change run with a 4px
                              // gap plus a leading space character (~8px
                              // effective at 14px Geist).
                              if (priceChangeColor != null) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  formatZecPriceChange24hPct(
                                    widget.priceChange24hPct!,
                                  ),
                                  key: const ValueKey(
                                    'home_desktop_balance_price_change_text',
                                  ),
                                  style: AppTypography.labelLarge.copyWith(
                                    color: priceChangeColor,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                        ],
                        Row(
                          // The Figma balance is one text run (amount 45px,
                          // ticker 32px) sharing a baseline. The Regular cut
                          // stands in for the spec'd Medium: white-on-dark
                          // rasterization runs ~8% heavier than Figma's
                          // renderer, so Medium reads bolder here than the
                          // design intends.
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              widget.hasBalance ? visibleBalance : '0',
                              key: const ValueKey(
                                'home_desktop_balance_amount_text',
                              ),
                              style: AppTypography.displayMedium.copyWith(
                                color: colors.text.homeCard,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              kZcashDefaultCurrencyTicker,
                              key: const ValueKey(
                                'home_desktop_balance_currency_text',
                              ),
                              style: AppTypography.headlineLarge.copyWith(
                                color: colors.text.homeCard,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.hasTransparentBalance)
                    _HomeTransparentBalanceStrip(
                      key: const ValueKey(
                        'home_desktop_transparent_balance_strip',
                      ),
                      balanceText: widget.transparentBalanceText,
                      canShieldBalance: widget.canShieldBalance,
                      isShieldingBalance: widget.isShieldingBalance,
                      privacyModeEnabled: widget.privacyModeEnabled,
                      shieldBalanceContentColor: shieldBalanceContentColor,
                      shieldBalanceHovered: isShieldBalanceHoverActive,
                      onShieldBalancePressed: widget.onShieldBalancePressed,
                      onShieldBalanceHoverChanged:
                          _handleShieldBalanceHoverChanged,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          if (!widget.hasBalance)
            _HomeDesktopActionButton(
              key: const ValueKey('home_desktop_receive_first_button'),
              icon: AppIcons.arrowDownCircle,
              label: 'Receive your first ZEC',
              onTap: widget.onReceive,
              primary: true,
              expanded: true,
            )
          else
            Row(
              children: [
                Expanded(
                  child: _HomeDesktopActionButton(
                    key: const ValueKey('home_desktop_send_button'),
                    icon: AppIcons.plane,
                    label: 'Send',
                    onTap: widget.onSend,
                    primary: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: _HomeDesktopActionButton(
                    key: const ValueKey('home_desktop_receive_button'),
                    icon: AppIcons.arrowDownCircle,
                    label: 'Receive',
                    onTap: widget.onReceive,
                    primary: false,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HomeDesktopActionButton extends StatelessWidget {
  const _HomeDesktopActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.primary,
    this.expanded = false,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = primary
        ? colors.button.primary.label
        : colors.button.secondary.label;
    return _HomeDesktopInteractiveTarget(
      semanticsLabel: label,
      onTap: onTap,
      builder: (context, hovered, focused) {
        final bg = primary
            ? hovered
                  ? colors.button.primary.bgHover
                  : colors.button.primary.bg
            : hovered
            ? colors.button.secondary.bgHover
            : colors.button.secondary.bg;
        final focusRingColor = primary
            ? hovered
                  ? colors.button.primary.bgHover
                  : colors.button.primary.bg
            : colors.state.focusRing;

        return SizedBox(
          height: 44,
          width: expanded ? double.infinity : null,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                height: 44,
                width: expanded ? double.infinity : null,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: bg,
                  shape: const StadiumBorder(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(icon, size: 16, color: fg),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      label,
                      style: AppTypography.labelMedium.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (focused)
                Positioned(
                  left: -2,
                  top: -2,
                  right: -2,
                  bottom: -2,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: StadiumBorder(
                          side: BorderSide(color: focusRingColor, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeDesktopPrivacyButton extends StatelessWidget {
  const _HomeDesktopPrivacyButton({
    required this.privacyModeEnabled,
    required this.onTap,
  });

  final bool privacyModeEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _HomeDesktopInteractiveTarget(
      semanticsLabel: privacyModeEnabled ? 'Show balance' : 'Hide balance',
      onTap: onTap,
      builder: (context, hovered, focused) {
        return SizedBox(
          key: const ValueKey('home_desktop_privacy_button'),
          width: 32,
          height: 32,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFFFFFFF,
                  ).withValues(alpha: hovered ? 0.10 : 0.05),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AppIcon(
                    privacyModeEnabled ? AppIcons.eyeClosed : AppIcons.eye,
                    size: 16,
                    color: colors.text.homeCard,
                  ),
                ),
              ),
              if (focused)
                Positioned(
                  left: -2,
                  top: -2,
                  right: -2,
                  bottom: -2,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: CircleBorder(
                          side: BorderSide(
                            color: colors.state.focusRing,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HomeDesktopInteractiveTarget extends StatefulWidget {
  const _HomeDesktopInteractiveTarget({
    required this.onTap,
    required this.builder,
    this.semanticsLabel,
  });

  final VoidCallback onTap;
  final String? semanticsLabel;
  final Widget Function(BuildContext context, bool hovered, bool focused)
  builder;

  @override
  State<_HomeDesktopInteractiveTarget> createState() =>
      _HomeDesktopInteractiveTargetState();
}

class _HomeDesktopInteractiveTargetState
    extends State<_HomeDesktopInteractiveTarget> {
  bool _hovered = false;
  bool _focused = false;

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused != value) setState(() => _focused = value);
  }

  void _activate() {
    _setHovered(false);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: _setFocused,
          shortcuts: _homeDesktopActivationShortcuts,
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
            child: widget.builder(context, _hovered, _focused),
          ),
        ),
      ),
    );
  }
}

class _HomeDesktopEmptyActivitySliver extends StatelessWidget {
  const _HomeDesktopEmptyActivitySliver({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final remainingHeight =
            constraints.viewportMainAxisExtent -
            constraints.precedingScrollExtent;
        final height = math.max(160.0, remainingHeight - AppSpacing.sm);

        return SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 420,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s,
                  0,
                  AppSpacing.s,
                  AppSpacing.sm,
                ),
                child: SizedBox(
                  height: height,
                  child: _HomeDesktopEmptyActivity(isLoading: isLoading),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeDesktopEmptyActivity extends StatelessWidget {
  const _HomeDesktopEmptyActivity({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 160) {
          return Center(
            child: Text(
              isLoading ? 'Loading activity...' : 'No activity, yet...',
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
          );
        }
        final compact = constraints.maxHeight < 300;
        final verticalOffset = compact ? 0.0 : 32.0;
        final availableIllustrationHeight =
            constraints.maxHeight - (compact ? 116.0 : 92.0);
        final illustrationHeight = math
            .min(
              192.0,
              math.max(compact ? 64.0 : 96.0, availableIllustrationHeight),
            )
            .toDouble();
        final illustrationWidth = illustrationHeight * (246 / 192);

        return Center(
          child: Transform.translate(
            offset: Offset(0, verticalOffset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isLoading ? 'Loading activity...' : 'No activity, yet...',
                  style: AppTypography.headlineSmall.copyWith(
                    color: colors.text.accent,
                  ),
                ),
                if (!isLoading) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  SizedBox(
                    width: 188,
                    child: Text(
                      'How about running your first ZEC tx?',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Image.asset(
                    'assets/illustrations/home_rest_character.png',
                    width: illustrationWidth,
                    height: illustrationHeight,
                    fit: BoxFit.contain,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeDesktopActivityCard extends StatelessWidget {
  const _HomeDesktopActivityCard({required this.rows, required this.onSeeAll});

  final List<ActivityRowData> rows;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = context.appTheme == AppThemeData.dark;
    return Container(
      width: 396,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? colors.surface.card : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: appSurfaceShadow(colors),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HomeDesktopActivityHeader(
            onSeeAll: onSeeAll,
            titleStyle: AppTypography.labelLarge.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
            seeAllStyle: AppTypography.labelLarge.copyWith(
              color: colors.button.ghost.label,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var index = 0; index < rows.length; index++) ...[
            _HomeDesktopActivityRow(index: index, row: rows[index]),
            if (index != rows.length - 1) const SizedBox(height: AppSpacing.s),
          ],
        ],
      ),
    );
  }
}

class _HomeDesktopActivityHeader extends StatelessWidget {
  const _HomeDesktopActivityHeader({
    required this.onSeeAll,
    required this.titleStyle,
    required this.seeAllStyle,
  });

  final VoidCallback onSeeAll;
  final TextStyle titleStyle;
  final TextStyle seeAllStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Text('Recent activity', style: titleStyle),
        const Spacer(),
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSeeAll,
            child: Row(
              key: const ValueKey('home_desktop_activity_see_all_button'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('See all', style: seeAllStyle),
                const SizedBox(width: AppSpacing.xxs),
                AppIcon(
                  AppIcons.chevronForward,
                  size: 16,
                  color: colors.icon.regular,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HomeDesktopActivityRow extends StatefulWidget {
  const _HomeDesktopActivityRow({required this.index, required this.row});

  final int index;
  final ActivityRowData row;

  @override
  State<_HomeDesktopActivityRow> createState() =>
      _HomeDesktopActivityRowState();
}

class _HomeDesktopActivityRowState extends State<_HomeDesktopActivityRow> {
  bool _hovered = false;
  bool _focused = false;

  bool get _isInteractive => widget.row.onTap != null;

  void _setHovered(bool value) {
    if (_hovered != value) setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused != value) setState(() => _focused = value);
  }

  void _activate() {
    _setHovered(false);
    widget.row.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final content = _HomeDesktopActivityRowContent(
      key: ValueKey('home_desktop_activity_row_${widget.index}'),
      row: widget.row,
      hovered: _hovered,
      focused: _focused,
    );

    if (!_isInteractive) return content;
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowFocusHighlight: _setFocused,
          shortcuts: _homeDesktopActivationShortcuts,
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

class _HomeDesktopActivityRowContent extends StatelessWidget {
  const _HomeDesktopActivityRowContent({
    super.key,
    required this.row,
    required this.hovered,
    required this.focused,
  });

  final ActivityRowData row;
  final bool hovered;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amountColor = row.amountColor ?? colors.text.primary;
    final showFocus = focused || row.selected;
    return SizedBox(
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            decoration: BoxDecoration(
              color:
                  row.backgroundColor ??
                  (hovered ? colors.state.hoverOpacity : Colors.transparent),
              borderRadius: BorderRadius.circular(AppRadii.small),
            ),
            child: Row(
              children: [
                _HomeDesktopActivityGlyph(row: row),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelLarge.copyWith(
                          color: colors.text.accent,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: [
                          if (row.subtitleIconName != null) ...[
                            AppIcon(
                              row.subtitleIconName!,
                              size: 16,
                              color: colors.text.brandCrimson,
                            ),
                            const SizedBox(width: AppSpacing.xxs),
                          ],
                          Flexible(
                            child: Text(
                              row.subtitle ?? row.statusText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.labelLarge.copyWith(
                                color: colors.text.secondary,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Content Line separates its left and right blocks by 10px.
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      row.amountText,
                      style: AppTypography.labelLarge.copyWith(
                        color: amountColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      row.timestampText,
                      style: AppTypography.labelSmall.copyWith(
                        color: colors.text.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showFocus)
            Positioned(
              left: -1,
              top: -1,
              right: -1,
              bottom: -1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.state.focusRing, width: 2),
                    borderRadius: BorderRadius.circular(AppRadii.small + 1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeDesktopActivityGlyph extends StatelessWidget {
  const _HomeDesktopActivityGlyph({required this.row});

  final ActivityRowData row;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final progress = row.leadingProgressValue;
    if (progress != null) {
      return SizedBox(
        width: 32,
        height: 32,
        child: OverflowBox(
          maxWidth: 37,
          maxHeight: 37,
          child: SizedBox(
            width: 37,
            height: 37,
            child: CustomPaint(
              painter: _HomeDesktopProgressRingPainter(
                progress: progress,
                trackColor: const Color(0xFFD4D4D4),
                progressColor: const Color(0xFFC2546A),
                innerFillColor: const Color(0x339A9A9A),
              ),
              child: Center(
                child: AppIcon(
                  row.leadingIconName,
                  size: 16,
                  color: colors.icon.regular,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: AppIcon(
          row.leadingIconName,
          size: 16,
          color: colors.icon.regular,
          animated: row.statusIconName == AppIcons.loader,
        ),
      ),
    );
  }
}

class _HomeDesktopProgressRingPainter extends CustomPainter {
  const _HomeDesktopProgressRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.innerFillColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final Color innerFillColor;

  @override
  void paint(Canvas canvas, Size size) {
    const segmentCount = 4;
    const segmentGapAngle = 0.32;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide / 2) - 1.5;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final segmentStep = math.pi * 2 / segmentCount;
    final segmentSweep = segmentStep - segmentGapAngle;
    final firstStartAngle = -math.pi + (segmentGapAngle / 2);
    final filledSegments = progress <= 0
        ? 0
        : math.max(1, math.min(segmentCount, (progress * segmentCount).ceil()));

    for (var index = 0; index < segmentCount; index++) {
      canvas.drawArc(
        rect,
        firstStartAngle + (segmentStep * index),
        segmentSweep,
        false,
        trackPaint,
      );
    }
    for (var index = 0; index < filledSegments; index++) {
      canvas.drawArc(
        rect,
        firstStartAngle + (segmentStep * index),
        segmentSweep,
        false,
        progressPaint,
      );
    }
    canvas.drawCircle(center, radius - 4, Paint()..color = innerFillColor);
  }

  @override
  bool shouldRepaint(covariant _HomeDesktopProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.innerFillColor != innerFillColor;
  }
}
