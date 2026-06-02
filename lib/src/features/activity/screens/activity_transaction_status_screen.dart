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
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/models/address_book_label_lookup.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../send/widgets/transaction_receipt_view.dart';

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
      ZecAmount.fromZatoshi(tx.displayAmount).activityDetail.toString(),
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
      onCopy: () => unawaited(_copyText(trimmedAddress, 'Address copied')),
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

  /// Sent "To" block: a matched address-book contact shows its nickname +
  /// crimson saved mark above the (truncated) address; copy sits at the end of
  /// the address line and always copies the full address.
  TransactionReceiptBlockData _recipientBlock(
    BuildContext context, {
    required String address,
    String? addressBookLabel,
  }) {
    final colors = context.colors;
    final trimmedAddress = address.trim();
    final displayAddress = compactActivityReceiptAddress(trimmedAddress);
    final nickname = addressBookLabel?.trim();
    final hasNickname = nickname != null && nickname.isNotEmpty;
    return TransactionReceiptBlockData(
      title: 'To',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasNickname) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  AppIcons.user,
                  size: 14,
                  color: colors.icon.brandCrimson,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Flexible(
                  child: Text(
                    nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayAddress,
                style: AppTypography.codeSmall.copyWith(
                  color: colors.text.muted,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _InlineCopyButton(
                onTap: () =>
                    unawaited(_copyText(trimmedAddress, 'Address copied')),
              ),
            ],
          ),
        ],
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
    List<AddressBookContact> addressBookContacts,
  ) {
    final primaryAddress = detail?.primaryAddress?.trim();
    final useFailedReceiptLayout = tx?.expiredUnmined == true;
    final compactAddress = detail?.memo?.trim().isNotEmpty == true;
    if (tx?.txKind == 'sent' &&
        primaryAddress != null &&
        primaryAddress.isNotEmpty) {
      final addressBookLabel = addressBookLabelFor(
        contacts: addressBookContacts,
        network: AddressBookNetwork.zcash,
        address: primaryAddress,
      );
      if (addressBookLabel != null && addressBookLabel.trim().isNotEmpty) {
        return _recipientBlock(
          context,
          address: primaryAddress,
          addressBookLabel: addressBookLabel,
        );
      }
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

  List<TransactionReceiptBlockData> _extraBlocksFor(
    rust_sync.TransactionDetail? detail,
  ) {
    final memo = detail?.memo?.trim();
    if (memo == null || memo.isEmpty) return const [];
    return [
      TransactionReceiptBlockData(
        title: 'Message',
        titleTrailing: TransactionReceiptMessageToggle(
          expanded: _messageExpanded,
          onTap: _toggleMessageExpanded,
        ),
        child: TransactionReceiptMessageText(
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
    final addressBookContacts =
        ref.watch(addressBookProvider).value?.contacts ?? const [];
    final privacyModeEnabled = ref.watch(privacyModeProvider);
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
                            primaryBlock: _primaryBlockFor(
                              context,
                              tx,
                              detail,
                              addressBookContacts,
                            ),
                            extraBlocks: _extraBlocksFor(detail),
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

const _activityReceiptAddressEdgeLength = 16;
const _activityReceiptAddressSeparator = ' ... ';

String compactActivityReceiptAddress(String address) {
  final trimmed = address.trim();
  final compactLength =
      _activityReceiptAddressEdgeLength * 2 +
      _activityReceiptAddressSeparator.length;
  if (trimmed.length <= compactLength) return trimmed;
  return '${trimmed.substring(0, _activityReceiptAddressEdgeLength)}'
      '$_activityReceiptAddressSeparator'
      '${trimmed.substring(trimmed.length - _activityReceiptAddressEdgeLength)}';
}

/// Icon-only copy affordance placed at the end of the recipient address line.
class _InlineCopyButton extends StatelessWidget {
  const _InlineCopyButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AppIcon(
          AppIcons.copy,
          size: 16,
          color: context.colors.icon.muted,
        ),
      ),
    );
  }
}
