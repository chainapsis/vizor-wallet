/// The Gift Card screen's local page cursor.
///
/// It is screen state, not routing: both the desktop pane and the mobile body
/// switch on it. It sits in its own file only so the mobile body can be a
/// separate library from the screen that owns the state machine.
library;

enum PaymentLinksLocalPage {
  home,
  amount,
  message,
  review,
  ready,
  shareQr,
  redeem,
  received,
}
