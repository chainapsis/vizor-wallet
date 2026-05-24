import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../main.dart' show log;
import '../../../core/formatting/zec_amount.dart';
import '../../../core/config/zcash_explorer.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_back_link.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/hidden_memos_provider.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../send/widgets/transaction_receipt_view.dart';
import '../models/memo_hide_key.dart';

class ActivityTransactionStatusArgs {
  const ActivityTransactionStatusArgs({
    required this.txidHex,
    this.txKind,
    this.initialTransaction,
    this.initialDetail,
  });

  final String txidHex;
  final String? txKind;
  final rust_sync.TransactionInfo? initialTransaction;
  final rust_sync.TransactionDetail? initialDetail;
}

class ActivityTransactionStatusScreen extends ConsumerStatefulWidget {
  const ActivityTransactionStatusScreen({super.key, required this.args});

  final ActivityTransactionStatusArgs args;

  @override
  ConsumerState<ActivityTransactionStatusScreen> createState() =>
      _ActivityTransactionStatusScreenState();
}

class _ActivityTransactionStatusScreenState
    extends ConsumerState<ActivityTransactionStatusScreen> {
  rust_sync.TransactionInfo? _transaction;
  rust_sync.TransactionDetail? _detail;
  bool _isLoading = false;
  String? _error;
  String? _activeAccountUuid;
  bool _messageExpanded = false;

  @override
  void initState() {
    super.initState();
    _transaction = widget.args.initialTransaction;
    _detail = widget.args.initialDetail;
    _activeAccountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
      unawaited(_loadTransaction(showLoading: _transaction == null));
    });
  }

  Future<void> _loadTransaction({bool showLoading = false}) async {
    final accountUuid = ref.read(accountProvider).value?.activeAccountUuid;
    _activeAccountUuid = accountUuid;

    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    if (accountUuid == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'No active account.';
      });
      return;
    }

    try {
      final dbPath = await getWalletDbPath();
      final endpoint = ref.read(rpcEndpointProvider);
      final txs = await rust_sync.getTransactionHistory(
        dbPath: dbPath,
        network: endpoint.networkName,
        accountUuid: accountUuid,
      );
      if (!mounted) return;
      if (accountUuid != ref.read(accountProvider).value?.activeAccountUuid) {
        return;
      }

      final tx = _findTransaction(
        txs,
        widget.args.txidHex,
        txKind:
            _transaction?.txKind ??
            widget.args.initialTransaction?.txKind ??
            widget.args.txKind,
      );
      rust_sync.TransactionDetail? detail;
      if (tx != null) {
        try {
          detail = rust_sync.getTransactionDetail(
            dbPath: dbPath,
            network: endpoint.networkName,
            accountUuid: accountUuid,
            txidHex: tx.txidHex,
            txKind: tx.txKind,
          );
        } catch (e, st) {
          log('ActivityTransactionStatus: detail load failed: $e\n$st');
        }
        if (!mounted) return;
        if (accountUuid != ref.read(accountProvider).value?.activeAccountUuid) {
          return;
        }
      }
      setState(() {
        if (tx != null) {
          _transaction = tx;
          _detail = detail;
          _error = null;
        } else {
          _detail = null;
          _error = _transaction == null
              ? 'Transaction could not be loaded.'
              : 'Latest transaction status could not be refreshed.';
        }
        _isLoading = false;
      });
    } catch (e, st) {
      log('ActivityTransactionStatus: transaction load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _detail = null;
        _error = _transaction == null
            ? 'Transaction could not be loaded.'
            : 'Latest transaction status could not be refreshed.';
        _isLoading = false;
      });
    }
  }

  rust_sync.TransactionInfo? _findTransaction(
    Iterable<rust_sync.TransactionInfo> transactions,
    String txidHex, {
    String? txKind,
  }) {
    final normalized = txidHex.toLowerCase();
    if (txKind != null) {
      for (final tx in transactions) {
        if (tx.txidHex.toLowerCase() == normalized &&
            _txKindMatches(txKind, tx.txKind)) {
          return tx;
        }
      }
      return null;
    }
    for (final tx in transactions) {
      if (tx.txidHex.toLowerCase() == normalized) return tx;
    }
    return null;
  }

  String _recentTxSignature(SyncState? sync) {
    final txid = widget.args.txidHex.toLowerCase();
    final txKind =
        _transaction?.txKind ??
        widget.args.initialTransaction?.txKind ??
        widget.args.txKind;
    if (txKind != null) {
      for (final tx in sync?.recentTransactions ?? const []) {
        if (tx.txidHex.toLowerCase() == txid &&
            _txKindMatches(txKind, tx.txKind)) {
          return [
            tx.txidHex,
            tx.minedHeight,
            tx.expiredUnmined,
            tx.txKind,
            tx.displayAmount,
          ].join(':');
        }
      }
      return '';
    }
    for (final tx in sync?.recentTransactions ?? const []) {
      if (tx.txidHex.toLowerCase() == txid) {
        return [
          tx.txidHex,
          tx.minedHeight,
          tx.expiredUnmined,
          tx.txKind,
          tx.displayAmount,
        ].join(':');
      }
    }
    return '';
  }

  bool _txKindMatches(String expected, String actual) {
    if (expected == actual) return true;
    return (expected == 'receiving' && actual == 'received') ||
        (expected == 'received' && actual == 'receiving');
  }

  Future<void> _copyTransactionHash() async {
    await _copyText(widget.args.txidHex, 'Transaction Hash Copied');
  }

  Future<void> _openTransactionExplorer() async {
    final endpoint = ref.read(rpcEndpointProvider);
    final launched = await launchZcashExplorerTransaction(
      networkName: endpoint.networkName,
      txidHex: widget.args.txidHex,
      txidOrder: ZcashExplorerTxidOrder.protocol,
    );
    if (launched || !mounted) return;
    await _copyText(widget.args.txidHex, 'Transaction Hash Copied');
  }

  Future<void> _copyText(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showAppToast(context, message);
  }

  void _toggleMessageExpanded() {
    setState(() {
      _messageExpanded = !_messageExpanded;
    });
  }

  TransactionReceiptPhase _phaseFor(rust_sync.TransactionInfo? tx) {
    if (tx == null) {
      return _isLoading
          ? TransactionReceiptPhase.loading
          : TransactionReceiptPhase.failed;
    }
    if (tx.expiredUnmined) return TransactionReceiptPhase.failed;
    if (tx.minedHeight == BigInt.zero) return TransactionReceiptPhase.pending;
    return TransactionReceiptPhase.succeeded;
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
    return hideAmountIfPrivacyMode(
      ZecAmount.fromZatoshi(tx.displayAmount).activity.toString(),
      privacyModeEnabled: privacyModeEnabled,
    );
  }

  String _dateText(rust_sync.TransactionInfo? tx) {
    if (tx == null) return '--';
    final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
    if (seconds <= BigInt.zero) return '--';
    return _formatDate(
      DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000),
    );
  }

  String _feeText(
    rust_sync.TransactionInfo? tx, {
    required bool privacyModeEnabled,
  }) {
    if (tx == null || tx.fee <= BigInt.zero) return '--';
    return hideAmountIfPrivacyMode(
      ZecAmount.fromZatoshi(tx.fee).fee.toString(),
      privacyModeEnabled: privacyModeEnabled,
    );
  }

  String _formatDate(DateTime value) {
    const months = <String>[
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${months[local.month]} ${local.day}, ${local.year} $hh:$mm';
  }

  List<String> _splitTxid(String txid) {
    if (txid.length <= 32) return [txid];
    return [txid.substring(0, 32), txid.substring(32)];
  }

  rust_sync.TransactionDetail? _matchingDetailFor(
    rust_sync.TransactionInfo? tx,
  ) {
    final detail = _detail;
    if (tx == null || detail == null) return null;
    if (detail.txidHex.toLowerCase() != tx.txidHex.toLowerCase()) {
      return null;
    }
    if (!_txKindMatches(detail.txKind, tx.txKind)) return null;
    return detail;
  }

  TransactionReceiptBlockData _transactionHashBlock(BuildContext context) {
    final colors = context.colors;
    final txidLines = _splitTxid(widget.args.txidHex);
    return TransactionReceiptBlockData(
      title: 'Transaction Hash',
      onCopy: () => unawaited(_copyTransactionHash()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in txidLines)
            Text(
              line,
              style: AppTypography.codeSmall.copyWith(
                color: colors.text.accent,
              ),
            ),
        ],
      ),
    );
  }

  TransactionReceiptBlockData _addressBlock(
    BuildContext context, {
    required String title,
    required String address,
    bool useFailedReceiptLayout = false,
    bool compactAddress = false,
  }) {
    final colors = context.colors;
    final trimmedAddress = address.trim();
    return TransactionReceiptBlockData(
      title: title,
      onCopy: () => unawaited(_copyText(trimmedAddress, 'Address Copied')),
      child: TransactionReceiptAddressText(
        address: trimmedAddress,
        highlightEdges: _shouldHighlightAddressEdges(trimmedAddress),
        compact: compactAddress,
        highlightColor: useFailedReceiptLayout
            ? colors.text.destructive
            : colors.text.success,
      ),
    );
  }

  bool _shouldHighlightAddressEdges(String address) {
    return address.startsWith('u1') || address.startsWith('zs');
  }

  TransactionReceiptBlockData _primaryBlockFor(
    BuildContext context,
    rust_sync.TransactionInfo? tx,
    rust_sync.TransactionDetail? detail,
  ) {
    final primaryAddress = detail?.primaryAddress?.trim();
    final useFailedReceiptLayout = tx?.expiredUnmined == true;
    final compactAddress = detail?.memo?.trim().isNotEmpty == true;
    if (tx?.txKind == 'sent' &&
        primaryAddress != null &&
        primaryAddress.isNotEmpty) {
      return _addressBlock(
        context,
        title: 'To',
        address: primaryAddress,
        useFailedReceiptLayout: useFailedReceiptLayout,
        compactAddress: compactAddress,
      );
    }
    if ((tx?.txKind == 'received' || tx?.txKind == 'receiving') &&
        primaryAddress != null &&
        primaryAddress.isNotEmpty) {
      return _addressBlock(
        context,
        title: 'From',
        address: primaryAddress,
        useFailedReceiptLayout: useFailedReceiptLayout,
        compactAddress: compactAddress,
      );
    }
    return _transactionHashBlock(context);
  }

  /// Computes whether the detail's memo is currently hidden for the active
  /// account. Returns false when there is no memo, no `memoOutputKey`, or no
  /// active account. [hiddenKeys] is the reactive hidden-set for the active
  /// account (read via `ref.watch` in [build]).
  bool _isMemoHidden(
    rust_sync.TransactionDetail? detail,
    Set<String> hiddenKeys,
  ) {
    final memoOutputKey = detail?.memoOutputKey;
    final accountUuid = _activeAccountUuid;
    if (memoOutputKey == null ||
        accountUuid == null ||
        accountUuid.isEmpty) {
      return false;
    }
    final hideKey = memoHideKeyFromDetail(
      txidHex: widget.args.txidHex,
      memoOutputKey: memoOutputKey,
    );
    return hiddenKeys.contains(hideKey);
  }

  List<TransactionReceiptBlockData> _extraBlocksFor(
    rust_sync.TransactionDetail? detail, {
    required bool isMemoHidden,
  }) {
    final memo = detail?.memo?.trim();
    if (memo == null || memo.isEmpty) return const [];
    return [
      TransactionReceiptBlockData(
        title: 'Message',
        // Restore the pre-extraction layout: the expand/collapse toggle sits
        // beside the "Message" title. When the memo is hidden, no toggle —
        // the placeholder + Restore live in the child instead.
        titleTrailing: isMemoHidden
            ? null
            : TransactionReceiptMessageToggle(
                expanded: _messageExpanded,
                onTap: _toggleMessageExpanded,
              ),
        child: MemoDetailSection(
          txidHex: widget.args.txidHex,
          detail: detail!,
          accountUuid: _activeAccountUuid ?? '',
          memo: memo,
          expanded: _messageExpanded,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AccountState>>(accountProvider, (previous, next) {
      final nextUuid = next.value?.activeAccountUuid;
      if (nextUuid != _activeAccountUuid) {
        unawaited(_loadTransaction(showLoading: _transaction == null));
      }
    });
    ref.listen<AsyncValue<SyncState>>(syncProvider, (previous, next) {
      final prevSig = _recentTxSignature(previous?.value);
      final nextSig = _recentTxSignature(next.value);
      if (prevSig != nextSig) {
        unawaited(_loadTransaction());
      }
    });

    final tx = _transaction;
    final detail = _matchingDetailFor(tx);
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final hiddenKeys = _activeAccountUuid == null
        ? const <String>{}
        : ref.watch(hiddenMemosProvider).keysFor(_activeAccountUuid!);
    final isMemoHidden = _isMemoHidden(detail, hiddenKeys);
    final useFailedReceiptLayout = tx?.expiredUnmined == true;
    final error = useFailedReceiptLayout
        ? 'Transaction expired before it was mined.'
        : _error;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: TransactionReceiptIllustration(
                  failed: useFailedReceiptLayout,
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                ),
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: AppRouteBackLink(),
                    ),
                    const SizedBox(height: AppSpacing.s),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 255),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TransactionReceiptView(
                            phase: _phaseFor(tx),
                            amountText: _amountText(
                              tx,
                              privacyModeEnabled: privacyModeEnabled,
                            ),
                            primaryBlock: _primaryBlockFor(context, tx, detail),
                            extraBlocks: _extraBlocksFor(
                              detail,
                              isMemoHidden: isMemoHidden,
                            ),
                            dateText: _dateText(tx),
                            feeText: _feeText(
                              tx,
                              privacyModeEnabled: privacyModeEnabled,
                            ),
                            error: error,
                            useFailedReceiptLayout: useFailedReceiptLayout,
                            showPrimaryCopyAction: true,
                            pinActionsToBottom: true,
                            onTransactionHashPressed: _openTransactionExplorer,
                          ),
                        ),
                      ),
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

/// Renders the memo text inside a transaction detail receipt, or — when the
/// memo has been hidden by the user — shows a "Memo hidden" placeholder with a
/// Restore affordance.
///
/// Extracted as a standalone [ConsumerWidget] so it can be unit-tested without
/// bringing up the full [ActivityTransactionStatusScreen] (which hits FFI on
/// build).
class MemoDetailSection extends ConsumerWidget {
  const MemoDetailSection({
    required this.txidHex,
    required this.detail,
    required this.accountUuid,
    required this.memo,
    required this.expanded,
    super.key,
  });

  final String txidHex;
  final rust_sync.TransactionDetail detail;
  final String accountUuid;

  /// Pre-trimmed memo text. Caller guarantees non-empty.
  final String memo;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoOutputKey = detail.memoOutputKey;

    if (memoOutputKey != null && accountUuid.isNotEmpty) {
      final hideKey = memoHideKeyFromDetail(
        txidHex: txidHex,
        memoOutputKey: memoOutputKey,
      );
      final hiddenKeys =
          ref.watch(hiddenMemosProvider).keysFor(accountUuid);
      if (hiddenKeys.contains(hideKey)) {
        return _MemoHiddenPlaceholder(
          key: const ValueKey('memo_hidden_placeholder'),
          onRestore: () => ref
              .read(hiddenMemosProvider.notifier)
              .restore(accountUuid: accountUuid, key: hideKey),
        );
      }
    }

    // Default: render the memo text. The expand/collapse toggle lives in the
    // surrounding block's titleTrailing (beside the "Message" heading), so it
    // is intentionally not owned here.
    return TransactionReceiptMessageText(memo: memo, expanded: expanded);
  }
}

class _MemoHiddenPlaceholder extends StatelessWidget {
  const _MemoHiddenPlaceholder({required this.onRestore, super.key});

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Memo hidden',
          style: AppTypography.bodyMedium.copyWith(
            color: colors.text.secondary,
          ),
        ),
        GestureDetector(
          key: const ValueKey('memo_restore_button'),
          onTap: onRestore,
          child: Text(
            'Restore',
            style: AppTypography.labelMedium.copyWith(
              color: colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}
