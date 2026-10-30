import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/swap_feature_config.dart';
import '../../../../core/config/zcash_explorer.dart';
import '../../../../core/formatting/address_display.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/privacy/privacy_mask.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_profile_picture.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/receipt_loading_skeleton.dart';
import '../../../../core/widgets/mobile/mobile_address_verify_sheet.dart';
import '../../../../core/widgets/mobile/mobile_review_row.dart';
import '../../../../core/widgets/mobile/mobile_tx_fee_info_sheet.dart';
import '../../../../core/widgets/review_info_row.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/enhance_pir_provider.dart';
import '../../../../providers/privacy_mode_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/zcash_explorer_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_book/providers/address_book_provider.dart';
import '../../../payment_links/widgets/mobile/payment_link_mobile_views.dart'
    show kPaymentLinkMobileCardHeight, kPaymentLinkMobileCardWidth;
import '../../../payment_links/widgets/payment_link_copy.dart';
import '../../../payment_links/widgets/payment_link_gift_card.dart';
import '../../../send/widgets/send_recipient_resolver.dart';
import '../../../send/widgets/send_review_layout.dart'
    show SendReviewContactRecipient;
import '../../../swap/models/swap_fiat_value_formatting.dart';
import '../../activity_row_mapper.dart'
    show
        formatActivityTimestamp,
        giftCardActivityTitle,
        transactionActivityPool,
        transactionShowsZeroAmount;
import '../../gift_card_activity_index.dart';
import '../../transaction_completeness.dart';
import '../../widgets/transparent_details_section.dart';
import '../transaction_receipt_loading.dart';

/// Route arguments for [MobileTransactionStatusScreen]. The row that
/// was tapped passes its [initialTransaction] so the screen renders
/// immediately; the screen refreshes itself from the wallet DB.
class MobileTransactionStatusArgs implements TransactionReceiptArgs {
  const MobileTransactionStatusArgs({
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

  /// The screen re-resolves the Gift Card from the index when this is null.
  @override
  final GiftCardActivityMetadata? giftCard;
}

/// Mobile transaction status/detail — Figma `ACTIVITY & STATUS` frames
/// `Status Sending` (4752:70731), `Status Scucess` (4752:71303),
/// `Status Fail` (4752:71663), and `Received` (4752:75264): the serif
/// review header (amount / counterparty with the flow arrow) above the
/// rounded detail card (status chip, message, timestamp, tx id, fee).
class MobileTransactionStatusScreen extends TransactionReceiptScreen {
  const MobileTransactionStatusScreen({
    required this.args,
    super.historyLoader,
    super.detailLoader,
    super.transparentDetailsPrioritizer,
    super.transparentDetailsPublicLookup,
    super.publicLookupConfirmation,
    super.key,
  });

  final MobileTransactionStatusArgs args;

  @override
  TransactionReceiptArgs get receiptArgs => args;

  @override
  ConsumerState<MobileTransactionStatusScreen> createState() =>
      _MobileTransactionStatusScreenState();
}

class _MobileTransactionStatusScreenState
    extends ConsumerState<MobileTransactionStatusScreen>
    with TransactionReceiptLoading<MobileTransactionStatusScreen> {
  bool _messageExpanded = false;

  @override
  void onReceiptAccountChanged() {
    _messageExpanded = false;
  }

  _TxPhase get _phase {
    final tx = receiptTransaction;
    if (tx == null) return _TxPhase.pending;
    if (tx.expiredUnmined) return _TxPhase.failed;
    if (tx.minedHeight == BigInt.zero) return _TxPhase.pending;
    return _TxPhase.succeeded;
  }

  bool get _isIncoming {
    final kind = receiptTransaction?.txKind ?? widget.args.txKind;
    return kind == 'received' || kind == 'receiving';
  }

  bool get _isShielding =>
      (receiptTransaction?.txKind ?? widget.args.txKind) == 'shielded';

  bool get _isMigration =>
      (receiptTransaction?.txKind ?? widget.args.txKind) == 'migration';

  bool get _isSent =>
      (receiptTransaction?.txKind ?? widget.args.txKind) == 'sent';

  /// The fee presentation of the shown entry. A Gift Card shows its own
  /// amount, so its fee stays separate.
  TransactionFeePresentation _feePresentationFor(
    rust_sync.TransactionInfo? tx,
    GiftCardActivityMetadata? giftCard,
  ) => tx == null || giftCard != null
      ? TransactionFeePresentation.separate
      : transactionFeePresentation(tx);

  _TxPhase _phaseFor(GiftCardActivityMetadata? giftCard) {
    if (giftCard?.isClaimInFlight == true) {
      return _TxPhase.pending;
    }
    return _phase;
  }

  String _titleFor(GiftCardActivityMetadata? giftCard) {
    if (giftCard != null) {
      return giftCardActivityTitle(
        giftCard.kind,
        isInFlight: _phaseFor(giftCard) == _TxPhase.pending,
        isFailed: _phaseFor(giftCard) == _TxPhase.failed,
      );
    }

    if (_isShielding) {
      return switch (_phase) {
        _TxPhase.pending => 'Shielding...',
        _TxPhase.succeeded => 'Shielded',
        _TxPhase.failed => 'Shielding failed',
      };
    }
    if (_isMigration) {
      return switch (_phase) {
        _TxPhase.pending => 'Migrating to Ironwood...',
        _TxPhase.succeeded => 'Migrated to Ironwood',
        _TxPhase.failed => 'Migration failed',
      };
    }
    if (_isIncoming) {
      return switch (_phase) {
        _TxPhase.pending => 'Receiving...',
        _TxPhase.succeeded => 'Received',
        _TxPhase.failed => 'Receive failed',
      };
    }
    // Unclassified transactions and balance movements stay neutral, like
    // the desktop fallback receipt: neither establishes an external payment.
    if (!_isSent ||
        _feePresentationFor(receiptTransaction, null) !=
            TransactionFeePresentation.separate) {
      return 'Transaction';
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
      customTemplate: ref.read(zcashExplorerProvider),
    );
    if (launched || !mounted) return;
    await Clipboard.setData(
      ClipboardData(
        text: zcashDisplayTxidHex(
          widget.args.txidHex,
          ZcashExplorerTxidOrder.protocol,
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    listenForReceiptRefresh();

    final colors = context.colors;
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final tx = receiptTransaction;
    final detail = matchingReceiptDetailFor(tx);
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
    final detailsLoading = giftCard == null && receiptDetailsLoading;
    if (tx == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: 'Transaction',
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    receiptLoading
                        ? 'Loading transaction…'
                        : (receiptError ?? 'Transaction could not be loaded.'),
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final failed = _phaseFor(giftCard) == _TxPhase.failed;
    // The fee appears once: a fee-only entry is its one fee line, and an
    // amount that includes the fee says so.
    final feePresentation = _feePresentationFor(tx, giftCard);
    final feeOnly = feePresentation == TransactionFeePresentation.feeOnly;

    final amountText = feeOnly
        ? _feeText(tx, privacyModeEnabled: privacyModeEnabled) ?? '--'
        : _amountText(
            tx,
            giftCardAmountZatoshi: giftCard?.amountZatoshi,
            privacyModeEnabled: privacyModeEnabled,
          );
    // A Gift Card's counterparty is the single-use link address, so the
    // receipt drops the address row and its verify affordance.
    final primaryAddress = giftCard != null
        ? null
        : receiptRecipientAddress(detail);
    final sourceAddress = giftCard != null
        ? null
        : detail?.sourceAddress?.trim();
    final sourcePool = detail?.sourcePool?.trim().toLowerCase();
    final receivingOutput = giftCard == null && _isIncoming
        ? _receivingOutputFor(detail)
        : null;
    final receivingAddress = receivingOutput?.address?.trim();
    final address = _isIncoming ? sourceAddress : primaryAddress;
    final poolLabel = giftCard != null
        ? _addressPoolLabel(giftCard.displayPool, null)
        : _isIncoming
        ? _addressPoolLabel(sourcePool, sourceAddress)
        : _addressPoolLabel(
            _isSent ? transactionActivityPool(tx) : tx.displayPool,
            primaryAddress,
            ordinary: _isSent,
          );
    final receivingPoolLabel = _addressPoolLabel(
      receivingOutput?.pool,
      receivingAddress,
    );
    // The card's note lives in the Gift Card record, not the funding memo.
    final memo = giftCard != null
        ? giftCard.message?.trim()
        : detail?.memo?.trim();

    // Resolve the counterparty to a saved contact / own account so the
    // From/To row shows a name + avatar instead of a raw address — parity
    // with the desktop receipt (sendReviewRecipientFor).
    final contacts =
        ref.watch(addressBookProvider).value?.contacts ??
        const <AddressBookContact>[];
    final ownAccounts =
        ref.watch(ownAccountAddressesProvider).value ??
        const <String, AccountInfo>{};
    final namedRecipient = address == null || address.isEmpty
        ? null
        : switch (sendReviewRecipientFor(
            contacts: contacts,
            address: address,
            ownAccounts: ownAccounts,
          )) {
            SendReviewContactRecipient r => r,
            _ => null,
          };

    final hasAddress = address != null && address.isNotEmpty;
    final amountBottom = _isMigration
        ? _BottomInfo(
            iconName: AppIcons.migrationSplit,
            iconColor: colors.icon.regular,
            text: 'From Orchard balance',
          )
        : _isIncoming && receivingAddress != null && receivingAddress.isNotEmpty
        ? _BottomInfo(
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
        : !hasAddress && !(_isSent && detailsLoading) && poolLabel != null
        ? _BottomInfo(
            iconName: _poolIconNameFor(poolLabel),
            iconColor: _poolIconColorFor(context, poolLabel),
            text: poolLabel,
          )
        : null;
    final amountRow = _reviewRow(
      label: switch (feePresentation) {
        TransactionFeePresentation.separate => 'Amount',
        TransactionFeePresentation.includedInAmount => kNetChangeText,
        TransactionFeePresentation.feeOnly => kNetChangeText,
      },
      value: amountText,
      leading: const MobileReviewZecBadge(),
      // With no counterparty row (shielded senders are unknown), the
      // pool tag moves under the amount — Figma `Received` keeps the
      // pool on the bottom strip.
      bottom: detailsLoading && _isIncoming ? null : amountBottom,
      bottomPlaceholder: detailsLoading && _isIncoming
          ? const Align(
              alignment: Alignment.centerLeft,
              child: ReceiptValueSkeleton(),
            )
          : null,
    );
    final addressRow = (address == null || address.isEmpty)
        ? null
        : _reviewRow(
            label: _isIncoming ? 'From' : 'To',
            value: namedRecipient != null
                ? namedRecipient.name
                : _truncateAddress(address),
            strikethrough: failed,
            leading: namedRecipient != null
                ? AppProfilePicture(
                    profilePictureId: namedRecipient.profilePictureId,
                    size: AppProfilePictureSize.navLarge,
                  )
                : MobileReviewIconBadge(
                    child: AppIcon(
                      AppIcons.wallet,
                      size: 18,
                      color: colors.icon.regular,
                    ),
                  ),
            bottom: _BottomInfo(
              iconName: poolLabel == null
                  ? null
                  : _poolIconNameFor(poolLabel, address: address),
              iconColor: poolLabel == null
                  ? null
                  : _poolIconColorFor(context, poolLabel, address: address),
              // For a named counterparty the headline holds the name, so the
              // bottom strip surfaces the (still pool-tagged) address instead.
              text: namedRecipient != null
                  ? _truncateAddress(address)
                  : poolLabel,
            ),
            trailingActionLabel: 'Show full address',
            trailingActionKey: const ValueKey(
              'mobile_tx_status_show_full_address',
            ),
            onTrailingAction: () => unawaited(_showFullAddressSheet(address)),
          );
    // Without an exact source address, the account the wallet recorded as
    // sending the received outputs still names where the funds came from.
    final sourceAccount = _isIncoming && addressRow == null && giftCard == null
        ? receiptSourceAccount(
            detail,
            ref.watch(accountProvider).value?.accounts ?? const <AccountInfo>[],
          )
        : null;
    final sourceAccountPool = switch (sourcePool) {
      'shielded' => 'Shielded',
      'transparent' => 'Transparent',
      _ => null,
    };
    final sourceAccountRow = sourceAccount == null
        ? null
        : _reviewRow(
            key: const ValueKey('received_from_account'),
            label: 'From',
            value: sourceAccount.name,
            leading: AppProfilePicture(
              profilePictureId: sourceAccount.profilePictureId,
              size: AppProfilePictureSize.navLarge,
            ),
            bottom: sourceAccountPool == null
                ? null
                : _BottomInfo(
                    iconName: _poolIconNameFor(sourceAccountPool),
                    iconColor: _poolIconColorFor(context, sourceAccountPool),
                    text: sourceAccountPool,
                  ),
          );
    final unknownFromLabel =
        _isIncoming &&
            addressRow == null &&
            sourceAccountRow == null &&
            giftCard == null
        ? _unknownFromLabelForSourcePool(sourcePool)
        : null;
    final unknownFromRow = unknownFromLabel == null
        ? null
        : _reviewRow(
            label: 'From',
            value: unknownFromLabel,
            leading: MobileReviewIconBadge(
              child: AppIcon(
                AppIcons.wallet,
                size: 18,
                color: colors.icon.regular,
              ),
            ),
            bottom: sourcePool == 'shielded'
                ? _BottomInfo(
                    iconName: _poolIconNameFor('Shielded'),
                    iconColor: _poolIconColorFor(context, 'Shielded'),
                    text: 'Shielded',
                  )
                : null,
          );

    // Sent flows read top-down as amount -> recipient; received flows as
    // sender source -> amount, with the receiving output attached under
    // Amount (Figma `Received` 4752:75264).
    final fromRow = _isIncoming
        ? detailsLoading
              ? const ReceiptCounterpartySkeleton(label: 'From')
              : addressRow ?? sourceAccountRow ?? unknownFromRow
        : null;
    // A send whose recipient the account did not record keeps the To row,
    // naming no one and offering nothing to verify.
    final toRow = _isSent && detailsLoading
        ? const ReceiptCounterpartySkeleton(label: 'To')
        : addressRow ??
              (giftCard == null && receiptHasUnknownRecipient(tx, detail)
                  ? _reviewRow(
                      key: const ValueKey('receipt_unknown_recipient'),
                      label: 'To',
                      value: kUnknownRecipientText,
                      strikethrough: failed,
                      leading: MobileReviewIconBadge(
                        child: AppIcon(
                          AppIcons.wallet,
                          size: 18,
                          color: colors.icon.regular,
                        ),
                      ),
                    )
                  : null);
    // Self-shield (own transparent -> own shielded) has no external
    // counterparty: mirror the desktop ShieldedReceiptView two-row flow,
    // "From transparent balance" -> "Shielded balance". No Figma frame for
    // this state yet; mobile is aligned to the (more informative) desktop
    // shape pending one.
    final reviewChildren = giftCard != null
        ? <Widget>[]
        : _isMigration
        ? <Widget>[
            amountRow,
            _reviewRow(
              label: 'To',
              value: 'Ironwood balance',
              leading: MobileReviewIconBadge(
                child: AppIcon(
                  AppIcons.shieldKeyholeOutline,
                  size: 18,
                  color: colors.icon.regular,
                ),
              ),
              bottom: _BottomInfo(
                iconName: AppIcons.shieldKeyhole,
                iconColor: colors.icon.success,
                text: 'Ironwood',
              ),
            ),
          ]
        : _isShielding
        ? <Widget>[
            _reviewRow(
              label: 'Amount',
              value: amountText,
              leading: const MobileReviewZecBadge(),
              bottom: _BottomInfo(
                iconName: AppIcons.transparentBalance,
                iconColor: colors.icon.muted,
                text: 'From transparent balance',
              ),
            ),
            _reviewRow(
              label: 'To',
              value: 'Shielded balance',
              leading: MobileReviewIconBadge(
                child: AppIcon(
                  AppIcons.shieldKeyholeOutline,
                  size: 18,
                  color: colors.icon.regular,
                ),
              ),
              bottom: _BottomInfo(
                iconName: AppIcons.shieldKeyhole,
                iconColor: colors.icon.brandCrimson,
                text: 'Shielded',
              ),
            ),
          ]
        : _isIncoming
        ? <Widget>[
            ?fromRow,
            amountRow,
          ]
        : toRow == null
        ? <Widget>[amountRow]
        : <Widget>[amountRow, toRow];

    return Scaffold(
      backgroundColor: colors.background.window,
      body: AppToastHost(
        child: SafeArea(
          child: Column(
            children: [
              MobileTopNav.back(
                title: _titleFor(giftCard),
                titleMaxLines: giftCard == null ? 1 : 2,
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
                      if (giftCard != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.s),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: PaymentLinkGiftCard(
                                artwork: PaymentLinkCardArtwork.fromProtocolId(
                                  giftCard.artworkId,
                                ),
                                cardWidth: kPaymentLinkMobileCardWidth,
                                cardHeight: kPaymentLinkMobileCardHeight,
                                amountText: hideAmountIfPrivacyMode(
                                  formatZecAmount(giftCard.amountZatoshi),
                                  privacyModeEnabled: privacyModeEnabled,
                                  denomination: '',
                                ),
                                supportingText:
                                    ref.watch(swapFeatureEnabledProvider) &&
                                        !privacyModeEnabled &&
                                        giftCard.fiatSnapshot != null
                                    ? swapFormatCompactFiatValue(
                                        giftCard.fiatSnapshot!.amount,
                                      )
                                    : null,
                                showCaret: false,
                              ),
                            ),
                          ),
                        ),
                      if (reviewChildren.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          child: ReviewInfoFlow(rows: reviewChildren),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      _DetailCard(
                        phase: _phaseFor(giftCard),
                        statusText: giftCard == null
                            ? null
                            : switch (_phaseFor(giftCard)) {
                                _TxPhase.pending =>
                                  giftCard.kind == GiftCardActivityKind.created
                                      ? 'Creating…'
                                      : 'Redeeming…',
                                _TxPhase.succeeded =>
                                  giftCard.kind == GiftCardActivityKind.created
                                      ? 'Created'
                                      : 'Redeemed',
                                _TxPhase.failed => 'Failed',
                              },
                        failed: failed,
                        memo: memo,
                        memoLoading:
                            detailsLoading &&
                            (_isSent || _isIncoming || _isShielding),
                        messageExpanded: _messageExpanded,
                        onToggleMessage: () => setState(
                          () => _messageExpanded = !_messageExpanded,
                        ),
                        timestampText: _dateText(
                          tx,
                          override: giftCard?.activityTimestamp,
                        ),
                        txidText: truncatedTxid(
                          zcashDisplayTxidHex(
                            widget.args.txidHex,
                            ZcashExplorerTxidOrder.protocol,
                          ),
                        ),
                        onOpenExplorer: () => unawaited(_openExplorer()),
                        isCardCreation:
                            giftCard?.kind == GiftCardActivityKind.created,
                        showsNetworkFee:
                            giftCard == null &&
                            unattributedReceiptNetworkFee(tx, receiptDetail) !=
                                null,
                        feeText: feeOnly
                            ? null
                            : _feeText(
                                tx,
                                giftCard: giftCard,
                                privacyModeEnabled: privacyModeEnabled,
                              ),
                        detailsIncomplete: _showIncompleteDetails(tx),
                      ),
                      if (giftCard == null &&
                          detail?.transparentDetailsState != null)
                        TransparentDetailsSection(
                          detail: detail,
                          privacyModeEnabled: privacyModeEnabled,
                          publicLookupText: publicLookupText,
                          onLoadPublicly: offersPublicDetailsLookup(detail)
                              ? () => unawaited(runPublicLookup(tx))
                              : null,
                        ),
                      if (receiptError != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          receiptError!,
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
    BigInt? giftCardAmountZatoshi,
    required bool privacyModeEnabled,
  }) {
    if (tx == null) return '--';
    if (privacyModeEnabled) {
      return hideAmountIfPrivacyMode('', privacyModeEnabled: true);
    }
    final amountZatoshi = giftCardAmountZatoshi ?? tx.displayAmount;
    if (amountZatoshi == BigInt.zero &&
        !transactionShowsZeroAmount(tx.txKind)) {
      return '--';
    }
    return ZecAmount.fromZatoshi(amountZatoshi).activityDetail.toString();
  }

  String _dateText(rust_sync.TransactionInfo? tx, {DateTime? override}) {
    if (tx == null) return '--';
    if (override != null) return formatActivityTimestamp(override);
    final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
    if (seconds <= BigInt.zero) return '--';
    return formatActivityTimestamp(
      DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000),
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

  String? _feeText(
    rust_sync.TransactionInfo? tx, {
    required bool privacyModeEnabled,
    GiftCardActivityMetadata? giftCard,
  }) {
    // Receives, including redeemed cards, show no network fee: the sender
    // paid it.
    if (tx == null || tx.txKind == 'received' || tx.txKind == 'receiving') {
      return null;
    }
    final networkFee = giftCard == null
        ? unattributedReceiptNetworkFee(tx, receiptDetail)
        : null;
    if (networkFee != null) {
      return hideAmountIfPrivacyMode(
        ZecAmount.fromZatoshi(networkFee).fee.toString(),
        privacyModeEnabled: privacyModeEnabled,
      );
    }
    if (_showUnknownFee(tx)) return kUnknownFeeText;
    if (tx.fee <= BigInt.zero) return null;
    final fee = giftCard == null ? tx.fee : giftCard.detailFeeZatoshi(tx.fee);
    if (privacyModeEnabled) {
      return hideAmountIfPrivacyMode('', privacyModeEnabled: true);
    }
    return ZecAmount.fromZatoshi(fee).fee.toString();
  }

  String? _poolLabel(String? pool, {bool ordinary = false}) {
    return switch (pool) {
      'transparent' => 'Transparent',
      'shielded' => 'Shielded',
      'orchard' when ordinary => 'Orchard',
      'sapling' when ordinary => 'Sapling',
      'ironwood' => 'Ironwood',
      'mixed' => 'Mixed',
      _ => null,
    };
  }

  String? _addressPoolLabel(
    String? pool,
    String? address, {
    bool ordinary = false,
  }) {
    final lower = address?.trim().toLowerCase();
    if (lower != null && lower.startsWith('tex')) return 'TEX';
    return _poolLabel(pool, ordinary: ordinary);
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

/// Bottom strip of a review row: an optional pool glyph and its text.
class _BottomInfo {
  const _BottomInfo({required this.text, this.iconName, this.iconColor});

  final String? text;
  final String? iconName;
  final Color? iconColor;
}

ReviewInfoRow _reviewRow({
  required String label,
  required String value,
  required Widget leading,
  _BottomInfo? bottom,
  Widget? bottomPlaceholder,
  bool strikethrough = false,
  String? trailingActionLabel,
  Key? trailingActionKey,
  VoidCallback? onTrailingAction,
  Key? key,
}) {
  return ReviewInfoRow(
    key: key,
    label: label,
    value: value,
    leading: leading,
    struckThrough: strikethrough,
    bottomLeftIconName: bottom?.iconName,
    bottomLeftIconColor: bottom?.iconColor,
    bottomLeftText: bottom?.text,
    bottomLeftPlaceholder: bottomPlaceholder,
    trailingActionLabel: trailingActionLabel,
    trailingActionKey: trailingActionKey,
    onTrailingAction: onTrailingAction,
  );
}

/// The rounded detail card — Figma `Review Wrap`: status chip, message
/// / timestamp / tx id list, divider, tx fee.
class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.phase,
    this.statusText,
    required this.failed,
    required this.memo,
    this.memoLoading = false,
    required this.messageExpanded,
    required this.onToggleMessage,
    required this.timestampText,
    required this.txidText,
    required this.onOpenExplorer,
    required this.feeText,
    this.isCardCreation = false,
    this.showsNetworkFee = false,
    this.detailsIncomplete = false,
  });

  final _TxPhase phase;
  final String? statusText;
  final bool failed;
  final String? memo;
  final bool memoLoading;
  final bool messageExpanded;
  final VoidCallback onToggleMessage;
  final String timestampText;
  final String txidText;
  final VoidCallback onOpenExplorer;
  final String? feeText;
  final bool isCardCreation;
  final bool showsNetworkFee;
  final bool detailsIncomplete;

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
            value: _StatusChip(phase: phase, statusText: statusText),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (memoLoading) ...[
            const ReceiptMemoSkeleton(),
            const SizedBox(height: AppSpacing.xs),
          ] else if (memoText != null && memoText.isNotEmpty) ...[
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
          if (detailsIncomplete) ...[
            const SizedBox(height: AppSpacing.xs),
            _ListRow(
              key: const ValueKey('mobile_tx_status_details_incomplete'),
              label: 'Details',
              value: _ValueWithIcon(
                text: 'Incomplete',
                iconName: AppIcons.help,
                iconColor: context.colors.icon.regular.withValues(alpha: 0.72),
                onTap: () => unawaited(
                  showMobileTxFeeInfoSheet(
                    context,
                    title: 'Details incomplete',
                    description: kIncompleteDetailsHelpText,
                  ),
                ),
              ),
            ),
          ],
          if (feeText != null) ...[
            const SizedBox(height: AppSpacing.sm),
            // Figma `border/neutral/default` (#d4d4d4 light).
            Container(height: 1, color: colors.border.regular),
            const SizedBox(height: AppSpacing.sm),
            _ListRow(
              label: isCardCreation
                  ? 'Card fee'
                  : showsNetworkFee
                  ? 'Network fee'
                  : 'Tx fee',
              labelStyle: AppTypography.labelLarge,
              value: _ValueWithIcon(
                text: feeText,
                iconName: AppIcons.help,
                iconColor: context.colors.icon.regular.withValues(alpha: 0.72),
                onTap: () => unawaited(
                  isCardCreation
                      ? showMobileTxFeeInfoSheet(
                          context,
                          title: 'Card fee',
                          description: kPaymentLinkCardFeeHelpText,
                        )
                      : showsNetworkFee
                      ? showMobileTxFeeInfoSheet(
                          context,
                          title: 'Network fee',
                          description: kUnattributedNetworkFeeHelpText,
                        )
                      : showMobileTxFeeInfoSheet(context),
                ),
              ),
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
  const _ValueWithIcon({
    this.text,
    this.iconName,
    this.onTap,
    this.iconColor,
    super.key,
  });

  final String? text;
  final String? iconName;
  final VoidCallback? onTap;
  final Color? iconColor;

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
            AppIcon(
              iconName!,
              size: 20,
              color: iconColor ?? colors.icon.accent,
            ),
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
  const _StatusChip({required this.phase, this.statusText});

  final _TxPhase phase;
  final String? statusText;

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
          AppIcon(iconName, size: 20, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              statusText ?? text,
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
