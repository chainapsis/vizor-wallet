import 'package:flutter/widgets.dart';

import '../../../core/formatting/address_display.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_icon_hover_button.dart';
import '../../../core/widgets/full_address_viewer.dart';
import '../../../core/widgets/pool_badge.dart';
import '../../../core/widgets/review_wrap_card.dart';
import '../models/send_prefill_args.dart' show PaymentRequestSource;
import 'send_review_layout.dart' show kWhitespaceOnlyMemoPlaceholder;
export '../models/send_prefill_args.dart' show PaymentRequestSource;

/// Desktop width of the payment-request modal card.
///
/// Wider than the 312px design-system default because the card carries a
/// full address row plus memo/note prose; 396 is the width the other wide
/// desktop modals in this app already use (settings uninstall/endpoint,
/// the home confirmation cards).
const double kPaymentRequestCardWidth = 396;

/// Horizontal room the mobile header leaves for the sheet's pinned close.
///
/// The card renders no close of its own on mobile — `MobileModalScaffold`
/// pins its shared 32x32 ⨯ to the top-right of the sheet. This mirrors the
/// scaffold's own title reservation (32 + an 8px gap) so a long title
/// ellipsizes instead of sliding under that button.
const double kPaymentRequestMobileCloseClearance = 40;

/// The one horizontal content inset every group on this card uses.
///
/// Sheet/modal chrome (title, actions, status line) sits on the outer
/// edge; everything inside a card — the requester summary, the
/// amount, recipient and memo rows — sits exactly this
/// far in from that card's edge. One gutter, two left edges.
const double kPaymentRequestGutter = AppSpacing.sm;

/// The scroll region's overlay scrollbar, for tests.
const kPaymentRequestScrollbarKey = ValueKey('payment_request_scrollbar');

/// The scroll region's scroll view, for tests.
const kPaymentRequestScrollViewKey = ValueKey('payment_request_scroll_view');

/// Which of the two presentations [PaymentRequestCard] lays itself out for.
///
/// App code leaves this at [auto], which resolves to [kAppFormFactor] — the
/// build-time form factor, never a `Platform` check. The explicit values
/// exist only for tooling that has to show both modes inside one binary
/// (the Widgetbook gallery and the figma-compare scenarios), the same
/// exemption the `*Desktop` / `*Mobile` token sets carry.
enum PaymentRequestLayout { auto, desktop, mobile }

/// The one condition that decides whether the request can be acted on.
///
/// Exactly one applies at a time. [ready] is the only value that lets the
/// primary action fire; everything else disables it and renders the card's
/// single status line.
///
/// Preconditions that are not about *this request* — no wallet yet, an
/// unfinished Ironwood migration, another signing session holding the
/// wallet — are settled by the route and the drain policy before the card
/// is ever built, so they are deliberately absent here.
enum PaymentRequestStatus {
  /// Checks passed — the request can be continued.
  ready,

  /// Address/balance checks are still running.
  checking,

  /// The request carries an address this wallet cannot pay.
  invalidAddress,

  /// The requested amount is above the spendable balance.
  insufficientFunds,

  /// Balances are not trustworthy yet because the wallet is syncing.
  syncing,

  /// [syncing] that has run out of ways to answer itself.
  ///
  /// The card re-checks a `syncing` verdict when the wallet finishes a sync,
  /// and — because a verdict published while the sync state is *already*
  /// settled has no completion left to wait for — a bounded number of times
  /// immediately. When that budget is spent and no real sync cycle follows,
  /// the wait [syncing]'s copy promises is one the card can no longer keep.
  /// This is that state said out loud: same blocked request, but the next
  /// move is the user's, and the primary action becomes "Check again".
  syncStalled,

  /// The check itself could not complete; the reason always comes through
  /// [PaymentRequestView.statusMessage].
  failed,
}

extension PaymentRequestStatusX on PaymentRequestStatus {
  /// True while the primary action must stay disabled.
  bool get blocksContinue => this != PaymentRequestStatus.ready;

  /// Something is wrong rather than merely pending, so the status line takes
  /// the destructive tone and the warning glyph.
  ///
  /// [PaymentRequestStatus.syncing] is deliberately not one of these. It
  /// blocks Review through [blocksContinue] like the rest, but it is the one
  /// blocked state that resolves itself: the card watches the sync and
  /// re-runs its own check, and its copy says so. A warning glyph on a line
  /// that promises to update itself asks the user to act on a condition they
  /// have nothing to do about.
  bool get isError =>
      this == PaymentRequestStatus.invalidAddress ||
      this == PaymentRequestStatus.insufficientFunds ||
      this == PaymentRequestStatus.failed;

  /// The request cannot be reviewed, but the card can ask the wallet again.
  ///
  /// Re-check stalled sync or a failed lookup without reopening the link.
  bool get offersRecheck =>
      this == PaymentRequestStatus.syncStalled ||
      this == PaymentRequestStatus.failed;
}

/// Default copy for each [PaymentRequestStatus].
///
/// One line each, no trailing period: the buttons under them already say
/// what the user can do, so the message only has to name the condition.
/// Callers may override any of these through
/// [PaymentRequestView.statusMessage].
///
/// [spendableText] is the preformatted spendable balance (`0.21 ZEC`). When
/// the caller supplies it, the insufficient-funds message states the amount
/// the user can actually send, which is the single fact that makes that
/// error actionable without leaving the card. It names the fee alongside it,
/// because the shortfall can be the fee alone: a request for exactly the
/// spendable balance passes the card's own comparison and is refused by the
/// proposal, and "Not enough ZEC (0.5 available)" beside a 0.5 request reads
/// as a bug in the balance rather than an instruction.
String? defaultPaymentRequestStatusMessage(
  PaymentRequestStatus status, {
  String? spendableText,
}) {
  final spendable = _bareAmount(spendableText);
  return switch (status) {
    // Checking is stated by the primary button (a spinner and its own
    // label), so the status slot stays reserved for the errors.
    PaymentRequestStatus.ready => null,
    PaymentRequestStatus.checking => null,
    PaymentRequestStatus.invalidAddress =>
      "Recipient address doesn't look right",
    PaymentRequestStatus.insufficientFunds =>
      spendable == null
          ? 'Not enough ZEC for this amount and the network fee'
          : 'Not enough ZEC for this amount and the network fee '
                '($spendable available)',
    // The card watches the sync and re-runs its check when it settles, so the
    // message promises exactly that rather than sending the user back to the
    // link they already opened.
    PaymentRequestStatus.syncing =>
      'Wallet is still syncing — this will update when it finishes',
    // The card has stopped promising to update itself, so the copy stops
    // saying it will: it names the same condition and hands the next move
    // to the button under it.
    PaymentRequestStatus.syncStalled =>
      'Still syncing — check again when the wallet is up to date',
    // Always overridden in practice: every failure the pre-check publishes
    // carries its own reason. This is the floor, not the message.
    PaymentRequestStatus.failed => "Couldn't check this request",
  };
}

/// Drops the unit off a preformatted balance, because the sentence around it
/// already names the currency: `0.21 ZEC` → `0.21`.
String? _bareAmount(String? text) {
  final trimmed = text?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  const unit = ' ZEC';
  if (trimmed.toUpperCase().endsWith(unit)) {
    final bare = trimmed.substring(0, trimmed.length - unit.length).trim();
    return bare.isEmpty ? null : bare;
  }
  return trimmed;
}

/// Whose name the "To" block is showing.
///
/// The two are rendered the same way — avatar, name, truncated address — but
/// they mean different things to the person reading the card, so the own-account
/// case says so in its own sub-label. Nothing else on the card can tell a user
/// that the address a stranger's link asked them to pay is one of their own.
enum PaymentRequestRecipientKind {
  /// The recipient address is saved in the address book.
  contact,

  /// The recipient address belongs to one of this wallet's own accounts.
  ownAccount,
}

/// A recipient address the wallet could put a name to.
///
/// Resolved outside the card (see `paymentRequestRecipientIdentityFor`), so
/// the widget stays a pure presentation surface that Widgetbook can drive
/// with literals.
@immutable
class PaymentRequestRecipientIdentity {
  const PaymentRequestRecipientIdentity({
    required this.kind,
    required this.name,
    required this.profilePictureId,
  });

  const PaymentRequestRecipientIdentity.contact({
    required String name,
    required String profilePictureId,
  }) : this(
         kind: PaymentRequestRecipientKind.contact,
         name: name,
         profilePictureId: profilePictureId,
       );

  const PaymentRequestRecipientIdentity.ownAccount({
    required String name,
    required String profilePictureId,
  }) : this(
         kind: PaymentRequestRecipientKind.ownAccount,
         name: name,
         profilePictureId: profilePictureId,
       );

  final PaymentRequestRecipientKind kind;

  /// Contact label or account name. Rendered as the "To" headline, clamped to
  /// one line — a contact label is user-authored and can be any length.
  final String name;

  /// Avatar id resolved through [AppProfilePicture].
  final String profilePictureId;

  bool get isOwnAccount => kind == PaymentRequestRecipientKind.ownAccount;

  /// One-line, whitespace-collapsed name, or null when there is nothing to
  /// show — a nameless identity is worse than the raw address, so the card
  /// falls back to the unmapped layout in that case.
  String? get displayName {
    final collapsed = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.isEmpty ? null : collapsed;
  }

  @override
  bool operator ==(Object other) =>
      other is PaymentRequestRecipientIdentity &&
      other.kind == kind &&
      other.name == name &&
      other.profilePictureId == profilePictureId;

  @override
  int get hashCode => Object.hash(kind, name, profilePictureId);
}

/// A part of a payment that the link asked for differently from the QR
/// scanned to check it.
enum PaymentRequestLinkDifference { address, amount, memo }

/// Everything [PaymentRequestCard] renders.
///
/// Immutable and free of providers, routing and parsing. The caller
/// sanitizes untrusted fields (a link can carry anything) before building
/// this; the widget still clamps every string so a hostile label or memo
/// cannot stretch, wrap or scroll the card.
@immutable
class PaymentRequestView {
  const PaymentRequestView({
    required this.source,
    required this.address,
    this.amountZecText,
    this.requesterLabel,
    this.fiatText,
    this.memo,
    this.note,
    this.spendableText,
    this.recipientIdentity,
    this.status = PaymentRequestStatus.ready,
    this.statusMessage,
    this.replacedNotice = false,
    this.linkDifferences,
  });

  /// Link or QR code. Kept for callers and logging; nothing renders it.
  final PaymentRequestSource source;

  /// Preformatted amount including the unit, e.g. `0.5 ZEC`.
  ///
  /// Null when the request carried no `amount`. The card then renders no
  /// amount block at all — no hero, no placeholder line — rather than
  /// inventing a number in its most prominent slot, and the primary action
  /// becomes "Enter amount", which hands the request to the composer.
  final String? amountZecText;

  /// Full recipient address. Displayed middle-truncated through
  /// [truncatedAddress]; the full value expands in place inside the To row.
  final String address;

  /// Who is asking, when the request carried a label. Null renders no name
  /// at all — an empty or invented identity would be worse than none.
  ///
  /// This string is attacker-controlled: it is whatever the link's `label`
  /// parameter said. The card keeps it inside the collapsed requester group
  /// instead of presenting it as verified contact information.
  final String? requesterLabel;

  /// Preformatted fiat equivalent, e.g. `$35.00`. Null hides the line.
  final String? fiatText;

  /// Encrypted memo that travels with the payment. The request card calls it
  /// "Transaction memo" to distinguish it from the requester's link message.
  final String? memo;

  /// Off-chain message embedded by the requester in the link or QR code.
  /// It is shown as "Note from requester" and is not copied into the payment.
  final String? note;

  /// Preformatted spendable balance used by the insufficient-funds message.
  final String? spendableText;

  /// The name this wallet can put to [address] — a saved contact or one of
  /// the user's own accounts — or null when the address maps to neither.
  ///
  /// Resolved by the host from the address book and the account list, which
  /// both load asynchronously, so null is also the honest "not looked up
  /// yet" value: the card renders the plain address until the lookup lands
  /// rather than blocking on it.
  final PaymentRequestRecipientIdentity? recipientIdentity;

  final PaymentRequestStatus status;

  /// Overrides [defaultPaymentRequestStatusMessage] for [status].
  final String? statusMessage;

  /// Indicates that this request replaced one already being reviewed.
  final bool replacedNotice;

  /// How this scanned QR compared with the link it was scanned to check
  /// ("Scan original QR"): empty when they ask for the same payment, the
  /// fields that differ otherwise. Null when the card was not opened that way.
  final Set<PaymentRequestLinkDifference>? linkDifferences;

  /// Same request, different verdict. The pre-check fills the amount and the
  /// requester in once, up front; only the status (and the two fields the
  /// status line reads) change as the checks land.
  PaymentRequestView copyWithStatus(
    PaymentRequestStatus status, {
    String? statusMessage,
    String? spendableText,
  }) => PaymentRequestView(
    source: source,
    address: address,
    amountZecText: amountZecText,
    requesterLabel: requesterLabel,
    fiatText: fiatText,
    memo: memo,
    note: note,
    spendableText: spendableText ?? this.spendableText,
    recipientIdentity: recipientIdentity,
    status: status,
    statusMessage: statusMessage,
    replacedNotice: replacedNotice,
    linkDifferences: linkDifferences,
  );

  /// Same request, with the "replaced an earlier link" notice shown.
  ///
  /// The notice normally comes from `present`, which knows it displaced a
  /// card. It is applied after the fact for the one case `present` cannot
  /// see: a newer link arriving while the previous card was mid-hand-back and
  /// therefore already gone. Without this the user's Review tap disappears
  /// with nothing on the new card to say why.
  PaymentRequestView withReplacedNotice() {
    if (replacedNotice) return this;
    return PaymentRequestView(
      source: source,
      address: address,
      amountZecText: amountZecText,
      requesterLabel: requesterLabel,
      fiatText: fiatText,
      memo: memo,
      note: note,
      spendableText: spendableText,
      recipientIdentity: recipientIdentity,
      status: status,
      statusMessage: statusMessage,
      replacedNotice: true,
      linkDifferences: linkDifferences,
    );
  }

  /// Same request, with the fiat sub-line attached (or removed).
  ///
  /// The host re-applies this on every build for the same reason as
  /// [withRecipientIdentity]: the ZEC price provider is autoDispose and
  /// resolves asynchronously, so a card presented over a screen that holds no
  /// subscription to it would otherwise keep the null it read at present time
  /// for the life of the card.
  PaymentRequestView withFiatText(String? fiatText) {
    if (fiatText == this.fiatText) return this;
    return PaymentRequestView(
      source: source,
      address: address,
      amountZecText: amountZecText,
      requesterLabel: requesterLabel,
      fiatText: fiatText,
      memo: memo,
      note: note,
      spendableText: spendableText,
      recipientIdentity: recipientIdentity,
      status: status,
      statusMessage: statusMessage,
      replacedNotice: replacedNotice,
      linkDifferences: linkDifferences,
    );
  }

  /// Same request, with the recipient's resolved name attached (or removed).
  ///
  /// The host re-applies this on every build, because the address book and
  /// the account addresses resolve after the card is already on screen.
  PaymentRequestView withRecipientIdentity(
    PaymentRequestRecipientIdentity? identity,
  ) {
    if (identity == recipientIdentity) return this;
    return PaymentRequestView(
      source: source,
      address: address,
      amountZecText: amountZecText,
      requesterLabel: requesterLabel,
      fiatText: fiatText,
      memo: memo,
      note: note,
      spendableText: spendableText,
      recipientIdentity: identity,
      status: status,
      statusMessage: statusMessage,
      replacedNotice: replacedNotice,
      linkDifferences: linkDifferences,
    );
  }

  String? get resolvedStatusMessage =>
      statusMessage ??
      defaultPaymentRequestStatusMessage(status, spendableText: spendableText);

  /// Amount text with surrounding whitespace removed, or null when the
  /// request carried no amount.
  String? get displayAmount {
    final raw = amountZecText?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  /// One-line, whitespace-collapsed requester label, or null when there is
  /// nothing to show.
  String? get displayRequesterLabel {
    final raw = requesterLabel?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  /// The memo exactly as the payment will carry it, or null when the request
  /// carries none.
  ///
  /// Deliberately not trimmed or collapsed, unlike [displayRequesterLabel]
  /// and [displayNote]. Those two are off-chain text the link says *about*
  /// itself, so tidying them costs nothing. This is the on-chain memo: the
  /// pre-check hands these exact bytes to the proposal, so trimming here
  /// would show the payer a memo their transaction does not pay, and would
  /// erase a whitespace-only memo from the card while still sending it.
  String? get displayMemo {
    final raw = memo;
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  /// True when [displayMemo] is present but every character in it is
  /// whitespace.
  ///
  /// Those bytes are still paid, so the memo is present, not absent — but
  /// rendering them verbatim draws nothing. The card surface uses this to put
  /// a visible placeholder in the memo's value slot rather than leave a row
  /// that reads as empty.
  bool get memoIsWhitespaceOnly {
    final raw = displayMemo;
    return raw != null && raw.trim().isEmpty;
  }

  String? get displayNote {
    final raw = note?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  /// The recipient identity the card should actually render, or null when
  /// the address maps to nothing this wallet can name — which includes an
  /// identity whose name turned out to be blank.
  PaymentRequestRecipientIdentity? get displayRecipientIdentity {
    final identity = recipientIdentity;
    return identity?.displayName == null ? null : identity;
  }

  /// Pool of [address], for the Shielded / Transparent badge.
  ZcashAddressDisplayKind get addressKind => zcashAddressDisplayKind(address);

  /// The card's serif title. Constant: the requester is never promoted into
  /// it, because a link-supplied name is not this card's identity.
  String get headerTitle => 'Payment request';

  bool get hasRequesterDetails =>
      displayRequesterLabel != null || displayNote != null;
}

/// A payment request someone else sent you, rendered as received content
/// with a single consent action.
///
/// This is deliberately *not* a form: the amount, address, memo and note
/// are read-only, and the only way to change any of them is "Edit", which
/// hands the request to the normal send composer. The card supplies no
/// surface of its own — [PaymentRequestSurface] (or any modal frame)
/// provides the card/sheet chrome, so the same widget renders in the
/// desktop modal and the mobile sheet.
///
/// The details block uses the send review's card and divider components, so
/// the request reads as a preview of the screen its primary action lands on.
class PaymentRequestCard extends StatefulWidget {
  const PaymentRequestCard({
    required this.request,
    required this.onContinue,
    required this.onEdit,
    required this.onCancel,
    this.onRecheck,
    this.onScan,
    this.layout = PaymentRequestLayout.auto,
    this.bottomSafeArea = false,
    this.initialAddressExpanded = false,
    this.initialMessageExpanded = false,
    this.initialLinkDetails = false,
    super.key,
  });

  final PaymentRequestView request;

  /// Accept the request as it stands and move to the review step. Ignored
  /// while [PaymentRequestStatusX.blocksContinue] is true.
  final VoidCallback onContinue;

  /// Open the request in the send composer for editing.
  final VoidCallback onEdit;

  /// Discard the request. Also backs the desktop close affordance.
  final VoidCallback onCancel;

  /// Ask the wallet again, for [PaymentRequestStatus.syncStalled].
  ///
  /// Null leaves that status's primary action disabled, which is the honest
  /// answer for a preview or a host that cannot re-run the check.
  final VoidCallback? onRecheck;

  /// Scan the requester's original QR inside Vizor.
  final VoidCallback? onScan;

  /// Applies [MobileBottomSafeArea] under the mobile action stack.
  ///
  /// Defaults to false because every presentation that ships today
  /// ([PaymentRequestSurface] and `showPaymentRequestSheet`) puts the card
  /// inside a `MobileModalScaffold` hosted by `MobileModalCard`, and the
  /// card already owns that edge — taking the inset here too would add the
  /// Android navigation bar twice. Pass true only when the card is the
  /// bottom-most content of its own route.
  final bool bottomSafeArea;

  /// Tooling-only layout override; see [PaymentRequestLayout].
  final PaymentRequestLayout layout;

  /// Opens the To row's full-address view on first build.
  ///
  /// Tooling-only, the same exemption [layout] carries: a static capture
  /// cannot tap the toggle, so the expanded state needs a way to be
  /// rendered directly. App code leaves this false.
  final bool initialAddressExpanded;

  /// Opens the Message row's full text on first build. Tooling-only, for
  /// the same reason as [initialAddressExpanded].
  final bool initialMessageExpanded;

  /// Tooling-only: starts at the parsed link details after the introduction.
  final bool initialLinkDetails;

  /// Resolves [layout] against the build-time form factor.
  bool get isMobileLayout => switch (layout) {
    PaymentRequestLayout.auto => kAppFormFactor == AppFormFactor.mobile,
    PaymentRequestLayout.desktop => false,
    PaymentRequestLayout.mobile => true,
  };

  @override
  State<PaymentRequestCard> createState() => _PaymentRequestCardState();
}

/// Expansion state lives here, above the scrolling region, rather than
/// inside the rows.
///
/// The rows sit inside a scroll region whose fade wrapper used to be added
/// and removed as the scroll offset changed. That moved the subtree to a
/// different position in the widget tree, which deactivates and re-inflates
/// every element under it, so an expanded memo collapsed the moment the
/// user scrolled. Hoisting the flags above the region makes expansion
/// immune to any rebuild of the content, and the region itself no longer
/// swaps its own subtree in and out (see [_FadingScrollRegion]).
class _PaymentRequestCardState extends State<PaymentRequestCard> {
  late bool _addressExpanded = widget.initialAddressExpanded;
  late bool _messageExpanded = widget.initialMessageExpanded;
  bool _requesterExpanded = false;
  late bool _linkDetails = widget.initialLinkDetails;

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final gap = widget.isMobileLayout ? AppSpacing.sm : AppSpacing.md;
    final external = request.source != PaymentRequestSource.qrCode;
    final introduction = external && !_linkDetails;
    if (introduction) {
      return _ExternalRequestIntroduction(
        // A pasted link rarely comes with its QR, so it is reviewed instead.
        canScanOriginal: request.source == PaymentRequestSource.link,
        onScan: widget.onScan,
        onReview: () => setState(() => _linkDetails = true),
        onClose: widget.onCancel,
        isMobileLayout: widget.isMobileLayout,
        replacedNotice: request.replacedNotice,
      );
    }
    final showDetails =
        external || request.status != PaymentRequestStatus.checking;
    final details = LayoutBuilder(
      builder: (context, constraints) {
        final content = _FadingScrollRegion(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (request.linkDifferences case final differences?) ...[
                if (differences.isEmpty)
                  const _LinkMatchNotice()
                else
                  _LinkMismatchNotice(differences: differences),
                SizedBox(height: gap),
              ],
              if (request.replacedNotice) ...[
                const _QuietNotice(
                  key: ValueKey('payment_request_replaced_notice'),
                  message: 'Replaced an earlier link',
                ),
                SizedBox(height: gap),
              ],
              if (showDetails && request.hasRequesterDetails) ...[
                _RequesterDetails(
                  request: request,
                  expanded: _requesterExpanded,
                  onToggle: () =>
                      setState(() => _requesterExpanded = !_requesterExpanded),
                ),
                SizedBox(height: gap),
              ],
              if (!showDetails) ...[
                SizedBox(height: gap),
                _RequestSummary(request: request),
              ] else
                ReviewWrapCard(
                  key: const ValueKey('payment_request_transaction_content'),
                  mainAxisSize: MainAxisSize.min,
                  padding: const EdgeInsets.all(kPaymentRequestGutter),
                  children: [
                    if (request.displayAmount != null)
                      _AmountHero(
                        amountText: request.displayAmount!,
                        fiatText: request.fiatText,
                      ),
                    _RecipientDetails(
                      request: request,
                      expanded: _addressExpanded,
                      onToggle: () =>
                          setState(() => _addressExpanded = !_addressExpanded),
                    ),
                    if (request.displayMemo != null) ...[
                      _PaymentDetailsDisclosure(
                        expanded: _messageExpanded,
                        onToggle: () => setState(
                          () => _messageExpanded = !_messageExpanded,
                        ),
                      ),
                      if (_messageExpanded)
                        Column(
                          key: const ValueKey('payment_request_memo'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Transaction memo',
                              style: AppTypography.bodySmall.copyWith(
                                color: context.colors.text.secondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              request.memoIsWhitespaceOnly
                                  ? kWhitespaceOnlyMemoPlaceholder
                                  : request.displayMemo!,
                              style: AppTypography.bodyMedium.copyWith(
                                color: request.memoIsWhitespaceOnly
                                    ? context.colors.text.muted
                                    : context.colors.text.primary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              if (request.resolvedStatusMessage != null) ...[
                SizedBox(height: gap),
                _StatusMessage(
                  key: const ValueKey('payment_request_status'),
                  status: request.status,
                  message: request.resolvedStatusMessage!,
                ),
              ],
            ],
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kPaymentRequestGutter,
              ),
              child: _Header(
                title: request.headerTitle,
                isMobileLayout: widget.isMobileLayout,
                onClose: widget.onCancel,
              ),
            ),
            SizedBox(height: gap),
            if (constraints.maxHeight.isFinite)
              Flexible(child: content)
            else
              content,
            SizedBox(height: gap),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kPaymentRequestGutter,
              ),
              child: _Actions(
                status: request.status,
                statusMessage: request.resolvedStatusMessage,
                hasAmount: request.displayAmount != null,
                isMobileLayout: widget.isMobileLayout,
                bottomSafeArea: widget.bottomSafeArea,
                onContinue: widget.onContinue,
                onEdit: widget.onEdit,
                onRecheck: widget.onRecheck,
              ),
            ),
          ],
        );
      },
    );
    // Padding belongs to the selected presentation, so the illustrated
    // introduction can fill the same modal frame as the parsed details.
    if (widget.isMobileLayout) {
      return MobileModalScaffold(
        title: '',
        showTitle: false,
        onClose: widget.onCancel,
        bottomPadding: AppSpacing.base,
        horizontalPadding: 0,
        child: Flexible(child: details),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: details,
    );
  }
}

/// Compact input feedback while a scanned request is being checked.
class _RequestSummary extends StatelessWidget {
  const _RequestSummary({required this.request});
  final PaymentRequestView request;

  @override
  Widget build(BuildContext context) => ReviewWrapCard(
    key: const ValueKey('payment_request_summary'),
    mainAxisSize: MainAxisSize.min,
    padding: const EdgeInsets.all(kPaymentRequestGutter),
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            request.displayAmount ?? 'Amount not specified',
            style: AppTypography.bodyMediumStrong.copyWith(
              color: context.colors.text.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            truncatedAddress(request.address),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.text.secondary,
            ),
          ),
        ],
      ),
    ],
  );
}

class _RequesterDetails extends StatelessWidget {
  const _RequesterDetails({
    required this.request,
    required this.expanded,
    required this.onToggle,
  });
  final PaymentRequestView request;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = request.displayRequesterLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPaymentRequestGutter),
      child: Column(
        key: const ValueKey('payment_request_requester_group'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            excludeSemantics: true,
            onTap: onToggle,
            label:
                '${expanded ? 'Hide' : 'Show'} requester information${name == null ? '' : ' for $name'}',
            value: name == null
                ? 'Note from requester'
                : 'Name supplied in the request.',
            child: AppButton(
              key: const ValueKey('payment_request_requester_toggle'),
              onPressed: onToggle,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              height: 48,
              growWithContent: true,
              expand: true,
              constrainContent: true,
              contentPadding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(AppRadii.small),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name == null ? 'Note from requester' : 'Request from',
                          style: AppTypography.bodySmall.copyWith(
                            color: c.text.secondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          name ?? 'View note',
                          key: const ValueKey('payment_request_requester'),
                          maxLines: expanded ? null : 2,
                          overflow: expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: AppTypography.bodyMediumStrong.copyWith(
                            color: c.text.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  ExcludeSemantics(
                    child: AppIcon(
                      expanded ? AppIcons.collapsed : AppIcons.expand,
                      color: c.icon.regular,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: AppSpacing.s),
            if (name != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: AppIcon(
                      AppIcons.warningCircle,
                      size: AppIconSize.medium,
                      color: c.icon.warning,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      "This name comes from the request. It doesn't confirm who owns the receiving address.",
                      style: AppTypography.bodySmall.copyWith(
                        color: c.text.primary,
                      ),
                    ),
                  ),
                ],
              ),
            if (request.displayNote != null) ...[
              if (name != null) const SizedBox(height: AppSpacing.sm),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.background.neutralSubtleOpacity,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Note from requester',
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w500,
                          color: c.text.secondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        request.displayNote!,
                        key: const ValueKey('payment_request_requester_note'),
                        style: AppTypography.bodyMedium.copyWith(
                          color: c.text.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _RecipientDetails extends StatelessWidget {
  const _RecipientDetails({
    required this.request,
    required this.expanded,
    required this.onToggle,
  });
  final PaymentRequestView request;
  final bool expanded;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final identity = request.displayRecipientIdentity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          onTap: onToggle,
          excludeSemantics: true,
          label: expanded
              ? 'Hide full recipient address'
              : 'Show full recipient address',
          value:
              '${identity?.displayName ?? ''} ${identity?.isOwnAccount == true ? 'Your account. ' : ''}${request.address}. ${request.addressKind == ZcashAddressDisplayKind.shielded ? 'Shielded' : 'Transparent'}',
          child: AppButton(
            key: const ValueKey('payment_request_show_full_address'),
            onPressed: onToggle,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            height: 48,
            growWithContent: true,
            expand: true,
            constrainContent: true,
            contentPadding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(AppRadii.small),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Recipient',
                            style: AppTypography.bodySmall.copyWith(
                              color: c.text.secondary,
                            ),
                          ),
                          if (identity?.isOwnAccount == true)
                            Text(
                              'Your account',
                              style: AppTypography.bodySmall.copyWith(
                                color: c.text.secondary,
                              ),
                            ),
                          PoolBadge(
                            key: const ValueKey('payment_request_pool_badge'),
                            isShielded:
                                request.addressKind ==
                                ZcashAddressDisplayKind.shielded,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        identity?.displayName ??
                            truncatedAddress(request.address),
                        key: identity == null
                            ? null
                            : const ValueKey('payment_request_recipient_name'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (identity == null
                                    ? AppTypography.codeMedium
                                    : AppTypography.bodyMediumStrong)
                                .copyWith(color: c.text.accent),
                      ),
                      if (identity != null)
                        Text(
                          truncatedAddress(request.address),
                          key: const ValueKey(
                            'payment_request_recipient_address',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.codeSmall.copyWith(
                            color: c.text.secondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppIcon(
                  expanded ? AppIcons.collapsed : AppIcons.chevronForward,
                  color: c.icon.regular,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: AppSpacing.xs),
          if (identity != null)
            Text(
              identity.displayName!,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: c.text.accent,
              ),
            ),
          if (identity?.isOwnAccount == true)
            Text(
              'Your account',
              style: AppTypography.bodySmall.copyWith(color: c.text.secondary),
            ),
          _AddressChunks(
            key: const ValueKey('payment_request_address_chunks'),
            address: request.address,
          ),
        ],
      ],
    );
  }
}

class _PaymentDetailsDisclosure extends StatelessWidget {
  const _PaymentDetailsDisclosure({
    required this.expanded,
    required this.onToggle,
  });
  final bool expanded;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = expanded ? 'Hide payment details' : 'Payment details';
    return Semantics(
      button: true,
      expanded: expanded,
      onTap: onToggle,
      excludeSemantics: true,
      label: label,
      value: 'Memo included. View the transaction memo.',
      child: AppButton(
        key: const ValueKey('payment_request_memo_toggle'),
        onPressed: onToggle,
        variant: AppButtonVariant.ghost,
        size: AppButtonSize.small,
        height: 48,
        growWithContent: true,
        expand: true,
        constrainContent: true,
        contentPadding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(AppRadii.small),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: c.text.primary,
                    ),
                  ),
                  Text(
                    'Memo included',
                    style: AppTypography.bodySmall.copyWith(
                      color: c.text.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            AppIcon(
              expanded ? AppIcons.collapsed : AppIcons.expand,
              color: c.icon.regular,
            ),
          ],
        ),
      ),
    );
  }
}

/// An illustrated caution screen before any unverified payment values appear.
/// The background illustration supports the warning without replacing the
/// app's neutral modal surface or controls.
class _ExternalRequestIntroduction extends StatelessWidget {
  const _ExternalRequestIntroduction({
    required this.canScanOriginal,
    required this.onScan,
    required this.onReview,
    required this.onClose,
    required this.isMobileLayout,
    required this.replacedNotice,
  });

  final bool canScanOriginal;
  final VoidCallback? onScan;
  final VoidCallback onReview;
  final VoidCallback onClose;
  final bool isMobileLayout;
  final bool replacedNotice;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = colors.background.base;
    return ColoredBox(
      color: background,
      child: Stack(
        children: [
          PositionedDirectional(
            top: -24,
            end: -20,
            width: 340,
            height: 340,
            child: ExcludeSemantics(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: 0.52,
                    child: Image.asset(
                      'assets/illustrations/payment_request_letter_caution.webp',
                      fit: BoxFit.contain,
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [background, background.withValues(alpha: 0)],
                        stops: const [0, 0.75],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [background.withValues(alpha: 0), background],
                        stops: const [0.22, 0.70],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: _FadingScrollRegion(
                  contentPadding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payment request',
                        key: const ValueKey('payment_request_title'),
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w500,
                          color: colors.text.secondary,
                        ),
                      ),
                      if (replacedNotice) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          'Replaced an earlier link',
                          key: const ValueKey(
                            'payment_request_replaced_notice',
                          ),
                          style: AppTypography.bodySmall.copyWith(
                            color: colors.text.secondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.base),
                      Semantics(
                        key: const ValueKey('external_request_warning'),
                        container: true,
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  height:
                                      MediaQuery.textScalerOf(context).scale(
                                        AppTypography.headlineLarge.fontSize!,
                                      ) *
                                      AppTypography.headlineLarge.height!,
                                  child: Center(
                                    child: AppIcon(
                                      AppIcons.warningCircle,
                                      size: 20,
                                      color: colors.text.warning,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Expanded(
                                  child: Semantics(
                                    header: true,
                                    child: Text(
                                      'Check before you pay',
                                      style: AppTypography.headlineLarge
                                          .copyWith(color: colors.text.accent),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.base),
                            Text(
                              'Other apps can change the address or amount in a request link.',
                              style: AppTypography.bodyMedium.copyWith(
                                color: colors.text.primary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              canScanOriginal
                                  ? 'Scan the original QR code directly in Vizor.'
                                  : 'Confirm the details with the person who sent it.',
                              style: AppTypography.bodyMedium.copyWith(
                                color: colors.text.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.base,
                  AppSpacing.md,
                  isMobileLayout ? AppSpacing.base : AppSpacing.md,
                ),
                child: _ExternalScanActions(
                  canScanOriginal: canScanOriginal,
                  onScan: onScan,
                  onReview: onReview,
                ),
              ),
            ],
          ),
          PositionedDirectional(
            top: AppSpacing.sm,
            end: AppSpacing.sm,
            child: AppIconHoverButton(
              key: const ValueKey('payment_request_close'),
              icon: AppIcons.cross,
              semanticLabel: 'Close payment request',
              onTap: onClose,
              idleColor: colors.button.secondary.bg,
              hoverColor: colors.button.secondary.bgHover,
              iconColor: colors.icon.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExternalScanActions extends StatelessWidget {
  const _ExternalScanActions({
    required this.canScanOriginal,
    required this.onScan,
    required this.onReview,
  });
  final bool canScanOriginal;
  final VoidCallback? onScan;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (canScanOriginal) ...[
        AppButton(
          key: const ValueKey('payment_request_scan'),
          onPressed: onScan,
          variant: AppButtonVariant.primary,
          expand: true,
          growWithContent: true,
          constrainContent: true,
          leading: const AppIcon(AppIcons.qr),
          child: const Text('Scan original QR'),
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
      AppButton(
        key: const ValueKey('payment_request_link_details'),
        onPressed: onReview,
        variant: canScanOriginal
            ? AppButtonVariant.ghost
            : AppButtonVariant.primary,
        expand: true,
        growWithContent: true,
        constrainContent: true,
        child: const Text('Review link details'),
      ),
    ],
  );
}

class _AddressChunks extends StatelessWidget {
  const _AddressChunks({required this.address, super.key});

  final String address;

  @override
  Widget build(BuildContext context) {
    return FullAddressText(address: address, color: context.colors.text.accent);
  }
}

/// The card's name in the serif headline scale the send screens use for
/// their titles, with the desktop close affordance beside it.
///
/// The title takes the step below the amount hero: the amount is the value
/// being consented to and has to stay the largest thing on the card, so a
/// same-size title would flatten the hierarchy instead of establishing it.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.isMobileLayout,
    required this.onClose,
  });

  final String title;
  final bool isMobileLayout;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      // Mobile has no close of its own; it reserves the room the sheet's
      // pinned ⨯ occupies instead.
      padding: EdgeInsetsDirectional.only(
        end: isMobileLayout ? kPaymentRequestMobileCloseClearance : 0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                key: const ValueKey('payment_request_title'),
                style: AppTypography.headlineMedium.copyWith(
                  color: colors.text.accent,
                ),
              ),
            ),
          ),
          if (!isMobileLayout) ...[
            const SizedBox(width: AppSpacing.xs),
            AppIconHoverButton(
              key: const ValueKey('payment_request_close'),
              icon: AppIcons.cross,
              semanticLabel: 'Close payment request',
              onTap: onClose,
              size: 32,
              iconColor: colors.icon.regular,
            ),
          ],
        ],
      ),
    );
  }
}

/// The requested amount, with its fiat equivalent underneath.
///
/// Both values are read-only on this card, so neither takes tabular figures
/// — the serif display style is the same one the home balance and every
/// `ReviewInfoRow` amount already use.
class _AmountHero extends StatelessWidget {
  const _AmountHero({required this.amountText, required this.fiatText});

  final String amountText;
  final String? fiatText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fiat = fiatText?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          // Long amounts scale down rather than ellipsize — a truncated
          // number is worse than a smaller one.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              amountText,
              key: const ValueKey('payment_request_amount'),
              maxLines: 1,
              // One serif step above the review screens' amount: this card
              // is a consent surface and the number is what is consented to.
              style: AppTypography.displayLarge.copyWith(
                color: colors.text.accent,
              ),
            ),
          ),
        ),
        if (fiat != null && fiat.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            fiat,
            key: const ValueKey('payment_request_fiat'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.text.secondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Pre-check feedback; payment contents remain available for inspection.
class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.status,
    required this.message,
    super.key,
  });

  final PaymentRequestStatus status;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null || message.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;

    // One rule for the tone, so the enum's own answer and what the card
    // paints cannot drift apart.
    final isError = status.isError;
    final color = isError ? colors.text.destructive : colors.text.secondary;
    final iconName = isError ? AppIcons.warning : null;

    final textStyle = AppTypography.bodySmall.copyWith(color: color);
    // The glyph centers on the first line of its own message, so it has to
    // grow with the text scale rather than sit at the unscaled line height.
    final lineHeight = MediaQuery.textScalerOf(
      context,
    ).scale(textStyle.fontSize! * textStyle.height!);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (iconName != null) ...[
            SizedBox(
              height: lineHeight,
              child: Center(
                child: AppIcon(
                  iconName,
                  size: AppIconSize.medium,
                  color: color,
                  animated: false,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(child: Text(message, style: textStyle)),
        ],
      ),
    );
  }
}

/// Quiet one-liner above the content (the replaced-link notice).
/// The scanned QR asks for the same payment as the link it was checking.
class _LinkMatchNotice extends StatelessWidget {
  const _LinkMatchNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      key: const ValueKey('payment_request_link_match'),
      children: [
        AppIcon(AppIcons.checkCircle, size: 16, color: colors.icon.success),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          'Matches the link',
          style: AppTypography.bodySmall.copyWith(color: colors.text.secondary),
        ),
      ],
    );
  }
}

/// The link asked for something the scanned QR does not. The card already
/// shows the QR, the trusted copy, so this names the link as the odd one out
/// rather than casting doubt on what the user just scanned.
class _LinkMismatchNotice extends StatelessWidget {
  const _LinkMismatchNotice({required this.differences});

  final Set<PaymentRequestLinkDifference> differences;

  String get _title => differences.length > 1
      ? 'The link had different details'
      : switch (differences.single) {
          PaymentRequestLinkDifference.address =>
            'The link had a different address',
          PaymentRequestLinkDifference.amount =>
            'The link had a different amount',
          PaymentRequestLinkDifference.memo => 'The link had a different memo',
        };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      key: const ValueKey('payment_request_link_mismatch'),
      decoration: BoxDecoration(
        color: colors.background.utilityDestructiveAlphaSubtle,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: AppIcon(
                AppIcons.warning,
                size: AppIconSize.medium,
                color: colors.icon.destructive,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _title,
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.text.destructive,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Using the QR instead — the link may have been changed.',
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.text.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietNotice extends StatelessWidget {
  const _QuietNotice({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: AppTypography.bodySmall.copyWith(
        color: context.colors.text.secondary,
      ),
    );
  }
}

/// The card's action area: one full-width primary over one full-width ghost
/// action, the pair `ReviewButtonsStack` already uses on the send review
/// screens.
///
/// "Review" names where the primary lands — the send review step — rather
/// than the generic "Continue" it replaced; nothing is signed from here.
/// While checks are running that button carries a spinner and says
/// "Checking…" instead, so the wait is stated where the action is.
///
/// An amount-less request has nothing to review yet, so its primary reads
/// "Enter amount" and opens the composer — the same destination `Edit`
/// leads to, which is why the secondary is absent in that state. That also
/// makes it the only control the card has left when such a request is
/// blocked, so it stays enabled and says "Edit" instead.
///
/// Neither form factor carries a Cancel button: desktop refuses through the
/// header's close ⨯, mobile through the sheet's pinned ⨯
/// (`MobileModalScaffold`).
class _Actions extends StatelessWidget {
  const _Actions({
    required this.status,
    required this.statusMessage,
    required this.hasAmount,
    required this.isMobileLayout,
    required this.bottomSafeArea,
    required this.onContinue,
    required this.onEdit,
    required this.onRecheck,
  });

  final PaymentRequestStatus status;
  final String? statusMessage;

  /// False when the request carried no amount: the primary becomes the edit
  /// action and the secondary is dropped.
  final bool hasAmount;

  final bool isMobileLayout;
  final bool bottomSafeArea;
  final VoidCallback onContinue;
  final VoidCallback onEdit;
  final VoidCallback? onRecheck;

  bool get _blocked => status.blocksContinue;

  bool get _checking => status == PaymentRequestStatus.checking;

  /// The request is blocked on the wallet, not on itself, and asking again is
  /// the move. Only meaningful with an amount: an amount-less request never
  /// reaches the pre-check answers that can stall.
  bool get _recheckable => status.offersRecheck && hasAmount;

  String get _primaryLabel => _checking
      ? 'Checking…'
      : _recheckable
      ? 'Check again'
      : hasAmount
      ? 'Review payment'
      // A blocked amount-less request is not waiting for an amount — the
      // address or the check is the problem — so naming the button after
      // the amount would point at the wrong fix.
      : _blocked
      ? 'Edit'
      : 'Enter amount';

  @override
  Widget build(BuildContext context) {
    final stack = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _primaryFill(),
        if (hasAmount) ...[const SizedBox(height: AppSpacing.xs), _editFill()],
      ],
    );

    if (!isMobileLayout || !bottomSafeArea) return stack;
    return MobileBottomSafeArea(
      bottomPadding: kIosHomeIndicatorClearance,
      child: stack,
    );
  }

  /// Wraps a button so a disabled primary still announces itself and says
  /// why it cannot be used, instead of disappearing from the accessibility
  /// tree with no explanation.
  Widget _semantics({
    required Widget child,
    required bool enabled,
    required String label,
  }) {
    if (enabled) {
      return Semantics(button: true, enabled: true, child: child);
    }
    final reason = statusMessage;
    return Semantics(
      button: true,
      enabled: false,
      label: reason == null
          ? '$label, unavailable'
          : '$label, unavailable. '
                '$reason',
      excludeSemantics: true,
      child: child,
    );
  }

  /// `AppButton` has no loading variant, so the spinner rides in the
  /// button's own leading slot beside the label it belongs to.
  /// `AppLoadingIcon` freezes itself under `MediaQuery.disableAnimations`.
  Widget? _primaryLeading() {
    if (!_checking) return null;
    return const AppIcon(AppIcons.loader, animated: true);
  }

  /// A 44px pill that fills whatever width it is given — the size the send
  /// review CTA uses (`ReviewButtonsStack`) and the mobile send steps'
  /// full-width primary.
  Widget _fillButton({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
    required AppButtonVariant variant,
    Widget? leading,
  }) {
    return _semantics(
      enabled: onPressed != null,
      label: label,
      child: AppButton(
        key: key,
        onPressed: onPressed,
        variant: variant,
        expand: true,
        constrainContent: true,
        growWithContent: true,
        leading: leading,
        child: Text(label),
      ),
    );
  }

  Widget _primaryFill() => _fillButton(
    key: const ValueKey('payment_request_continue'),
    label: _primaryLabel,
    // Without an amount the primary *is* the edit action, and there is no
    // second Edit under it. Blocking it too would leave the card with no
    // enabled control at all — a stated error and no way to act on it. Edit
    // is never blocked; it only waits while the checks run.
    onPressed: _recheckable
        ? onRecheck
        : hasAmount
        ? (_blocked ? null : onContinue)
        : (_checking ? null : onEdit),
    variant: AppButtonVariant.primary,
    leading: _primaryLeading(),
  );

  Widget _editFill() => _fillButton(
    key: const ValueKey('payment_request_edit'),
    label: 'Edit',
    onPressed: onEdit,
    variant: AppButtonVariant.ghost,
  );
}

/// Scrolls the request details between the pinned header and actions.
/// Content keeps the modal's horizontal inset; the scrollbar occupies the
/// outer gutter so it never crosses a nested card or its text.
class _FadingScrollRegion extends StatefulWidget {
  const _FadingScrollRegion({
    required this.child,
    this.contentPadding = const EdgeInsets.symmetric(
      horizontal: kPaymentRequestGutter,
    ),
  });

  final Widget child;
  final Key scrollViewKey = kPaymentRequestScrollViewKey;
  final Key scrollbarKey = kPaymentRequestScrollbarKey;
  final EdgeInsetsGeometry contentPadding;

  static const _fadeHeight = AppSpacing.md;

  /// Overlay scrollbar geometry: the pane scrollbar's 6px capsule, centered
  /// in the modal's 16px outer gutter.
  static const scrollbarThickness = 6.0;
  static const scrollbarMargin = (AppSpacing.sm - scrollbarThickness) / 2;

  @override
  State<_FadingScrollRegion> createState() => _FadingScrollRegionState();
}

class _FadingScrollRegionState extends State<_FadingScrollRegion> {
  final _controller = ScrollController();
  bool _hasMoreAbove = false;
  bool _hasMoreBelow = false;
  bool _canScroll = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Seeds and re-seeds the cues from the live scroll position.
  ///
  /// A `ScrollNotification` only fires once something scrolls, so at rest —
  /// which is how the card is first seen — the notification listener alone
  /// leaves the fade off and the content hard-cut. This runs after every
  /// frame instead, which also covers the content growing when a memo is
  /// expanded.
  void _syncFromPosition() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    if (!position.hasContentDimensions) return;
    _update(
      hasMoreAbove: position.extentBefore > 0.5,
      hasMoreBelow: position.extentAfter > 0.5,
      canScroll: position.maxScrollExtent > 0.5,
    );
  }

  void _update({
    required bool hasMoreAbove,
    required bool hasMoreBelow,
    required bool canScroll,
  }) {
    if (hasMoreAbove == _hasMoreAbove &&
        hasMoreBelow == _hasMoreBelow &&
        canScroll == _canScroll) {
      return;
    }
    setState(() {
      _hasMoreAbove = hasMoreAbove;
      _hasMoreBelow = hasMoreBelow;
      _canScroll = canScroll;
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    _update(
      hasMoreAbove: notification.metrics.extentBefore > 0.5,
      hasMoreBelow: notification.metrics.extentAfter > 0.5,
      canScroll: notification.metrics.maxScrollExtent > 0.5,
    );
    return false; // Observe only — let the notification bubble on.
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFromPosition());
    final animate = !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    final duration = animate
        ? const Duration(milliseconds: 120)
        : Duration.zero;

    final scroller = NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      // Without this the ambient behavior adds a second, platform-default
      // scrollbar of its own, pinned to the very edge of the region.
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          key: widget.scrollViewKey,
          controller: _controller,
          padding: widget.contentPadding,
          child: widget.child,
        ),
      ),
    );

    // The scrollbar stays outside the mask: the thumb is a control, not
    // content, and a cue that dissolves the control it belongs to reads as
    // a rendering fault.
    return RawScrollbar(
      key: widget.scrollbarKey,
      controller: _controller,
      thumbVisibility: _canScroll,
      thickness: _FadingScrollRegion.scrollbarThickness,
      radius: const Radius.circular(AppRadii.full),
      crossAxisMargin: _FadingScrollRegion.scrollbarMargin,
      mainAxisMargin: AppSpacing.xs,
      thumbColor: context.colors.surface.scrollbarThumb,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: _hasMoreAbove ? 1 : 0),
        duration: duration,
        curve: Curves.easeOut,
        child: scroller,
        builder: (context, top, child) => TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: _hasMoreBelow ? 1 : 0),
          duration: duration,
          curve: Curves.easeOut,
          child: child,
          builder: (context, bottom, child) => ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) =>
                _fadeShader(bounds, top: top, bottom: bottom),
            child: child,
          ),
        ),
      ),
    );
  }

  Shader _fadeShader(
    Rect bounds, {
    required double top,
    required double bottom,
  }) {
    const opaque = Color(0xFFFFFFFF);
    final fade = bounds.height <= 0
        ? 0.5
        : (_FadingScrollRegion._fadeHeight / bounds.height).clamp(0.0, 0.5);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        opaque.withValues(alpha: 1 - top),
        opaque,
        opaque,
        opaque.withValues(alpha: 1 - bottom),
      ],
      stops: [0, fade, 1 - fade, 1],
    ).createShader(bounds);
  }
}
