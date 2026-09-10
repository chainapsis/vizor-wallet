#include "../../../native/ledger/ble_protocol.h"
#include "../../../native/ledger/ble_operation_gate.h"

#include <cassert>
#include <functional>
#include <iostream>

namespace {
void Rejects(const std::function<void()>& action, const char* code = "unavailable") {
  bool rejected = false;
  try {
    action();
  } catch (const ledger_ble::Error& error) {
    rejected = error.code == code;
  }
  assert(rejected);
}
}  // namespace

int main() {
  using namespace ledger_ble;
  const Bytes command = {0xb0, 0x01, 0, 0};
  assert((FrameApdu(command, 20) ==
          std::vector<Bytes>{{0x05, 0, 0, 0, 4, 0xb0, 1, 0, 0}}));
  for (const size_t mtu : {20, 64, 244}) {
    Bytes response(8192, 0x42);
    response[response.size() - 2] = 0x90;
    response.back() = 0;
    const auto frames = FrameApdu(response, mtu);
    ResponseAssembler assembler;
    for (size_t index = 0; index < frames.size(); ++index) {
      assert(frames[index].size() <= mtu);
      assert(assembler.Add(frames[index]) == (index + 1 == frames.size()));
    }
    assert(assembler.bytes() == response);
    Rejects([&] { assembler.Add(frames.front()); });
  }
  Rejects([] { FrameApdu({}, 20); });
  Rejects([] { FrameApdu({1}, 5); });
  Rejects([] { FrameApdu(Bytes(65536), 20); });
  Rejects([] { ResponseAssembler().Add({0x05, 0, 1, 0x90, 0}); });
  Rejects([] { ResponseAssembler().Add({0x08, 0, 0, 0, 2, 0x90, 0}); });
  Rejects([] { ResponseAssembler().Add({0x05, 0}); });
  Rejects([] { ResponseAssembler().Add({0x05, 0, 0, 0}); });
  Rejects([] { ResponseAssembler().Add({0x05, 0, 0, 0, 1, 0}); });
  Rejects([] { ResponseAssembler().Add({0x05, 0, 0, 0, 2, 0x90, 0, 1}); });
  ResponseAssembler partial;
  assert(!partial.Add({0x05, 0, 0, 0, 4, 0x90}));
  Rejects([&] { partial.Add({0x05, 0, 2, 0, 0, 0}); });
  assert(NegotiatedMtu({0x08, 0, 0, 0, 0, 244}, 185) == 182);
  assert(NegotiatedMtu({0x08, 0, 0, 0, 0, 244}, 23) == 20);
  assert(NegotiatedMtu({0x08, 0, 0, 0, 0, 20}, 247) == 20);
  Rejects([] { NegotiatedMtu({0x08, 0, 0}, 247); });
  Rejects([] { NegotiatedMtu({0x08, 0, 0, 0, 0, 19}, 247); });
  assert(HasSuccessStatus({0x90, 0}));
  assert(!HasSuccessStatus({0x69, 0x85}));
  Rejects([] { RequireSuccess({0x55, 0x15}); }, "locked");
  Rejects([] { RequireSuccess({0x69, 0x85}); }, "rejected");
  Rejects([] { RequireSuccess({0x69, 0x01}); }, "device_busy");
  Rejects([] { RequireSuccess({}); });
  const auto app = DecodeAppInfo(
      {1, 5, 'Z', 'c', 'a', 's', 'h', 5, '3', '.', '9', '.', '3', 0x90, 0});
  assert(app.name == "Zcash" && app.version == "3.9.3");
  Rejects([] { DecodeAppInfo({1, 5, 'Z', 0x90, 0}); });
  OperationGate gate;
  const auto first = gate.Begin();
  assert(first && gate.IsActive(*first));
  gate.Cancel();
  assert(!gate.IsActive(*first) && !gate.Begin());
  gate.Finish(*first + 1);
  assert(gate.busy());
  gate.Finish(*first);
  const auto second = gate.Begin();
  assert(second && gate.IsActive(*second));
  gate.Finish(*first);
  assert(gate.busy() && gate.IsActive(*second));
  gate.Finish(*second);
  assert(!gate.busy());
  std::cout << "Ledger BLE protocol checks passed\n";
}
