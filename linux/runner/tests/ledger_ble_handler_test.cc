// Drives the Linux Ledger method channel end to end: Flutter's real channel
// and codec code, the production handler and BlueZ transport, and a fake
// BlueZ on a private bus. Run with linux/runner/tests/run_ledger_ble_tests.sh.
#include "../ledger_ble_handler.h"

#include <chrono>
#include <iostream>
#include <thread>

#include "fake_bluez.h"
#include "flutter/shell/platform/linux/fl_method_codec_private.h"
#include "test_binary_messenger.h"

namespace {
using namespace ledger_test;
using namespace std::chrono_literals;
constexpr const char* kMethods = "com.zcash.wallet/ledger_mobile";
constexpr const char* kEvents = "com.zcash.wallet/ledger_mobile/discovery";
constexpr const char* kConnection = "com.zcash.wallet/ledger_mobile/connection";

struct ValueDeleter { void operator()(FlValue* value) const { if (value) fl_value_unref(value); } };
using Value = std::unique_ptr<FlValue, ValueDeleter>;
struct ResponseDeleter { void operator()(FlMethodResponse* value) const { if (value) g_object_unref(value); } };
using Response = std::unique_ptr<FlMethodResponse, ResponseDeleter>;

void Pump(std::chrono::milliseconds duration) {
  const auto until = std::chrono::steady_clock::now() + duration;
  while (std::chrono::steady_clock::now() < until) {
    while (g_main_context_iteration(nullptr, false)) {}
    std::this_thread::sleep_for(1ms);
  }
}

struct Channels {
  TestMessenger* messenger = test_messenger_new();
  FlStandardMethodCodec* codec = fl_standard_method_codec_new();
  ~Channels() { g_object_unref(codec); g_object_unref(messenger); }

  std::shared_ptr<Reply> Send(const char* channel, const char* name, FlValue* args) {
    g_autoptr(GError) error = nullptr;
    g_autoptr(GBytes) message = fl_method_codec_encode_method_call(FL_METHOD_CODEC(codec), name, args, &error);
    Require(message != nullptr, "encode method call");
    return test_messenger_deliver(messenger, channel, message);
  }

  Response Wait(const std::shared_ptr<Reply>& reply, std::chrono::milliseconds timeout = 5000ms) {
    const auto until = std::chrono::steady_clock::now() + timeout;
    while (!reply->done && std::chrono::steady_clock::now() < until) {
      while (g_main_context_iteration(nullptr, false)) {}
      std::this_thread::sleep_for(1ms);
    }
    Require(reply->done, "the handler replied in time");
    Require(reply->bytes != nullptr, "reply carries a payload");
    g_autoptr(GError) error = nullptr;
    Response response(fl_method_codec_decode_response(FL_METHOD_CODEC(codec), reply->bytes, &error));
    Require(response != nullptr, "decode reply");
    return response;
  }

  Response Call(const char* name, FlValue* args = nullptr) { return Wait(Send(kMethods, name, args)); }

  // Events the handler pushed on an event stream, decoded, oldest first.
  std::vector<Value> Events(const char* channel = kEvents) {
    std::vector<Value> events;
    for (auto& sent : test_messenger_sent(messenger)) {
      if (sent.channel != channel) continue;
      g_autoptr(GError) error = nullptr;
      Response response(fl_method_codec_decode_response(FL_METHOD_CODEC(codec), sent.bytes, &error));
      Require(response != nullptr && FL_IS_METHOD_SUCCESS_RESPONSE(response.get()), "decode event");
      events.emplace_back(fl_value_ref(fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(response.get()))));
    }
    return events;
  }
};

FlValue* Success(const Response& response, const char* context) {
  if (FL_IS_METHOD_ERROR_RESPONSE(response.get())) {
    throw std::runtime_error(std::string(context) + ": unexpected error " +
        fl_method_error_response_get_code(FL_METHOD_ERROR_RESPONSE(response.get())) + ": " +
        fl_method_error_response_get_message(FL_METHOD_ERROR_RESPONSE(response.get())));
  }
  Require(FL_IS_METHOD_SUCCESS_RESPONSE(response.get()), context);
  return fl_method_success_response_get_result(FL_METHOD_SUCCESS_RESPONSE(response.get()));
}

std::string ErrorCode(const Response& response, const char* context) {
  Require(FL_IS_METHOD_ERROR_RESPONSE(response.get()), context);
  return fl_method_error_response_get_code(FL_METHOD_ERROR_RESPONSE(response.get()));
}

std::string ErrorText(const Response& response) {
  return fl_method_error_response_get_message(FL_METHOD_ERROR_RESPONSE(response.get()));
}

std::string Str(FlValue* map, const char* key) {
  auto* value = fl_value_lookup_string(map, key);
  Require(value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING, key);
  return fl_value_get_string(value);
}

FlValue* Apdu(uint8_t ins, std::initializer_list<uint8_t> data) {
  auto* command = fl_value_new_map();
  fl_value_set_string_take(command, "cla", fl_value_new_int(0xE0));
  fl_value_set_string_take(command, "ins", fl_value_new_int(ins));
  fl_value_set_string_take(command, "p1", fl_value_new_int(0));
  fl_value_set_string_take(command, "p2", fl_value_new_int(0));
  fl_value_set_string_take(command, "data", fl_value_new_uint8_list(std::vector<uint8_t>(data).data(), data.size()));
  return command;
}

FlValue* Commands(std::initializer_list<FlValue*> commands) {
  auto* list = fl_value_new_list();
  for (auto* command : commands) fl_value_append_take(list, command);
  auto* args = fl_value_new_map();
  fl_value_set_string_take(args, "commands", list);
  return args;
}

FlValue* DeviceArgs(const char* id) {
  auto* args = fl_value_new_map();
  fl_value_set_string_take(args, "deviceId", fl_value_new_string(id));
  return args;
}
}  // namespace

int main() {
  FakeBluez fake;
  Channels channels;
  auto owner = create_ledger_ble_handler_for_testing(FL_BINARY_MESSENGER(channels.messenger), fake.client);
  try {
    // Permissions are the adapter being powered.
    Require(fl_value_get_bool(Success(channels.Call("requestPermissions"), "requestPermissions")), "adapter ready");
    fake.powered = false;
    Require(ErrorCode(channels.Call("requestPermissions"), "adapter off") == "bluetooth_off", "adapter off is reported");
    fake.powered = true;

    // Connect validates its arguments before touching the gate.
    Require(ErrorCode(channels.Call("connect"), "connect without a device") == "disconnected", "missing device id");
    Require(fake.connects == 0, "no connection attempt without a device id");
    Success(channels.Wait(channels.Send(kConnection, "listen", nullptr)), "listen for connection events");
    Success(channels.Call("connect", DeviceArgs(kDevice)), "connect");
    Require(fake.pairs == 1 && fake.connects == 1, "pair then connect");
    {
      // Vizor's own agent confirmed the pairing, so Dart got the code to
      // compare with the Ledger and then the end of the prompt.
      const auto events = channels.Events(kConnection);
      Require(events.size() == 2, "two pairing events");
      Require(Str(events[0].get(), "type") == "pairing" && Str(events[0].get(), "code") == "123456", "pairing code event");
      Require(Str(events[1].get(), "type") == "pairing_ended", "pairing ended event");
    }
    {
      const auto app = channels.Call("currentApp");
      auto* result = Success(app, "currentApp");
      Require(Str(result, "name") == "Zcash" && Str(result, "version") == "3.9.3", "app info round trip");
    }

    // One request at a time: a second call while the gate is busy is refused
    // without disturbing the first.
    fake.hold_response = true;
    auto held = channels.Send(kMethods, "exchangeApdus", Commands({Apdu(0x01, {1, 2, 3})}));
    Pump(50ms);
    Require(!held->done, "the held exchange is still waiting on the device");
    const auto refused = channels.Call("currentApp");
    Require(ErrorCode(refused, "busy gate") == "unavailable" && ErrorText(refused).find("Wait for the previous") != std::string::npos,
        "a concurrent request is refused, not queued");
    Require(!held->done, "the refusal did not cancel the held exchange");

    // Cancelling reaches the blocked worker; its reply is 'cancelled' and the
    // link is dropped so the next request starts clean.
    Success(channels.Call("cancelSigning"), "cancelSigning");
    Require(ErrorCode(channels.Wait(held), "held exchange after cancel") == "cancelled", "cancelled reply");
    Require(fake.disconnects >= 1, "a failed request disconnects");
    fake.hold_response = false;

    // Disconnect while busy waits for the worker to drain before replying.
    Success(channels.Call("connect", DeviceArgs(kDevice)), "reconnect");
    fake.hold_response = true;
    held = channels.Send(kMethods, "exchangeApdus", Commands({Apdu(0x01, {1, 2, 3})}));
    Pump(50ms);
    auto waiter = channels.Send(kMethods, "disconnect", nullptr);
    Require(!waiter->done, "disconnect is not acknowledged before the worker drains");
    Require(ErrorCode(channels.Wait(held), "exchange interrupted by disconnect") == "cancelled", "disconnect cancels the worker");
    Success(channels.Wait(waiter), "disconnect after drain");
    Require(!fake.connected, "the device is disconnected once the worker drained");
    fake.hold_response = false;

    // APDU batches stop at the first non-success status; a short UFVK export
    // needs no continuation while a longer one is stitched from two frames.
    Success(channels.Call("connect", DeviceArgs(kDevice)), "connect for exchanges");
    fake.response = {0x6A, 0x80};
    {
      const auto batch = channels.Call("exchangeApdus", Commands({Apdu(0x01, {1}), Apdu(0x02, {2})}));
      Require(fl_value_get_length(Success(batch, "exchangeApdus")) == 1, "stops after a failing status");
    }
    // The two-byte length prefix counts as received payload, so a declared
    // length of two arrives complete in this single frame.
    fake.response = {0x00, 0x02, 0xAA, 0xBB, 0x90, 0x00};
    {
      auto* args = fl_value_new_map();
      fl_value_set_string_take(args, "first", Apdu(0x10, {0}));
      fl_value_set_string_take(args, "continuation", Apdu(0x11, {}));
      const auto export_response = channels.Call("exchangeUfvk", args);
      Require(fl_value_get_length(Success(export_response, "exchangeUfvk")) == 1, "complete export in one frame");
    }
    fake.response = {0x00, 0x06, 0xAA, 0xBB, 0xCC, 0xDD, 0x90, 0x00};
    {
      auto* args = fl_value_new_map();
      fl_value_set_string_take(args, "first", Apdu(0x10, {0}));
      fl_value_set_string_take(args, "continuation", Apdu(0x11, {}));
      const auto export_response = channels.Call("exchangeUfvk", args);
      Require(fl_value_get_length(Success(export_response, "exchangeUfvk continuation")) == 2,
          "continuation frame requested once");
    }
    Success(channels.Call("disconnect"), "disconnect idle");

    // Discovery streams nearby Ledgers while someone listens and stops cleanly.
    Success(channels.Wait(channels.Send(kEvents, "listen", nullptr)), "listen");
    Success(channels.Call("startDiscovery"), "startDiscovery");
    Require(fake.discovering, "BlueZ discovery started");
    Success(channels.Call("startDiscovery"), "a second start is a no-op");
    Pump(700ms);
    {
      const auto events = channels.Events();
      Require(!events.empty(), "a discovery poll emitted devices");
      auto* last = events.back().get();
      Require(Str(last, "type") == "devices", "devices event");
      auto* devices = fl_value_lookup_string(last, "devices");
      Require(devices && fl_value_get_length(devices) == 1, "one nearby Ledger");
      auto* device = fl_value_get_list_value(devices, 0);
      Require(Str(device, "id") == kDevice && Str(device, "model") == "Ledger Stax", "device identity");
    }
    Success(channels.Call("stopDiscovery"), "stopDiscovery");
    Require(!fake.discovering, "BlueZ discovery stopped");

    Success(channels.Call("cancelSigning"), "cancel while idle is harmless");
    Require(FL_IS_METHOD_NOT_IMPLEMENTED_RESPONSE(channels.Call("unknownMethod").get()), "unknown methods are not implemented");

    owner.reset();
    Pump(100ms);
    std::cout << "Linux Ledger BLE handler tests passed\n";
  } catch (const std::exception& error) {
    owner.reset();
    Pump(100ms);
    std::cerr << error.what() << '\n';
    return 1;
  }
}
