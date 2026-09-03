import 'package:flutter/widgets.dart';

import '../../../core/formatting/address_display.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_icon_hover_button.dart';
import '../../../core/widgets/app_profile_picture.dart';
import '../../../core/widgets/app_tooltip.dart';
import '../../../core/widgets/pool_badge.dart';
import '../../../core/widgets/review_list_row.dart'
    show kPaymentRequestRequesterTooltip;
import '../../../core/widgets/review_wrap_card.dart';

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
/// transaction label and amount, the To and memo rows — sits exactly this
/// far in from that card's edge. One gutter, two left edges.
const double kPaymentRequestGutter = AppSpacing.sm;

/// Horizontal breathing room inside the two-line disclosure controls.
/// They stay visually quiet on hover like the existing review rows, while
/// keeping their labels away from the full-row hit target's edges.
const _paymentRequestDisclosurePadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.xs,
);

/// The scroll region's overlay scrollbar, for tests.
const kPaymentRequestScrollbarKey = ValueKey('payment_request_scrollbar');

/// The scroll region's scroll view, for tests.
const kPaymentRequestScrollViewKey = ValueKey('payment_request_scroll_view');

/// The requester note's nested scroll view, for tests.
const kPaymentRequestRequesterNoteScrollViewKey = ValueKey(
  'payment_request_requester_note_scroll_view',
);

/// The requester note's nested scrollbar, for tests.
const kPaymentRequestRequesterNoteScrollbarKey = ValueKey(
  'payment_request_requester_note_scrollbar',
);

/// Which of the two presentations [PaymentRequestCard] lays itself out for.
///
/// App code leaves this at [auto], which resolves to [kAppFormFactor] — the
/// build-time form factor, never a `Platform` check. The explicit values
/// exist only for tooling that has to show both modes inside one binary
/// (the Widgetbook gallery and the figma-compare scenarios), the same
/// exemption the `*Desktop` / `*Mobile` token sets carry.
enum PaymentRequestLayout { auto, desktop, mobile }

/// Where a payment request reached the wallet from.
///
/// Carried by the view model for the routes and logs that care; the card
/// itself renders no provenance line.
enum PaymentRequestSource { link, qrCode }

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
  /// The only status whose primary action is neither Review nor Edit: the
  /// request is fine, the wallet just could not answer, and re-asking is the
  /// one thing that can change that.
  bool get offersRecheck => this == PaymentRequestStatus.syncStalled;
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

  /// Renders the "Replaced an earlier link" notice above the amount.
  final bool replacedNotice;

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

  String? get displayMemo {
    final raw = memo?.trim();
    return (raw == null || raw.isEmpty) ? null : raw;
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
    this.layout = PaymentRequestLayout.auto,
    this.bottomSafeArea = false,
    this.initialAddressExpanded = false,
    this.initialMessageExpanded = false,
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

  void _toggleAddress() => setState(() => _addressExpanded = !_addressExpanded);
  void _toggleMessage() => setState(() => _messageExpanded = !_messageExpanded);
  void _toggleRequester() =>
      setState(() => _requesterExpanded = !_requesterExpanded);

  PaymentRequestView get _request => widget.request;

  bool get _isMobile => widget.isMobileLayout;

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final status = request.status;
    final isMobile = _isMobile;

    // Gap between the card's top-level groups. Mobile runs against a fixed
    // viewport budget, so it takes the tighter step; both stay at least 2x
    // the 8px gaps used inside a group.
    final sectionGap = isMobile ? AppSpacing.sm : AppSpacing.md;
    final statusMessage = request.resolvedStatusMessage;
    final amount = request.displayAmount;

    // Header, requester, amount, status and actions stay pinned. The
    // transaction details scroll only when expanded or unusually long.
    final rows = _detailRows();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: request.headerTitle,
              isMobileLayout: isMobile,
              onClose: widget.onCancel,
            ),
            if (request.replacedNotice) ...[
              const SizedBox(height: AppSpacing.xs),
              const _QuietNotice(
                key: ValueKey('payment_request_replaced_notice'),
                message: 'Replaced an earlier link',
              ),
            ],
            if (request.hasRequesterDetails) ...[
              SizedBox(height: sectionGap),
              _RequesterDetailsCard(
                requester: request.displayRequesterLabel,
                note: request.displayNote,
                expanded: _requesterExpanded,
                onToggle: request.displayNote == null ? null : _toggleRequester,
              ),
            ],
            SizedBox(height: sectionGap),
            if (constraints.maxHeight.isFinite)
              Flexible(
                child: _TransactionContentFrame(
                  amountText: amount,
                  fiatText: request.fiatText,
                  rows: rows,
                  bounded: true,
                ),
              )
            else
              _TransactionContentFrame(
                amountText: amount,
                fiatText: request.fiatText,
                rows: rows,
                bounded: false,
              ),
            // A request error belongs to the details card, so keep it close
            // to that surface and leave the full section gap before actions.
            if (statusMessage != null) ...[
              SizedBox(height: isMobile ? AppSpacing.xxs : AppSpacing.xs),
              _StatusMessage(
                key: const ValueKey('payment_request_status'),
                status: status,
                message: statusMessage,
              ),
              SizedBox(height: sectionGap),
            ] else
              SizedBox(height: sectionGap),
            _Actions(
              status: status,
              statusMessage: statusMessage,
              hasAmount: amount != null,
              isMobileLayout: isMobile,
              bottomSafeArea: widget.bottomSafeArea,
              onContinue: widget.onContinue,
              onEdit: widget.onEdit,
              onRecheck: widget.onRecheck,
            ),
          ],
        );
      },
    );
  }

  /// Transaction content only. Requester metadata lives in its own disclosure
  /// above this group so off-chain request text is not confused with the memo.
  List<Widget> _detailRows() {
    final request = _request;
    final memo = request.displayMemo;
    final addressRow = _AddressRow(
      key: const ValueKey('payment_request_to_row'),
      address: request.address,
      identity: request.displayRecipientIdentity,
      isMobileLayout: _isMobile,
      expanded: _addressExpanded,
      onToggle: _toggleAddress,
    );

    return [
      addressRow,
      if (memo != null) ...[
        const ReviewWrapDivider(),
        _ProseRows(
          key: const ValueKey('payment_request_memo'),
          label: 'Transaction memo',
          text: memo,
          expanded: _messageExpanded,
          onToggle: _toggleMessage,
        ),
      ],
    ];
  }
}

/// Off-chain metadata supplied by the payment link's requester.
///
/// The name remains visible as the collapsed summary. A requester note is
/// progressive disclosure because it is context for the request, not content
/// that will be included in the Zcash transaction.
class _RequesterDetailsCard extends StatelessWidget {
  const _RequesterDetailsCard({
    required this.requester,
    required this.note,
    required this.expanded,
    required this.onToggle,
  });

  final String? requester;
  final String? note;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final transparent = colors.background.ground.withValues(alpha: 0);
    final summary = requester ?? 'Note from requester';
    final scaler = MediaQuery.textScalerOf(context);
    // Label over value, both at body size: the requester is text the link
    // supplied, not an identity the wallet verified, so it does not take
    // the headline the address-book name gets in the To row.
    final labelStyle = AppTypography.bodyMediumStrong;
    final valueStyle = AppTypography.bodyMediumStrong;
    final summaryHeight =
        (scaler.scale(labelStyle.fontSize!) * labelStyle.height! +
                AppSpacing.xxs +
                scaler.scale(valueStyle.fontSize!) * valueStyle.height!)
            .ceilToDouble() +
        1;
    final summaryRow = Row(
      children: [
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      'Requester',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle.copyWith(color: colors.text.secondary),
                    ),
                  ),
                  // Only a link-supplied name needs the caveat; a note-only
                  // card has no name to be mistaken for a verified sender.
                  if (requester != null) ...[
                    const SizedBox(width: AppSpacing.xxs),
                    AppTooltip(
                      tapToShow: true,
                      message: kPaymentRequestRequesterTooltip,
                      child: AppIcon(
                        AppIcons.help,
                        key: const ValueKey('payment_request_requester_help'),
                        size: AppIconSize.medium,
                        color: colors.icon.regular,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                summary,
                key: const ValueKey('payment_request_requester'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: valueStyle.copyWith(color: colors.text.accent),
              ),
            ],
          ),
        ),
        if (onToggle != null) ...[
          const SizedBox(width: AppSpacing.xs),
          AppIcon(
            expanded ? AppIcons.collapsed : AppIcons.expand,
            color: colors.icon.regular,
          ),
        ],
      ],
    );

    final toggle = onToggle;
    final summaryControl = toggle == null
        ? summaryRow
        : Semantics(
            button: true,
            expanded: expanded,
            excludeSemantics: true,
            label: expanded
                ? 'Hide requester details'
                : 'Show requester details',
            value: requester == null
                ? 'Requester, $summary'
                : 'Label from link, $summary',
            onTap: toggle,
            child: AppButton(
              key: const ValueKey('payment_request_requester_toggle'),
              onPressed: toggle,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              height: summaryHeight,
              enabledBackgroundColor: transparent,
              pressedBackgroundColor: transparent,
              expand: true,
              constrainContent: true,
              contentPadding: _paymentRequestDisclosurePadding,
              child: summaryRow,
            ),
          );

    return ReviewWrapCard(
      key: const ValueKey('payment_request_requester_group'),
      mainAxisSize: MainAxisSize.min,
      // The card's content gutter: the same 16 every group on this card
      // uses, so the label here, the transaction label, and the rows in
      // the details card all share one left edge.
      padding: const EdgeInsets.all(kPaymentRequestGutter),
      children: [
        summaryControl,
        if (expanded && note != null) ...[
          const ReviewWrapDivider(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Note from requester',
                style: labelStyle.copyWith(color: colors.text.secondary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: AppSpacing.xl3),
                child: _FadingScrollRegion(
                  scrollViewKey: kPaymentRequestRequesterNoteScrollViewKey,
                  scrollbarKey: kPaymentRequestRequesterNoteScrollbarKey,
                  contentPadding: const EdgeInsetsDirectional.only(
                    end: kPaymentRequestGutter,
                  ),
                  child: Text(
                    note!,
                    key: const ValueKey('payment_request_requester_note'),
                    style: AppTypography.bodyMediumStrong.copyWith(
                      color: colors.text.accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The amount and the on-chain destination/memo as one visual group.
///
/// Only the inner details region flexes and scrolls. The group label and the
/// amount being approved remain pinned in every state.
class _TransactionContentFrame extends StatelessWidget {
  const _TransactionContentFrame({
    required this.amountText,
    required this.fiatText,
    required this.rows,
    required this.bounded,
  });

  final String? amountText;
  final String? fiatText;
  final List<Widget> rows;
  final bool bounded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final details = bounded
        ? Flexible(child: _DetailsFrame(rows: rows))
        : ReviewWrapCard(
            padding: const EdgeInsets.all(kPaymentRequestGutter),
            children: rows,
          );

    final radius = BorderRadius.circular(AppRadii.large);
    return Container(
      key: const ValueKey('payment_request_transaction_content'),
      width: double.infinity,
      padding: const EdgeInsets.only(top: kPaymentRequestGutter),
      decoration: BoxDecoration(borderRadius: radius),
      // Painted over the content rather than as part of the box so the 1px
      // stroke does not shift the gutter: content sits exactly 16 in from
      // the frame edge, the same as inside every other card here.
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: colors.border.regular),
        borderRadius: radius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kPaymentRequestGutter,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Transaction content',
                  style: AppTypography.bodyMediumStrong.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
                if (amountText != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _AmountHero(amountText: amountText!, fiatText: fiatText),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Flush with the frame: same radius at zero inset keeps the two
          // corners concentric, and the card's own 16 inset lands its rows
          // on the frame label's left edge.
          details,
        ],
      ),
    );
  }
}

/// The "To" block: pool beside the label, then the address beside its
/// verification action. Keeping each related pair together saves a row and
/// makes the privacy status and address action easier to scan.
///
/// The full address never leaves this card. "Show full address" swaps the
/// one-line truncation for the canonical verify grouping — 5-character
/// groups with the same head/tail emphasis the verify-address modal uses —
/// so the user can compare characters without losing the request behind a
/// second modal.
///
/// When the wallet can put a name to the address ([identity]) the block leads
/// with that name and an avatar instead, the way the pay and send reviews
/// render a known recipient, and the address drops to the sub-line. The pool
/// badge and the expand control are unchanged in both shapes: a name is not a
/// reason to stop stating the pool, and the full address still has to be
/// verifiable from inside the card.
class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.address,
    required this.identity,
    required this.isMobileLayout,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final String address;

  /// The name behind [address], or null for an address this wallet does not
  /// recognize — which is also the state while the lookup is still running.
  final PaymentRequestRecipientIdentity? identity;

  final bool isMobileLayout;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isShielded =
        zcashAddressDisplayKind(address) == ZcashAddressDisplayKind.shielded;
    final actionLabel = expanded ? 'Hide full address' : 'Show full address';
    final identity = this.identity;
    final chunks = _AddressChunks(
      key: const ValueKey('payment_request_address_chunks'),
      address: address,
    );

    final recipient = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (identity != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _RecipientIdentityBlock(identity: identity),
        ],
        const SizedBox(height: AppSpacing.xxs),
        if (expanded) ...[
          chunks,
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _addressAction(context, actionLabel),
          ),
        ] else
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xxs,
            runSpacing: 0,
            children: [
              Text(
                truncatedAddress(address),
                key: identity == null
                    ? null
                    : const ValueKey('payment_request_recipient_address'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.codeMedium.copyWith(
                  color: identity == null
                      ? colors.text.accent
                      : colors.text.secondary,
                ),
              ),
              _addressAction(context, actionLabel),
            ],
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xxs,
          children: [
            Text(
              'To',
              maxLines: 1,
              style: AppTypography.bodyMediumStrong.copyWith(
                color: colors.text.secondary,
              ),
            ),
            // Paying a transparent address is the one detail on this card
            // with a privacy consequence the review step cannot undo.
            PoolBadge(
              key: const ValueKey('payment_request_pool_badge'),
              isShielded: isShielded,
            ),
          ],
        ),
        // On touch the whole recipient block toggles the full address —
        // address line plus pill is 45px, above the 44px floor — so the
        // pill keeps its 24px Figma height and no transparent ring has
        // to be padded into the row rhythm. Translucent: the pill's own
        // detector still wins inside its bounds.
        if (isMobileLayout)
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            excludeFromSemantics: true,
            onTap: onToggle,
            child: recipient,
          )
        else
          recipient,
      ],
    );
  }

  Widget _addressAction(BuildContext context, String label) {
    final colors = context.colors;
    final usesLargeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final visibleLabel = usesLargeText ? (expanded ? 'Hide' : 'Show') : label;
    return Semantics(
      button: true,
      label: label,
      onTap: onToggle,
      excludeSemantics: true,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.5,
        child: AppButton(
          key: const ValueKey('payment_request_show_full_address'),
          onPressed: onToggle,
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.small,
          iconGap: 0,
          leading: usesLargeText
              ? null
              : AppIcon(
                  expanded ? AppIcons.eyeClosed : AppIcons.eye,
                  color: colors.button.ghost.label,
                ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            child: Text(
              visibleLabel,
              maxLines: 1,
              style: AppTypography.labelSmall,
            ),
          ),
        ),
      ),
    );
  }
}

/// Avatar + name for a recipient the wallet recognizes.
///
/// The composition is the pay/send review's contact recipient
/// (`AppProfilePicture` leading, name headline, address sub-line) fitted to
/// this card's tighter scale: the name takes the sans headline step rather
/// than the review's serif, because the serif belongs to the amount and the
/// card title above it and a third serif line would flatten that hierarchy.
///
/// An own-account recipient adds one muted line saying so. Paying yourself is
/// a legitimate thing to do from a link, but it is also exactly what a
/// swapped-address attack looks like from the other direction, so the card
/// states the relationship instead of leaving the user to recognize a name.
class _RecipientIdentityBlock extends StatelessWidget {
  const _RecipientIdentityBlock({required this.identity});

  final PaymentRequestRecipientIdentity identity;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Row(
      // Centered against the whole text block, the way `ReviewInfoRow` seats
      // its own leading avatar: top-aligning it against the name alone left
      // the 32px circle visibly high beside a three-line own-account block.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppProfilePicture(
          key: const ValueKey('payment_request_recipient_avatar'),
          profilePictureId: identity.profilePictureId,
          size: AppProfilePictureSize.large,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // Non-null: the card only builds this block for an identity
                // that survived `displayRecipientIdentity`.
                identity.displayName!,
                key: const ValueKey('payment_request_recipient_name'),
                // A contact label is user-authored and unbounded; it is cut,
                // never wrapped, the same way the requester line is.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.headlineSmall.copyWith(
                  color: colors.text.accent,
                ),
              ),
              if (identity.isOwnAccount) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Your account',
                  key: const ValueKey('payment_request_own_account_label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                    color: colors.text.secondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The full address in 5-character groups, five groups to a row.
///
/// Chunking and the head/tail crimson emphasis come from
/// [addressVerifyGrid], the same source the verify-address modal renders,
/// so a user who has compared an address in one place reads the other
/// identically. The glyphs stay monospace here because the collapsed form
/// directly above them is monospace too.
class _AddressChunks extends StatelessWidget {
  const _AddressChunks({required this.address, super.key});

  final String address;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rows = addressVerifyGrid(address);
    final normalStyle = AppTypography.codeMedium.copyWith(
      color: colors.text.accent,
    );
    final highlightedStyle = AppTypography.codeMedium.copyWith(
      color: colors.text.brandCrimson,
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < rows.length; row++) ...[
          if (row > 0) const SizedBox(height: AppSpacing.xxs),
          // scaleDown keeps wide glyph metrics (and the test environment's
          // square Ahem font) from overflowing the card column; with the
          // production Geist Mono metrics the row fits and renders 1:1.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < rows[row].length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  Text(
                    rows[row][i].text,
                    style: rows[row][i].highlighted
                        ? highlightedStyle
                        : normalStyle,
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

/// The transaction memo block, in the send review's own message shape.
///
/// The label sits above the value so it remains readable at mobile widths and
/// large text sizes. The value toggles between a one-line preview and the full
/// memo.
///
/// The expanded flag is owned by [_PaymentRequestCardState]; this widget is
/// stateless on purpose, so no rebuild of the scrolling content can reset it.
class _ProseRows extends StatelessWidget {
  const _ProseRows({
    required this.label,
    required this.text,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  /// Visible label for the encrypted memo that travels with the payment.
  final String label;

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final transparent = colors.background.ground.withValues(alpha: 0);
    final valueStyle = AppTypography.bodyMediumStrong;
    final scaler = MediaQuery.textScalerOf(context);
    // The control is the whole label-over-value block: 54px on mobile,
    // 46 on desktop, so it clears the 44px touch floor by itself instead
    // of padding an oversized box around the value line.
    final controlHeight =
        (scaler.scale(valueStyle.fontSize!) * valueStyle.height! * 2 +
                AppSpacing.xxs)
            .ceilToDouble() +
        1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          excludeSemantics: true,
          label: expanded
              ? 'Collapse transaction memo'
              : 'Expand transaction memo',
          value: expanded ? null : '$label, $text',
          onTap: onToggle,
          child: AppButton(
            key: const ValueKey('payment_request_memo_toggle'),
            onPressed: onToggle,
            variant: AppButtonVariant.ghost,
            size: AppButtonSize.small,
            height: controlHeight,
            enabledBackgroundColor: transparent,
            pressedBackgroundColor: transparent,
            expand: true,
            constrainContent: true,
            contentPadding: _paymentRequestDisclosurePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  label,
                  // Inside a fixed-height control a label must not wrap.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle.copyWith(color: colors.text.secondary),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        expanded ? 'Collapse' : text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: valueStyle.copyWith(color: colors.text.accent),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    AppIcon(
                      expanded ? AppIcons.collapsed : AppIcons.expand,
                      color: colors.icon.regular,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(text, style: valueStyle.copyWith(color: colors.text.accent)),
        ],
      ],
    );
  }
}

/// The card's one status line.
///
/// The request errors ([PaymentRequestStatusX.isError]) take the destructive
/// tone and the warning glyph the text fields already use. The one other line
/// that reaches this slot is `syncing`, which is a pending state the card
/// resolves on its own, so it renders as quiet secondary text with no glyph —
/// the same treatment the replaced-link notice gets. "Checking" says itself
/// inside the primary button and never comes through here.
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
      ? 'Review'
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
        leading: leading,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
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

/// The details card as a fixed frame: a [ReviewWrapCard] that takes the
/// height it is given, with the received content scrolling inside its own
/// rounded clip.
///
/// The card's inner inset moves into the scroll viewport so the content
/// runs edge to edge under the clip while the scrollbar rides in the
/// gutter that inset leaves, and the fade cues sit on the card's own top
/// and bottom edges instead of cutting the content off mid-surface under
/// the pinned header.
class _DetailsFrame extends StatelessWidget {
  const _DetailsFrame({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return ReviewWrapCard(
      // The frame hugs short content and fills for long content; the
      // viewport inside decides which, so the card must not force a height.
      mainAxisSize: MainAxisSize.min,
      padding: EdgeInsets.zero,
      children: [
        // Flexible, so the viewport inherits the frame's bounded height: a
        // `Column` hands a plain child unbounded main-axis space, which
        // would let the content size the scroll view instead of the frame.
        Flexible(
          fit: FlexFit.loose,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.large),
            child: _FadingScrollRegion(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    // The row gap the wrap card applies to its children.
                    if (i > 0) const SizedBox(height: AppSpacing.sm),
                    rows[i],
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Scrolls the received content inside the details frame, dissolves
/// whichever edge still has content beyond it, and owns the overlay
/// scrollbar for that scroll.
///
/// The fade is a mask on the content itself, not a gradient painted in the
/// wrap-card color: masking dissolves the glyphs against whatever the card
/// surface is in the current theme, with no second color to keep in sync.
///
/// The [ShaderMask] is present on every build, including while both fades
/// are fully transparent. An earlier revision returned the bare child at
/// zero opacity and inserted the mask only once the content overflowed;
/// that changed the subtree's position in the widget tree, which
/// deactivates and re-inflates every element under it. The scroll offset
/// and every expansion state below were discarded on the first scroll as a
/// result — the reason an expanded memo collapsed the moment the user
/// scrolled.
class _FadingScrollRegion extends StatefulWidget {
  const _FadingScrollRegion({
    required this.child,
    this.scrollViewKey = kPaymentRequestScrollViewKey,
    this.scrollbarKey = kPaymentRequestScrollbarKey,
    this.contentPadding = defaultContentPadding,
  });

  final Widget child;
  final Key scrollViewKey;
  final Key scrollbarKey;
  final EdgeInsetsGeometry contentPadding;

  static const _fadeHeight = AppSpacing.md;

  /// The card's inset, moved inside the viewport so the content scrolls
  /// the full height of the card. The card gutter on every side, not the
  /// review screen's 24/16 pair: this card sits inside a frame that uses
  /// 16, and two vertical rhythms one level apart read as a mistake.
  static const defaultContentPadding = EdgeInsets.all(kPaymentRequestGutter);

  /// Overlay scrollbar geometry: the pane scrollbar's 6px capsule, centered
  /// in the card's 16px inner gutter so it never rides over text.
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
