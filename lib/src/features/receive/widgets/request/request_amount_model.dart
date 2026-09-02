/// The immutable snapshot every "Request ZEC" widget renders, plus the
/// copy the flow shares between form factors.
///
/// Nothing here reads a provider, touches storage, or calls Rust. The desktop
/// modal and the mobile sheet are both pure functions of a [ZecRequestView],
/// which is what lets the whole flow be reviewed in Widgetbook before it is
/// wired to the Receive screen.
library;

import 'package:flutter/foundation.dart';

import '../../../../core/config/network_config.dart'
    show kZcashDefaultCurrencyTicker;
import '../../../../core/zcash/zip321_payment_request_builder.dart';

/// Toast shown after the request link reaches the clipboard.
const kRequestLinkCopiedToast = 'Request link copied';

/// Header for both the desktop modal and the mobile sheet.
///
/// One title for the whole flow: the mobile result step keeps it and adds a
/// back chevron, so the two steps read as one task rather than two screens.
final String kRequestFlowTitle = 'Request $kZcashDefaultCurrencyTicker';

/// The collapsed message prompt, worded as the action it starts.
const kRequestAddMessageLabel = 'Add a message';

/// The two steps both form factors present the request flow in.
///
/// Named here rather than beside either presentation because the desktop
/// modal and the mobile sheet are the same two steps in different chrome, and
/// the screen that drives them holds one step value for whichever is mounted.
enum RequestModalStep {
  /// Amount and optional message. Nothing is a request yet.
  compose,

  /// The request itself: QR, summary, and the ways of handing it over.
  result,
}

/// Why the message exists and where it does not: the same sentence the send
/// composer's memo card carries, so the two prompts stay one component.
const kRequestMessageHelpText = 'Encrypted, for shielded addresses only.';

/// Inline amount errors. Both are phrased as the correction to make, not as a
/// verdict on what was typed.
const kRequestAmountDecimalsError = 'Enter up to 8 decimals';
const kRequestAmountSupplyError = 'Amount exceeds the ZEC supply';

/// Body of the share sheet a mobile request opens.
///
/// Deliberately a full templated sentence rather than fragments concatenated
/// around the amount — word order changes per language, and this string is
/// destined for translation.
String buildRequestShareText({required String amountZec, required String uri}) {
  return 'Pay me $amountZec $kZcashDefaultCurrencyTicker with Vizor\n$uri';
}

/// Everything the request widgets draw.
///
/// [amountZec] is the canonical ZEC value as typed, independent of which unit
/// the field is currently showing; [amountDisplayText] is what the field
/// itself renders, so a USD-mode preview can show `35.00` while the request
/// still encodes `0.5`.
@immutable
class ZecRequestView {
  const ZecRequestView({
    required this.address,
    this.amountZec = '',
    this.amountDisplayText = '',
    this.amountInputIsUsd = false,
    this.conversionText,
    this.messageText,
    this.amountError,
  });

  /// The receiving address the request pays to. Snapshotted by the caller at
  /// the moment the request is created — a shielded address the user renews
  /// afterwards must not silently change a link already handed out.
  final String address;

  /// Canonical ZEC amount as typed (`'0.5'`), empty when nothing is entered.
  final String amountZec;

  /// What the amount field shows. Defaults to [amountZec] when blank.
  final String amountDisplayText;

  /// True while the field is collecting USD rather than ZEC.
  final bool amountInputIsUsd;

  /// The other-unit line under the field (`$35.00`, or `0.5 ZEC` in USD
  /// mode). Null renders the price-unavailable placeholder.
  final String? conversionText;

  /// The optional encrypted memo. Shielded requests only.
  final String? messageText;

  /// Inline error under the amount field, or null.
  final String? amountError;

  bool get isShielded => !zip321AddressIsTransparent(address);

  /// The message the request will carry, or null when there is none to carry.
  ///
  /// A transparent address can never carry one, so the getter refuses it here
  /// rather than leaving every caller to remember the rule.
  String? get effectiveMessage {
    if (!isShielded) return null;
    final trimmed = messageText?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : messageText;
  }

  bool get hasMessage => effectiveMessage != null;

  /// The text shown in the amount field.
  String get fieldText =>
      amountDisplayText.isNotEmpty ? amountDisplayText : amountZec;

  /// The ZIP-321 URI this request encodes, or null when the amount is not yet
  /// a usable number.
  ///
  /// Errors are swallowed on purpose: an in-progress amount is not a failure
  /// state, it is simply not a request yet. The field's own inline error is
  /// what tells the user something is wrong.
  String? get requestUri {
    if (amountZec.trim().isEmpty) return null;
    try {
      return buildZip321PaymentUri(
        address: address,
        amountZec: amountZec,
        memoText: effectiveMessage,
      );
    } on Zip321BuildException {
      return null;
    }
  }

  /// What the QR encodes.
  ///
  /// With no valid amount this falls back to the bare address, so the code on
  /// screen is always scannable and always means something: before an amount
  /// is entered the request QR *is* the address QR.
  String get qrData => requestUri ?? address;

  /// `0.5 ZEC` for the line under the QR, or null before there is an amount.
  String? get summaryAmountText {
    final uri = requestUri;
    if (uri == null) return null;
    try {
      return '${normalizeZip321Amount(amountZec)} $kZcashDefaultCurrencyTicker';
    } on Zip321BuildException {
      return null;
    }
  }

  /// The message a share sheet sends, or null before there is a request.
  ///
  /// Composed here rather than at each call site so the desktop and mobile
  /// flows can never drift into two differently worded shares.
  String? get shareText {
    final uri = requestUri;
    if (uri == null) return null;
    try {
      return buildRequestShareText(
        amountZec: normalizeZip321Amount(amountZec),
        uri: uri,
      );
    } on Zip321BuildException {
      return null;
    }
  }

  /// True once the request can be copied or shared.
  bool get isReady => requestUri != null;
}
