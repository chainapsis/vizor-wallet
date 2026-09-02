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
    this.layout = PaymentRequestLayout.auto,
    this.initialAddressExpanded = false,
    this.initialMessageExpanded = false,
    this.background,
    super.key,
  });

  final PaymentRequestView request;
  final VoidCallback onContinue;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  /// Tooling-only layout override; see [PaymentRequestLayout].
  final PaymentRequestLayout layout;

  /// Tooling-only: renders the To row already expanded to the full address.
  final bool initialAddressExpanded;

  /// Tooling-only: renders the Message row already expanded to its full text.
  final bool initialMessageExpanded;

  /// What the modal sits on top of. Defaults to the flat window color so a
  /// preview does not have to supply a whole screen.
  final Widget? background;

  bool get _isMobile => switch (layout) {
    PaymentRequestLayout.auto => kAppFormFactor == AppFormFactor.mobile,
    PaymentRequestLayout.desktop => false,
    PaymentRequestLayout.mobile => true,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final card = PaymentRequestCard(
      request: request,
      onContinue: onContinue,
      onEdit: onEdit,
      onCancel: onCancel,
      layout: layout,
      initialAddressExpanded: initialAddressExpanded,
      initialMessageExpanded: initialMessageExpanded,
      // The surrounding modal frame owns the bottom edge in both form
      // factors.
      bottomSafeArea: false,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        background ?? ColoredBox(color: colors.background.window),
        if (_isMobile)
          Stack(
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
                    child: paymentRequestSheetBody(card, onClose: onCancel),
                  ),
                ),
              ),
            ],
          )
        else
          AppPaneModalOverlay(
            onDismiss: onCancel,
            // The card is hosted above the router, so its scrim covers the
            // whole window — but the request is content, and content belongs
            // over the content pane. The shell's published pane insets move
            // the card off the sidebar's half of the window; with no shell
            // mounted they are zero and this centers on the window as before.
            child: ContentPaneCenteringPadding(
              child: AppModalCard(width: kPaymentRequestCardWidth, child: card),
            ),
          ),
      ],
    );
  }
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
/// [bottomPadding] is 16, the inset the card's action stack sits on; the
/// bottom safe area itself stays with `MobileModalCard`, so it is never
/// applied twice.
Widget paymentRequestSheetBody(Widget card, {required VoidCallback onClose}) {
  return MobileModalScaffold(
    title: '',
    showTitle: false,
    onClose: onClose,
    bottomPadding: AppSpacing.sm,
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
