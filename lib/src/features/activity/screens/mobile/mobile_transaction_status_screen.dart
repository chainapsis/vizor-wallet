import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../main.dart' show log;
import '../../../../core/config/zcash_explorer.dart';
import '../../../../core/formatting/address_display.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/privacy/privacy_mask.dart';
import '../../../../core/storage/wallet_paths.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/mobile/mobile_address_verify_sheet.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/privacy_mode_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../activity_row_mapper.dart' show formatActivityTimestamp;

/// Route arguments for [MobileTransactionStatusScreen]. The row that
/// was tapped passes its [initialTransaction] so the screen renders
/// immediately; the screen refreshes itself from the wallet DB.
class MobileTransactionStatusArgs {
  const MobileTransactionStatusArgs({
    required this.txidHex,
    this.txKind,
    this.initialTransaction,
  });

  final String txidHex;
  final String? txKind;
  final rust_sync.TransactionInfo? initialTransaction;
}

/// Loads the transaction history; injectable so widget tests can avoid
/// the Rust FFI.
typedef MobileTxHistoryLoader =
    Future<List<rust_sync.TransactionInfo>> Function(String accountUuid);

/// Loads one transaction's detail; injectable for widget tests.
typedef MobileTxDetailLoader =
    Future<rust_sync.TransactionDetail?> Function(
      String accountUuid,
      rust_sync.TransactionInfo transaction,
    );

/// Mobile transaction status/detail — Figma `ACTIVITY & STATUS` frames
/// `Status Sending` (4752:70731), `Status Scucess` (4752:71303),
/// `Status Fail` (4752:71663), and `Received` (4752:75264): the serif
/// review header (amount / counterparty with the flow arrow) above the
/// rounded detail card (status chip, message, timestamp, tx id, fee).
class MobileTransactionStatusScreen extends ConsumerStatefulWidget {
  const MobileTransactionStatusScreen({
    required this.args,
    this.historyLoader,
    this.detailLoader,
    super.key,
  });

  final MobileTransactionStatusArgs args;

  /// Test seam — production reads the wallet DB through Rust.
  @visibleForTesting
  final MobileTxHistoryLoader? historyLoader;

  /// Test seam — production reads the wallet DB through Rust.
  @visibleForTesting
  final MobileTxDetailLoader? detailLoader;

  @override
  ConsumerState<MobileTransactionStatusScreen> createState() =>
      _MobileTransactionStatusScreenState();
}

class _MobileTransactionStatusScreenState
    extends ConsumerState<MobileTransactionStatusScreen> {
  rust_sync.TransactionInfo? _transaction;
  rust_sync.TransactionDetail? _detail;
  String? _error;
  String? _activeAccountUuid;
  bool _messageExpanded = false;

  @override
  void initState() {
    super.initState();
    _transaction = widget.args.initialTransaction;
    _activeAccountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    unawaited(_loadTransaction());
  }

  Future<List<rust_sync.TransactionInfo>> _loadHistory(
    String accountUuid,
  ) async {
    final loader = widget.historyLoader;
    if (loader != null) return loader(accountUuid);
    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointProvider);
    return rust_sync.getTransactionHistory(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
    );
  }

  Future<rust_sync.TransactionDetail?> _loadDetail(
    String accountUuid,
    rust_sync.TransactionInfo transaction,
  ) async {
    final loader = widget.detailLoader;
    if (loader != null) return loader(accountUuid, transaction);
    final dbPath = await getWalletDbPath();
    final endpoint = ref.read(rpcEndpointProvider);
    return rust_sync.getTransactionDetail(
      dbPath: dbPath,
      network: endpoint.networkName,
      accountUuid: accountUuid,
      txidHex: transaction.txidHex,
      txKind: transaction.txKind,
    );
  }

  Future<void> _loadTransaction() async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    _activeAccountUuid = accountUuid;
    if (accountUuid == null) {
      if (!mounted) return;
      setState(() => _error = 'No active account.');
      return;
    }

    try {
      final txs = await _loadHistory(accountUuid);
      if (!mounted ||
          accountUuid != ref.read(accountProvider).value?.activeAccountUuid) {
        return;
      }
      final tx = _findTransaction(txs);
      rust_sync.TransactionDetail? detail;
      if (tx != null) {
        try {
          detail = await _loadDetail(accountUuid, tx);
        } catch (e, st) {
          log('MobileTransactionStatus: detail load failed: $e\n$st');
        }
        if (!mounted ||
            accountUuid != ref.read(accountProvider).value?.activeAccountUuid) {
          return;
        }
      }
      setState(() {
        if (tx != null) {
          _transaction = tx;
          _detail = detail;
          _error = null;
        } else if (_transaction == null) {
          _error = 'Transaction could not be loaded.';
        }
      });
    } catch (e, st) {
      log('MobileTransactionStatus: transaction load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = _transaction == null
            ? 'Transaction could not be loaded.'
            : 'Latest transaction status could not be refreshed.';
      });
    }
  }

  rust_sync.TransactionInfo? _findTransaction(
    Iterable<rust_sync.TransactionInfo> transactions,
  ) {
    final normalized = widget.args.txidHex.toLowerCase();
    final txKind =
        _transaction?.txKind ??
        widget.args.initialTransaction?.txKind ??
        widget.args.txKind;
    for (final tx in transactions) {
      if (tx.txidHex.toLowerCase() != normalized) continue;
      if (txKind == null || _txKindMatches(txKind, tx.txKind)) return tx;
    }
    return null;
  }

  bool _txKindMatches(String expected, String actual) {
    if (expected == actual) return true;
    return (expected == 'receiving' && actual == 'received') ||
        (expected == 'received' && actual == 'receiving');
  }

  String _recentTxSignature(SyncState? sync) {
    final txid = widget.args.txidHex.toLowerCase();
    for (final tx in sync?.recentTransactions ?? const []) {
      if (tx.txidHex.toLowerCase() == txid) {
        return '${tx.txidHex}:${tx.minedHeight}:${tx.expiredUnmined}:'
            '${tx.txKind}:${tx.displayAmount}';
      }
    }
    return '';
  }

  _TxPhase get _phase {
    final tx = _transaction;
    if (tx == null) return _TxPhase.pending;
    if (tx.expiredUnmined) return _TxPhase.failed;
    if (tx.minedHeight == BigInt.zero) return _TxPhase.pending;
    return _TxPhase.succeeded;
  }

  bool get _isIncoming {
    final kind = _transaction?.txKind ?? widget.args.txKind;
    return kind == 'received' || kind == 'receiving';
  }

  bool get _isShielding =>
      (_transaction?.txKind ?? widget.args.txKind) == 'shielded';

  String get _title {
    if (_isShielding) return 'Shielded';
    if (_isIncoming) {
      return _phase == _TxPhase.pending ? 'Receiving...' : 'Received';
    }
    return switch (_phase) {
      _TxPhase.pending => 'Sending...',
      _TxPhase.succeeded => 'Sent successfully',
      _TxPhase.failed => 'Send failed',
    };
  }

  Future<void> _openExplorer() async {
    final endpoint = ref.read(rpcEndpointProvider);
    final launched = await launchZcashExplorerTransaction(
      networkName: endpoint.networkName,
      txidHex: widget.args.txidHex,
      txidOrder: ZcashExplorerTxidOrder.protocol,
    );
    if (launched || !mounted) return;
    await Clipboard.setData(ClipboardData(text: widget.args.txidHex));
    if (!mounted) return;
    showAppToast(context, 'Transaction Hash Copied');
  }

  Future<void> _showFullAddressSheet(String address) {
    return showMobileAddressVerifySheet(
      context,
      title: _addressVerifyTitle(address),
      address: address,
      leading: _AddressVerifyZecIcon(address: address),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AccountState>>(accountProvider, (previous, next) {
      final nextUuid = next.value?.activeAccountUuid;
      if (nextUuid != _activeAccountUuid) unawaited(_loadTransaction());
    });
    ref.listen<AsyncValue<SyncState>>(syncProvider, (previous, next) {
      if (_recentTxSignature(previous?.value) !=
          _recentTxSignature(next.value)) {
        unawaited(_loadTransaction());
      }
    });

    final colors = context.colors;
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final tx = _transaction;
    final detail = _detail;
    final failed = _phase == _TxPhase.failed;

    final amountText = _amountText(tx, privacyModeEnabled: privacyModeEnabled);
    final primaryAddress = detail?.primaryAddress?.trim();
    final sourceAddress = detail?.sourceAddress?.trim();
    final sourcePool = detail?.sourcePool?.trim().toLowerCase();
    final receivingOutput = _isIncoming ? _receivingOutputFor(detail) : null;
    final receivingAddress = receivingOutput?.address?.trim();
    final address = _isIncoming ? sourceAddress : primaryAddress;
    final poolLabel = _isIncoming
        ? _addressPoolLabel(sourcePool, sourceAddress)
        : _addressPoolLabel(tx?.displayPool, primaryAddress);
    final receivingPoolLabel = _addressPoolLabel(
      receivingOutput?.pool,
      receivingAddress,
    );
    final memo = detail?.memo?.trim();

    final hasAddress = address != null && address.isNotEmpty;
    final amountBottom =
        _isIncoming && receivingAddress != null && receivingAddress.isNotEmpty
        ? _BottomInfoRow(
            iconName: _poolIconNameFor(
              receivingPoolLabel,
              address: receivingAddress,
            ),
            iconColor: _poolIconColorFor(
              context,
              receivingPoolLabel,
              address: receivingAddress,
            ),
            text: _truncateAddress(receivingAddress),
          )
        : !hasAddress && poolLabel != null
        ? _BottomInfoRow(
            iconName: _poolIconNameFor(poolLabel),
            iconColor: _poolIconColorFor(context, poolLabel),
            text: poolLabel,
          )
        : null;
    final amountRow = _ReviewInfoRow(
      label: 'Amount',
      value: amountText,
      leading: const _ZecCoinBadge(),
      // With no counterparty row (shielded senders are unknown), the
      // pool tag moves under the amount — Figma `Received` keeps the
      // pool on the bottom strip.
      bottom: amountBottom,
    );
    final addressRow = (address == null || address.isEmpty)
        ? null
        : _ReviewInfoRow(
            label: _isIncoming ? 'From' : 'To',
            value: _truncateAddress(address),
            strikethrough: failed,
            leading: _IconBadge(
              child: AppIcon(
                AppIcons.wallet,
                size: 18,
                color: colors.icon.regular,
              ),
            ),
            bottom: _BottomInfoRow(
              iconName: poolLabel == null
                  ? null
                  : _poolIconNameFor(poolLabel, address: address),
              iconColor: poolLabel == null
                  ? null
                  : _poolIconColorFor(context, poolLabel, address: address),
              text: poolLabel,
              trailing: _GhostIconLabelButton(
                key: const ValueKey('mobile_tx_status_show_full_address'),
                iconName: AppIcons.eye,
                label: 'Show full address',
                onTap: () => unawaited(_showFullAddressSheet(address)),
              ),
            ),
          );
    final unknownFromLabel = _isIncoming && addressRow == null
        ? _unknownFromLabelForSourcePool(sourcePool)
        : null;
    final unknownFromRow = unknownFromLabel == null
        ? null
        : _ReviewInfoRow(
            label: 'From',
            value: unknownFromLabel,
            leading: _IconBadge(
              child: AppIcon(
                AppIcons.wallet,
                size: 18,
                color: colors.icon.regular,
              ),
            ),
            bottom: sourcePool == 'shielded'
                ? _BottomInfoRow(
                    iconName: _poolIconNameFor('Shielded'),
                    iconColor: _poolIconColorFor(context, 'Shielded'),
                    text: 'Shielded',
                  )
                : null,
          );

    // Sent flows read top-down as amount -> recipient; received flows as
    // sender source -> amount, with the receiving output attached under
    // Amount (Figma `Received` 4752:75264).
    final fromRow = _isIncoming ? addressRow ?? unknownFromRow : null;
    final reviewChildren = _isIncoming
        ? <Widget>[
            if (fromRow != null) ...[fromRow, const _FlowArrow()],
            amountRow,
          ]
        : addressRow == null
        ? <Widget>[amountRow]
        : <Widget>[amountRow, const _FlowArrow(), addressRow];

    return Scaffold(
      backgroundColor: colors.background.window,
      body: AppToastHost(
        child: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: _title,
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('mobile_tx_status_scroll'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.s,
                    AppSpacing.sm,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < reviewChildren.length; i++) ...[
                              if (i > 0) const SizedBox(height: AppSpacing.xs),
                              reviewChildren[i],
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _DetailCard(
                        phase: _phase,
                        failed: failed,
                        memo: memo,
                        messageExpanded: _messageExpanded,
                        onToggleMessage: () => setState(
                          () => _messageExpanded = !_messageExpanded,
                        ),
                        timestampText: _dateText(tx),
                        txidText: _truncateTxid(widget.args.txidHex),
                        onOpenExplorer: () => unawaited(_openExplorer()),
                        feeText: _feeText(
                          tx,
                          privacyModeEnabled: privacyModeEnabled,
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodySmall.copyWith(
                            color: colors.text.destructive,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _amountText(
    rust_sync.TransactionInfo? tx, {
    required bool privacyModeEnabled,
  }) {
    if (tx == null) return '--';
    if (privacyModeEnabled) {
      return hideAmountIfPrivacyMode('', privacyModeEnabled: true);
    }
    if (tx.displayAmount == BigInt.zero) return '--';
    return ZecAmount.fromZatoshi(tx.displayAmount).activityDetail.toString();
  }

  String _dateText(rust_sync.TransactionInfo? tx) {
    if (tx == null) return '--';
    final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
    if (seconds <= BigInt.zero) return '--';
    return formatActivityTimestamp(
      DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000),
    );
  }

  String? _feeText(
    rust_sync.TransactionInfo? tx, {
    required bool privacyModeEnabled,
  }) {
    if (tx == null || tx.fee <= BigInt.zero) return null;
    if (privacyModeEnabled) {
      return hideAmountIfPrivacyMode('', privacyModeEnabled: true);
    }
    return ZecAmount.fromZatoshi(tx.fee).fee.toString();
  }

  String? _poolLabel(String? pool) {
    return switch (pool) {
      'transparent' => 'Transparent',
      'shielded' => 'Shielded',
      'mixed' => 'Mixed',
      _ => null,
    };
  }

  String? _addressPoolLabel(String? pool, String? address) {
    final lower = address?.trim().toLowerCase();
    if (lower != null && lower.startsWith('tex')) return 'TEX';
    return _poolLabel(pool);
  }

  String _poolIconNameFor(String? poolLabel, {String? address}) {
    final isTransparent =
        poolLabel == 'Transparent' ||
        (address != null &&
            zcashAddressDisplayKind(address) ==
                ZcashAddressDisplayKind.transparent);
    return isTransparent ? AppIcons.transparentBalance : AppIcons.shieldKeyhole;
  }

  Color _poolIconColorFor(
    BuildContext context,
    String? poolLabel, {
    String? address,
  }) {
    final isTransparent =
        poolLabel == 'Transparent' ||
        (address != null &&
            zcashAddressDisplayKind(address) ==
                ZcashAddressDisplayKind.transparent);
    return isTransparent
        ? context.colors.icon.muted
        : context.colors.icon.brandCrimson;
  }

  rust_sync.TransactionDetailOutput? _receivingOutputFor(
    rust_sync.TransactionDetail? detail,
  ) {
    rust_sync.TransactionDetailOutput? best;
    final outputs =
        detail?.outputs ?? const <rust_sync.TransactionDetailOutput>[];
    for (final output in outputs) {
      final address = output.address?.trim();
      if (address == null || address.isEmpty) continue;
      if (best == null || output.amountZatoshi > best.amountZatoshi) {
        best = output;
      }
    }
    return best;
  }

  String? _unknownFromLabelForSourcePool(String? pool) {
    if (pool == null || pool.isEmpty) return null;
    return pool == 'shielded' ? 'Shielded sender' : 'Unknown sender';
  }

  String _addressVerifyTitle(String address) {
    final lower = address.trim().toLowerCase();
    if (lower.startsWith('u1')) return 'Unified address';
    if (lower.startsWith('zs')) return 'Shielded address';
    if (lower.startsWith('t')) return 'Transparent address';
    return 'Zcash address';
  }

  String _truncateAddress(String address) {
    if (address.length <= 14) return address;
    return '${address.substring(0, 6)} ... '
        '${address.substring(address.length - 5)}';
  }

  String _truncateTxid(String txid) {
    if (txid.length <= 16) return txid;
    return '${txid.substring(0, 8)}...${txid.substring(txid.length - 8)}';
  }
}

class _AddressVerifyZecIcon extends StatelessWidget {
  const _AddressVerifyZecIcon({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    final isTransparent =
        zcashAddressDisplayKind(address) == ZcashAddressDisplayKind.transparent;
    final colors = context.colors;
    return Container(
      width: AppAssetSize.size,
      height: AppAssetSize.size,
      decoration: BoxDecoration(
        color: colors.background.neutralSubtleOpacity,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: AppIcon(
          isTransparent
              ? AppIcons.transparentBalance
              : AppIcons.shieldKeyholeOutline,
          size: AppIconSize.medium,
          color: isTransparent ? colors.icon.muted : colors.icon.brandCrimson,
        ),
      ),
    );
  }
}

enum _TxPhase { pending, succeeded, failed }

class _BottomInfoRow extends StatelessWidget {
  const _BottomInfoRow({
    required this.text,
    this.iconName,
    this.iconColor,
    this.trailing,
  });

  final String? text;
  final String? iconName;
  final Color? iconColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final label = text;
    final trailingWidget = trailing;
    return LayoutBuilder(
      builder: (context, constraints) {
        final leadingWidth = iconName == null
            ? 0.0
            : AppIconSize.medium + AppSpacing.xxs;
        final maxTrailingWidth = constraints.hasBoundedWidth
            ? (constraints.maxWidth - leadingWidth)
                  .clamp(0.0, constraints.maxWidth)
                  .toDouble()
            : double.infinity;

        return Row(
          children: [
            if (iconName != null) ...[
              AppIcon(
                iconName!,
                size: AppIconSize.medium,
                color: iconColor ?? context.colors.text.secondary,
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
            if (label != null)
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelMedium.copyWith(
                    color: context.colors.text.secondary,
                  ),
                ),
              )
            else
              const Spacer(),
            if (trailingWidget != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxTrailingWidth),
                child: trailingWidget,
              ),
          ],
        );
      },
    );
  }
}

/// One serif review row — Figma `_Reivew Info` (4265:59148): a 40px
/// leading badge, the small grey label, the Headline L serif value, and
/// an optional bottom strip (pool tag / show-full-address).
class _ReviewInfoRow extends StatelessWidget {
  const _ReviewInfoRow({
    required this.label,
    required this.value,
    required this.leading,
    this.bottom,
    this.strikethrough = false,
  });

  final String label;
  final String value;
  final Widget leading;
  final Widget? bottom;
  final bool strikethrough;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 90),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 40, child: Center(child: leading)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 24,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: AppTypography.labelMedium.copyWith(
                        color: colors.text.secondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.headlineLarge.copyWith(
                    color: colors.text.accent,
                    decoration: strikethrough
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                SizedBox(height: 24, child: bottom ?? const SizedBox()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The 24px flow arrow centered under the 40px badge column.
class _FlowArrow extends StatelessWidget {
  const _FlowArrow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: Center(
        child: AppIcon(
          AppIcons.arrowDown,
          size: AppIconSize.large,
          color: context.colors.icon.accent,
        ),
      ),
    );
  }
}

/// The round ZEC coin — Figma `Asset Image` with the ZEC network logo.
class _ZecCoinBadge extends StatelessWidget {
  const _ZecCoinBadge();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.full),
      child: Image.asset(
        'assets/swap/tokens/zec.png',
        width: 32,
        height: 32,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// 40x32 rounded badge on the neutral subtle-opacity fill.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 32,
      decoration: BoxDecoration(
        color: context.colors.background.neutralSubtleOpacity,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: Center(child: child),
    );
  }
}

/// Ghost icon+label action, 24px tall — Figma ghost `Button`.
class _GhostIconLabelButton extends StatelessWidget {
  const _GhostIconLabelButton({
    required this.iconName,
    required this.label,
    required this.onTap,
    super.key,
  });

  final String iconName;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppIcon(
                iconName,
                size: AppIconSize.medium,
                color: colors.button.ghost.label,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge.copyWith(
                    color: colors.button.ghost.label,
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

/// The rounded detail card — Figma `Review Wrap`: status chip, message
/// / timestamp / tx id list, divider, tx fee.
class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.phase,
    required this.failed,
    required this.memo,
    required this.messageExpanded,
    required this.onToggleMessage,
    required this.timestampText,
    required this.txidText,
    required this.onOpenExplorer,
    required this.feeText,
  });

  final _TxPhase phase;
  final bool failed;
  final String? memo;
  final bool messageExpanded;
  final VoidCallback onToggleMessage;
  final String timestampText;
  final String txidText;
  final VoidCallback onOpenExplorer;
  final String? feeText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final memoText = memo;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.base,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ListRow(
            label: 'Status',
            labelColor: failed ? colors.text.destructive : null,
            value: _StatusChip(phase: phase),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (memoText != null && memoText.isNotEmpty) ...[
            _ListRow(
              label: 'Message',
              value: _ValueWithIcon(
                key: const ValueKey('mobile_tx_status_message_toggle'),
                text: messageExpanded ? null : _previewMemo(memoText),
                iconName: AppIcons.expand,
                onTap: onToggleMessage,
              ),
            ),
            if (messageExpanded)
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.xxs,
                  right: AppSpacing.xxs,
                  bottom: AppSpacing.xs,
                ),
                child: Text(
                  memoText,
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.accent,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
          ],
          _ListRow(
            label: 'Timestamp',
            value: _ValueWithIcon(text: timestampText),
          ),
          const SizedBox(height: AppSpacing.xs),
          _ListRow(
            key: const ValueKey('mobile_tx_status_txid'),
            label: 'Tx ID',
            value: _ValueWithIcon(
              text: txidText,
              iconName: AppIcons.arrowTopRight,
              onTap: onOpenExplorer,
            ),
          ),
          if (feeText != null) ...[
            const SizedBox(height: AppSpacing.sm),
            // Figma `border/neutral/default` (#d4d4d4 light).
            Container(height: 1, color: colors.border.regular),
            const SizedBox(height: AppSpacing.sm),
            _ListRow(
              label: 'Tx fee',
              labelStyle: AppTypography.labelLarge,
              value: _ValueWithIcon(text: feeText, iconName: AppIcons.help),
            ),
          ],
        ],
      ),
    );
  }

  String _previewMemo(String memoText) {
    final collapsed = memoText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.length <= 18) return collapsed;
    return '${collapsed.substring(0, 18).trimRight()}...';
  }
}

/// One 32px-tall label/value line of the detail card.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.label,
    required this.value,
    this.labelColor,
    this.labelStyle,
    super.key,
  });

  final String label;
  final Widget value;
  final Color? labelColor;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              label,
              style: (labelStyle ?? AppTypography.labelMedium).copyWith(
                color: labelColor ?? colors.text.secondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: value),
          ),
        ],
      ),
    );
  }
}

/// Right-side value: text plus an optional trailing 20px icon, padded
/// like the Figma `Item Right` (8 left, 4 right/vertical).
class _ValueWithIcon extends StatelessWidget {
  const _ValueWithIcon({this.text, this.iconName, this.onTap, super.key});

  final String? text;
  final String? iconName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xxs,
        AppSpacing.xxs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (text != null)
            Flexible(
              child: Text(
                text!,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: AppTypography.labelLarge.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
          if (iconName != null) ...[
            const SizedBox(width: AppSpacing.xxs),
            AppIcon(iconName!, size: 20, color: colors.icon.accent),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// Status chip: spinner + "In progress", green check + "Completed", or
/// destructive cross + "Failed, funds returned".
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.phase});

  final _TxPhase phase;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (iconName, text, color) = switch (phase) {
      _TxPhase.pending => (
        AppIcons.loader,
        'In progress',
        colors.text.secondary,
      ),
      _TxPhase.succeeded => (
        AppIcons.checkCircle,
        'Completed',
        colors.text.positiveStrong,
      ),
      // The Figma frame says "Failed, refunded minus tx fee", but the
      // only failure the wallet records is expiry before mining, where
      // no fee is spent at all.
      _TxPhase.failed => (
        AppIcons.cross,
        'Failed, funds returned',
        colors.text.destructive,
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.xxs,
        AppSpacing.xxs,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (phase == _TxPhase.pending)
            _SpinningIcon(color: color)
          else
            AppIcon(iconName, size: 20, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The in-progress loader, slowly rotating; static under reduce-motion.
class _SpinningIcon extends StatefulWidget {
  const _SpinningIcon({required this.color});

  final Color color;

  @override
  State<_SpinningIcon> createState() => _SpinningIconState();
}

class _SpinningIconState extends State<_SpinningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (motion && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!motion && _controller.isAnimating) {
      _controller.stop();
    }
    return RotationTransition(
      turns: _controller,
      child: AppIcon(AppIcons.loader, size: 20, color: widget.color),
    );
  }
}
