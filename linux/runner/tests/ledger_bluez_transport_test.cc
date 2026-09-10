// Run on Linux with gio-2.0 and dbus-daemon; uses a private bus, never hardware.
/* From the repository root:
g++ -std=c++17 -Wall -Wextra -Werror -pthread \
  linux/runner/tests/ledger_bluez_transport_test.cc \
  linux/runner/ledger_bluez_transport.cc $(pkg-config --cflags --libs gio-2.0) \
  -o /tmp/ledger-bluez-test && /tmp/ledger-bluez-test
*/
#include "fake_bluez.h"

#include <future>
#include <iostream>
#include <thread>

namespace {
using namespace ledger_test;
template <typename Action>
auto Run(Action action) {
  auto future = std::async(std::launch::async, action);
  while (future.wait_for(std::chrono::milliseconds(0)) != std::future_status::ready) {
    while (g_main_context_iteration(nullptr, false)) {}
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  while (g_main_context_iteration(nullptr, false)) {}
  return future.get();
}

template <typename Action>
void Fails(const char* code, Action action) {
  try { Run(action); } catch (const Error& error) {
    Require(error.code == code, error.what());
    return;
  }
  throw std::runtime_error(std::string("Expected failure: ") + code);
}

template <typename Action>
Error Catch(Action action) {
  try { Run(action); } catch (const Error& error) { return error; }
  throw std::runtime_error("Expected a failure");
}
}  // namespace

int main() {
  FakeBluez fake;
  ledger_bluez::Transport transport(fake.client);
  try {
    Require(Run([&] { return transport.ReadyAdapter(nullptr); }) == kAdapter, "powered adapter");
    fake.powered = false;
    Fails("bluetooth_off", [&] { transport.ReadyAdapter(nullptr); });
    fake.powered = true;
    const auto devices = [&](bool nearby) {
      return Run([&] { return ledger_bluez::Transport::Devices(transport.Objects(nullptr).get(), nearby); });
    };
    Require(devices(true).size() == 1 && devices(true)[0].model == "Ledger Stax", "UUID discovery");
    fake.nearby = false;
    Require(devices(true).empty(), "bonded device out of range is not offered");
    Require(devices(false).size() == 1, "known device stays connectable without discovery");
    fake.fail_start = "org.bluez.Error.Failed";
    const auto start_failure = Catch([&] { transport.StartDiscovery(kAdapter, nullptr); });
    Require(start_failure.code == "unavailable" && std::string(start_failure.what()) == "Linux Bluetooth: boom",
        "remote error text is stripped of its D-Bus prefix");
    fake.fail_start.clear();
    Run([&] { transport.StartDiscovery(kAdapter, nullptr); transport.StopDiscovery(kAdapter); });
    fake.hold_start = true;
    g_autoptr(GCancellable) scan_cancel = g_cancellable_new();
    fake.cancel_start = scan_cancel;
    Fails("cancelled", [&] { transport.StartDiscovery(kAdapter, scan_cancel); });
    Require(!fake.discovering && !fake.pending_start, "cancelled discovery drains BlueZ");
    fake.hold_start = false;
    fake.cancel_start = nullptr;
    fake.reject_pairing = true;
    Fails("pairing_rejected", [&] { transport.Connect(kDevice, nullptr); });
    Run([&] { transport.Disconnect(); });
    fake.reject_pairing = false;
    Run([&] { transport.Connect(kDevice, nullptr); });
    Require(fake.pairs == 2, "pair before GATT");
    Require(fake.agent_path == "/com/zcash/wallet/ledger/agent" && fake.agent_capability == "KeyboardDisplay",
        "the transport registers its own pairing agent");
    Require(fake.agent_answers == 1 && fake.agent_rejections == 0, "the agent confirmed our own pairing");
    Run([&] { transport.Disconnect(); });
    // The agent vouches only for the Ledger being connected, never for
    // another device BlueZ happens to pair in the same session.
    fake.paired = false;
    fake.agent_confirm_device = "/org/bluez/hci0/dev_BB";
    Fails("pairing_rejected", [&] { transport.Connect(kDevice, nullptr); });
    Require(fake.agent_rejections == 1 && !fake.paired, "a foreign device is rejected");
    Run([&] { transport.Disconnect(); });
    fake.agent_confirm_device = kDevice;
    fake.agent_service_uuid = "13d63400-2c97-6004-0000-4c6564676572";
    Run([&] { transport.Connect(kDevice, nullptr); });
    Require(fake.paired, "the Ledger service is authorized");
    Run([&] { transport.Disconnect(); });
    fake.paired = false;
    fake.agent_service_uuid = "0000180f-0000-1000-8000-00805f9b34fb";
    Fails("pairing_rejected", [&] { transport.Connect(kDevice, nullptr); });
    Require(fake.agent_rejections == 2, "other services are not authorized");
    fake.agent_service_uuid.clear();
    Run([&] { transport.Disconnect(); });
    Run([&] { transport.Connect(kDevice, nullptr); });
    auto app = Run([&] { return transport.CurrentApp(nullptr); });
    Require(app.name == "Zcash" && app.version == "3.9.3", "decode app");
    fake.hold_mtu = true;
    const auto initialization_started = std::chrono::steady_clock::now();
    Fails("unavailable", [&] { transport.Connect(kDevice, nullptr); });
    Require(std::chrono::steady_clock::now() - initialization_started < std::chrono::seconds(15),
        "initialization must not use the five-minute signing timeout");
    Run([&] { transport.Disconnect(); });
    fake.hold_mtu = false;
    Run([&] { transport.Connect(kDevice, nullptr); });
    fake.response.assign(180, 0x42);
    fake.response.insert(fake.response.end(), {0x90, 0});
    Require(Run([&] { return transport.Exchange(Bytes(100, 0x55), nullptr); }) == fake.response, "fragmented APDU round trip");
    fake.deny_write = true;
    Fails("permission_denied", [&] { transport.Exchange({1, 2, 3}, nullptr); });
    fake.deny_write = false;
    fake.hold_response = true;
    g_autoptr(GCancellable) cancel = g_cancellable_new();
    g_timeout_add(50, [](gpointer data) -> gboolean { g_cancellable_cancel(G_CANCELLABLE(data)); return G_SOURCE_REMOVE; }, cancel);
    Fails("cancelled", [&] { transport.Exchange({1, 2, 3}, cancel); });
    Run([&] { transport.Disconnect(); });
    fake.hold_response = false;
    Run([&] { transport.Connect(kDevice, nullptr); });
    Require(Run([&] { return transport.Exchange({1, 2, 3}, nullptr); }) == fake.response, "reconnect after cancel");
    fake.disconnect_on_write = true;
    Fails("disconnected", [&] { transport.Exchange({1, 2, 3}, nullptr); });
    Run([&] { transport.Disconnect(); });
    fake.disconnect_on_write = false;
    fake.paired = false;
    fake.fail_pair = "org.bluez.Error.ConnectionAttemptFailed";
    Fails("disconnected", [&] { transport.Connect(kDevice, nullptr); });
    Run([&] { transport.Disconnect(); });
    fake.fail_pair = "org.bluez.Error.AlreadyExists";
    Run([&] { transport.Connect(kDevice, nullptr); });
    Require(fake.paired, "a bond completed elsewhere is accepted");
    fake.fail_pair.clear();
    Run([&] { transport.Disconnect(); });
    fake.fail_connect = "org.bluez.Error.Failed";
    const auto connect_failure = Catch([&] { transport.Connect(kDevice, nullptr); });
    Require(connect_failure.code == "disconnected" &&
            std::string(connect_failure.what()).find("GDBus") == std::string::npos,
        "unreachable peer is reported as disconnected");
    Run([&] { transport.Disconnect(); });
    fake.fail_connect = "org.bluez.Error.AlreadyConnected";
    Run([&] { transport.Connect(kDevice, nullptr); });
    Require(Run([&] { return transport.Exchange({1, 2, 3}, nullptr); }) == fake.response,
        "already connected peer completes initialization");
    fake.fail_connect.clear();
    Run([&] { transport.Disconnect(); });
    transport.Close();
    // UnregisterAgent is fire-and-forget; let the bus deliver it.
    for (int i = 0; i < 200 && !fake.agent_path.empty(); ++i) {
      while (g_main_context_iteration(nullptr, false)) {}
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    Require(fake.agent_path.empty(), "closing unregisters the agent");
    {
      // An old BlueZ without an agent manager: pairing still goes through the
      // session agent, exactly as before.
      FakeBluez legacy;
      legacy.agent_manager = false;
      ledger_bluez::Transport fallback(legacy.client);
      Run([&] { fallback.Connect(kDevice, nullptr); });
      Require(legacy.paired && legacy.agent_answers == 0, "pairing without our agent");
      Run([&] { fallback.Disconnect(); });
      fallback.Close();
    }
    std::cout << "Linux BlueZ transport tests passed\n";
  } catch (const std::exception& error) {
    transport.Close();
    std::cerr << error.what() << '\n';
    return 1;
  }
}
