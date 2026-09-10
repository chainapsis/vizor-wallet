#ifndef VIZOR_LINUX_LEDGER_BLE_HANDLER_H_
#define VIZOR_LINUX_LEDGER_BLE_HANDLER_H_
#include <flutter_linux/flutter_linux.h>

// The view owns the handler, so closing the Flutter view tears down its channels.
void register_ledger_ble_handler(FlView* view);

#endif  // VIZOR_LINUX_LEDGER_BLE_HANDLER_H_
