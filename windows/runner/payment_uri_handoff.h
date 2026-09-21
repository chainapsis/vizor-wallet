#ifndef RUNNER_PAYMENT_URI_HANDOFF_H_
#define RUNNER_PAYMENT_URI_HANDOFF_H_

#include <windows.h>

#include <string>
#include <vector>

// Forwards zcash: payment URIs to an already-running Vizor instance. The target
// window is the one that acknowledges |activation_message| (the registered
// single-instance message from SingleInstanceGuard), so the instance boundary
// used here is the same one the instance lock enforces. Retries while the
// primary is still starting and returns true only when at least one URI was
// delivered.
bool ForwardPaymentUrisToRunningInstance(const std::vector<std::string>& uris,
                                         UINT activation_message);

// Decodes and validates a WM_COPYDATA payload produced by
// ForwardPaymentUrisToRunningInstance.
bool TryReadPaymentUriCopyData(LPARAM lparam, std::string* uri);

#endif  // RUNNER_PAYMENT_URI_HANDOFF_H_
