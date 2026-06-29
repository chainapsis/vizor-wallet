#ifndef RUNNER_PAYMENT_URI_HANDOFF_H_
#define RUNNER_PAYMENT_URI_HANDOFF_H_

#include <windows.h>

#include <string>
#include <vector>

// Forwards zcash: payment URIs to an already-running Vizor instance from the
// same executable path. Returns true only when at least one URI was delivered.
bool ForwardPaymentUrisToRunningInstance(const std::vector<std::string>& uris);

// Decodes and validates a WM_COPYDATA payload produced by
// ForwardPaymentUrisToRunningInstance.
bool TryReadPaymentUriCopyData(LPARAM lparam, std::string* uri);

#endif  // RUNNER_PAYMENT_URI_HANDOFF_H_
