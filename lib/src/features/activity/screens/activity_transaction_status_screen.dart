import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../../main.dart' show log;
import '../../../core/formatting/address_display.dart';
import '../../../core/formatting/date_format.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/config/zcash_explorer.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/storage/wallet_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_copy_feedback.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_info_row.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/sync_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../send/widgets/send_recipient_resolver.dart';
import '../../send/widgets/send_status_content_view.dart';
import '../../send/widgets/send_verify_address_overlay.dart';
import '../widgets/received_receipt_view.dart';
import '../widgets/shielded_receipt_view.dart';

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
  String? _verifyAddress;

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
        _error = AppLocalizations.of(context).activityNoActiveAccount;
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
              ? AppLocalizations.of(context).activityTxLoadError
              : AppLocalizations.of(context).activityTxRefreshError;
        }
        _isLoading = false;
      });
    } catch (e, st) {
      log('ActivityTransactionStatus: transaction load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _detail = null;
        _error = _transaction == null
            ? AppLocalizations.of(context).activityTxLoadError
            : AppLocalizations.of(context).activityTxRefreshError;
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

  Future<void> _openTransactionExplorer() async {
    final endpoint = ref.read(rpcEndpointProvider);
    final launched = await launchZcashExplorerTransaction(
      networkName: endpoint.networkName,
      txidHex: widget.args.txidHex,
      txidOrder: ZcashExplorerTxidOrder.protocol,
    );
    if (launched || !mounted) return;
    copyTextWithToast(
      context,
      text: widget.args.txidHex,
      toastMessage: AppLocalizations.of(context).activityTxHashCopied,
    );
  }

  void _toggleMessageExpanded() {
    setState(() {
      _messageExpanded = !_messageExpanded;
    });
  }

  void _showVerifyAddress(String address) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _verifyAddress = trimmed;
    });
  }

  void _closeVerifyAddress() {
    if (_verifyAddress == null) return;
    setState(() {
      _verifyAddress = null;
    });
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

  /// Figma receipt timestamp ("25 May, 13:30") for the redesigned views.
  String _timestampText(rust_sync.TransactionInfo tx) {
    final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
    if (seconds <= BigInt.zero) return '--';
    return formatDayMonthTime(
      DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000),
      locale: AppLocalizations.of(context).localeName,
    );
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

  /// The output the funds arrived on (the "Amount" sub-address) — the
  /// largest of our visible received outputs that carries an address.
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

  ReceivedReceiptStatus _receivedStatusFor(rust_sync.TransactionInfo tx) {
    if (tx.expiredUnmined) return ReceivedReceiptStatus.failed;
    if (tx.minedHeight == BigInt.zero) return ReceivedReceiptStatus.inProgress;
    return ReceivedReceiptStatus.completed;
  }

  ShieldedReceiptStatus _shieldedStatusFor(rust_sync.TransactionInfo tx) {
    if (tx.expiredUnmined) return ShieldedReceiptStatus.failed;
    if (tx.minedHeight == BigInt.zero) return ShieldedReceiptStatus.inProgress;
    return ShieldedReceiptStatus.completed;
  }

  SendStatusPhase _sentPhaseFor(rust_sync.TransactionInfo tx) {
    if (tx.expiredUnmined) return SendStatusPhase.failed;
    if (tx.minedHeight == BigInt.zero) return SendStatusPhase.inProgress;
    return SendStatusPhase.completed;
  }

  Widget _receivedContent(
    rust_sync.TransactionInfo tx,
    rust_sync.TransactionDetail? detail, {
    required List<AddressBookContact> addressBookContacts,
    required bool privacyModeEnabled,
  }) {
    final fromAddress = detail?.sourceAddress?.trim();
    final fromPool = detail?.sourcePool?.trim().toLowerCase();
    final hasFromAddress = fromAddress != null && fromAddress.isNotEmpty;
    final receivingOutput = _receivingOutputFor(detail);
    final receivingAddress = receivingOutput?.address?.trim();
    // Trust the authoritative output pool; a unified-address sub-line must
    // not flip a transparent receive to the shielded badge (see the received
    // t-address recovery in Rust `detail_address`).
    final receivingIsShielded = receivingOutput?.pool == 'shielded';
    final memo = detail?.memo?.trim();
    final hasMemo = memo != null && memo.isNotEmpty;
    final ownAccounts =
        ref.watch(ownAccountAddressesProvider).value ??
        const <String, AccountInfo>{};
    final fromRecipient = hasFromAddress
        ? sendReviewRecipientFor(
            contacts: addressBookContacts,
            address: fromAddress,
            ownAccounts: ownAccounts,
          )
        : null;

    return _ReceiptContentColumn(
      child: ReceivedReceiptView(
        status: _receivedStatusFor(tx),
        amountText: _amountText(tx, privacyModeEnabled: privacyModeEnabled),
        timestampText: _timestampText(tx),
        txIdText: truncatedTxid(tx.txidHex),
        fromRecipient: fromRecipient,
        unknownFromKind: hasFromAddress
            ? null
            : _unknownFromKindForSourcePool(fromPool),
        isShieldedSource: fromPool == 'shielded',
        // Received receipts still show the transaction-level network fee.
        // The sender paid it, so the row is labeled separately from send fees.
        feeText: tx.fee > BigInt.zero
            ? _feeText(tx, privacyModeEnabled: privacyModeEnabled)
            : null,
        receivingAddress: receivingAddress,
        isShieldedReceivingAddress: receivingIsShielded,
        memoText: memo,
        memoExpanded: _messageExpanded,
        onShowFullAddress: hasFromAddress
            ? () => _showVerifyAddress(fromAddress)
            : null,
        onExpandMemo: hasMemo ? _toggleMessageExpanded : null,
        onTxIdPressed: () => unawaited(_openTransactionExplorer()),
      ),
    );
  }

  ReceivedReceiptUnknownFromKind? _unknownFromKindForSourcePool(String? pool) {
    if (pool == null || pool.isEmpty) return null;
    return pool == 'shielded'
        ? ReceivedReceiptUnknownFromKind.shieldedSender
        : ReceivedReceiptUnknownFromKind.unknownSender;
  }

  Widget _sentContent(
    rust_sync.TransactionInfo tx,
    rust_sync.TransactionDetail detail,
    String recipientAddress,
    List<AddressBookContact> addressBookContacts, {
    required bool privacyModeEnabled,
  }) {
    final ownAccounts =
        ref.watch(ownAccountAddressesProvider).value ??
        const <String, AccountInfo>{};
    final recipient = sendReviewRecipientFor(
      contacts: addressBookContacts,
      address: recipientAddress,
      ownAccounts: ownAccounts,
    );
    final memo = detail.memo?.trim();
    final hasMemo = memo != null && memo.isNotEmpty;

    return SendStatusContentView(
      phase: _sentPhaseFor(tx),
      amountText: _amountText(tx, privacyModeEnabled: privacyModeEnabled),
      recipient: recipient,
      timestampText: _timestampText(tx),
      txIdText: truncatedTxid(tx.txidHex),
      feeText: _feeText(tx, privacyModeEnabled: privacyModeEnabled),
      isShieldedRecipient:
          zcashAddressDisplayKind(recipientAddress) ==
          ZcashAddressDisplayKind.shielded,
      recipientAddressType: _recipientAddressTypeForDisplay(recipientAddress),
      memoText: hasMemo ? memo : null,
      memoExpanded: _messageExpanded,
      onShowFullAddress: () => _showVerifyAddress(recipientAddress),
      onExpandMemo: hasMemo ? _toggleMessageExpanded : null,
      onOpenExplorer: () => unawaited(_openTransactionExplorer()),
    );
  }

  String? _recipientAddressTypeForDisplay(String address) {
    final lower = address.trim().toLowerCase();
    return lower.startsWith('tex') ? 'tex' : null;
  }

  Widget _shieldedContent(
    rust_sync.TransactionInfo tx,
    rust_sync.TransactionDetail? detail, {
    required bool privacyModeEnabled,
  }) {
    final memo = detail?.memo?.trim();
    final hasMemo = memo != null && memo.isNotEmpty;

    return _ReceiptContentColumn(
      child: ShieldedReceiptView(
        status: _shieldedStatusFor(tx),
        amountText: _amountText(tx, privacyModeEnabled: privacyModeEnabled),
        timestampText: _timestampText(tx),
        txIdText: truncatedTxid(tx.txidHex),
        feeText: tx.fee > BigInt.zero
            ? _feeText(tx, privacyModeEnabled: privacyModeEnabled)
            : null,
        memoText: hasMemo ? memo : null,
        memoExpanded: _messageExpanded,
        onExpandMemo: hasMemo ? _toggleMessageExpanded : null,
        onTxIdPressed: () => unawaited(_openTransactionExplorer()),
      ),
    );
  }

  /// Fallback for the states without a dedicated redesigned receipt: a
  /// loading / not-found message when no transaction is available, and a
  /// minimal receipt (amount + status card, no counterparty) for an unknown
  /// kind or a sent tx whose recipient could not be resolved. Mirrors the
  /// mobile status screen, which renders these states the same unified way.
  Widget _fallbackContent(
    rust_sync.TransactionInfo? tx, {
    required bool privacyModeEnabled,
  }) {
    final colors = context.colors;
    if (tx == null) {
      return _ReceiptContentColumn(
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: Text(
            _isLoading
                ? AppLocalizations.of(context).activityLoadingTx
                : (_error ?? AppLocalizations.of(context).activityTxLoadError),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      );
    }

    final l10n = AppLocalizations.of(context);
    final (statusValue, statusIconName, statusColor) = tx.expiredUnmined
        ? (l10n.activityFailed, AppIcons.cancel, colors.text.destructive)
        : tx.minedHeight == BigInt.zero
        ? (l10n.activityInProgress, AppIcons.loader, colors.text.secondary)
        : (
            l10n.activityCompleted,
            AppIcons.checkCircle,
            colors.text.positiveStrong,
          );
    final feeText = tx.fee > BigInt.zero
        ? _feeText(tx, privacyModeEnabled: privacyModeEnabled)
        : null;

    return _ReceiptContentColumn(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.navTransaction,
            textAlign: TextAlign.center,
            style: AppTypography.bodyLarge.copyWith(
              color: colors.text.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: ReviewInfoRow(
              label: l10n.navAmount,
              value: _amountText(tx, privacyModeEnabled: privacyModeEnabled),
              leading: ClipOval(
                child: Image.asset(
                  'assets/icons/network_zec.png',
                  width: AppAssetSize.size,
                  height: AppAssetSize.size,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          ReviewWrapCard(
            children: [
              ReviewListRow(
                label: l10n.navStatus,
                value: statusValue,
                valueColor: statusColor,
                leadingIconName: statusIconName,
              ),
              ReviewListRow(
                label: l10n.activityTimestamp,
                value: _timestampText(tx),
              ),
              ReviewListRow(
                label: l10n.activityTxId,
                value: truncatedTxid(widget.args.txidHex),
                trailingIconName: AppIcons.arrowTopRight,
                onPressed: () => unawaited(_openTransactionExplorer()),
              ),
              if (feeText != null) ...[
                const ReviewWrapDivider(),
                ReviewListRow(
                  label: l10n.txFeeSheetTitle,
                  value: feeText,
                  trailingIconName: AppIcons.help,
                  trailingIconColor: colors.text.secondary,
                  trailingIconTooltip: l10n.txFeeHelpTooltip,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _redesignedPane(Widget content) {
    return Positioned.fill(
      child: AppPaneScrollScaffold(
        toolbar: const AppPaneToolbar(backLinkMinWidth: 60),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: content,
      ),
    );
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

    final sentRecipientAddress = detail?.primaryAddress?.trim();
    Widget? redesignedContent;
    if (tx != null && (tx.txKind == 'received' || tx.txKind == 'receiving')) {
      redesignedContent = _receivedContent(
        tx,
        detail,
        addressBookContacts: addressBookContacts,
        privacyModeEnabled: privacyModeEnabled,
      );
    } else if (tx != null &&
        tx.txKind == 'sent' &&
        detail != null &&
        sentRecipientAddress != null &&
        sentRecipientAddress.isNotEmpty) {
      redesignedContent = _sentContent(
        tx,
        detail,
        sentRecipientAddress,
        addressBookContacts,
        privacyModeEnabled: privacyModeEnabled,
      );
    } else if (tx != null && tx.txKind == 'shielded') {
      redesignedContent = _shieldedContent(
        tx,
        detail,
        privacyModeEnabled: privacyModeEnabled,
      );
    }

    final verifyAddress = _verifyAddress;
    final verifyAccountUuid =
        _activeAccountUuid ??
        ref.watch(accountProvider).value?.activeAccountUuid;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            if (redesignedContent != null)
              _redesignedPane(redesignedContent)
            else
              _redesignedPane(
                _fallbackContent(tx, privacyModeEnabled: privacyModeEnabled),
              ),
            if (verifyAddress != null && verifyAccountUuid != null)
              SendVerifyAddressOverlay(
                accountUuid: verifyAccountUuid,
                address: verifyAddress,
                isShieldedAddress:
                    zcashAddressDisplayKind(verifyAddress) ==
                    ZcashAddressDisplayKind.shielded,
                onClose: _closeVerifyAddress,
              ),
          ],
        ),
      ),
    );
  }
}

/// Centered 420px content column for the received/shielding receipts.
///
/// Scrolling is owned by the containing pane scaffold.
class _ReceiptContentColumn extends StatelessWidget {
  const _ReceiptContentColumn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: AppWindowSizing.contentAreaMaxWidth,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.sm,
          ),
          child: child,
        ),
      ),
    );
  }
}
