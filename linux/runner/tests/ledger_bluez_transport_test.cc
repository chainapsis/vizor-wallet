// Run on Linux with gio-2.0 and dbus-daemon; uses a private bus, never hardware.
/* From the repository root:
g++ -std=c++17 -Wall -Wextra -Werror -pthread \
  linux/runner/tests/ledger_bluez_transport_test.cc \
  linux/runner/ledger_bluez_transport.cc $(pkg-config --cflags --libs gio-2.0) \
  -o /tmp/ledger-bluez-test && /tmp/ledger-bluez-test
*/
#include "../ledger_bluez_transport.h"

#include <future>
#include <iostream>
#include <thread>

namespace {
using ledger_ble::Bytes;
using ledger_ble::Error;
using ledger_bluez::Variant;
constexpr const char* kAdapter = "/org/bluez/hci0";
constexpr const char* kDevice = "/org/bluez/hci0/dev_AA";
constexpr const char* kService = "/org/bluez/hci0/dev_AA/service001";
constexpr const char* kNotify = "/org/bluez/hci0/dev_AA/service001/char001";
constexpr const char* kWrite = "/org/bluez/hci0/dev_AA/service001/char002";
constexpr const char* kXml = R"xml(<node>
<interface name='org.freedesktop.DBus.ObjectManager'><method name='GetManagedObjects'><arg type='a{oa{sa{sv}}}' direction='out'/></method></interface>
<interface name='org.bluez.Adapter1'>
<method name='SetDiscoveryFilter'><arg type='a{sv}' direction='in'/></method><method name='StartDiscovery'/><method name='StopDiscovery'/>
<property name='Powered' type='b' access='read'/></interface>
<interface name='org.bluez.Device1'>
<method name='Pair'/><method name='CancelPairing'/><method name='Connect'/><method name='Disconnect'/>
<property name='UUIDs' type='as' access='read'/><property name='Alias' type='s' access='read'/>
<property name='Paired' type='b' access='read'/><property name='Connected' type='b' access='read'/><property name='ServicesResolved' type='b' access='read'/></interface>
<interface name='org.bluez.GattService1'><property name='UUID' type='s' access='read'/><property name='Device' type='o' access='read'/></interface>
<interface name='org.bluez.GattCharacteristic1'>
<method name='StartNotify'/><method name='StopNotify'/><method name='WriteValue'><arg type='ay' direction='in'/><arg type='a{sv}' direction='in'/></method>
<property name='UUID' type='s' access='read'/><property name='Service' type='o' access='read'/><property name='MTU' type='q' access='read'/></interface>
</node>)xml";

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

struct FakeBluez {
  GTestDBus* test_bus = g_test_dbus_new(G_TEST_DBUS_NONE);
  GDBusConnection* server = nullptr;
  GDBusConnection* client = nullptr;
  GDBusNodeInfo* node = nullptr;
  std::vector<guint> registrations;
  bool powered = true, paired = false, connected = false;
  bool reject_pairing = false, deny_write = false, hold_response = false;
  bool hold_mtu = false;
  bool disconnect_on_write = false;
  bool hold_start = false, discovering = false;
  GCancellable* cancel_start = nullptr;
  GDBusMethodInvocation* pending_start = nullptr;
  int pairs = 0, connects = 0, disconnects = 0, writes = 0;
  ledger_ble::ResponseAssembler input;
  Bytes response = {1, 5, 'Z', 'c', 'a', 's', 'h', 5, '3', '.', '9', '.', '3', 0x90, 0};

  FakeBluez() {
    g_test_dbus_up(test_bus);
    g_autoptr(GError) error = nullptr;
    const auto flags = static_cast<GDBusConnectionFlags>(G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT | G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION);
    server = g_dbus_connection_new_for_address_sync(g_test_dbus_get_bus_address(test_bus), flags, nullptr, nullptr, &error);
    Require(server != nullptr, "open fake server bus");
    client = g_dbus_connection_new_for_address_sync(g_test_dbus_get_bus_address(test_bus), flags, nullptr, nullptr, &error);
    Require(client != nullptr, "open transport bus");
    Variant owner(g_dbus_connection_call_sync(server, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", g_variant_new("(su)", "org.bluez", 0u), nullptr, G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error));
    Require(owner != nullptr, "own fake BlueZ name");
    node = g_dbus_node_info_new_for_xml(kXml, &error);
    Require(node != nullptr, "parse fake API");
    static const GDBusInterfaceVTable table = {Method, Property, nullptr, {nullptr}};
    for (const auto& entry : Entries()) {
      auto* info = g_dbus_node_info_lookup_interface(node, entry.second);
      const auto id = g_dbus_connection_register_object(server, entry.first, info, &table, this, nullptr, &error);
      Require(id != 0, "register fake interface");
      registrations.push_back(id);
    }
  }

  ~FakeBluez() {
    g_clear_object(&pending_start);
    for (const auto id : registrations) g_dbus_connection_unregister_object(server, id);
    g_dbus_node_info_unref(node);
    g_dbus_connection_close_sync(client, nullptr, nullptr);
    g_dbus_connection_close_sync(server, nullptr, nullptr);
    g_object_unref(client);
    g_object_unref(server);
    g_test_dbus_down(test_bus);
    g_object_unref(test_bus);
  }

  static std::vector<std::pair<const char*, const char*>> Entries() {
    return {{"/", "org.freedesktop.DBus.ObjectManager"}, {kAdapter, "org.bluez.Adapter1"},
      {kDevice, "org.bluez.Device1"}, {kService, "org.bluez.GattService1"},
      {kNotify, "org.bluez.GattCharacteristic1"}, {kWrite, "org.bluez.GattCharacteristic1"}};
  }

  static GVariant* Property(GDBusConnection*, const gchar*, const gchar* path,
      const gchar* interface, const gchar* key, GError**, gpointer data) {
    auto& self = *static_cast<FakeBluez*>(data);
    const std::string name(key);
    if (name == "Powered") return g_variant_new_boolean(self.powered);
    if (name == "Paired") return g_variant_new_boolean(self.paired);
    if (name == "Connected" || name == "ServicesResolved") return g_variant_new_boolean(self.connected);
    if (name == "Alias") return g_variant_new_string("Test Stax");
    if (name == "MTU") return g_variant_new_uint16(23);
    if (name == "Device") return g_variant_new_object_path(kDevice);
    if (name == "Service") return g_variant_new_object_path(kService);
    if (name == "UUIDs") {
      const char* uuids[] = {"13d63400-2c97-6004-0000-4c6564676572"};
      return g_variant_new_strv(uuids, 1);
    }
    if (name == "UUID") {
      if (std::string(interface) == "org.bluez.GattService1") return g_variant_new_string("13d63400-2c97-6004-0000-4c6564676572");
      return g_variant_new_string(std::string(path) == kNotify ? "13d63400-2c97-6004-0001-4c6564676572" : "13d63400-2c97-6004-0002-4c6564676572");
    }
    return nullptr;
  }

  void Signal(const char* path, const char* interface, const char* key, GVariant* value) {
    GVariantBuilder changed, invalidated;
    g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_init(&invalidated, G_VARIANT_TYPE("as"));
    g_variant_builder_add(&changed, "{sv}", key, value);
    g_dbus_connection_emit_signal(server, nullptr, path, "org.freedesktop.DBus.Properties", "PropertiesChanged", g_variant_new("(sa{sv}as)", interface, &changed, &invalidated), nullptr);
  }

  void Notify(const Bytes& bytes) {
    Signal(kNotify, "org.bluez.GattCharacteristic1", "Value", g_variant_new_fixed_array(G_VARIANT_TYPE_BYTE, bytes.data(), bytes.size(), 1));
  }

  static void Method(GDBusConnection*, const gchar*, const gchar*, const gchar*,
      const gchar* method, GVariant* parameters, GDBusMethodInvocation* invocation, gpointer data) {
    auto& self = *static_cast<FakeBluez*>(data);
    const std::string name(method);
    if (name == "GetManagedObjects") {
      GVariantBuilder objects;
      g_variant_builder_init(&objects, G_VARIANT_TYPE("a{oa{sa{sv}}}"));
      for (const auto& entry : Entries()) {
        GVariantBuilder interfaces, properties;
        g_variant_builder_init(&interfaces, G_VARIANT_TYPE("a{sa{sv}}"));
        g_variant_builder_init(&properties, G_VARIANT_TYPE("a{sv}"));
        auto* info = g_dbus_node_info_lookup_interface(self.node, entry.second);
        if (info->properties) for (auto** property = info->properties; *property; ++property) {
          g_variant_builder_add(&properties, "{sv}", (*property)->name, Property(nullptr, nullptr, entry.first, entry.second, (*property)->name, nullptr, &self));
        }
        g_variant_builder_add(&interfaces, "{sa{sv}}", entry.second, &properties);
        g_variant_builder_add(&objects, "{oa{sa{sv}}}", entry.first, &interfaces);
      }
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(a{oa{sa{sv}}})", &objects));
      return;
    }
    if (name == "StartDiscovery") {
      self.discovering = true;
      if (self.hold_start) {
        self.pending_start = G_DBUS_METHOD_INVOCATION(g_object_ref(invocation));
        // Cancel only after BlueZ has started discovery, before its reply.
        g_cancellable_cancel(self.cancel_start);
        return;
      }
    } else if (name == "StopDiscovery") {
      self.discovering = false;
      if (self.pending_start) {
        g_dbus_method_invocation_return_value(self.pending_start, nullptr);
        g_clear_object(&self.pending_start);
      }
    } else if (name == "Pair") {
      ++self.pairs;
      if (self.reject_pairing) {
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.AuthenticationRejected", "Pairing rejected");
        return;
      }
      self.paired = true;
    } else if (name == "Connect") {
      ++self.connects;
      self.connected = true;
    } else if (name == "Disconnect") {
      ++self.disconnects;
      self.connected = false;
      self.input = {};
      self.Signal(kDevice, "org.bluez.Device1", "Connected", g_variant_new_boolean(false));
    } else if (name == "WriteValue") {
      ++self.writes;
      Variant options(g_variant_get_child_value(parameters, 1));
      const char* type = nullptr;
      if (!g_variant_lookup(options.get(), "type", "&s", &type) ||
          std::string(type) != "request") {
        // Ledger's 0002 characteristic supports Write With Response only.
        // A permissive fake previously hid Linux's use of a write command.
        g_dbus_method_invocation_return_dbus_error(invocation,
            "org.bluez.Error.NotSupported", "Ledger write characteristic requires request");
        return;
      }
      if (self.deny_write) {
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.NotAuthorized", "Permission denied");
        return;
      }
      Variant bytes(g_variant_get_child_value(parameters, 0));
      gsize length;
      const auto* raw = static_cast<const uint8_t*>(g_variant_get_fixed_array(bytes.get(), &length, 1));
      Bytes packet(raw, raw + length);
      if (packet[0] == 0x08) {
        if (!self.hold_mtu) self.Notify({0x08, 0, 0, 0, 0, 20});
      } else if (self.input.Add(packet)) {
        self.input = {};
        if (self.disconnect_on_write) {
          self.connected = false;
          self.Signal(kDevice, "org.bluez.Device1", "Connected", g_variant_new_boolean(false));
        } else if (!self.hold_response) {
          for (const auto& frame : ledger_ble::FrameApdu(self.response, 20)) self.Notify(frame);
        }
      }
    }
    g_dbus_method_invocation_return_value(invocation, nullptr);
  }
};

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
}  // namespace

int main() {
  FakeBluez fake;
  ledger_bluez::Transport transport(fake.client);
  try {
    Require(Run([&] { return transport.ReadyAdapter(nullptr); }) == kAdapter, "powered adapter");
    fake.powered = false;
    Fails("bluetooth_off", [&] { transport.ReadyAdapter(nullptr); });
    fake.powered = true;
    auto devices = Run([&] { return ledger_bluez::Transport::Devices(transport.Objects(nullptr).get()); });
    Require(devices.size() == 1 && devices[0].model == "Ledger Stax", "UUID discovery");
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
    transport.Close();
    std::cout << "Linux BlueZ transport tests passed\n";
  } catch (const std::exception& error) {
    transport.Close();
    std::cerr << error.what() << '\n';
    return 1;
  }
}
