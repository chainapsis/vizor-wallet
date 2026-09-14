/// A payment request waiting for the unlocked wallet to present its card.
/// Sending ZEC and paying another asset share intake lifetime, not execution.
abstract interface class PaymentRequestDraft {
  String get id;
}
