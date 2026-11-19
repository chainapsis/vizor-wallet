import 'dart:async';

import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/network_config.dart';
import '../../../../core/config/swap_feature_config.dart';
import '../../../../core/config/zcash_explorer.dart';
import '../../../../core/formatting/address_display.dart';
import '../../../../core/formatting/zec_amount.dart';
import '../../../../core/layout/mobile/app_mobile_sheet.dart'
    show showAppMobileSheet;
import '../../../../core/layout/mobile/mobile_scroll_edge_fades.dart';
import '../../../../core/layout/mobile/mobile_sticky_bottom_action.dart';
import '../../../../core/layout/mobile/mobile_top_nav.dart';
import '../../../../core/formatting/sync_status_label.dart'
    show withTabularFigures;
import '../../../../core/privacy/privacy_mask.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/mobile/mobile_transaction_progress_screen.dart'
    show mobileTransactionProgressBackgroundImage;
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_icon.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/receipt_loading_skeleton.dart';
import '../../../../core/widgets/mobile/mobile_address_verify_sheet.dart';
import '../../../../core/widgets/mobile/mobile_surface_card.dart';
import '../../../../core/widgets/mobile/mobile_tx_fee_info_sheet.dart';
import '../../../../core/zcash/spendable_wait.dart';
import '../../../../providers/sync_provider.dart';
import '../../../../providers/account_provider.dart';
import '../../../../providers/enhance_pir_provider.dart';
import '../../../../providers/privacy_mode_provider.dart';
import '../../../../providers/zec_price_change_provider.dart';
import '../../../../providers/rpc_endpoint_provider.dart';
import '../../../../providers/spendable_wait_provider.dart';
import '../../../../providers/zcash_explorer_provider.dart';
import '../../../../rust/api/sync.dart' as rust_sync;
import '../../../address_book/models/address_book_contact.dart';
import '../../../address_book/providers/address_book_provider.dart';
import '../../../pay/widgets/mobile/mobile_pay_add_contact_card.dart';
import '../../../payment_links/widgets/mobile/payment_link_mobile_views.dart'
    show kPaymentLinkMobileCardHeight, kPaymentLinkMobileCardWidth;
import '../../../payment_links/widgets/payment_link_gift_card.dart';
import '../../../send/widgets/send_recipient_resolver.dart';
import '../../../send/widgets/send_review_layout.dart'
    show SendReviewAddressRecipient, SendReviewContactRecipient;
import '../../../swap/models/swap_fiat_value_formatting.dart';
import '../../activity_row_mapper.dart'
    show
        activityKindIconName,
        formatActivityTimestamp,
        giftCardActivityTitle,
        transactionActivityPool,
        transactionShowsZeroAmount;
import '../../gift_card_activity_index.dart';
import '../../transaction_completeness.dart';
import '../../widgets/mobile/transaction_type_hero.dart';
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
/// `Status Sending` (9293:34799, sent), `Status Sent` (9292:34716,
/// received), and `Status Sending` (9296:35482, failed): the type icon in
/// liquid metal (or a Gift Card's art), the status chip and serif amount below
/// it, then the rounded detail card (counterparty, message, tx id; timestamp,
/// fee).
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
        context.l10n,
        giftCard.kind,
        isInFlight: _phaseFor(giftCard) == _TxPhase.pending,
        isFailed: _phaseFor(giftCard) == _TxPhase.failed,
      );
    }

    if (_isShielding) {
      return switch (_phase) {
        _TxPhase.pending => context.l10n.commonShielding,
        _TxPhase.succeeded => context.l10n.activityTitleShielded,
        _TxPhase.failed => context.l10n.activityTitleShieldingFailed,
      };
    }
    if (_isMigration) {
      return switch (_phase) {
        _TxPhase.pending => context.l10n.activityTitleMigrating,
        _TxPhase.succeeded => context.l10n.activityTitleMigrated,
        _TxPhase.failed => context.l10n.activityTitleMigrationFailed,
      };
    }
    if (_isIncoming) {
      return switch (_phase) {
        _TxPhase.pending => context.l10n.activityTitleReceivingZec,
        _TxPhase.succeeded => context.l10n.activityTitleReceivedZec,
        _TxPhase.failed => context.l10n.activityTitleReceiveZecFailed,
      };
    }
    // Unclassified transactions and balance movements stay neutral, like
    // the desktop fallback receipt: neither establishes an external payment.
    if (!_isSent ||
        _feePresentationFor(receiptTransaction, null) !=
            TransactionFeePresentation.separate) {
      return context.l10n.activityTitleTransaction;
    }
    return switch (_phase) {
      _TxPhase.pending => context.l10n.activityTitleSendingZec,
      _TxPhase.succeeded => context.l10n.activityTitleSentZec,
      _TxPhase.failed => context.l10n.activityTitleSendZecFailed,
    };
  }

  /// Pins "Add address to contacts" over the receipt while [address] is an
  /// unsaved recipient; otherwise the receipt scrolls on its own.
  Widget _withSaveContactAction({
    required String? address,
    required Widget child,
  }) {
    if (address == null) return child;
    return MobileStickyBottomAction(
      action: AppButton(
        key: const ValueKey('mobile_tx_status_add_contact'),
        expand: true,
        // A long translation or large text shortens instead of overflowing.
        constrainContent: true,
        onPressed: () => unawaited(_addRecipientToContacts(address)),
        leading: const AppIcon(AppIcons.addNew),
        child: Text(context.l10n.activityAddAddressToContacts),
      ),
      child: child,
    );
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
    showAppToast(context, context.l10n.activityToastHashCopiedMobile);
  }

  /// Saves a sent payment's recipient as a Zcash contact, on the same card
  /// the Pay flow offers after a payment.
  Future<void> _addRecipientToContacts(String address) {
    return showAppMobileSheet<void>(
      context: context,
      builder: (sheetContext) => MobilePayAddContactCard(
        network: AddressBookNetwork.zcash,
        address: address,
        onCancel: () => Navigator.of(sheetContext).pop(),
        onSave: (label, profilePictureId) async {
          await ref
              .read(addressBookProvider.notifier)
              .addContact(
                label: label,
                network: AddressBookNetwork.zcash,
                address: address,
                profilePictureId: profilePictureId,
              );
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        },
      ),
    );
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
    final l10n = context.l10n;
    final privacyModeEnabled = ref.watch(privacyModeProvider);
    final transparentStop = ref.watch(
      syncProvider.select((sync) => sync.value?.transparentStop),
    );
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
                title: l10n.activityTitleTransaction,
                titleStyle: AppTypography.headlineSmall,
                onBack: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    receiptLoading
                        ? l10n.activityReceiptLoading
                        : (receiptError ?? l10n.activityReceiptLoadFailed),
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

    // The amount's dollar value at today's price, like Home's balance. A
    // receipt is a stored record, so privacy mode masks it with the amount.
    // A Gift Card shows the dollar value saved when it was made.
    final fiatValue = feeOnly
        ? null
        : giftCard != null
        ? (ref.watch(swapFeatureEnabledProvider) &&
                  giftCard.fiatSnapshot != null
              ? swapFormatCompactFiatValue(giftCard.fiatSnapshot!.amount)
              : null)
        : fiatTextForZatoshi(
            tx.displayAmount.abs(),
            zecUsdUnitPrice: ref.watch(zecHomeUsdUnitPriceProvider),
          );
    final fiatText = fiatValue == null
        ? null
        : privacyModeEnabled
        ? fixedPrivacyMask()
        : fiatValue;
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
    // The card's note lives in the Gift Card record, not the funding memo.
    final memo = giftCard != null
        ? giftCard.message?.trim()
        : detail?.memo?.trim();

    // Resolve the counterparty to a saved contact / own account so the
    // From/To row shows a name + avatar instead of a raw address — parity
    // with the desktop receipt (sendReviewRecipientFor).
    final addressBook = ref.watch(addressBookProvider);
    final contacts =
        addressBook.value?.contacts ?? const <AddressBookContact>[];
    final ownAccountsState = ref.watch(ownAccountAddressesProvider);
    final ownAccounts = ownAccountsState.value ?? const <String, AccountInfo>{};
    final resolvedRecipient = address == null || address.isEmpty
        ? null
        : sendReviewRecipientFor(
            contacts: contacts,
            address: address,
            ownAccounts: ownAccounts,
          );
    final namedRecipient = switch (resolvedRecipient) {
      SendReviewContactRecipient r => r,
      _ => null,
    };
    // A sent payment to an address that is neither a contact nor one of the
    // wallet's own accounts offers to save it. Waits for both lists, so the
    // button never flashes for a recipient that is already saved.
    final unsavedRecipient =
        _isSent &&
            giftCard == null &&
            !failed &&
            !detailsLoading &&
            addressBook.hasValue &&
            ownAccountsState.hasValue &&
            resolvedRecipient is SendReviewAddressRecipient
        ? address
        : null;

    // The amount sits in the hero without a row label; only a net change says
    // what it is. A shielding always showed its plain amount.
    final amountCaption = _isShielding
        ? null
        : switch (feePresentation) {
            TransactionFeePresentation.separate => null,
            TransactionFeePresentation.includedInAmount =>
              l10n.activityReceiptNetChange,
            TransactionFeePresentation.feeOnly => l10n.activityReceiptNetChange,
          };
    final addressRow = (address == null || address.isEmpty)
        ? null
        : _ListRow(
            label: _isIncoming
                ? l10n.activityReceiptFrom
                : l10n.activityReceiptRecipient,
            value: _ValueWithIcon(
              key: const ValueKey('mobile_tx_status_show_full_address'),
              leadingIconName: poolLabel == null
                  ? null
                  : _poolIconNameFor(poolLabel, address: address),
              leadingIconColor: poolLabel == null
                  ? null
                  : _poolIconColorFor(context, poolLabel, address: address),
              leadingIconLabel: poolLabel,
              text: namedRecipient != null
                  ? namedRecipient.name
                  : _truncateAddress(address),
              struckThrough: failed,
              iconName: AppIcons.chevronForward,
              onTap: () => unawaited(_showFullAddressSheet(address)),
              semanticsLabel: l10n.commonShowFullAddress,
            ),
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
      'shielded' => l10n.poolShielded,
      'transparent' => l10n.poolTransparent,
      _ => null,
    };
    final sourceAccountRow = sourceAccount == null
        ? null
        : _ListRow(
            key: const ValueKey('received_from_account'),
            label: l10n.activityReceiptFrom,
            value: _ValueWithIcon(
              leadingIconName: sourceAccountPool == null
                  ? null
                  : _poolIconNameFor(sourceAccountPool),
              leadingIconColor: sourceAccountPool == null
                  ? null
                  : _poolIconColorFor(context, sourceAccountPool),
              leadingIconLabel: sourceAccountPool,
              text: sourceAccount.name,
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
        : _ListRow(
            label: l10n.activityReceiptFrom,
            value: _ValueWithIcon(
              leadingIconName: sourcePool == 'shielded'
                  ? _poolIconNameFor(l10n.poolShielded)
                  : null,
              leadingIconColor: sourcePool == 'shielded'
                  ? _poolIconColorFor(context, l10n.poolShielded)
                  : null,
              leadingIconLabel: sourcePool == 'shielded'
                  ? l10n.poolShielded
                  : null,
              text: unknownFromLabel,
            ),
          );

    // Received flows name the sender; sent flows the recipient. Either one
    // opens the detail card (Figma `Status Sending` 9293:34799).
    final fromRow = _isIncoming
        ? detailsLoading
              ? _ListRow(
                  key: const ValueKey('mobile_tx_status_counterparty_skeleton'),
                  label: l10n.activityReceiptFrom,
                  value: const ReceiptValueSkeleton(),
                )
              : addressRow ?? sourceAccountRow ?? unknownFromRow
        : null;
    // A send whose recipient the account did not record keeps the To row,
    // naming no one and offering nothing to verify.
    final toRow = _isSent && detailsLoading
        ? _ListRow(
            key: const ValueKey('mobile_tx_status_counterparty_skeleton'),
            label: l10n.activityReceiptRecipient,
            value: const ReceiptValueSkeleton(),
          )
        : addressRow ??
              (giftCard == null && receiptHasUnknownRecipient(tx, detail)
                  ? _ListRow(
                      key: const ValueKey('receipt_unknown_recipient'),
                      label: l10n.activityReceiptRecipient,
                      value: _ValueWithIcon(
                        text: l10n.activityDetailsUnknownRecipient,
                        struckThrough: failed,
                      ),
                    )
                  : null);
    // Self-shield (own transparent -> own shielded) and migration have no
    // external counterparty: the hero line says where the funds came from and
    // the first card row names the balance they went to, like the desktop
    // ShieldedReceiptView. No Figma frame for these states yet.
    final counterpartyRow = giftCard != null
        ? null
        : _isMigration
        ? _ListRow(
            label: l10n.commonTo,
            value: _ValueWithIcon(
              leadingIconName: AppIcons.shieldKeyhole,
              leadingIconColor: colors.icon.success,
              leadingIconLabel: 'Ironwood', // l10n-ignore: product name
              text: l10n.activityBalanceIronwood,
            ),
          )
        : _isShielding
        ? _ListRow(
            label: l10n.commonTo,
            value: _ValueWithIcon(
              leadingIconName: AppIcons.shieldKeyhole,
              leadingIconColor: colors.icon.brandCrimson,
              leadingIconLabel: l10n.poolShielded,
              text: l10n.commonShieldedBalance,
            ),
          )
        : _isIncoming
        ? fromRow
        : toRow;
    // What the hero line used to say, as card rows: a net change names what
    // the amount is, and a shielding or migration says where it came from.
    final sourceRow = _isShielding
        ? _ListRow(
            label: l10n.activityReceiptFrom,
            value: _ValueWithIcon(
              leadingIconName: AppIcons.transparentBalance,
              leadingIconColor: colors.icon.muted,
              leadingIconLabel: l10n.poolTransparent,
              text: l10n.activityBalanceTransparent,
            ),
          )
        : _isMigration
        ? _ListRow(
            label: l10n.activityReceiptFrom,
            value: _ValueWithIcon(
              leadingIconName: AppIcons.migrationSplit,
              leadingIconColor: colors.icon.regular,
              text: l10n.activityBalanceOrchard,
            ),
          )
        : null;
    final phase = _phaseFor(giftCard);
    // A receipt whose funds cannot be spent yet says when they can.
    final spendableWait = giftCard != null
        ? null
        : receivedSpendableWaitFor(
            tx,
            ref.watch(activeReceivedSpendableWaitsProvider),
          );
    final leadingRows = <Widget>[
      // The status heads the card, in the same two columns as its rows.
      _ListRow(
        key: const ValueKey('mobile_tx_status_status'),
        label: l10n.activityReceiptStatus,
        value: _StatusChip(
          phase: phase,
          waiting: spendableWait != null,
          statusText: giftCard == null
              ? (spendableWait == null
                    ? null
                    : availableInLabel(l10n, spendableWait.wait))
              : switch (phase) {
                  _TxPhase.pending =>
                    giftCard.kind == GiftCardActivityKind.created
                        ? l10n.commonCreating
                        : l10n.activityGiftStatusRedeeming,
                  _TxPhase.succeeded =>
                    giftCard.kind == GiftCardActivityKind.created
                        ? l10n.commonCreated
                        : l10n.activityGiftStatusRedeemed,
                  _TxPhase.failed => l10n.commonFailed,
                },
        ),
      ),
      if (spendableWait != null)
        _ListRow(
          key: const ValueKey('mobile_tx_status_confirmations'),
          label: l10n.activityReceiptConfirmations,
          value: _ValueWithIcon(
            text: l10n.activityReceiptConfirmationsProgress(
              spendableWait.confirmations.toString(),
              spendableWait.requiredConfirmations.toString(),
            ),
          ),
        ),
      if (amountCaption != null)
        _ListRow(
          key: const ValueKey('mobile_tx_status_net_change'),
          label: amountCaption,
          value: _ValueWithIcon(text: amountText),
        ),
      ?sourceRow,
      ?counterpartyRow,
    ];

    return Scaffold(
      backgroundColor: colors.background.window,
      body: _RecordBackdrop(
        child: AppToastHost(
          child: SafeArea(
            // The scroll runs to the bottom edge, where the save action
            // floats like the tab bar; its padding clears the home indicator.
            bottom: false,
            child: Column(
              children: [
                MobileTopNav.back(
                  title: _titleFor(giftCard),
                  titleStyle: AppTypography.headlineSmall,
                  titleMaxLines: giftCard == null ? 1 : 2,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: _withSaveContactAction(
                    address: unsavedRecipient,
                    child: SingleChildScrollView(
                      key: const ValueKey('mobile_tx_status_scroll'),
                      padding: EdgeInsets.fromLTRB(
                        kMobilePageMargin,
                        AppSpacing.s,
                        kMobilePageMargin,
                        unsavedRecipient == null
                            ? AppSpacing.md +
                                  MediaQuery.paddingOf(context).bottom
                            : MobileStickyBottomAction.contentInset(context),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Figma `Review Info`: the hero, then the status chip
                          // and the amount.
                          if (giftCard != null)
                            Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.s),
                              child: Center(
                                // About 30% under the full-width card, so the
                                // record does not open on a page-wide card.
                                // The whole card scales, its text included.
                                child: SizedBox(
                                  width: kPaymentLinkMobileCardWidth * 0.7,
                                  height: kPaymentLinkMobileCardHeight * 0.7,
                                  child: FittedBox(
                                    child: PaymentLinkGiftCard(
                                      artwork:
                                          PaymentLinkCardArtwork.fromProtocolId(
                                            giftCard.artworkId,
                                          ),
                                      cardWidth: kPaymentLinkMobileCardWidth,
                                      cardHeight: kPaymentLinkMobileCardHeight,
                                      // The amount sits under the card, as on
                                      // every record.
                                      showAmount: false,
                                    ),
                                  ),
                                ),
                              ),
                            )
                          else
                            // The type's icon in liquid metal, with room above
                            // and below so it floats between the nav and the
                            // status.
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.s,
                              ),
                              child: Center(
                                child: TransactionTypeHero(
                                  iconName: activityKindIconName(tx.txKind),
                                ),
                              ),
                            ),
                          const SizedBox(height: AppSpacing.xs),
                          // The top holds only the type icon (or the Gift
                          // Card), the amount and its dollar value;
                          // everything else, the status included, is in the
                          // card.
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.s,
                            ),
                            child: _HeroAmount(
                              amountText: amountText,
                              fiatText: fiatText,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _DetailCard(
                            leadingRows: leadingRows,
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
                                unattributedReceiptNetworkFee(
                                      tx,
                                      receiptDetail,
                                    ) !=
                                    null,
                            feeText: feeOnly
                                ? null
                                : _feeText(
                                    tx,
                                    giftCard: giftCard,
                                    privacyModeEnabled: privacyModeEnabled,
                                  ),
                            detailsIncomplete: _showIncompleteDetails(tx),
                            detailsAwaitPrivateCheck: receiptAwaitsPrivateCheck(
                              tx,
                              recoveryStopped: transparentStop != null,
                            ),
                            detailsStop: receiptPrivateCheckStop(
                              tx,
                              stop: transparentStop,
                            ),
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
                              style: AppTypography.bodyMedium.copyWith(
                                color: colors.text.destructive,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
    // A receive reads as money in, as its activity row does.
    return ZecAmount.fromZatoshi(
      amountZatoshi,
    ).activityDetailPretty(signed: _isIncoming).toString();
  }

  String _dateText(rust_sync.TransactionInfo? tx, {DateTime? override}) {
    if (tx == null) return '--';
    if (override != null) {
      return formatActivityTimestamp(context.l10n, override);
    }
    final seconds = tx.blockTime > BigInt.zero ? tx.blockTime : tx.createdTime;
    if (seconds <= BigInt.zero) return '--';
    return formatActivityTimestamp(
      context.l10n,
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
    if (_showUnknownFee(tx)) return context.l10n.commonUnknown;
    if (tx.fee <= BigInt.zero) return null;
    final fee = giftCard == null ? tx.fee : giftCard.detailFeeZatoshi(tx.fee);
    if (privacyModeEnabled) {
      return hideAmountIfPrivacyMode('', privacyModeEnabled: true);
    }
    return ZecAmount.fromZatoshi(fee).fee.toString();
  }

  String? _poolLabel(String? pool, {bool ordinary = false}) {
    return switch (pool) {
      'transparent' => context.l10n.poolTransparent,
      'shielded' => context.l10n.poolShielded,
      'orchard' when ordinary => 'Orchard', // l10n-ignore: product name
      'sapling' when ordinary => 'Sapling', // l10n-ignore: product name
      'ironwood' => 'Ironwood', // l10n-ignore: product name
      'mixed' => context.l10n.activityPoolMixed,
      _ => null,
    };
  }

  String? _addressPoolLabel(
    String? pool,
    String? address, {
    bool ordinary = false,
  }) {
    final lower = address?.trim().toLowerCase();
    if (lower != null && lower.startsWith('tex')) {
      return 'TEX'; // l10n-ignore: protocol name
    }
    return _poolLabel(pool, ordinary: ordinary);
  }

  String _poolIconNameFor(String? poolLabel, {String? address}) {
    final isTransparent =
        poolLabel == context.l10n.poolTransparent ||
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
        poolLabel == context.l10n.poolTransparent ||
        (address != null &&
            zcashAddressDisplayKind(address) ==
                ZcashAddressDisplayKind.transparent);
    return isTransparent
        ? context.colors.icon.muted
        : context.colors.icon.brandCrimson;
  }

  String? _unknownFromLabelForSourcePool(String? pool) {
    if (pool == null || pool.isEmpty) return null;
    return pool == 'shielded'
        ? context.l10n.activitySenderShielded
        : context.l10n.activitySenderUnknown;
  }

  String _addressVerifyTitle(String address) {
    final lower = address.trim().toLowerCase();
    if (lower.startsWith('u1')) return context.l10n.activityAddressUnified;
    if (lower.startsWith('zs')) return context.l10n.commonShieldedAddress;
    if (lower.startsWith('t')) return context.l10n.commonTransparentAddress;
    return context.l10n.commonZcashAddress;
  }

  String _truncateAddress(String address) {
    if (address.length <= 14) return address;
    return '${address.substring(0, 6)} ... ' // l10n-ignore: address
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
          isTransparent ? AppIcons.transparentBalance : AppIcons.shieldKeyhole,
          size: AppIconSize.medium,
          color: isTransparent ? colors.icon.muted : colors.icon.brandCrimson,
        ),
      ),
    );
  }
}

enum _TxPhase { pending, succeeded, failed }

/// The faded castle engraving behind a record, the artwork of the send
/// status screen (Figma `Status Sending` background). The asset fades into
/// the page halfway down. It is a translucent grey, so it reads on both
/// themes, as the send status screen shows it.
class _RecordBackdrop extends StatelessWidget {
  const _RecordBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const Positioned.fill(
          child: Image(
            key: ValueKey('mobile_tx_status_backdrop'),
            image: mobileTransactionProgressBackgroundImage,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            // Faded further, so the coin stays the focus.
            opacity: AlwaysStoppedAnimation(0.6),
            excludeFromSemantics: true,
          ),
        ),
        // The page fades paint the window color, which would band across
        // the engraving; the record scrolls without them here.
        MobileScrollEdgeFades.off(child: child),
      ],
    );
  }
}

/// Figma `Asset Details`: the serif amount, centered, with its dollar value
/// on a reserved 24px line below.
// The Send amount input's size (48, with a 38 ticker), the app's largest
// amount style.
const _heroAmountFontSize = 48.0;
const _heroUnitFontSize = 38.0;

class _HeroAmount extends StatelessWidget {
  const _HeroAmount({required this.amountText, this.fiatText});

  final String amountText;

  /// The amount's dollar value (Figma `$250.12`), when a price is known.
  final String? fiatText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amountStyle = AppTypography.displayLarge.copyWith(
      color: colors.text.accent,
      fontSize: _heroAmountFontSize,
    );
    // Figma sets the ticker a step smaller (Young Serif 32) than the number.
    final unit = ' $kZcashDefaultCurrencyTicker';
    final hasUnit =
        amountText.length > unit.length && amountText.endsWith(unit);
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.xxs,
      children: [
        // Long amounts scale down to fit between the page margins rather
        // than truncate or wrap.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            key: const ValueKey('mobile_tx_status_amount'),
            hasUnit
                ? TextSpan(
                    children: [
                      serifPrivacyMaskSpan(
                        amountText.substring(
                          0,
                          amountText.length - unit.length + 1,
                        ),
                        amountStyle,
                      ),
                      TextSpan(
                        text: kZcashDefaultCurrencyTicker,
                        style: AppTypography.displaySmall.copyWith(
                          fontSize: _heroUnitFontSize,
                        ),
                      ),
                    ],
                  )
                : serifPrivacyMaskSpan(amountText, amountStyle),
            maxLines: 1,
            textAlign: TextAlign.center,
            style: amountStyle,
          ),
        ),
        // A reserved line, so the card does not move when the price arrives.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.md),
          child: fiatText == null
              ? null
              : Text(
                  fiatText!,
                  key: const ValueKey('mobile_tx_status_fiat'),
                  textAlign: TextAlign.center,
                  style: withTabularFigures(
                    AppTypography.labelLarge.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// The rounded detail card — Figma `Review Wrap`: the counterparty /
/// message / tx id list, then the timestamp / tx fee list.
class _DetailCard extends StatelessWidget {
  const _DetailCard({
    this.leadingRows = const [],
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
    this.detailsAwaitPrivateCheck = false,
    this.detailsStop,
  });

  /// The From / To row, when the transaction has a counterparty to name.
  /// Rows heading the first group: what the amount is, then where the
  /// funds came from and went.
  final List<Widget> leadingRows;
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

  /// Whether the incomplete details wait only on the private check, which
  /// finishes on its own; see `receiptAwaitsPrivateCheck`.
  final bool detailsAwaitPrivateCheck;

  /// Why private recovery stopped checking these details; see
  /// `receiptPrivateCheckStop`.
  final rust_sync.TransparentStopReason? detailsStop;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final memoText = memo;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.background.ground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: mobileSurfaceShadows(colors),
      ),
      // Two lists, 12px apart with no divider: 8px between the rows of the
      // first, none in the second.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.s,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppSpacing.xs,
            children: [
              ...leadingRows,
              if (memoLoading)
                const ReceiptMemoSkeleton()
              else if (memoText != null && memoText.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ListRow(
                      label: context.l10n.commonMessage,
                      value: _ValueWithIcon(
                        key: const ValueKey('mobile_tx_status_message_toggle'),
                        text: messageExpanded ? null : _previewMemo(memoText),
                        iconName: AppIcons.expand,
                        onTap: onToggleMessage,
                        // Expanded, the toggle shows only its icon; keep it
                        // named.
                        semanticsLabel: context.l10n.commonMessage,
                        expanded: messageExpanded,
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
                  ],
                ),
              _ListRow(
                key: const ValueKey('mobile_tx_status_txid'),
                label: context.l10n.commonTxId,
                value: _ValueWithIcon(
                  text: txidText,
                  iconName: AppIcons.arrowTopRight,
                  onTap: onOpenExplorer,
                ),
              ),
              if (detailsIncomplete)
                _ListRow(
                  key: const ValueKey('mobile_tx_status_details_incomplete'),
                  label: context.l10n.activityReceiptDetails,
                  value: _ValueWithIcon(
                    text: detailsAwaitPrivateCheck
                        ? context.l10n.activityReceiptCheckingPrivately
                        : context.l10n.activityReceiptIncomplete,
                    iconName: AppIcons.help,
                    iconColor: context.colors.icon.muted,
                    onTap: () => unawaited(
                      showMobileTxFeeInfoSheet(
                        context,
                        title: detailsAwaitPrivateCheck
                            ? context.l10n.activityReceiptCheckingPrivately
                            : context.l10n.activityReceiptDetailsIncomplete,
                        description: receiptIncompleteDetailsHelp(
                          context.l10n,
                          awaitsPrivateCheck: detailsAwaitPrivateCheck,
                          stop: detailsStop,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ListRow(
                label: context.l10n.commonTimestamp,
                value: _ValueWithIcon(text: timestampText),
              ),
              if (feeText != null)
                _ListRow(
                  label: isCardCreation
                      ? context.l10n.activityReceiptCardFee
                      : showsNetworkFee
                      ? context.l10n.commonNetworkFee
                      : context.l10n.txFeeInfoTitle,
                  value: _ValueWithIcon(
                    text: feeText,
                    iconName: AppIcons.help,
                    iconColor: context.colors.icon.muted,
                    onTap: () => unawaited(
                      isCardCreation
                          ? showMobileTxFeeInfoSheet(
                              context,
                              title: context.l10n.activityReceiptCardFee,
                              description:
                                  context.l10n.paymentLinkCardFeeHelpText,
                            )
                          : showsNetworkFee
                          ? showMobileTxFeeInfoSheet(
                              context,
                              title: context.l10n.commonNetworkFee,
                              description: context
                                  .l10n
                                  .activityReceiptUnattributedFeeHelp,
                            )
                          : showMobileTxFeeInfoSheet(context),
                    ),
                  ),
                ),
            ],
          ),
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
  const _ListRow({required this.label, required this.value, super.key});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // At least the Figma 32px row; grows with large text instead of
    // clipping it.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            child: Text(
              label,
              style: AppTypography.labelLarge.copyWith(
                color: colors.text.secondary,
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

/// Right-side value: text plus optional leading and trailing 20px icons,
/// padded like the Figma `Item Right` (8 left, 4 right/vertical).
class _ValueWithIcon extends StatelessWidget {
  const _ValueWithIcon({
    this.text,
    this.iconName,
    this.onTap,
    this.iconColor,
    this.leadingIconName,
    this.leadingIconColor,
    this.leadingIconLabel,
    this.struckThrough = false,
    this.semanticsLabel,
    this.expanded,
    super.key,
  });

  final String? text;
  final String? iconName;
  final VoidCallback? onTap;
  final Color? iconColor;

  /// Pool glyph before the text (Figma `Shield Fill` on the Recipient row).
  final String? leadingIconName;
  final Color? leadingIconColor;

  /// What the leading glyph stands for, for screen readers (the pool).
  final String? leadingIconLabel;

  /// Line-through on the text — a failed send's counterparty.
  final bool struckThrough;

  /// Names a tappable value whose visible content may be only an icon.
  final String? semanticsLabel;

  /// Expanded state for a disclosure toggle; null for other values.
  final bool? expanded;

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
          if (leadingIconName != null) ...[
            AppIcon(
              leadingIconName!,
              size: 20,
              color: leadingIconColor ?? colors.icon.accent,
              semanticLabel: leadingIconLabel,
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
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
                  decoration: struckThrough ? TextDecoration.lineThrough : null,
                  decorationColor: struckThrough ? colors.text.accent : null,
                ),
              ),
            ),
          if (iconName != null) ...[
            const SizedBox(width: AppSpacing.xxs),
            // Figma `Review Wrap` draws its trailing glyphs in icon/muted.
            AppIcon(iconName!, size: 20, color: iconColor ?? colors.icon.muted),
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: semanticsLabel,
      expanded: expanded,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// Status chip centered above the hero amount: spinner + "In progress",
/// green check + "Completed", or destructive cancel + "Failed, funds
/// returned".
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.phase,
    this.statusText,
    this.waiting = false,
  });

  final _TxPhase phase;
  final String? statusText;

  /// Completed, but its funds cannot be spent yet: a clock, not a check.
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (iconName, text, color) = switch (phase) {
      _TxPhase.pending => (
        AppIcons.loader,
        context.l10n.commonInProgress,
        colors.text.secondary,
      ),
      _TxPhase.succeeded when waiting => (
        AppIcons.time,
        context.l10n.commonCompleted,
        colors.text.accent,
      ),
      _TxPhase.succeeded => (
        AppIcons.checkCircle,
        context.l10n.commonCompleted,
        colors.text.positiveStrong,
      ),
      // The Figma frame says "Failed, refunded minus tx fee", but the
      // only failure the wallet records is expiry before mining, where
      // no fee is spent at all.
      _TxPhase.failed => (
        AppIcons.cancel,
        context.l10n.activityStatusFailedFundsReturned,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(iconName, size: 20, color: color),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              statusText ?? text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              // The card's value style; color and icon carry the state.
              style: AppTypography.labelLarge.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
