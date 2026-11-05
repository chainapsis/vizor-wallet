import '../../../core/l10n/l10n.dart';
import '../../address_book/models/address_book_contact.dart';
import 'swap_detail_tooltips.dart';

enum SwapStatusBadgeKind { liveQuote, completed, refunded, warning, failed }

enum SwapStatusTab { progress, details }

enum SwapStatusStepState { complete, active, pending }

class SwapStatusStepData {
  const SwapStatusStepData({
    required this.title,
    required this.state,
    this.completeTitle,
    this.activeTitle,
    this.pendingTitle,
    this.lastCheckedLabel,
    this.description,
  });

  final String title;
  final SwapStatusStepState state;
  final String? completeTitle;
  final String? activeTitle;
  final String? pendingTitle;
  final String? lastCheckedLabel;
  final String? description;

  String titleForState(SwapStatusStepState state) {
    return switch (state) {
      SwapStatusStepState.complete => completeTitle ?? title,
      SwapStatusStepState.active => activeTitle ?? title,
      SwapStatusStepState.pending => pendingTitle ?? title,
    };
  }

  SwapStatusStepData copyWithState(SwapStatusStepState state) {
    return SwapStatusStepData(
      title: title,
      state: state,
      completeTitle: completeTitle,
      activeTitle: activeTitle,
      pendingTitle: pendingTitle,
      lastCheckedLabel: lastCheckedLabel,
      description: description,
    );
  }
}

/// Semantic identity of a status detail row. Widgets branch on this, never on
/// the (localized) label text.
enum SwapStatusDetailKind {
  swapFee,
  totalFees,
  txFee,
  refundFee,
  refundedAmount,
  refundTo,
  guaranteedMinimum,
  priceProtection,
  account,
  timestamp,
  txId,
  slippageTolerance,
  memo,
  missingDeposit,
  requiredDeposit,
  detectedDeposit,
  depositDeadline,
  depositAddress,
  recipient,
  refundAddress,
  sourceTx,
  deliveryTx,
  other;

  /// Fee rows sort last and get the divider before them.
  bool get isFee => switch (this) {
    swapFee || totalFees || txFee || refundFee => true,
    _ => false,
  };

  /// Values that are addresses or tx ids: shortened/scaled to fit the row.
  bool get compactsValue => switch (this) {
    depositAddress ||
    recipient ||
    refundAddress ||
    refundTo ||
    refundFee ||
    refundedAmount ||
    txId ||
    sourceTx ||
    deliveryTx => true,
    _ => false,
  };

  bool get isDepositAddress => this == depositAddress;

  /// Address rows hidden from the mobile success details.
  bool get isSuccessAddress => this == recipient || this == depositAddress;

  bool get hiddenOnMobile => this == priceProtection || this == account;

  /// Rows kept in the mobile progress "transaction details" card.
  bool get inMobileProgressTransactionDetails => switch (this) {
    depositAddress ||
    slippageTolerance ||
    guaranteedMinimum ||
    memo ||
    missingDeposit ||
    requiredDeposit ||
    detectedDeposit ||
    depositDeadline ||
    refundFee ||
    timestamp ||
    txId => true,
    _ => false,
  };

  /// Fallback tooltip for a help row that carries no explicit tooltip.
  String helpTooltipFor(AppLocalizations l10n) => switch (this) {
    swapFee => swapFeeTooltip(l10n),
    guaranteedMinimum => swapGenericMinimumReceiveTooltip(l10n),
    totalFees => swapTotalFeesTooltip(l10n),
    _ => swapStatusDetailTooltip(l10n),
  };
}

class SwapStatusDetailRowData {
  const SwapStatusDetailRowData({
    required this.label,
    required this.value,
    this.kind = SwapStatusDetailKind.other,
    this.copyable = false,
    this.copyText,
    this.help = false,
    this.helpTooltip,
    this.linkUri,
    this.accountProfilePictureId,
    this.addressBookLabel,
    this.addressNetwork,
  });

  final String label;
  final String value;
  final SwapStatusDetailKind kind;
  final bool copyable;
  final String? copyText;
  final bool help;
  final String? helpTooltip;

  /// Optional external URI opened from the row's trailing action, e.g. the
  /// completed swap's deposit tx row linking to the NEAR Intents explorer.
  final Uri? linkUri;
  final String? accountProfilePictureId;

  /// When this row is an address that matches a saved address-book contact,
  /// the contact's nickname. Renders as a matched-contact identity cell
  /// (nickname + saved mark above the network + address).
  final String? addressBookLabel;

  /// The contact's network, used to draw the chain chip on the address line.
  /// Only set when [addressBookLabel] is non-null.
  final AddressBookNetwork? addressNetwork;
}
