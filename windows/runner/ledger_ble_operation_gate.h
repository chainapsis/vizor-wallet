#ifndef RUNNER_LEDGER_BLE_OPERATION_GATE_H_
#define RUNNER_LEDGER_BLE_OPERATION_GATE_H_

#include <atomic>
#include <cstdint>
#include <optional>

namespace ledger_ble {

// Begin, Cancel and Finish run on the Flutter platform thread. Workers only
// read IsActive. Cancellation invalidates delivery without releasing ownership
// of an in-flight request before that worker has finished its cleanup.
class OperationGate {
 public:
  std::optional<uint64_t> Begin() {
    if (busy_) return std::nullopt;
    busy_ = true;
    owner_ = ++generation_;
    return owner_;
  }
  void Cancel() { ++generation_; }
  void Finish(uint64_t owner) {
    if (owner_ == owner) busy_ = false;
  }
  bool IsActive(uint64_t owner) const { return generation_.load() == owner; }
  bool busy() const { return busy_; }

 private:
  std::atomic<uint64_t> generation_{0};
  uint64_t owner_ = 0;
  bool busy_ = false;
};

}  // namespace ledger_ble

#endif  // RUNNER_LEDGER_BLE_OPERATION_GATE_H_
