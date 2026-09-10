// Shared in-process BlueZ fake for the Linux Ledger tests: a private
// dbus-daemon bus with one adapter and one Ledger Stax exposing the Ledger
// GATT profile. Never touches hardware.
#ifndef VIZOR_LEDGER_TESTS_FAKE_BLUEZ_H_
#define VIZOR_LEDGER_TESTS_FAKE_BLUEZ_H_

#include "../ledger_bluez_transport.h"

#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace ledger_test {
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
<interface name='org.bluez.AgentManager1'>
<method name='RegisterAgent'><arg type='o' direction='in'/><arg type='s' direction='in'/></method>
<method name='UnregisterAgent'><arg type='o' direction='in'/></method>
<method name='RequestDefaultAgent'><arg type='o' direction='in'/></method></interface>
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
  bool nearby = true;
  // Pairing agent: BlueZ asks the registering application's agent to confirm
  // its own pairing requests. `agent_manager` false models an old BlueZ
  // without org.bluez.AgentManager1.
  bool agent_manager = true;
  std::string agent_path, agent_sender, agent_capability;
  std::string agent_confirm_device = kDevice;
  std::string agent_service_uuid;  // when set, AuthorizeService instead of RequestConfirmation
  int agent_answers = 0, agent_rejections = 0;
  int agent_registrations = 0, agent_duplicate_registrations = 0;
  std::string fail_start, fail_pair, fail_connect;
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
    return {{"/", "org.freedesktop.DBus.ObjectManager"}, {"/org/bluez", "org.bluez.AgentManager1"},
      {kAdapter, "org.bluez.Adapter1"},
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

  // Completes a Pair call through the registered agent, as BlueZ would.
  void AskAgent(GDBusMethodInvocation* invocation) {
    const bool authorize = !agent_service_uuid.empty();
    auto* context = new std::pair<FakeBluez*, GDBusMethodInvocation*>(
        this, G_DBUS_METHOD_INVOCATION(g_object_ref(invocation)));
    g_dbus_connection_call(server, agent_sender.c_str(), agent_path.c_str(), "org.bluez.Agent1",
        authorize ? "AuthorizeService" : "RequestConfirmation",
        authorize ? g_variant_new("(os)", agent_confirm_device.c_str(), agent_service_uuid.c_str())
                  : g_variant_new("(ou)", agent_confirm_device.c_str(), 123456u),
        nullptr, G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
        [](GObject* source, GAsyncResult* result, gpointer data) {
          std::unique_ptr<std::pair<FakeBluez*, GDBusMethodInvocation*>> context(
              static_cast<std::pair<FakeBluez*, GDBusMethodInvocation*>*>(data));
          auto& self = *context->first;
          auto* pair = context->second;
          g_autoptr(GError) error = nullptr;
          Variant reply(g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error));
          ++self.agent_answers;
          if (reply) {
            self.paired = true;
            g_dbus_method_invocation_return_value(pair, nullptr);
          } else {
            ++self.agent_rejections;
            g_dbus_method_invocation_return_dbus_error(pair, "org.bluez.Error.AuthenticationRejected", "Pairing rejected by agent");
          }
          g_object_unref(pair);
        }, context);
  }

  static void Method(GDBusConnection*, const gchar* sender, const gchar*, const gchar*,
      const gchar* method, GVariant* parameters, GDBusMethodInvocation* invocation, gpointer data) {
    auto& self = *static_cast<FakeBluez*>(data);
    const std::string name(method);
    if (name == "RegisterAgent") {
      if (!self.agent_manager) {
        g_dbus_method_invocation_return_dbus_error(invocation, "org.freedesktop.DBus.Error.UnknownMethod", "no agent manager");
        return;
      }
      const char* path = nullptr;
      const char* capability = nullptr;
      g_variant_get(parameters, "(&o&s)", &path, &capability);
      ++self.agent_registrations;
      if (self.agent_path == path) {
        ++self.agent_duplicate_registrations;
        g_dbus_method_invocation_return_dbus_error(invocation, "org.bluez.Error.AlreadyExists", "Already Exists");
        return;
      }
      self.agent_path = path;
      self.agent_sender = sender;
      self.agent_capability = capability;
    } else if (name == "UnregisterAgent") {
      self.agent_path.clear();
      self.agent_sender.clear();
    } else if (name == "GetManagedObjects") {
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
        if (std::string(entry.second) == "org.bluez.Device1" && self.nearby) {
          // BlueZ exposes RSSI only for devices the current discovery has seen.
          g_variant_builder_add(&properties, "{sv}", "RSSI", g_variant_new_int16(-60));
        }
        g_variant_builder_add(&interfaces, "{sa{sv}}", entry.second, &properties);
        g_variant_builder_add(&objects, "{oa{sa{sv}}}", entry.first, &interfaces);
      }
      g_dbus_method_invocation_return_value(invocation, g_variant_new("(a{oa{sa{sv}}})", &objects));
      return;
    }
    if (name == "StartDiscovery") {
      if (!self.fail_start.empty()) {
        g_dbus_method_invocation_return_dbus_error(invocation, self.fail_start.c_str(), "boom");
        return;
      }
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
      if (!self.fail_pair.empty()) {
        self.paired = self.fail_pair == "org.bluez.Error.AlreadyExists";
        g_dbus_method_invocation_return_dbus_error(invocation, self.fail_pair.c_str(), "Pair failed");
        return;
      }
      if (!self.agent_path.empty()) {
        self.AskAgent(invocation);
        return;
      }
      self.paired = true;
    } else if (name == "Connect") {
      ++self.connects;
      if (!self.fail_connect.empty()) {
        self.connected = self.fail_connect == "org.bluez.Error.AlreadyConnected";
        g_dbus_method_invocation_return_dbus_error(invocation, self.fail_connect.c_str(), "Connect failed");
        return;
      }
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
}  // namespace ledger_test

#endif  // VIZOR_LEDGER_TESTS_FAKE_BLUEZ_H_
