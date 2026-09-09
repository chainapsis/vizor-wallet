#ifndef RUNNER_LEDGER_BLE_HANDLER_H_
#define RUNNER_LEDGER_BLE_HANDLER_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

#include <memory>

class LedgerBleHandler {
 public:
  LedgerBleHandler(HWND window, flutter::BinaryMessenger* messenger);
  ~LedgerBleHandler();
  LedgerBleHandler(const LedgerBleHandler&) = delete;
  LedgerBleHandler& operator=(const LedgerBleHandler&) = delete;

  bool HandleWindowMessage(UINT message, WPARAM wparam);

 private:
  class Impl;
  std::shared_ptr<Impl> impl_;
};

#endif  // RUNNER_LEDGER_BLE_HANDLER_H_
