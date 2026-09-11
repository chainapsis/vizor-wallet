#ifndef RUNNER_PAYMENT_URI_PROTOCOL_H_
#define RUNNER_PAYMENT_URI_PROTOCOL_H_

// Install/update: keep Zcash's existing registration behavior. Additional
// payment schemes are registered only when another live handler does not own
// them, preserving the user's other wallet choices.
void RegisterPaymentProtocolHandlers();
// Normal startup: leave every live or unreadable registration alone, including
// this install's own registration, and repair only missing or dangling owners.
void RegisterPaymentProtocolHandlersIfUnclaimed();
// Remove only schemes whose effective command launches this exact install.
void UnregisterPaymentProtocolHandlers();

#endif  // RUNNER_PAYMENT_URI_PROTOCOL_H_
