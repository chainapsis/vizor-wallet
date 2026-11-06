import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/swap_feature_config.dart';
import '../../../core/config/zcash_explorer.dart';
import '../../../core/formatting/address_display.dart';
import '../../../core/formatting/date_format.dart';
import '../../../core/formatting/zec_amount.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/layout/app_desktop_shell.dart';
import '../../../core/layout/app_layout.dart';
import '../../../core/layout/app_main_sidebar.dart';
import '../../../core/layout/app_pane_scroll_scaffold.dart';
import '../../../core/privacy/privacy_mask.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_copy_feedback.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/review_info_row.dart';
import '../../../core/widgets/receipt_loading_skeleton.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../../../providers/account_provider.dart';
import '../../../providers/enhance_pir_provider.dart';
import '../../../providers/privacy_mode_provider.dart';
import '../../../providers/rpc_endpoint_provider.dart';
import '../../../providers/zcash_explorer_provider.dart';
import '../../../rust/api/sync.dart' as rust_sync;
import '../../address_book/models/address_book_contact.dart';
import '../../address_book/providers/address_book_provider.dart';
import '../../payment_links/widgets/payment_link_gift_card.dart';
import '../../send/widgets/send_recipient_resolver.dart';
import '../../send/widgets/send_status_content_view.dart';
import '../../send/widgets/send_verify_address_overlay.dart';
import '../../swap/models/swap_fiat_value_formatting.dart';
import '../activity_row_mapper.dart' show transactionShowsZeroAmount;
import '../gift_card_activity_index.dart';
import '../transaction_completeness.dart';
import '../widgets/gift_card_activity_detail_view.dart';
import '../widgets/received_receipt_view.dart';
import '../widgets/shielded_receipt_view.dart';
import '../widgets/transparent_details_section.dart';
import 'transaction_receipt_loading.dart';

// Callers and tests name the receipt seams from here.
export 'transaction_receipt_loading.dart'
    show
        ActivityTxDetailLoader,
        ActivityTxHistoryLoader,
        PublicLookupConfirmation,
        TransparentDetailsPrioritizer,
        TransparentDetailsPublicLookup;

class ActivityTransactionStatusArgs implements TransactionReceiptArgs {
  const ActivityTransactionStatusArgs({
    required this.txidHex,
    this.txKind,
    this.initialTransaction,
    this.initialDetail,
    this.sourceAccountUuid,
    this.giftCard,
  });

  @override
  final String txidHex;
  @override
  final String? txKind;
  @override
  final rust_sync.TransactionInfo? initialTransaction;
  @override
  final rust_sync.TransactionDetail? initialDetail;
  @override
  final String? sourceAccountUuid;
  @override
  final GiftCardActivityMetadata? giftCard;
}

class ActivityTransactionStatusScreen extends TransactionReceiptScreen {
  const ActivityTransactionStatusScreen({
    super.key,
    required this.args,
    super.historyLoader,
    super.detailLoader,
    super.transparentDetailsPrioritizer,
    super.transparentDetailsPublicLookup,
    super.publicLookupConfirmation,
  });

  final ActivityTransactionStatusArgs args;

  @override
  TransactionReceiptArgs get receiptArgs => args;

  @override
  ConsumerState<ActivityTransactionStatusScreen> createState() =>
      _ActivityTransactionStatusScreenState();
}

class _ActivityTransactionStatusScreenState
    extends ConsumerState<ActivityTransactionStatusScreen>
    with TransactionReceiptLoading<ActivityTransactionStatusScreen> {
  bool _messageExpanded = false;
  String? _verifyAddress;

  @override
  void onReceiptFirstFrame() {
    ref.read(appLayoutProvider.notifier).setMode(AppLayoutMode.large);
  }

  @override
  void onReceiptAccountChanged() {
    _verifyAddress = null;
    _messageExpanded = false;
  }

  Future<void> _openTransactionExplorer() async {
    final endpoint = ref.read(rpcEndpointProvider);
    final launched = await launchZcashExplorerTransaction(
      networkName: endpoint.networkName,
      txidHex: widget.args.txidHex,
      txidOrder: ZcashExplorerTxidOrder.protocol,
      customTemplate: ref.read(zcashExplorerProvider),
    );
    if (launched || !mounted) return;
    copyTextWithToast(
      context,
      text: zcashDisplayTxidHex(
        widget.args.txidHex,
        ZcashExplorerTxidOrder.protocol,
      ),
      toastMessage: context.l10n.commonTransactionHashCopied,
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
    if (tx.displayAmount == BigInt.zero &&
        !transactionShowsZeroAmount(tx.txKind)) {
      return '--';
    }
    return hideAmountIfPrivacyMode(
      ZecAmount.fromZatoshi(tx.displayAmount).activityDetail.toString(),
      privacyModeEnabled: privacyModeEnabled,
    );
  }

  // Temporary integration feedback is scoped to the Private queries setting.
  bool _showUnknownFee(rust_sync.TransactionInfo tx) =>
      ref.watch(enhancePirProvider) && transactionFeeIsUnknown(tx);

  /// The receipt's own detail, once read, can complete what the activity
  /// entry could not: private transparent details that establish every payee.
  bool _showIncompleteDetails(rust_sync.TransactionInfo tx) =>
      ref.watch(enhancePirProvider) &&
      transactionDetailsIncomplete(tx) &&
      !receiptDetailsComplete(receiptDetail);

  bool _showsNetworkFee(rust_sync.TransactionInfo tx) =>
      unattributedReceiptNetworkFee(tx, matchingReceiptDetailFor(tx)) != null;

  String _feeLabel(rust_sync.TransactionInfo tx) => _showsNetworkFee(tx)
      ? context.l10n.commonNetworkFee
      : context.l10n.txFeeInfoTitle;

  String _feeHelpText(rust_sync.TransactionInfo tx) => _showsNetworkFee(tx)
      ? context.l10n.activityReceiptUnattributedFeeHelp
      : context.l10n.txFeeHelpTooltip;

  String _feeText(
    rust_sync.TransactionInfo? tx, {
    required bool privacyModeEnabled,
    GiftCardActivityMetadata? giftCard,
  }) {
    final networkFee = tx == null || giftCard != null
        ? null
        : unattributedReceiptNetworkFee(tx, matchingReceiptDetailFor(tx));
    if (networkFee != null) {
      return hideAmountIfPrivacyMode(
        ZecAmount.fromZatoshi(networkFee).fee.toString(),
        privacyModeEnabled: privacyModeEnabled,
      );
    }
    if (tx != null && _showUnknownFee(tx)) {
      return context.l10n.commonUnknown;
    }
    if (tx == null || tx.fee <= BigInt.zero) return '--';
    final fee = giftCard == null ? tx.fee : giftCard.detailFeeZatoshi(tx.fee);
    return hideAmountIfPrivacyMode(
      ZecAmount.fromZatoshi(fee).fee.toString(),
      privacyModeEnabled: privacyModeEnabled,
    );
  }

  /// Figma receipt timestamp ("25 May, 13:30") for the redesigned views.
  String _timestampText(rust_sync.TransactionInfo tx, {DateTime? override}) {
    final localeName = context.l10n.localeName;
    if (override != null) return formatDayMonthTime(override, localeName);
    final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
    if (seconds <= BigInt.zero) return '--';
    return formatDayMonthTime(
      DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000),
      localeName,
    );
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
    final fromAccount = receiptSourceAccount(
      detail,
      ref.watch(accountProvider).value?.accounts ?? const <AccountInfo>[],
    );

    return _ReceiptContentColumn(
      child: ReceivedReceiptView(
        status: _receivedStatusFor(tx),
        amountText: _amountText(tx, privacyModeEnabled: privacyModeEnabled),
        timestampText: _timestampText(tx),
        txIdText: _truncatedDisplayTxid(tx.txidHex),
        fromRecipient: fromRecipient,
        fromAccount: fromAccount == null
            ? null
            : (
                name: fromAccount.name,
                profilePictureId: fromAccount.profilePictureId,
                shieldedPool: switch (fromPool) {
                  'shielded' => true,
                  'transparent' => false,
                  _ => null,
                },
              ),
        unknownFromKind: hasFromAddress
            ? null
            : _unknownFromKindForSourcePool(fromPool),
        isShieldedSource: fromPool == 'shielded',
        receivingAddress: receivingAddress,
        isShieldedReceivingAddress: receivingIsShielded,
        memoText: memo,
        memoExpanded: _messageExpanded,
        detailsLoading: receiptDetailsLoading,
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
    rust_sync.TransactionDetail? detail,
    String? recipientAddress,
    List<AddressBookContact> addressBookContacts, {
    required bool privacyModeEnabled,
  }) {
    final ownAccounts =
        ref.watch(ownAccountAddressesProvider).value ??
        const <String, AccountInfo>{};
    final recipient = recipientAddress == null
        ? null
        : sendReviewRecipientFor(
            contacts: addressBookContacts,
            address: recipientAddress,
            ownAccounts: ownAccounts,
          );
    final memo = detail?.memo?.trim();
    final hasMemo = memo != null && memo.isNotEmpty;

    return SendStatusContentView(
      phase: _sentPhaseFor(tx),
      amountText: _amountText(tx, privacyModeEnabled: privacyModeEnabled),
      recipient: recipient,
      // A send whose recipient the account did not record keeps the send
      // shell; nothing names a recipient or offers to verify one.
      recipientRow: recipient != null
          ? null
          : receiptDetailsLoading
          ? ReceiptCounterpartySkeleton(label: context.l10n.commonTo)
          : ReviewInfoRow(
              key: const ValueKey('receipt_unknown_recipient'),
              label: context.l10n.commonTo,
              value: context.l10n.activityDetailsUnknownRecipient,
              struckThrough: _sentPhaseFor(tx) == SendStatusPhase.failed,
              leading: const ReviewInfoIconCircle(iconName: AppIcons.wallet),
            ),
      timestampText: _timestampText(tx),
      txIdText: _truncatedDisplayTxid(tx.txidHex),
      feeLabel: _feeLabel(tx),
      feeHelpText: _feeHelpText(tx),
      feeText: _feeText(tx, privacyModeEnabled: privacyModeEnabled),
      isShieldedRecipient:
          recipientAddress != null &&
          zcashAddressDisplayKind(recipientAddress) ==
              ZcashAddressDisplayKind.shielded,
      recipientAddressType: recipientAddress == null
          ? null
          : _recipientAddressTypeForDisplay(recipientAddress),
      memoText: hasMemo ? memo : null,
      memoExpanded: _messageExpanded,
      memoLoading: receiptDetailsLoading,
      onShowFullAddress: recipientAddress == null
          ? null
          : () => _showVerifyAddress(recipientAddress),
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
        txIdText: _truncatedDisplayTxid(tx.txidHex),
        feeLabel: _feeLabel(tx),
        feeHelpText: _feeHelpText(tx),
        feeText:
            tx.fee > BigInt.zero || _showUnknownFee(tx) || _showsNetworkFee(tx)
            ? _feeText(tx, privacyModeEnabled: privacyModeEnabled)
            : null,
        memoText: hasMemo ? memo : null,
        memoExpanded: _messageExpanded,
        memoLoading: receiptDetailsLoading,
        onExpandMemo: hasMemo ? _toggleMessageExpanded : null,
        onTxIdPressed: () => unawaited(_openTransactionExplorer()),
      ),
    );
  }

  Widget _giftCardContent(
    rust_sync.TransactionInfo tx,
    GiftCardActivityMetadata giftCard, {
    required bool privacyModeEnabled,
  }) {
    final colors = context.colors;
    final isFailed = tx.expiredUnmined && !giftCard.isClaimInFlight;
    final isInFlight =
        !isFailed &&
        (tx.minedHeight == BigInt.zero || giftCard.isClaimInFlight);
    final (statusText, statusIconName, statusColor) = isFailed
        ? (context.l10n.commonFailed, AppIcons.cancel, colors.text.destructive)
        : isInFlight
        ? (
            context.l10n.commonInProgress,
            AppIcons.loader,
            colors.text.secondary,
          )
        : (
            context.l10n.commonCompleted,
            AppIcons.checkCircle,
            colors.text.positiveStrong,
          );
    final batchCount = giftCard.batchCount;
    if (giftCard.kind == GiftCardActivityKind.created &&
        batchCount != null &&
        batchCount > 1) {
      String privateAmount(BigInt value) => hideAmountIfPrivacyMode(
        formatZecAmount(value),
        privacyModeEnabled: privacyModeEnabled,
        denomination: '',
      );
      final reserve = giftCard.claimFeeReserveZatoshi!;
      final feeUnknown = _showUnknownFee(tx);
      final networkFeeText = feeUnknown
          ? context.l10n.commonUnknown
          : '${privateAmount(tx.fee)} ZEC'; // l10n-ignore: amount format
      final networkFeeLabel = isInFlight || isFailed
          ? context.l10n.activityReceiptEstimatedNetworkFee
          : context.l10n.commonNetworkFee;
      return GiftCardActivityDetailView.batch(
        batch: GiftCardActivityBatch(
          count: batchCount,
          totalLabel: isFailed
              ? context.l10n.activityGiftTotalPlanned
              : isInFlight
              ? context.l10n.activityGiftTotalSubmitted
              : context.l10n.activityGiftTotalSpent,
          totalText: feeUnknown
              ? context.l10n.commonUnknown
              : '${privateAmount(giftCard.amountZatoshi + reserve + tx.fee)} ZEC', // l10n-ignore: amount format
          breakdownText: context.l10n.activityGiftBatchBreakdown(
            privateAmount(giftCard.amountZatoshi),
            privateAmount(reserve),
            networkFeeLabel,
            networkFeeText,
          ),
        ),
        isInFlight: isInFlight,
        isFailed: isFailed,
        artwork: PaymentLinkCardArtwork.fromProtocolId(giftCard.artworkId),
        amountText: privateAmount(
          giftCard.amountPerCardZatoshi ??
              giftCard.amountZatoshi ~/ BigInt.from(batchCount),
        ),
        statusText: statusText,
        statusIconName: statusIconName,
        statusColor: statusColor,
        timestampText: _timestampText(tx),
        txIdText: truncatedTxid(tx.txidHex),
        onTxIdPressed: () => unawaited(_openTransactionExplorer()),
        message: giftCard.message,
        messageExpanded: _messageExpanded,
        onToggleMessage: giftCard.message?.trim().isNotEmpty == true
            ? _toggleMessageExpanded
            : null,
      );
    }
    final amountText = hideAmountIfPrivacyMode(
      formatZecAmount(giftCard.amountZatoshi),
      privacyModeEnabled: privacyModeEnabled,
      denomination: '',
    );
    return GiftCardActivityDetailView(
      kind: giftCard.kind,
      isInFlight: isInFlight,
      isFailed: isFailed,
      artwork: PaymentLinkCardArtwork.fromProtocolId(giftCard.artworkId),
      amountText: amountText,
      supportingText:
          ref.watch(swapFeatureEnabledProvider) &&
              !privacyModeEnabled &&
              giftCard.fiatSnapshot != null
          ? swapFormatCompactFiatValue(giftCard.fiatSnapshot!.amount)
          : null,
      statusText: statusText,
      statusIconName: statusIconName,
      statusColor: statusColor,
      message: giftCard.message,
      messageExpanded: _messageExpanded,
      onToggleMessage: giftCard.message?.trim().isNotEmpty == true
          ? _toggleMessageExpanded
          : null,
      timestampText: _timestampText(tx, override: giftCard.activityTimestamp),
      txIdText: _truncatedDisplayTxid(tx.txidHex),
      // Redeeming a card is a receive, so it shows no network fee.
      feeText: giftCard.kind == GiftCardActivityKind.redeemed
          ? null
          : _feeText(
              tx,
              privacyModeEnabled: privacyModeEnabled,
              giftCard: giftCard,
            ),
      onTxIdPressed: () => unawaited(_openTransactionExplorer()),
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
            receiptLoading
                ? context.l10n.activityReceiptLoading
                : (receiptError ?? context.l10n.activityReceiptLoadFailed),
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ),
      );
    }

    final isMigration = tx.txKind == 'migration';
    final (statusValue, statusIconName, statusColor) = tx.expiredUnmined
        ? (context.l10n.commonFailed, AppIcons.cancel, colors.text.destructive)
        : tx.minedHeight == BigInt.zero
        ? (
            context.l10n.commonInProgress,
            AppIcons.loader,
            colors.text.secondary,
          )
        : (
            context.l10n.commonCompleted,
            AppIcons.checkCircle,
            colors.text.positiveStrong,
          );
    // The fee appears once: a fee-only entry is its one fee line, and an
    // amount that includes the fee says so.
    final feePresentation = transactionFeePresentation(tx);
    final feeOnly = feePresentation == TransactionFeePresentation.feeOnly;
    final feeText =
        !feeOnly &&
            (tx.fee > BigInt.zero ||
                _showUnknownFee(tx) ||
                _showsNetworkFee(tx))
        ? _feeText(tx, privacyModeEnabled: privacyModeEnabled)
        : null;

    return _ReceiptContentColumn(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isMigration
                ? tx.expiredUnmined
                      ? context.l10n.activityTitleMigrationFailed
                      : tx.minedHeight == BigInt.zero
                      ? context.l10n.activityTitleMigratingVerb
                      : context.l10n.activityTitleMigrated
                : context.l10n.activityTitleTransaction,
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
              label: isMigration
                  ? context.l10n.activityReceiptAmountMigrated
                  : switch (feePresentation) {
                      TransactionFeePresentation.separate =>
                        context.l10n.commonAmount,
                      TransactionFeePresentation.includedInAmount =>
                        context.l10n.activityReceiptNetChange,
                      TransactionFeePresentation.feeOnly =>
                        context.l10n.activityReceiptNetChange,
                    },
              value: feeOnly
                  ? _feeText(tx, privacyModeEnabled: privacyModeEnabled)
                  : _amountText(tx, privacyModeEnabled: privacyModeEnabled),
              leading: ClipOval(
                child: Image.asset(
                  'assets/icons/desktop/network_zec.png',
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
              if (isMigration) ...[
                ReviewListRow(
                  label: context.l10n.activityReceiptFrom,
                  value: context.l10n.activityBalanceOrchard,
                  leadingIconName: AppIcons.migrationSplit,
                ),
                ReviewListRow(
                  label: context.l10n.commonTo,
                  value: context.l10n.activityBalanceIronwood,
                  leadingIconName: AppIcons.shieldKeyholeOutline,
                ),
                const ReviewWrapDivider(),
              ],
              ReviewListRow(
                label: context.l10n.activityReceiptStatus,
                value: statusValue,
                valueColor: statusColor,
                leadingIconName: statusIconName,
              ),
              ReviewListRow(
                label: context.l10n.commonTimestamp,
                value: _timestampText(tx),
              ),
              ReviewListRow(
                label: context.l10n.commonTxId,
                value: _truncatedDisplayTxid(widget.args.txidHex),
                trailingIconName: AppIcons.arrowTopRight,
                onPressed: () => unawaited(_openTransactionExplorer()),
              ),
              if (_showIncompleteDetails(tx))
                ReviewListRow(
                  label: context.l10n.activityReceiptDetails,
                  value: context.l10n.activityReceiptIncomplete,
                  trailingIconName: AppIcons.help,
                  trailingIconColor: colors.text.secondary,
                  trailingIconTooltip:
                      context.l10n.activityReceiptDetailsIncompleteHelp,
                ),
              if (feeText != null) ...[
                const ReviewWrapDivider(),
                ReviewListRow(
                  label: _feeLabel(tx),
                  value: feeText,
                  trailingIconName: AppIcons.help,
                  trailingIconColor: colors.text.secondary,
                  trailingIconTooltip: _feeHelpText(tx),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// A row tapped before the Gift Card index finished loading arrives with no
  /// metadata, so the receipt resolves it here instead of staying generic.
  GiftCardActivityMetadata? _resolvedGiftCard(
    rust_sync.TransactionInfo? tx,
    String? accountUuid,
  ) {
    if (tx == null || accountUuid == null) return null;
    return ref
        .watch(giftCardActivityIndexProvider(accountUuid))
        .value
        ?.metadataFor(tx);
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
    listenForReceiptRefresh();

    final tx = receiptTransaction;
    final detail = matchingReceiptDetailFor(tx);
    final addressBookContacts =
        ref.watch(addressBookProvider).value?.contacts ?? const [];
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final activeAccountUuid =
        ref.watch(accountProvider).value?.activeAccountUuid ??
        receiptAccountUuid;
    // The args metadata was resolved for the account that was active when the
    // row was tapped; under another account only that account's index counts.
    final suppliedGiftCard = receiptArgsAccountUuid == activeAccountUuid
        ? widget.args.giftCard
        : null;
    final giftCard =
        _resolvedGiftCard(tx, activeAccountUuid) ?? suppliedGiftCard;

    final sentRecipientAddress = receiptRecipientAddress(detail);
    Widget? redesignedContent;
    if (tx != null && giftCard != null) {
      redesignedContent = _giftCardContent(
        tx,
        giftCard,
        privacyModeEnabled: privacyModeEnabled,
      );
    } else if (tx != null &&
        (tx.txKind == 'received' || tx.txKind == 'receiving')) {
      redesignedContent = _receivedContent(
        tx,
        detail,
        addressBookContacts: addressBookContacts,
        privacyModeEnabled: privacyModeEnabled,
      );
    } else if (tx != null &&
        tx.txKind == 'sent' &&
        transactionFeePresentation(tx) == TransactionFeePresentation.separate &&
        (receiptDetailsLoading ||
            sentRecipientAddress != null ||
            receiptHasUnknownRecipient(tx, detail))) {
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

    // Dedicated receipts show what is known; the notice says it may be partial.
    // The fallback receipt carries its own row.
    if (redesignedContent != null && tx != null && _showIncompleteDetails(tx)) {
      redesignedContent = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [redesignedContent, const _IncompleteDetailsNotice()],
      );
    }

    Widget receiptContent =
        redesignedContent ??
        _fallbackContent(tx, privacyModeEnabled: privacyModeEnabled);
    if (tx != null &&
        giftCard == null &&
        (offersPublicDetailsLookup(detail) ||
            transparentDetailsNotice(detail) != null ||
            listedTransactionOutputs(detail).isNotEmpty)) {
      receiptContent = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          receiptContent,
          _ReceiptContentColumn(
            child: TransparentDetailsSection(
              detail: detail,
              privacyModeEnabled: privacyModeEnabled,
              publicLookupText: publicLookupText,
              onLoadPublicly: offersPublicDetailsLookup(detail)
                  ? () => unawaited(runPublicLookup(tx))
                  : null,
              spaced: false,
            ),
          ),
        ],
      );
    }
    // Both dedicated and summary-only receipts retain refresh errors. When
    // there is no row, the fallback already displays its loading/error state.
    if (tx != null && receiptError != null) {
      receiptContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          receiptContent,
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              receiptError!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: context.colors.text.secondary,
              ),
            ),
          ),
        ],
      );
    }

    final verifyAddress = _verifyAddress;
    final verifyAccountUuid =
        receiptAccountUuid ??
        ref.watch(accountProvider).value?.activeAccountUuid;

    return AppDesktopShell(
      sidebar: const AppMainSidebar(),
      pane: AppDesktopPane(
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            _redesignedPane(receiptContent),
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

String _truncatedDisplayTxid(String protocolTxid) => truncatedTxid(
  zcashDisplayTxidHex(protocolTxid, ZcashExplorerTxidOrder.protocol),
);

/// Marks a dedicated receipt whose entry is incomplete.
class _IncompleteDetailsNotice extends StatelessWidget {
  const _IncompleteDetailsNotice();

  @override
  Widget build(BuildContext context) {
    return _ReceiptContentColumn(
      child: ReviewWrapCard(
        children: [
          ReviewListRow(
            label: context.l10n.activityReceiptDetails,
            value: context.l10n.activityReceiptIncomplete,
            trailingIconName: AppIcons.help,
            trailingIconColor: context.colors.text.secondary,
            trailingIconTooltip:
                context.l10n.activityReceiptDetailsIncompleteHelp,
          ),
        ],
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
