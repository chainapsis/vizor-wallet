#ifndef VIZOR_LEDGER_BLUEZ_TRANSPORT_H_
#define VIZOR_LEDGER_BLUEZ_TRANSPORT_H_

#include <gio/gio.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

#include "../../native/ledger/ble_protocol.h"

namespace ledger_bluez {

struct VariantDeleter {
  void operator()(GVariant* value) const { if (value) g_variant_unref(value); }
};
using Variant = std::unique_ptr<GVariant, VariantDeleter>;

struct Device {
  std::string id;
  std::string name;
  std::string model;
};

// Construct/Close on the GLib platform thread. Blocking methods run on one
// worker; D-Bus signals arrive on the platform thread and wake that worker.
//
// The transport also registers an org.bluez.Agent1 for its own pairing
// requests, so pairing works in sessions without a desktop Bluetooth agent.
// BlueZ asks the registering application's agent for the pairings that
// application starts; the agent answers only for the Ledger being connected.
class Transport {
 public:
  explicit Transport(GDBusConnection* connection);
  ~Transport();
  Transport(const Transport&) = delete;
  Transport& operator=(const Transport&) = delete;

  void Close();
  void Wake();
  Variant Objects(GCancellable* cancel);
  static std::vector<Device> Devices(GVariant* objects, bool nearby);
  std::string ReadyAdapter(GCancellable* cancel);
  void StartDiscovery(const std::string& adapter, GCancellable* cancel);
  void StopDiscovery(const std::string& adapter);
  void Connect(const std::string& id, GCancellable* cancel);
  void Disconnect();
  ledger_ble::Bytes Exchange(const ledger_ble::Bytes& apdu, GCancellable* cancel);
  ledger_ble::AppInfo CurrentApp(GCancellable* cancel);
  ledger_ble::AppInfo OpenZcash(GCancellable* cancel);

 private:
  Variant Call(const std::string& path, const char* interface, const char* method,
               GVariant* parameters, GCancellable* cancel, int timeout = 10000);
  Variant Properties(const std::string& path, const char* interface, GCancellable* cancel);
  ledger_ble::Bytes ExchangePackets(const std::vector<ledger_ble::Bytes>& frames,
                                    GCancellable* cancel, bool mtu = false);
  void Changed(const char* path, GVariant* parameters);
  void Removed(GVariant* parameters);
  void Check(GCancellable* cancel) const;
  void RegisterAgent();
  void UnregisterAgent();
  bool AgentAccepts(const std::string& device);
  static void AgentMethod(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                          const gchar* method, GVariant* parameters,
                          GDBusMethodInvocation* invocation, gpointer data);

  GDBusConnection* bus_;
  guint changed_id_ = 0;
  guint removed_id_ = 0;
  std::mutex mutex_;
  std::condition_variable changed_;
  std::string device_;
  std::string notify_;
  std::string write_;
  guint agent_id_ = 0;
  GDBusNodeInfo* agent_node_ = nullptr;
  bool connected_ = false;
  bool awaiting_ = false;
  std::atomic<bool> pairing_{false};
  std::deque<ledger_ble::Bytes> packets_;
  std::optional<ledger_ble::Error> failure_;
  size_t mtu_ = 20;
};

}  // namespace ledger_bluez
#endif  // VIZOR_LEDGER_BLUEZ_TRANSPORT_H_
