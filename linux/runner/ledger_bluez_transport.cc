#include "ledger_bluez_transport.h"

#include <algorithm>
#include <thread>
#include <utility>

namespace ledger_bluez {
namespace {
using ledger_ble::Bytes;
using ledger_ble::Error;
using namespace std::chrono_literals;
constexpr const char* kDevice = "org.bluez.Device1";
constexpr const char* kCharacteristic = "org.bluez.GattCharacteristic1";
constexpr const char* kAdapter = "org.bluez.Adapter1";

std::string Narrow(const wchar_t* text) {
  std::string value;
  while (*text) value.push_back(static_cast<char>(*text++));
  return value;
}

std::string String(GVariant* properties, const char* key) {
  const char* value = nullptr;
  if (!g_variant_lookup(properties, key, "&s", &value) &&
      !g_variant_lookup(properties, key, "&o", &value)) return {};
  return value;
}

bool Boolean(GVariant* properties, const char* key) {
  gboolean value = FALSE;
  return g_variant_lookup(properties, key, "b", &value) && value;
}

const ledger_ble::ServiceSpec* Profile(GVariant* properties) {
  Variant uuids(g_variant_lookup_value(properties, "UUIDs", G_VARIANT_TYPE("as")));
  if (!uuids) return nullptr;
  GVariantIter iter;
  g_variant_iter_init(&iter, uuids.get());
  const char* uuid;
  while (g_variant_iter_next(&iter, "&s", &uuid)) {
    for (const auto& profile : ledger_ble::kServices) {
      if (g_ascii_strcasecmp(uuid, Narrow(profile.service).c_str()) == 0) return &profile;
    }
  }
  return nullptr;
}

constexpr const char* kAgentManager = "org.bluez.AgentManager1";
constexpr const char* kAgentPath = "/com/zcash/wallet/ledger/agent";
constexpr const char* kAgentXml = R"xml(<node>
<interface name='org.bluez.Agent1'>
<method name='Release'/>
<method name='RequestPinCode'><arg type='o' direction='in'/><arg type='s' direction='out'/></method>
<method name='DisplayPinCode'><arg type='o' direction='in'/><arg type='s' direction='in'/></method>
<method name='RequestPasskey'><arg type='o' direction='in'/><arg type='u' direction='out'/></method>
<method name='DisplayPasskey'><arg type='o' direction='in'/><arg type='u' direction='in'/><arg type='q' direction='in'/></method>
<method name='RequestConfirmation'><arg type='o' direction='in'/><arg type='u' direction='in'/></method>
<method name='RequestAuthorization'><arg type='o' direction='in'/></method>
<method name='AuthorizeService'><arg type='o' direction='in'/><arg type='s' direction='in'/></method>
<method name='Cancel'/>
</interface>
</node>)xml";

bool LedgerService(const char* uuid) {
  for (const auto& profile : ledger_ble::kServices) {
    if (g_ascii_strcasecmp(uuid, Narrow(profile.service).c_str()) == 0) return true;
  }
  return false;
}

constexpr const char* kUnreachable =
    "Linux could not reach your Ledger. Keep it nearby and unlocked, then try again.";

// A D-Bus failure keeps BlueZ's error name so callers can special-case it.
struct BusFailure : Error {
  BusFailure(std::string remote_name, bool local_timeout, std::string code, const std::string& message)
      : Error(std::move(code), message), remote(std::move(remote_name)), timed_out(local_timeout) {}
  std::string remote;
  bool timed_out;
};

BusFailure BusError(GError* error) {
  g_autofree gchar* remote = g_dbus_error_get_remote_error(error);
  const std::string name = remote ? remote : "";
  const bool timed_out = g_error_matches(error, G_IO_ERROR, G_IO_ERROR_TIMED_OUT);
  // GLib prefixes remote messages with "GDBus.Error:<name>:"; keep only the text.
  g_dbus_error_strip_remote_error(error);
  const auto failure = [&](const char* code, const std::string& message) {
    return BusFailure(name, timed_out, code, message);
  };
  if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) {
    return failure("cancelled", "The Ledger Bluetooth request was cancelled.");
  }
  if (timed_out) {
    return failure("unavailable", "Linux Bluetooth did not respond in time. Try again.");
  }
  if (name.find("Authentication") != std::string::npos) {
    return failure("pairing_rejected", "Ledger Bluetooth pairing was not completed. Try again and approve pairing on your Ledger when it shows the same code as Vizor.");
  }
  if (name.find("NotAuthorized") != std::string::npos ||
      name.find("AccessDenied") != std::string::npos ||
      name.find("NotPermitted") != std::string::npos) {
    return failure("permission_denied", "Linux denied Bluetooth access. Check Bluetooth permissions and Ledger pairing in system settings.");
  }
  if (name.find("NotConnected") != std::string::npos ||
      name.find("UnknownObject") != std::string::npos) {
    return failure("disconnected", "The Ledger disconnected. Keep it nearby and unlocked, then reconnect.");
  }
  if (name.find("ConnectionAttemptFailed") != std::string::npos) {
    return failure("disconnected", kUnreachable);
  }
  if (name.find("NotReady") != std::string::npos) {
    return failure("bluetooth_off", "Turn on Bluetooth in Linux system settings, then try again.");
  }
  if (name.find("ServiceUnknown") != std::string::npos ||
      name.find("NameHasNoOwner") != std::string::npos) {
    return failure("unavailable", "Linux Bluetooth is unavailable. Check that BlueZ is running and a Bluetooth LE adapter is connected.");
  }
  if (name.find("InProgress") != std::string::npos) {
    return failure("unavailable", "Linux Bluetooth is still finishing an earlier request. Wait a moment, then try again.");
  }
  return failure("unavailable", "Linux Bluetooth: " + std::string(error->message));
}

// A generic BlueZ failure while reaching the peer means it is off or out of range.
Error Unreachable(const Error& error) {
  return error.code == "unavailable" ? Error("disconnected", kUnreachable) : error;
}
}  // namespace

Transport::Transport(GDBusConnection* connection)
    : bus_(G_DBUS_CONNECTION(g_object_ref(connection))) {
  changed_id_ = g_dbus_connection_signal_subscribe(
      bus_, "org.bluez", "org.freedesktop.DBus.Properties", "PropertiesChanged",
      nullptr, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      [](GDBusConnection*, const gchar*, const gchar* path, const gchar*,
         const gchar*, GVariant* parameters, gpointer data) {
        static_cast<Transport*>(data)->Changed(path, parameters);
      }, this, nullptr);
  removed_id_ = g_dbus_connection_signal_subscribe(
      bus_, "org.bluez", "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved",
      nullptr, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
      [](GDBusConnection*, const gchar*, const gchar*, const gchar*, const gchar*,
         GVariant* parameters, gpointer data) {
        static_cast<Transport*>(data)->Removed(parameters);
      }, this, nullptr);
  ExportAgent();
}

Transport::~Transport() {
  if (pairing_prompt_) g_object_unref(pairing_prompt_);
  if (agent_node_) g_dbus_node_info_unref(agent_node_);
  g_object_unref(bus_);
}

void Transport::Close() {
  if (changed_id_) g_dbus_connection_signal_unsubscribe(bus_, changed_id_);
  if (removed_id_) g_dbus_connection_signal_unsubscribe(bus_, removed_id_);
  changed_id_ = removed_id_ = 0;
  ResolvePairingPrompt(false, "org.bluez.Error.Canceled");
  UnregisterAgent();
  Wake();
}

void Transport::SetPairingListener(std::function<void(const std::string& code)> listener) {
  pairing_listener_ = std::move(listener);
}

void Transport::NotifyPairing(const std::string& code) {
  if (pairing_listener_) pairing_listener_(code);
}

void Transport::HoldPairingPrompt(GDBusMethodInvocation* invocation) {
  // The handler owns the invocation's reference until it is answered.
  ResolvePairingPrompt(false, "org.bluez.Error.Canceled");
  std::lock_guard lock(mutex_);
  pairing_prompt_ = invocation;
}

void Transport::ResolvePairingPrompt(bool accept, const char* error_name) {
  GDBusMethodInvocation* prompt = nullptr;
  {
    std::lock_guard lock(mutex_);
    prompt = std::exchange(pairing_prompt_, nullptr);
  }
  if (!prompt) return;
  if (accept) {
    g_dbus_method_invocation_return_value(prompt, nullptr);
  } else {
    g_dbus_method_invocation_return_dbus_error(prompt, error_name, "Vizor did not confirm the pairing code.");
  }
}

void Transport::ConfirmPairing(bool accept) {
  g_message("Ledger BLE agent: pairing code %s", accept ? "confirmed" : "rejected");
  ResolvePairingPrompt(accept);
}

void Transport::ExportAgent() {
  g_autoptr(GError) error = nullptr;
  agent_node_ = g_dbus_node_info_new_for_xml(kAgentXml, &error);
  if (!agent_node_) {
    g_warning("Ledger BLE agent: %s", error->message);
    return;
  }
  static const GDBusInterfaceVTable table = {AgentMethod, nullptr, nullptr, {nullptr}};
  agent_id_ = g_dbus_connection_register_object(bus_, kAgentPath, agent_node_->interfaces[0], &table, this, nullptr, &error);
  if (!agent_id_) g_warning("Ledger BLE agent: %s", error->message);
}

void Transport::RegisterAgent(GCancellable* cancel) {
  if (!agent_id_) return;
  // Registered before each pairing so a restarted bluetoothd still routes the
  // request here. Best effort: without an agent manager the session's own
  // Bluetooth agent (if any) answers instead. DisplayYesNo matches what the
  // agent does: it shows the code and the Ledger's screen gives the yes/no.
  g_autoptr(GError) error = nullptr;
  Variant reply(g_dbus_connection_call_sync(bus_, "org.bluez", "/org/bluez", kAgentManager, "RegisterAgent",
      g_variant_new("(os)", kAgentPath, "DisplayYesNo"), nullptr, G_DBUS_CALL_FLAGS_NO_AUTO_START, 3000, cancel, &error));
  if (reply) return;
  if (g_dbus_error_is_remote_error(error)) {
    g_autofree gchar* name = g_dbus_error_get_remote_error(error);
    if (name && g_str_has_suffix(name, ".AlreadyExists")) return;
  }
  g_message("Ledger BLE agent: not registered (%s); the session agent handles pairing", error->message);
}

void Transport::UnregisterAgent() {
  if (!agent_id_) return;
  g_dbus_connection_call(bus_, "org.bluez", "/org/bluez", kAgentManager, "UnregisterAgent",
      g_variant_new("(o)", kAgentPath), nullptr, G_DBUS_CALL_FLAGS_NO_AUTO_START, 3000, nullptr, nullptr, nullptr);
  g_dbus_connection_unregister_object(bus_, agent_id_);
  agent_id_ = 0;
}

bool Transport::AgentAccepts(const std::string& device) {
  std::lock_guard lock(mutex_);
  return pairing_ && device_ == device;
}

void Transport::AgentMethod(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                            const gchar* method, GVariant* parameters,
                            GDBusMethodInvocation* invocation, gpointer data) {
  auto& self = *static_cast<Transport*>(data);
  const std::string name(method);
  const auto reject = [&](const char* message) {
    g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.Rejected", message);
  };
  if (name == "Release" || name == "Cancel" || name == "DisplayPinCode" || name == "DisplayPasskey") {
    g_message("Ledger BLE agent: %s", method);
    if (name == "Cancel") {
      self.ResolvePairingPrompt(false, "org.bluez.Error.Canceled");
      self.NotifyPairing("");
    }
    g_dbus_method_invocation_return_value(invocation, nullptr);
    return;
  }
  if (name == "RequestConfirmation") {
    const char* device = nullptr;
    guint32 passkey = 0;
    g_variant_get(parameters, "(&ou)", &device, &passkey);
    if (!self.AgentAccepts(device)) {
      reject("Vizor only pairs the Ledger it is connecting.");
      return;
    }
    // Numeric comparison only defeats a device in the middle when both sides
    // condition their yes on the codes matching, so the host reply waits for
    // the user's answer to the code shown in Vizor (ConfirmPairing).
    char code[16];
    g_snprintf(code, sizeof code, "%06u", passkey);
    self.HoldPairingPrompt(invocation);
    self.NotifyPairing(code);
    return;
  }
  if (name == "RequestAuthorization") {
    // Just Works: no code, no protection. A Ledger always offers a code.
    reject("Ledger pairing requires a code to confirm.");
    return;
  }
  if (name == "AuthorizeService") {
    const char* device = nullptr;
    const char* uuid = nullptr;
    g_variant_get(parameters, "(&o&s)", &device, &uuid);
    if (self.AgentAccepts(device) && LedgerService(uuid)) {
      g_dbus_method_invocation_return_value(invocation, nullptr);
    } else {
      reject("Vizor only authorizes the Ledger service.");
    }
    return;
  }
  if (name == "RequestPinCode" || name == "RequestPasskey") {
    reject("Ledger pairing does not use a PIN.");
    return;
  }
  g_dbus_method_invocation_return_dbus_error(invocation, "org.freedesktop.DBus.Error.UnknownMethod", method);
}

void Transport::Wake() { changed_.notify_all(); }

void Transport::Check(GCancellable* cancel) const {
  if (cancel && g_cancellable_is_cancelled(cancel)) {
    throw Error("cancelled", "The Ledger Bluetooth request was cancelled.");
  }
}

Variant Transport::Call(const std::string& path, const char* interface,
                        const char* method, GVariant* parameters,
                        GCancellable* cancel, int timeout) {
  g_autoptr(GError) error = nullptr;
  Variant result(g_dbus_connection_call_sync(
      bus_, "org.bluez", path.c_str(), interface, method, parameters, nullptr,
      G_DBUS_CALL_FLAGS_NO_AUTO_START, timeout, cancel, &error));
  if (!result) throw BusError(error);
  return result;
}

Variant Transport::Objects(GCancellable* cancel) {
  auto result = Call("/", "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", nullptr, cancel);
  return Variant(g_variant_get_child_value(result.get(), 0));
}

Variant Transport::Properties(const std::string& path, const char* interface,
                             GCancellable* cancel) {
  auto result = Call(path, "org.freedesktop.DBus.Properties", "GetAll",
                     g_variant_new("(s)", interface), cancel);
  return Variant(g_variant_get_child_value(result.get(), 0));
}

std::vector<Device> Transport::Devices(GVariant* objects, bool nearby) {
  std::vector<Device> devices;
  GVariantIter iter;
  g_variant_iter_init(&iter, objects);
  const char* path;
  GVariant* raw;
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &raw)) {
    Variant interfaces(raw);
    Variant properties(g_variant_lookup_value(interfaces.get(), kDevice, G_VARIANT_TYPE("a{sv}")));
    if (!properties) continue;
    const auto* profile = Profile(properties.get());
    if (!profile) continue;
    if (nearby) {
      // BlueZ keeps bonded devices even when they are off. RSSI exists only
      // while the current discovery has seen the device.
      Variant rssi(g_variant_lookup_value(properties.get(), "RSSI", G_VARIANT_TYPE_INT16));
      if (!rssi && !Boolean(properties.get(), "Connected")) continue;
    }
    auto name = String(properties.get(), "Alias");
    if (name.empty()) name = profile->model;
    devices.push_back({path, name, profile->model});
  }
  return devices;
}

std::string Transport::ReadyAdapter(GCancellable* cancel) {
  auto objects = Objects(cancel);
  GVariantIter iter;
  g_variant_iter_init(&iter, objects.get());
  const char* path;
  GVariant* raw;
  bool found = false;
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &raw)) {
    Variant interfaces(raw);
    Variant properties(g_variant_lookup_value(interfaces.get(), kAdapter, G_VARIANT_TYPE("a{sv}")));
    if (!properties) continue;
    found = true;
    if (Boolean(properties.get(), "Powered")) return path;
  }
  if (found) throw Error("bluetooth_off", "Turn on Bluetooth in Linux system settings to find your Ledger.");
  throw Error("unavailable", "Linux has no Bluetooth adapter. Connect a Bluetooth LE adapter, then try again.");
}

void Transport::StartDiscovery(const std::string& adapter, GCancellable* cancel) {
  GVariantBuilder filter;
  g_variant_builder_init(&filter, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&filter, "{sv}", "Transport", g_variant_new_string("le"));
  GVariantBuilder uuids;
  g_variant_builder_init(&uuids, G_VARIANT_TYPE("as"));
  for (const auto& profile : ledger_ble::kServices) {
    g_variant_builder_add(&uuids, "s", Narrow(profile.service).c_str());
  }
  g_variant_builder_add(&filter, "{sv}", "UUIDs", g_variant_builder_end(&uuids));
  Call(adapter, kAdapter, "SetDiscoveryFilter", g_variant_new("(a{sv})", &filter), cancel);
  try {
    Call(adapter, kAdapter, "StartDiscovery", nullptr, cancel);
  } catch (...) {
    // Cancelling the local D-Bus wait does not cancel BlueZ's method. It may
    // already have started discovery before its reply reaches this process.
    StopDiscovery(adapter);
    throw;
  }
}

void Transport::StopDiscovery(const std::string& adapter) {
  if (adapter.empty()) return;
  try { Call(adapter, kAdapter, "StopDiscovery", nullptr, nullptr, 3000); }
  catch (const Error& error) { g_warning("Ledger discovery cleanup: %s", error.what()); }
}

void Transport::Connect(const std::string& id, GCancellable* cancel) {
  // Log only connection stages, never device identities or APDU contents.
  const auto started = std::chrono::steady_clock::now();
  const auto stage = [&](const char* name) {
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - started).count();
    g_message("Ledger BLE connect: %s (%lld ms)", name, static_cast<long long>(elapsed));
  };
  stage("starting");
  Disconnect();
  const auto devices = Devices(Objects(cancel).get(), false);
  if (std::none_of(devices.begin(), devices.end(), [&](const auto& device) { return device.id == id; })) {
    throw Error("disconnected", "Select a nearby Ledger from the Bluetooth device list again.");
  }
  {
    std::lock_guard lock(mutex_);
    device_ = id;
    failure_.reset();
  }
  auto properties = Properties(id, kDevice, cancel);
  g_message("Ledger BLE connect: paired=%d connected=%d services=%d",
      Boolean(properties.get(), "Paired"), Boolean(properties.get(), "Connected"),
      Boolean(properties.get(), "ServicesResolved"));
  if (!Boolean(properties.get(), "Paired")) {
    stage("pairing requested");
    RegisterAgent(cancel);
    pairing_ = true;
    std::optional<BusFailure> pair_failure;
    try {
      Call(id, kDevice, "Pair", nullptr, cancel, 120000);
    } catch (const BusFailure& failure) {
      pair_failure = failure;
    }
    pairing_ = false;
    ResolvePairingPrompt(false, "org.bluez.Error.Canceled");
    NotifyPairing("");
    // AlreadyExists means the bond completed elsewhere while this call ran.
    if (pair_failure && pair_failure->remote.find("AlreadyExists") == std::string::npos) {
      if (pair_failure->timed_out) {
        throw Error("pairing_rejected", "Ledger Bluetooth pairing timed out. Try again and approve pairing on your Ledger when it shows the same code as Vizor.");
      }
      throw Unreachable(*pair_failure);
    }
    stage("pairing completed");
  }
  properties = Properties(id, kDevice, cancel);
  if (!Boolean(properties.get(), "Connected")) {
    stage("connection requested");
    try {
      Call(id, kDevice, "Connect", nullptr, cancel, 30000);
    } catch (const BusFailure& failure) {
      if (failure.remote.find("AlreadyConnected") == std::string::npos) throw Unreachable(failure);
    }
    stage("connection call completed");
  }
  const auto deadline = std::chrono::steady_clock::now() + 20s;
  int previous_state = -1;
  while (true) {
    Check(cancel);
    properties = Properties(id, kDevice, cancel);
    const bool connected = Boolean(properties.get(), "Connected");
    const bool resolved = Boolean(properties.get(), "ServicesResolved");
    const int state = (connected ? 1 : 0) | (resolved ? 2 : 0);
    if (state != previous_state) {
      g_message("Ledger BLE connect: connected=%d services=%d", connected, resolved);
      previous_state = state;
    }
    if (connected && resolved) break;
    if (std::chrono::steady_clock::now() >= deadline) {
      stage("service discovery timed out");
      throw Error("disconnected", "Linux could not discover the Ledger Bluetooth services. Reconnect and try again.");
    }
    std::unique_lock lock(mutex_);
    changed_.wait_for(lock, 100ms);
  }
  stage("services resolved");
  auto objects = Objects(cancel);
  std::string service_path;
  const ledger_ble::ServiceSpec* selected = nullptr;
  GVariantIter iter;
  g_variant_iter_init(&iter, objects.get());
  const char* path;
  GVariant* raw;
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &raw)) {
    Variant interfaces(raw);
    Variant service(g_variant_lookup_value(interfaces.get(), "org.bluez.GattService1", G_VARIANT_TYPE("a{sv}")));
    if (!service || String(service.get(), "Device") != id) continue;
    for (const auto& profile : ledger_ble::kServices) {
      if (g_ascii_strcasecmp(String(service.get(), "UUID").c_str(), Narrow(profile.service).c_str()) == 0) {
        selected = &profile;
        service_path = path;
        break;
      }
    }
    if (selected) break;
  }
  if (!selected) throw Error("unavailable", "This device does not expose a supported Ledger Bluetooth service.");
  std::string notify, write;
  guint16 att_mtu = 23;
  g_variant_iter_init(&iter, objects.get());
  while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &raw)) {
    Variant interfaces(raw);
    Variant characteristic(g_variant_lookup_value(interfaces.get(), kCharacteristic, G_VARIANT_TYPE("a{sv}")));
    if (!characteristic || String(characteristic.get(), "Service") != service_path) continue;
    const auto uuid = String(characteristic.get(), "UUID");
    if (g_ascii_strcasecmp(uuid.c_str(), Narrow(selected->notify).c_str()) == 0) notify = path;
    if (g_ascii_strcasecmp(uuid.c_str(), Narrow(selected->write).c_str()) == 0) {
      write = path;
      g_variant_lookup(characteristic.get(), "MTU", "q", &att_mtu);
    }
  }
  if (notify.empty() || write.empty()) throw Error("unavailable", "Ledger Bluetooth characteristics are missing.");
  {
    std::lock_guard lock(mutex_);
    notify_ = notify;
    write_ = write;
    connected_ = true;
    packets_.clear();
  }
  Call(notify, kCharacteristic, "StartNotify", nullptr, cancel);
  stage("notifications started");
  mtu_ = ledger_ble::NegotiatedMtu(ExchangePackets({{0x08, 0, 0, 0, 0}}, cancel, true), att_mtu);
  stage("ready");
}

void Transport::Disconnect() {
  std::string device, notify;
  {
    std::lock_guard lock(mutex_);
    device = device_;
    notify = std::move(notify_);
    write_.clear();
    connected_ = awaiting_ = false;
    packets_.clear();
    failure_.reset();
  }
  Wake();
  if (!device.empty() && pairing_) {
    try { Call(device, kDevice, "CancelPairing", nullptr, nullptr, 3000); } catch (const Error&) {}
  }
  pairing_ = false;
  if (!notify.empty()) {
    try { Call(notify, kCharacteristic, "StopNotify", nullptr, nullptr, 3000); } catch (const Error&) {}
  }
  if (!device.empty()) {
    try {
      Call(device, kDevice, "Disconnect", nullptr, nullptr, 3000);
    } catch (const Error& error) {
      // An absent device is already disconnected; other failures must block a
      // new session until cleanup can be retried successfully.
      if (error.code != "disconnected") throw;
    }
    std::lock_guard lock(mutex_);
    if (device_ == device) device_.clear();
  }
}

Bytes Transport::ExchangePackets(const std::vector<Bytes>& frames, GCancellable* cancel, bool mtu) {
  std::string write;
  {
    std::lock_guard lock(mutex_);
    if (!connected_) throw Error("disconnected", "Reconnect your Ledger over Bluetooth, then try again.");
    write = write_;
    packets_.clear();
    failure_.reset();
    awaiting_ = true;
  }
  const auto finish = [this](void*) { std::lock_guard lock(mutex_); awaiting_ = false; };
  std::unique_ptr<void, decltype(finish)> guard(this, finish);
  for (const auto& frame : frames) {
    Check(cancel);
    GVariantBuilder options;
    g_variant_builder_init(&options, G_VARIANT_TYPE("a{sv}"));
    // kServices selects Ledger's 0002 write characteristic, not the 0003
    // write-command characteristic. It requires Write With Response.
    g_variant_builder_add(&options, "{sv}", "type", g_variant_new_string("request"));
    Call(write, kCharacteristic, "WriteValue",
         g_variant_new("(@aya{sv})", g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, frame.data(), frame.size(), 1), &options), cancel);
  }
  ledger_ble::ResponseAssembler assembler;
  const auto deadline = std::chrono::steady_clock::now() + (mtu ? 10s : 300s);
  while (true) {
    Check(cancel);
    std::unique_lock lock(mutex_);
    if (failure_) throw *failure_;
    if (!connected_) throw Error("disconnected", "The Ledger disconnected. Reconnect and try again.");
    if (!packets_.empty()) {
      auto packet = std::move(packets_.front());
      packets_.pop_front();
      lock.unlock();
      if (mtu) return packet;
      if (assembler.Add(packet)) return assembler.bytes();
    } else {
      if (std::chrono::steady_clock::now() >= deadline) {
        throw Error("unavailable", mtu
            ? "Ledger Bluetooth initialization timed out. Keep your Ledger unlocked and reconnect."
            : "Ledger Bluetooth request timed out. Reconnect and try again.");
      }
      changed_.wait_for(lock, 100ms);
    }
  }
}

Bytes Transport::Exchange(const Bytes& apdu, GCancellable* cancel) {
  return ExchangePackets(ledger_ble::FrameApdu(apdu, mtu_), cancel);
}

ledger_ble::AppInfo Transport::CurrentApp(GCancellable* cancel) {
  return ledger_ble::DecodeAppInfo(Exchange({0xb0, 0x01, 0, 0}, cancel));
}

ledger_ble::AppInfo Transport::OpenZcash(GCancellable* cancel) {
  auto app = CurrentApp(cancel);
  if (app.name == "Zcash") return app;
  if (app.name != "BOLOS" && app.name != "OLOS" && app.name != std::string("OLOS\0", 5)) {
    throw Error("wrong_app", "Open the Zcash app on your Ledger, then try again.");
  }
  std::string device;
  { std::lock_guard lock(mutex_); device = device_; }
  try {
    ledger_ble::RequireSuccess(Exchange({0xe0, 0xd8, 0, 0, 5, 'Z', 'c', 'a', 's', 'h'}, cancel));
  } catch (const Error& error) {
    if (error.code != "disconnected") throw;
  }
  const auto deadline = std::chrono::steady_clock::now() + 10s;
  do {
    Check(cancel);
    try {
      Connect(device, cancel);
      app = CurrentApp(cancel);
      if (app.name == "Zcash") return app;
    } catch (const Error& error) {
      if (error.code == "cancelled" || error.code == "rejected" || error.code == "locked" ||
          error.code == "permission_denied" || error.code == "pairing_rejected") throw;
    }
    std::unique_lock lock(mutex_);
    changed_.wait_for(lock, 200ms);
  } while (std::chrono::steady_clock::now() < deadline);
  throw Error("wrong_app", "Open the Zcash app on your Ledger, then reconnect.");
}

void Transport::Changed(const char* path, GVariant* parameters) {
  const char* interface;
  GVariant* raw;
  g_variant_get(parameters, "(&s@a{sv}@as)", &interface, &raw, nullptr);
  Variant properties(raw);
  std::lock_guard lock(mutex_);
  if (device_ == path && std::string(interface) == kDevice) {
    gboolean connected;
    if (g_variant_lookup(properties.get(), "Connected", "b", &connected) && !connected) connected_ = false;
  } else if (notify_ == path && std::string(interface) == kCharacteristic && awaiting_) {
    Variant bytes(g_variant_lookup_value(properties.get(), "Value", G_VARIANT_TYPE("ay")));
    if (bytes) {
      gsize size;
      const auto* data = static_cast<const uint8_t*>(g_variant_get_fixed_array(bytes.get(), &size, 1));
      if (size > 512 || size == 0 || packets_.size() >= 256) {
        failure_ = Error("unavailable", "Ledger sent invalid Bluetooth fragments.");
      } else {
        packets_.emplace_back(data, data + size);
      }
    }
  }
  changed_.notify_all();
}

void Transport::Removed(GVariant* parameters) {
  const char* path;
  g_variant_get(parameters, "(&o@as)", &path, nullptr);
  std::lock_guard lock(mutex_);
  if (device_ == path || notify_ == path || write_ == path) connected_ = false;
  changed_.notify_all();
}
}  // namespace ledger_bluez
