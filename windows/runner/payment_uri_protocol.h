#ifndef RUNNER_PAYMENT_URI_PROTOCOL_H_
#define RUNNER_PAYMENT_URI_PROTOCOL_H_

void RegisterZcashProtocolHandler();
// Like RegisterZcashProtocolHandler, but only registers when no handler owns
// the zcash: scheme yet, or when this exact install already owns it. Use this
// on normal startup so a launch does not steal the handler the user picked;
// the install/update hooks use the unconditional variant to claim it.
void RegisterZcashProtocolHandlerIfUnclaimed();
void UnregisterZcashProtocolHandler();

#endif  // RUNNER_PAYMENT_URI_PROTOCOL_H_
