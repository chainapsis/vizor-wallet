#include "ledger_ble_handler.h"

#include <atomic>
#include <functional>
#include <memory>
#include <optional>
#include <system_error>
#include <thread>
#include <utility>

#include "ledger_bluez_transport.h"
#include "../../native/ledger/ble_operation_gate.h"

namespace {
using ledger_ble::Bytes;
using ledger_ble::Error;
using Action = std::function<FlValue*(GCancellable*)>;

struct ValueDeleter { void operator()(FlValue* value) const { if (value) fl_value_unref(value); } };
using Value = std::unique_ptr<FlValue, ValueDeleter>;

FlValue* Field(FlValue* map, const char* key) {
  return map && fl_value_get_type(map) == FL_VALUE_TYPE_MAP ? fl_value_lookup_string(map, key) : nullptr;
}

uint8_t Byte(FlValue* value) {
  if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_INT ||
      fl_value_get_int(value) < 0 || fl_value_get_int(value) > 255) {
    throw Error("unavailable", "Ledger APDU arguments are invalid.");
  }
  return static_cast<uint8_t>(fl_value_get_int(value));
}

Bytes Command(FlValue* value) {
  auto* data = Field(value, "data");
  Bytes bytes;
  if (data && fl_value_get_type(data) == FL_VALUE_TYPE_UINT8_LIST) {
    const auto* begin = fl_value_get_uint8_list(data);
    const auto size = fl_value_get_length(data);
    if (size) bytes.assign(begin, begin + size);
  } else if (data && fl_value_get_type(data) == FL_VALUE_TYPE_LIST) {
    for (size_t i = 0; i < fl_value_get_length(data); ++i) bytes.push_back(Byte(fl_value_get_list_value(data, i)));
  } else {
    throw Error("unavailable", "Ledger APDU data is invalid.");
  }
  if (bytes.size() > 255) throw Error("unavailable", "Ledger APDU data exceeds its length limit.");
  Bytes apdu = {Byte(Field(value, "cla")), Byte(Field(value, "ins")),
                Byte(Field(value, "p1")), Byte(Field(value, "p2")), static_cast<uint8_t>(bytes.size())};
  apdu.insert(apdu.end(), bytes.begin(), bytes.end());
  return apdu;
}

FlValue* AppValue(const ledger_ble::AppInfo& app) {
  auto* result = fl_value_new_map();
  fl_value_set_string_take(result, "name", fl_value_new_string(app.name.c_str()));
  fl_value_set_string_take(result, "version", fl_value_new_string(app.version.c_str()));
  return result;
}

void Reply(FlMethodCall* call, FlValue* value, const std::optional<Error>& error = {}) {
  if (!call) return;
  g_autoptr(GError) failure = nullptr;
  if (error) {
    fl_method_call_respond_error(call, error->code.c_str(), error->what(), nullptr, &failure);
  } else {
    fl_method_call_respond_success(call, value, &failure);
  }
  if (failure) g_warning("Ledger channel reply failed: %s", failure->message);
}

void Post(std::function<void()> callback) {
  // Always enqueue: g_main_context_invoke can execute inline on a worker when
  // that worker can acquire the context. Flutter channel replies must be on UI.
  g_idle_add_full(G_PRIORITY_DEFAULT, [](gpointer data) -> gboolean {
    (*static_cast<std::function<void()>*>(data))();
    return G_SOURCE_REMOVE;
  }, new std::function<void()>(std::move(callback)), [](gpointer data) {
    delete static_cast<std::function<void()>*>(data);
  });
}

class Handler : public std::enable_shared_from_this<Handler> {
 public:
  void Initialize(FlBinaryMessenger* messenger, GDBusConnection* bus = nullptr) {
    g_autoptr(GError) error = nullptr;
    bus_ = bus ? G_DBUS_CONNECTION(g_object_ref(bus)) : g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &error);
    if (bus_) {
      transport_ = std::make_unique<ledger_bluez::Transport>(bus_);
      transport_->SetPairingListener([weak = weak_from_this()](const std::string& code) {
        Post([weak, code] { if (const auto self = weak.lock()) self->EmitPairing(code); });
      });
    }
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    methods_ = fl_method_channel_new(messenger, "com.zcash.wallet/ledger_mobile", FL_METHOD_CODEC(codec));
    fl_method_channel_set_method_call_handler(methods_, [](FlMethodChannel*, FlMethodCall* call, gpointer data) {
      static_cast<Handler*>(data)->Handle(call);
    }, this, nullptr);
    events_ = fl_event_channel_new(messenger, "com.zcash.wallet/ledger_mobile/discovery", FL_METHOD_CODEC(codec));
    fl_event_channel_set_stream_handlers(events_,
        [](FlEventChannel*, FlValue*, gpointer data) -> FlMethodErrorResponse* {
          static_cast<Handler*>(data)->listening_ = true;
          return nullptr;
        },
        [](FlEventChannel*, FlValue*, gpointer data) -> FlMethodErrorResponse* {
          auto* self = static_cast<Handler*>(data);
          self->listening_ = false;
          self->StopDiscovery(nullptr);
          return nullptr;
        }, this, nullptr);
    connection_events_ = fl_event_channel_new(messenger, "com.zcash.wallet/ledger_mobile/connection", FL_METHOD_CODEC(codec));
    fl_event_channel_set_stream_handlers(connection_events_,
        [](FlEventChannel*, FlValue*, gpointer data) -> FlMethodErrorResponse* {
          static_cast<Handler*>(data)->listening_connection_ = true;
          return nullptr;
        },
        [](FlEventChannel*, FlValue*, gpointer data) -> FlMethodErrorResponse* {
          static_cast<Handler*>(data)->listening_connection_ = false;
          return nullptr;
        }, this, nullptr);
  }

  ~Handler() {
    g_clear_object(&cancel_);
    g_clear_object(&bus_);
    g_clear_object(&methods_);
    g_clear_object(&events_);
    g_clear_object(&connection_events_);
  }

  void Close() {
    closed_ = true;
    StopDiscovery(nullptr);
    Cancel();
    if (transport_) transport_->Close();
    fl_method_channel_set_method_call_handler(methods_, nullptr, nullptr, nullptr);
    fl_event_channel_set_stream_handlers(events_, nullptr, nullptr, nullptr, nullptr);
    fl_event_channel_set_stream_handlers(connection_events_, nullptr, nullptr, nullptr, nullptr);
    if (!gate_.busy() && transport_) {
      const auto self = shared_from_this();
      Run([self](GCancellable*) { self->transport_->Disconnect(); return fl_value_new_null(); }, nullptr, true);
    }
  }

 private:
  void Cancel() {
    gate_.Cancel();
    if (cancel_) g_cancellable_cancel(cancel_);
    if (transport_) transport_->Wake();
  }

  bool Run(Action action, FlMethodCall* call, bool drain = false) {
    if (!transport_) {
      Reply(call, nullptr, Error("unavailable", "Linux system D-Bus is unavailable. Check the Bluetooth service and try again."));
      return false;
    }
    const auto operation = gate_.Begin();
    if (!operation) {
      Reply(call, nullptr, Error("unavailable", "Wait for the previous Ledger Bluetooth request to finish, then try again."));
      return false;
    }
    g_clear_object(&cancel_);
    cancel_ = g_cancellable_new();
    auto* cancel = G_CANCELLABLE(g_object_ref(cancel_));
    if (call) g_object_ref(call);
    // No handler-level watchdog: every transport wait has its own deadline,
    // and a cap here would report a slow device review as a cancellation.
    const auto self = shared_from_this();
    auto work = [self, action = std::move(action), call, cancel, operation = *operation, drain] {
      FlValue* result = nullptr;
      std::optional<Error> error;
      std::optional<Error> cleanup_error;
      try {
        result = action(cancel);
        if (g_cancellable_is_cancelled(cancel)) throw Error("cancelled", "The Ledger Bluetooth request was cancelled.");
      } catch (const Error& failure) {
        error = failure;
      } catch (const std::exception&) {
        error = Error("unavailable", "Linux could not complete the Ledger Bluetooth request.");
      }
      if (error && !drain) {
        try { self->transport_->Disconnect(); } catch (const Error& failure) { cleanup_error = failure; }
      }
      g_object_unref(cancel);
      Post([self, call, result, operation, error, cleanup_error, drain] {
        Value value(result);
        const bool active = self->gate_.IsActive(operation);
        self->gate_.Finish(operation);
        if (!self->closed_) {
          const auto failure = !active ? std::optional<Error>(Error("cancelled", "The Ledger Bluetooth request was cancelled.")) : error;
          Reply(call, result, failure);
        }
        if (call) g_object_unref(call);
        if (drain) {
          if (error) g_warning("Ledger disconnect cleanup: %s", error->what());
          for (auto* waiter : self->disconnect_waiters_) {
            Reply(waiter, nullptr, cleanup_error ? cleanup_error : error);
            g_object_unref(waiter);
          }
          self->disconnect_waiters_.clear();
        } else if (!self->disconnect_waiters_.empty() || self->closed_) {
          // Do not acknowledge disconnect until the cancelled worker and the
          // physical connection have both drained.
          self->Run([self](GCancellable*) { self->transport_->Disconnect(); return fl_value_new_null(); }, nullptr, true);
        }
      });
    };
    try {
      std::thread(std::move(work)).detach();
    } catch (const std::system_error&) {
      gate_.Finish(*operation);
      g_object_unref(cancel);
      const Error error("unavailable", "Linux could not start the Ledger Bluetooth request. Try again.");
      Reply(call, nullptr, error);
      if (call) g_object_unref(call);
      for (auto* waiter : disconnect_waiters_) {
        Reply(waiter, nullptr, error);
        g_object_unref(waiter);
      }
      disconnect_waiters_.clear();
      return false;
    }
    return true;
  }

  void Emit(FlValue* value) {
    if (closed_ || !listening_ || !value) return;
    g_autoptr(GError) error = nullptr;
    if (!fl_event_channel_send(events_, value, nullptr, &error)) g_warning("Ledger discovery event failed: %s", error->message);
  }

  // Pairing progress for the connect in flight: the code to compare with the
  // Ledger, then the end of that prompt.
  void EmitPairing(const std::string& code) {
    if (closed_ || !listening_connection_) return;
    Value event(fl_value_new_map());
    fl_value_set_string_take(event.get(), "type", fl_value_new_string(code.empty() ? "pairing_ended" : "pairing"));
    if (!code.empty()) fl_value_set_string_take(event.get(), "code", fl_value_new_string(code.c_str()));
    g_autoptr(GError) error = nullptr;
    if (!fl_event_channel_send(connection_events_, event.get(), nullptr, &error)) g_warning("Ledger connection event failed: %s", error->message);
  }

  void EmitError(const Error& error) {
    Value event(fl_value_new_map());
    fl_value_set_string_take(event.get(), "type", fl_value_new_string("error"));
    fl_value_set_string_take(event.get(), "code", fl_value_new_string(error.code.c_str()));
    fl_value_set_string_take(event.get(), "message", fl_value_new_string(error.what()));
    Emit(event.get());
  }

  void Poll() {
    if (!scanning_ || poll_in_flight_ || closed_) return;
    poll_in_flight_ = true;
    // A read-only discovery poll must not occupy the connection/signing gate.
    // Selecting a device can therefore connect immediately while this drains.
    using PollContext = std::pair<std::shared_ptr<Handler>, uint64_t>;
    g_dbus_connection_call(bus_, "org.bluez", "/", "org.freedesktop.DBus.ObjectManager",
        "GetManagedObjects", nullptr, G_VARIANT_TYPE("(a{oa{sa{sv}}})"),
        G_DBUS_CALL_FLAGS_NO_AUTO_START, 3000, nullptr,
        [](GObject* source, GAsyncResult* result, gpointer data) {
      std::unique_ptr<PollContext> context(static_cast<PollContext*>(data));
      const auto& self = context->first;
      self->poll_in_flight_ = false;
      g_autoptr(GError) error = nullptr;
      ledger_bluez::Variant reply(g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error));
      if (self->closed_ || !self->scanning_ || context->second != self->scan_generation_) return;
      if (!reply) {
        self->EmitError(Error("unavailable", "Linux could not discover Bluetooth devices. Check the Bluetooth service and try again."));
        self->StopDiscovery(nullptr);
        return;
      }
      ledger_bluez::Variant objects(g_variant_get_child_value(reply.get(), 0));
      const auto devices = ledger_bluez::Transport::Devices(objects.get(), true);
      Value event(fl_value_new_map());
      Value list(fl_value_new_list());
      for (const auto& device : devices) {
        auto* item = fl_value_new_map();
        fl_value_set_string_take(item, "id", fl_value_new_string(device.id.c_str()));
        fl_value_set_string_take(item, "name", fl_value_new_string(device.name.c_str()));
        fl_value_set_string_take(item, "model", fl_value_new_string(device.model.c_str()));
        fl_value_append_take(list.get(), item);
      }
      fl_value_set_string_take(event.get(), "type", fl_value_new_string("devices"));
      fl_value_set_string_take(event.get(), "devices", list.release());
      self->Emit(event.get());
    }, new PollContext(shared_from_this(), scan_generation_));
  }

  void StopDiscovery(FlMethodCall* call) {
    scanning_ = false;
    ++scan_generation_;
    if (scan_timer_) g_source_remove(scan_timer_);
    if (scan_end_) g_source_remove(scan_end_);
    scan_timer_ = scan_end_ = 0;
    if (adapter_.empty() || !bus_) { Reply(call, nullptr); return; }
    const auto adapter = std::exchange(adapter_, {});
    if (call) g_object_ref(call);
    g_dbus_connection_call(bus_, "org.bluez", adapter.c_str(), "org.bluez.Adapter1", "StopDiscovery", nullptr,
        nullptr, G_DBUS_CALL_FLAGS_NO_AUTO_START, 3000, nullptr,
        [](GObject* source, GAsyncResult* result, gpointer data) {
          auto* call = static_cast<FlMethodCall*>(data);
          g_autoptr(GError) error = nullptr;
          ledger_bluez::Variant reply(g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error));
          if (error) {
            if (!call) g_warning("Ledger discovery cleanup: %s", error->message);
            Reply(call, nullptr, Error("unavailable", "Linux could not stop Bluetooth discovery. Try again."));
          }
          else Reply(call, nullptr);
          if (call) g_object_unref(call);
        }, call);
  }

  void Handle(FlMethodCall* call) {
    const std::string name = fl_method_call_get_name(call);
    auto* args = fl_method_call_get_args(call);
    const auto self = shared_from_this();
    try {
      if (name == "requestPermissions") {
        Run([self](GCancellable* cancel) { self->transport_->ReadyAdapter(cancel); return fl_value_new_bool(true); }, call);
      } else if (name == "startDiscovery") {
        if (scanning_) { Reply(call, nullptr); return; }
        const auto generation = scan_generation_ + 1;
        const bool started = Run([self, generation](GCancellable* cancel) {
          const auto adapter = self->transport_->ReadyAdapter(cancel);
          self->transport_->StartDiscovery(adapter, cancel);
          Post([self, adapter, generation] {
            self->adapter_ = adapter;
            if (self->closed_ || self->scan_generation_ != generation) { self->StopDiscovery(nullptr); return; }
            self->scanning_ = true;
            self->scan_timer_ = g_timeout_add(500, [](gpointer data) -> gboolean { static_cast<Handler*>(data)->Poll(); return G_SOURCE_CONTINUE; }, self.get());
            self->scan_end_ = g_timeout_add_seconds(15, [](gpointer data) -> gboolean {
              auto* self = static_cast<Handler*>(data);
              self->scan_end_ = 0;
              Value event(fl_value_new_map());
              fl_value_set_string_take(event.get(), "type", fl_value_new_string("ended"));
              self->Emit(event.get());
              self->StopDiscovery(nullptr);
              return G_SOURCE_REMOVE;
            }, self.get());
          });
          return fl_value_new_null();
        }, call);
        // Only a request that owns the gate may retire the previous scan.
        if (started) scan_generation_ = generation;
      } else if (name == "stopDiscovery") {
        StopDiscovery(call);
      } else if (name == "confirmPairing") {
        auto* accept = Field(args, "accept");
        if (!accept || fl_value_get_type(accept) != FL_VALUE_TYPE_BOOL) throw Error("unavailable", "Ledger pairing answer is invalid.");
        if (!transport_) throw Error("unavailable", "Linux system D-Bus is unavailable. Check the Bluetooth service and try again.");
        transport_->ConfirmPairing(fl_value_get_bool(accept));
        Reply(call, nullptr);
      } else if (name == "cancelSigning") {
        Cancel();
        Reply(call, nullptr);
      } else if (name == "disconnect") {
        StopDiscovery(nullptr);
        if (gate_.busy()) {
          Cancel();
          disconnect_waiters_.push_back(FL_METHOD_CALL(g_object_ref(call)));
        } else {
          Run([self](GCancellable*) { self->transport_->Disconnect(); return fl_value_new_null(); }, call);
        }
      } else if (name == "connect") {
        auto* value = Field(args, "deviceId");
        if (!value || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) throw Error("disconnected", "Select a Ledger before connecting.");
        const std::string id = fl_value_get_string(value);
        StopDiscovery(nullptr);
        Run([self, id](GCancellable* cancel) { self->transport_->Connect(id, cancel); return fl_value_new_null(); }, call);
      } else if (name == "currentApp") {
        Run([self](GCancellable* cancel) { return AppValue(self->transport_->CurrentApp(cancel)); }, call);
      } else if (name == "openZcashApp") {
        Run([self](GCancellable* cancel) { return AppValue(self->transport_->OpenZcash(cancel)); }, call);
      } else if (name == "exchangeUfvk") {
        const auto first = Command(Field(args, "first"));
        const auto continuation = Command(Field(args, "continuation"));
        Run([self, first, continuation](GCancellable* cancel) {
          Value responses(fl_value_new_list());
          auto response = self->transport_->Exchange(first, cancel);
          fl_value_append_take(responses.get(), fl_value_new_uint8_list(response.data(), response.size()));
          if (!ledger_ble::HasSuccessStatus(response) || response.size() < 4) return responses.release();
          const size_t expected = 2 + ledger_ble::ReadU16(response, 0);
          if (expected > 8192) return responses.release();
          size_t received = response.size() - 2;
          while (received < expected) {
            response = self->transport_->Exchange(continuation, cancel);
            fl_value_append_take(responses.get(), fl_value_new_uint8_list(response.data(), response.size()));
            if (!ledger_ble::HasSuccessStatus(response) || response.size() <= 2) break;
            received += response.size() - 2;
          }
          return responses.release();
        }, call);
      } else if (name == "exchangeApdus") {
        auto* list = Field(args, "commands");
        if (!list || fl_value_get_type(list) != FL_VALUE_TYPE_LIST || fl_value_get_length(list) == 0) throw Error("unavailable", "Ledger APDU list is invalid.");
        std::vector<Bytes> commands;
        for (size_t i = 0; i < fl_value_get_length(list); ++i) commands.push_back(Command(fl_value_get_list_value(list, i)));
        Run([self, commands](GCancellable* cancel) {
          Value responses(fl_value_new_list());
          for (const auto& command : commands) {
            const auto response = self->transport_->Exchange(command, cancel);
            fl_value_append_take(responses.get(), fl_value_new_uint8_list(response.data(), response.size()));
            if (!ledger_ble::HasSuccessStatus(response)) break;
          }
          return responses.release();
        }, call);
      } else {
        fl_method_call_respond_not_implemented(call, nullptr);
      }
    } catch (const Error& error) { Reply(call, nullptr, error); }
  }

  GDBusConnection* bus_ = nullptr;
  std::unique_ptr<ledger_bluez::Transport> transport_;
  FlMethodChannel* methods_ = nullptr;
  FlEventChannel* events_ = nullptr;
  FlEventChannel* connection_events_ = nullptr;
  bool listening_connection_ = false;
  GCancellable* cancel_ = nullptr;
  ledger_ble::OperationGate gate_;
  std::atomic<bool> closed_{false};
  bool listening_ = false;
  bool scanning_ = false;
  bool poll_in_flight_ = false;
  uint64_t scan_generation_ = 0;
  guint scan_timer_ = 0;
  guint scan_end_ = 0;
  std::string adapter_;
  std::vector<FlMethodCall*> disconnect_waiters_;
};
}  // namespace

namespace {
struct HandlerOwner : LedgerBleHandlerOwner {
  std::shared_ptr<Handler> handler;
  ~HandlerOwner() override { handler->Close(); }
};
}  // namespace

std::unique_ptr<LedgerBleHandlerOwner> create_ledger_ble_handler_for_testing(
    FlBinaryMessenger* messenger, GDBusConnection* bus) {
  auto owner = std::make_unique<HandlerOwner>();
  owner->handler = std::make_shared<Handler>();
  owner->handler->Initialize(messenger, bus);
  return owner;
}

void register_ledger_ble_handler(FlView* view) {
  auto handler = std::make_shared<Handler>();
  handler->Initialize(fl_engine_get_binary_messenger(fl_view_get_engine(view)));
  g_object_set_data_full(G_OBJECT(view), "vizor-ledger-ble", new std::shared_ptr<Handler>(handler), [](gpointer data) {
    auto* handler = static_cast<std::shared_ptr<Handler>*>(data);
    (*handler)->Close();
    delete handler;
  });
}
