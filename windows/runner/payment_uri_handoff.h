#ifndef RUNNER_PAYMENT_URI_HANDOFF_H_
#define RUNNER_PAYMENT_URI_HANDOFF_H_

#include <windows.h>

#include <string>
#include <vector>

bool ForwardPaymentLinksToRunningInstance(
    const std::vector<std::string>& uris);
bool TryReadPaymentLinkCopyData(LPARAM lparam, std::string* uri);

#endif  // RUNNER_PAYMENT_URI_HANDOFF_H_
