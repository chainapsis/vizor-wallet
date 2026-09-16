#ifndef VIZOR_LINUX_LEDGER_BLE_HANDLER_H_
#define VIZOR_LINUX_LEDGER_BLE_HANDLER_H_
#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>

#include <memory>

// The view owns the handler, so closing the Flutter view tears down its channels.
void register_ledger_ble_handler(FlView* view);

// Test seam: the same handler on an explicit bus (a private fake BlueZ)
// instead of the system bus. Deleting the owner closes the handler.
class LedgerBleHandlerOwner {
 public:
  virtual ~LedgerBleHandlerOwner() = default;
};
std::unique_ptr<LedgerBleHandlerOwner> create_ledger_ble_handler_for_testing(
    FlBinaryMessenger* messenger, GDBusConnection* bus);

#endif  // VIZOR_LINUX_LEDGER_BLE_HANDLER_H_
