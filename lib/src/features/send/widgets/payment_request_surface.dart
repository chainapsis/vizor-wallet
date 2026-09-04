import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';

import '../../../core/layout/app_form_factor.dart';
import '../../../core/layout/content_overlay_inset.dart';
import '../../../core/layout/mobile/app_mobile_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_modal_card.dart';
import '../../../core/widgets/app_pane_modal_overlay.dart';
import 'payment_request_card.dart';

/// Modal chrome for [PaymentRequestCard].
///
/// A payment request always arrives over whatever the user was already
/// doing, so it presents as a modal in both form factors: a centered card
/// above the pane scrim on desktop, a bottom-anchored sheet card on mobile.
/// This widget renders that presentation inline (no route push), which is
/// what the Widgetbook and figma-compare previews use; the live mobile
/// route can use [showPaymentRequestSheet] instead.
class PaymentRequestSurface extends StatelessWidget {
  const PaymentRequestSurface({
    required this.request,
    required this.onContinue,
    required this.onEdit,
    required this.onCancel,
    this.onRecheck,
    this.layout = PaymentRequestLayout.auto,
    this.initialAddressExpanded = false,
    this.initialMessageExpanded = false,
    this.cardKey,
    this.background,
    super.key,
  }) : _paintsBackground = true;

  /// Just the scrim and the card, over whatever is already on screen.
  ///
  /// The live host renders the app underneath itself and layers this on top,
  /// so that the routed content keeps one position in the widget tree whether
  /// or not a request is up. Handing that content in as [background] instead
  /// would re-parent it every time a card appears or is dismissed, which
  /// disposes and remounts the whole routed subtree.
  const PaymentRequestSurface.overlay({
    required this.request,
    required this.onContinue,
    required this.onEdit,
    required this.onCancel,
    this.onRecheck,
    this.layout = PaymentRequestLayout.auto,
    this.initialAddressExpanded = false,
    this.initialMessageExpanded = false,
    this.cardKey,
    super.key,
  }) : background = null,
       _paintsBackground = false;

  final PaymentRequestView request;
  final VoidCallback onContinue;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  /// Ask the wallet again; see [PaymentRequestCard.onRecheck].
  final VoidCallback? onRecheck;

  /// Tooling-only layout override; see [PaymentRequestLayout].
  final PaymentRequestLayout layout;

  /// Tooling-only: renders the To row already expanded to the full address.
  final bool initialAddressExpanded;

  /// Tooling-only: renders the Message row already expanded to its full text.
  final bool initialMessageExpanded;

  /// Identity of the request whose disclosure state the card owns.
  final Key? cardKey;

  /// What the modal sits on top of. Defaults to the flat window color so a
  /// preview does not have to supply a whole screen. Always null on
  /// [PaymentRequestSurface.overlay], which paints no background at all.
  final Widget? background;

  /// False on [PaymentRequestSurface.overlay]: the caller already owns what is
  /// underneath, so painting the fallback window color would cover it.
  final bool _paintsBackground;

  bool get _isMobile => switch (layout) {
    PaymentRequestLayout.auto => kAppFormFactor == AppFormFactor.mobile,
    PaymentRequestLayout.desktop => false,
    PaymentRequestLayout.mobile => true,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Hosted above the router there is no Material ancestor, so without this
    // the card's text falls back to the framework default style (and the
    // debug yellow underline). Transparent, so nothing else changes.
    final card = Material(
      type: MaterialType.transparency,
      child: PaymentRequestCard(
        key: cardKey,
        request: request,
        onContinue: onContinue,
        onEdit: onEdit,
        onCancel: onCancel,
        onRecheck: onRecheck,
        layout: layout,
        initialAddressExpanded: initialAddressExpanded,
        initialMessageExpanded: initialMessageExpanded,
        // The surrounding modal frame owns the bottom edge in both form
        // factors.
        bottomSafeArea: false,
      ),
    );

    final modal = _ModalOverlayScope(
      child: _isMobile
          ? _mobileModal(context, card)
          : _desktopModal(context, card),
    );
    if (!_paintsBackground) return modal;

    return Stack(
      fit: StackFit.expand,
      children: [
        background ?? ColoredBox(color: colors.background.window),
        modal,
      ],
    );
  }

  Widget _mobileModal(BuildContext context, Widget card) {
    final colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Same dismissal contract as the desktop branch, which gets
        // scrim-tap and Escape from `AppPaneModalOverlay`. The Android
        // back gesture belongs to the route host — `showAppMobileSheet`
        // already provides it, and a `PopScope` here would also swallow
        // back for whatever route embeds this inline.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCancel,
          child: ColoredBox(color: colors.background.neutralScrim),
        ),
        // `showAppMobileSheet` gets this from `useSafeArea`; the inline
        // presentation has to keep the same clearance itself so a tall
        // request never runs into the status bar.
        SafeArea(
          bottom: false,
          minimum: const EdgeInsets.only(top: AppSpacing.base),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: MobileModalCard(
              child: Material(
                type: MaterialType.transparency,
                child: paymentRequestSheetBody(card, onClose: onCancel),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _desktopModal(BuildContext context, Widget card) {
    return AppPaneModalOverlay(
      onDismiss: onCancel,
      // The card is hosted above the router, so its scrim covers the
      // whole window — but the request is content, and content belongs
      // over the content pane. The shell's published pane insets move
      // the card off the sidebar's half of the window; with no shell
      // mounted they are zero and this centers on the window as before.
      child: ContentPaneCenteringPadding(
        child: AppModalCard(width: kPaymentRequestCardWidth, child: card),
      ),
    );
  }
}

/// Gives the scrim-and-card branch an [Overlay] ancestor.
///
/// The live host mounts this surface from `MaterialApp.router`'s `builder`,
/// above the `Router` — so there is no `Navigator`, and therefore no
/// `Overlay`, anywhere above the card. The requester help tooltip needs one,
/// for the same reason the card needs its transparent [Material].
///
/// Only the modal branch goes inside. The background stays where it was in
/// the outer stack, so the app underneath is not re-parented.
class _ModalOverlayScope extends StatefulWidget {
  const _ModalOverlayScope({required this.child});

  final Widget child;

  @override
  State<_ModalOverlayScope> createState() => _ModalOverlayScopeState();
}

class _ModalOverlayScopeState extends State<_ModalOverlayScope> {
  // `initialEntries` is read once, so the entry has to read `widget.child`
  // at build time and be told when a new request replaces it.
  late final OverlayEntry _entry = OverlayEntry(builder: (_) => widget.child);

  @override
  void didUpdateWidget(covariant _ModalOverlayScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.child, widget.child)) _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}

/// The mobile sheet body: the app's shared modal chrome around the card.
///
/// [MobileModalScaffold] owns the standard top 32 / sides 16 padding and the
/// pinned 32x32 top-right close every mobile sheet has, which is why the
/// card carries no Cancel button of its own. The card renders its own serif
/// title (and the requester line under it), so the scaffold's title row is
/// off — the shared reservation for the pinned close lives in the card's
/// header instead ([kPaymentRequestMobileCloseClearance]).
///
/// [bottomPadding] is the Figma modal base's 32 under the action stack; the
/// bottom safe area itself stays with `MobileModalCard`, so it is never
/// applied twice.
Widget paymentRequestSheetBody(Widget card, {required VoidCallback onClose}) {
  return MobileModalScaffold(
    title: '',
    showTitle: false,
    onClose: onClose,
    // Figma `_Modal Type` (4638:74505): 32 between the button stack and
    // the sheet's bottom edge.
    bottomPadding: AppSpacing.base,
    // The scaffold lays its body out in a min-size Column, which hands a
    // plain child unbounded height. The card needs a bounded one — that is
    // what makes its details region scroll instead of overflowing the sheet.
    child: Flexible(child: card),
  );
}

/// Presents the payment request as a mobile bottom sheet.
///
/// Resolves to `'continue'`, `'edit'`, or null when dismissed, so the
/// caller decides what each answer routes to. Nothing here reads providers
/// or parses the request.
Future<String?> showPaymentRequestSheet({
  required BuildContext context,
  required PaymentRequestView request,
}) {
  return showAppMobileSheet<String>(
    context: context,
    builder: (sheetContext) => paymentRequestSheetBody(
      PaymentRequestCard(
        request: request,
        bottomSafeArea: false,
        onContinue: () => Navigator.of(sheetContext).pop('continue'),
        onEdit: () => Navigator.of(sheetContext).pop('edit'),
        onCancel: () => Navigator.of(sheetContext).pop(),
      ),
      onClose: () => Navigator.of(sheetContext).pop(),
    ),
  );
}
