import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../core/formatting/address_display.dart';
import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/mobile/mobile_bottom_safe_area.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_icon.dart';
import '../../../core/widgets/app_icon_hover_button.dart';
import '../../../core/widgets/pool_badge.dart';
import '../../../core/widgets/review_list_row.dart';
import '../../../core/widgets/review_wrap_card.dart';

/// Desktop width of the payment-request modal card.
///
/// Wider than the 312px design-system default because the card carries a
/// full address row plus memo/note prose; 396 is the width the other wide
/// desktop modals in this app already use (settings uninstall/endpoint,
/// the home confirmation cards).
const double kPaymentRequestCardWidth = 396;

/// Vertical padding added around the card's 24px-high compact ghost button
/// ("Show full address") in the mobile layout.
///
/// The pill keeps its Figma height; the transparent ring around it brings the
/// tap target to 44px, which is what a thumb needs. Desktop keeps the bare
/// 24px control — it is above the WCAG 2.5.8 floor and pointer-driven.
const double kPaymentRequestTouchRingInset = 10;

/// Horizontal room the mobile header leaves for the sheet's pinned close.
///
/// The card renders no close of its own on mobile — `MobileModalScaffold`
/// pins its shared 32x32 ⨯ to the top-right of the sheet. This mirrors the
/// scaffold's own title reservation (32 + an 8px gap) so a long title
/// ellipsizes instead of sliding under that button.
const double kPaymentRequestMobileCloseClearance = 40;

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
}

extension PaymentRequestStatusX on PaymentRequestStatus {
  /// True while the primary action must stay disabled.
  bool get blocksContinue => this != PaymentRequestStatus.ready;

  /// Something is wrong rather than merely pending, so the status line takes
  /// the destructive tone and the warning glyph.
  bool get isError =>
      this == PaymentRequestStatus.invalidAddress ||
      this == PaymentRequestStatus.insufficientFunds ||
      this == PaymentRequestStatus.syncing;
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
/// error actionable without leaving the card.
String? defaultPaymentRequestStatusMessage(
  PaymentRequestStatus status, {
  String? spendableText,
}) {
  final spendable = _bareAmount(spendableText);
  return switch (status) {
    // Checking is stated by the primary button (a spinner and its own
    // label), so the status slot stays reserved for the three errors.
    PaymentRequestStatus.ready => null,
    PaymentRequestStatus.checking => null,
    PaymentRequestStatus.invalidAddress =>
      "Recipient address doesn't look right",
    PaymentRequestStatus.insufficientFunds =>
      spendable == null
          ? 'Not enough ZEC'
          : 'Not enough ZEC ($spendable available)',
    PaymentRequestStatus.syncing => 'Wallet is still syncing — try again soon',
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
  /// parameter said, which is why it is stated as a muted "Requested by …"
  /// line rather than dressed up as a title of its own.
  final String? requesterLabel;

  /// Preformatted fiat equivalent, e.g. `$35.00`. Null hides the line.
  final String? fiatText;

  /// Encrypted memo that travels with the payment. Labelled "Message" —
  /// the name the send composer and the send review both give it.
  final String? memo;

  /// Message that stays local to this device.
  final String? note;

  /// Preformatted spendable balance used by the insufficient-funds message.
  final String? spendableText;

  final PaymentRequestStatus status;

  /// Overrides [defaultPaymentRequestStatusMessage] for [status].
  final String? statusMessage;

  /// Renders the "Replaced an earlier link" notice above the amount.
  final bool replacedNotice;

  /// Same request, different verdict. The pre-check fills the amount and the
  /// requester in once, up front; only the status (and the two fields the
  /// status line reads) change as the checks land.
  ///
  /// [clearMemo] drops the Message row: a transparent-like recipient cannot
  /// receive one, so the memo the link carried is not part of the payment the
  /// user is being asked to approve.
  PaymentRequestView copyWithStatus(
    PaymentRequestStatus status, {
    String? statusMessage,
    String? spendableText,
    bool clearMemo = false,
  }) => PaymentRequestView(
    source: source,
    address: address,
    amountZecText: amountZecText,
    requesterLabel: requesterLabel,
    fiatText: fiatText,
    memo: clearMemo ? null : memo,
    note: note,
    spendableText: spendableText ?? this.spendableText,
    status: status,
    statusMessage: statusMessage,
    replacedNotice: replacedNotice,
  );

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

  /// Pool of [address], for the Shielded / Transparent badge.
  ZcashAddressDisplayKind get addressKind => zcashAddressDisplayKind(address);

  /// The card's serif title. Constant: the requester is never promoted into
  /// it, because a link-supplied name is not this card's identity.
  String get headerTitle => 'Payment request';

  /// The one muted line under the title, or null when the request carried
  /// no label at all — an invented identity would be worse than none.
  String? get requesterLine {
    final requester = displayRequesterLabel;
    return requester == null ? null : 'Requested by $requester';
  }
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
/// The details block is built from the send review's own row components
/// ([ReviewWrapCard], [ReviewListRow], [ReviewWrapDivider]), so the card
/// reads as a preview of the screen its primary action lands on.
class PaymentRequestCard extends StatefulWidget {
  const PaymentRequestCard({
    required this.request,
    required this.onContinue,
    required this.onEdit,
    required this.onCancel,
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
  bool _noteExpanded = false;

  void _toggleAddress() => setState(() => _addressExpanded = !_addressExpanded);
  void _toggleMessage() => setState(() => _messageExpanded = !_messageExpanded);
  void _toggleNote() => setState(() => _noteExpanded = !_noteExpanded);

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

    // Header, amount, status and actions stay pinned. The details card is a
    // fixed frame whose *content* scrolls inside it, so neither a 512-byte
    // memo nor the scroll offset can push the amount being consented to off
    // the card, and long content ends on the card's own rounded edge rather
    // than at a straight cut under the header.
    final rows = _detailRows();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: request.headerTitle,
              requesterLine: request.requesterLine,
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
            // An amount-less request has no hero at all: the title and the
            // requester line flow straight into the details card.
            if (amount != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _AmountHero(amountText: amount, fiatText: request.fiatText),
            ],
            SizedBox(height: sectionGap),
            // A scroll viewport needs a bounded height. When the host gives
            // the card unbounded space there is nothing to overflow, so the
            // details lay out at their natural height in a plain card.
            if (constraints.maxHeight.isFinite)
              Flexible(child: _DetailsFrame(rows: rows))
            else
              ReviewWrapCard(children: rows),
            // One status slot for every condition, directly under the
            // details card and directly above the buttons it explains.
            if (statusMessage != null) ...[
              SizedBox(height: sectionGap),
              _StatusMessage(
                key: const ValueKey('payment_request_status'),
                status: status,
                message: statusMessage,
              ),
              // The status line explains the buttons underneath, so it sits
              // close to them and far from the content above — the gap below
              // stays well under half the gap above in both lanes.
              SizedBox(height: isMobile ? AppSpacing.xxs : AppSpacing.xs),
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
            ),
          ],
        );
      },
    );
  }

  /// The three received values, laid out with the send review's own rows:
  /// "To" label-above-value (the review's `Review Info` shape), "Message"
  /// and "Note" label-beside-value in a [ReviewListRow], separated by the
  /// review's hairline divider.
  List<Widget> _detailRows() {
    final request = _request;
    final memo = request.displayMemo;
    final note = request.displayNote;

    return [
      _AddressRow(
        key: const ValueKey('payment_request_to_row'),
        address: request.address,
        isMobileLayout: _isMobile,
        expanded: _addressExpanded,
        onToggle: _toggleAddress,
      ),
      if (memo != null) ...[
        const ReviewWrapDivider(),
        _ProseRows(
          key: const ValueKey('payment_request_memo'),
          label: 'Message',
          text: memo,
          expanded: _messageExpanded,
          onToggle: _toggleMessage,
        ),
      ],
      if (note != null) ...[
        const ReviewWrapDivider(),
        _ProseRows(
          key: const ValueKey('payment_request_note'),
          label: 'Note',
          text: note,
          expanded: _noteExpanded,
          onToggle: _toggleNote,
        ),
      ],
    ];
  }
}

/// The "To" block: the label above the address, with the pool badge and the
/// expand control on the line below — the composition the send review's
/// "To" row uses (`ReviewInfoRow`), minus the 32px leading circle, which in
/// Vizor lives *outside* the wrap card.
///
/// The full address never leaves this card. "Show full address" swaps the
/// one-line truncation for the canonical verify grouping — 5-character
/// groups with the same head/tail emphasis the verify-address modal uses —
/// so the user can compare characters without losing the request behind a
/// second modal.
class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.address,
    required this.isMobileLayout,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final String address;
  final bool isMobileLayout;
  final bool expanded;
  final VoidCallback onToggle;

  /// Small ghost button chrome around its label: outer padding 4 per side,
  /// the button's own glyph, and the label's own 4 per side.
  ///
  /// The glyph is the *button's* icon token, not [AppIconSize.medium]: a
  /// small `AppButton` resolves 16px on desktop and 20px on mobile, so
  /// hardcoding 16 under-reserved the chrome by 4px in the mobile lane and
  /// overflowed the row.
  static const _ghostChrome =
      AppSpacing.xxs * 2 +
      AppButtonSizing.mediumSmallIconSize +
      AppSpacing.xxs * 2;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isShielded =
        zcashAddressDisplayKind(address) == ZcashAddressDisplayKind.shielded;
    final actionLabel = expanded ? 'Hide full address' : 'Show full address';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'To',
          maxLines: 1,
          // The review's row label: the same size and weight as the value
          // it labels, one colour step down — never a tiny muted caption.
          style: AppTypography.bodyMediumStrong.copyWith(
            color: colors.text.secondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        if (expanded)
          _AddressChunks(
            key: const ValueKey('payment_request_address_chunks'),
            address: address,
          )
        else
          Text(
            truncatedAddress(address),
            // Monospace so the head and tail characters a user compares
            // are fixed-width; the amount above keeps the serif style.
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.codeMedium.copyWith(color: colors.text.accent),
          ),
        const SizedBox(height: AppSpacing.xxs),
        LayoutBuilder(
          builder: (context, constraints) => Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              // Paying a transparent address is the one detail on this card
              // with a privacy consequence the review step cannot undo.
              PoolBadge(
                key: const ValueKey('payment_request_pool_badge'),
                isShielded: isShielded,
              ),
              _TouchTargetRing(
                apply: isMobileLayout,
                onTap: onToggle,
                child: Semantics(
                  button: true,
                  label: actionLabel,
                  onTap: onToggle,
                  excludeSemantics: true,
                  child: AppButton(
                    key: const ValueKey('payment_request_show_full_address'),
                    onPressed: onToggle,
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.small,
                    iconGap: 0,
                    leading: AppIcon(
                      expanded ? AppIcons.eyeClosed : AppIcons.eye,
                      color: colors.button.ghost.label,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: math.max(
                            0,
                            constraints.maxWidth - _AddressRow._ghostChrome,
                          ),
                        ),
                        child: Text(
                          actionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.labelLarge,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
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

/// Adds a transparent ring around a compact control so the tap target
/// reaches 44px on touch without changing the pill.
///
/// The inner control keeps its own opaque gesture detector; this one only
/// catches the ring, and both call the same callback.
class _TouchTargetRing extends StatelessWidget {
  const _TouchTargetRing({
    required this.apply,
    required this.onTap,
    required this.child,
  });

  final bool apply;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!apply) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: kPaymentRequestTouchRingInset,
        ),
        child: child,
      ),
    );
  }
}

/// The card's name in the serif headline scale the send screens use for
/// their titles, the desktop close affordance beside it, and — only when
/// the request carried a label — the muted "Requested by …" line under it.
///
/// The title takes the step below the amount hero: the amount is the value
/// being consented to and has to stay the largest thing on the card, so a
/// same-size title would flatten the hierarchy instead of establishing it.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.requesterLine,
    required this.isMobileLayout,
    required this.onClose,
  });

  final String title;
  final String? requesterLine;
  final bool isMobileLayout;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
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
        ),
        if (requesterLine != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            requesterLine!,
            key: const ValueKey('payment_request_requester'),
            // One line: an 80-character label is cut, never wrapped.
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

/// The Message / Note block, in the send review's own Message shape.
///
/// Collapsed it is a single [ReviewListRow]: the label on the leading edge,
/// the text truncated to one line inside the trailing pill, and the expand
/// glyph. Expanded, the pill swaps to a "Collapse" affordance and the full
/// text renders underneath the row — exactly what `ReviewMemoRows` does on
/// the review screen, so the two surfaces read as one component.
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

  /// Visible label — "Message" (the memo, which travels with the payment)
  /// or "Note" (local to this device).
  final String label;

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return ReviewListRow(
        label: label,
        value: text,
        trailingIconName: AppIcons.expand,
        onPressed: onToggle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReviewListRow(
          label: label,
          value: 'Collapse',
          trailingIconName: AppIcons.collapsed,
          onPressed: onToggle,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
          child: Text(
            text,
            style: AppTypography.bodyMediumStrong.copyWith(
              color: context.colors.text.accent,
            ),
          ),
        ),
      ],
    );
  }
}

/// The card's one status line, which now only ever carries one of the three
/// request errors: they take the destructive tone and the warning glyph the
/// text fields already use. "Checking" says itself inside the primary
/// button, so nothing neutral competes for this slot.
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

    final (Color color, String? iconName, bool animatedIcon) = switch (status) {
      PaymentRequestStatus.invalidAddress ||
      PaymentRequestStatus.insufficientFunds ||
      PaymentRequestStatus.syncing => (
        colors.text.destructive,
        AppIcons.warning,
        false,
      ),
      PaymentRequestStatus.ready ||
      PaymentRequestStatus.checking => (colors.text.secondary, null, false),
    };

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
                  animated: animatedIcon,
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

/// The card's action area: one full-width primary over one full-width
/// secondary, the pair `ReviewButtonsStack` already uses on the send review
/// screens.
///
/// "Review" names where the primary lands — the send review step — rather
/// than the generic "Continue" it replaced; nothing is signed from here.
/// While checks are running that button carries a spinner and says
/// "Checking…" instead, so the wait is stated where the action is.
///
/// An amount-less request has nothing to review yet, so its primary reads
/// "Enter amount" and opens the composer — the same destination `Edit`
/// leads to, which is why the secondary is absent in that state.
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

  bool get _blocked => status.blocksContinue;

  bool get _checking => status == PaymentRequestStatus.checking;

  String get _primaryLabel => _checking
      ? 'Checking…'
      : hasAmount
      ? 'Review'
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
    // Without an amount the primary *is* the edit action.
    onPressed: _blocked ? null : (hasAmount ? onContinue : onEdit),
    variant: AppButtonVariant.primary,
    leading: _primaryLeading(),
  );

  Widget _editFill() => _fillButton(
    key: const ValueKey('payment_request_edit'),
    label: 'Edit',
    onPressed: onEdit,
    variant: AppButtonVariant.secondary,
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
  const _FadingScrollRegion({required this.child});

  final Widget child;

  static const _fadeHeight = AppSpacing.md;

  /// The wrap card's own inset, moved inside the viewport so the content
  /// scrolls the full height of the card.
  static const contentPadding = kReviewWrapCardPadding;

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
          key: kPaymentRequestScrollViewKey,
          controller: _controller,
          padding: _FadingScrollRegion.contentPadding,
          child: widget.child,
        ),
      ),
    );

    // The scrollbar stays outside the mask: the thumb is a control, not
    // content, and a cue that dissolves the control it belongs to reads as
    // a rendering fault.
    return RawScrollbar(
      key: kPaymentRequestScrollbarKey,
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
