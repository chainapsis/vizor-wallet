#include "ledger_ble_handler.h"

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <functional>
#include <future>
#include <map>
#include <mutex>
#include <set>
#include <thread>
#include <utility>

#include "ledger_ble_operation_gate.h"
#include "ledger_ble_protocol.h"

namespace {
using namespace std::chrono_literals;
namespace bt = winrt::Windows::Devices::Bluetooth;
namespace adv = winrt::Windows::Devices::Bluetooth::Advertisement;
namespace gatt = winrt::Windows::Devices::Bluetooth::GenericAttributeProfile;
namespace devices = winrt::Windows::Devices::Enumeration;
namespace radios = winrt::Windows::Devices::Radios;
namespace streams = winrt::Windows::Storage::Streams;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;
using Result = flutter::MethodResult<Value>;
using ledger_ble::Bytes;
using ledger_ble::Error;

const Value* Field(const Value* value, const char* key) {
  if (!value) return nullptr;
  const auto* map = std::get_if<Map>(value);
  if (!map) return nullptr;
  const auto found = map->find(Value(key));
  return found == map->end() ? nullptr : &found->second;
}

uint8_t Byte(const Value* value) {
  int64_t number = -1;
  if (value) {
    if (const auto* integer = std::get_if<int32_t>(value)) number = *integer;
    if (const auto* integer = std::get_if<int64_t>(value)) number = *integer;
  }
  if (number < 0 || number > 255) {
    throw Error("unavailable", "Ledger APDU arguments are invalid.");
  }
  return static_cast<uint8_t>(number);
}

Bytes Command(const Value* value) {
  Bytes data;
  const auto* field = Field(value, "data");
  if (field) {
    if (const auto* bytes = std::get_if<Bytes>(field)) {
      data = *bytes;
    } else if (const auto* list = std::get_if<List>(field)) {
      for (const auto& item : *list) data.push_back(Byte(&item));
    } else {
      throw Error("unavailable", "Ledger APDU data is invalid.");
    }
  } else {
    throw Error("unavailable", "Ledger APDU data is missing.");
  }
  if (data.size() > 255) {
    throw Error("unavailable", "Ledger APDU data exceeds its length limit.");
  }
  Bytes command = {Byte(Field(value, "cla")), Byte(Field(value, "ins")),
                   Byte(Field(value, "p1")), Byte(Field(value, "p2")),
                   static_cast<uint8_t>(data.size())};
  command.insert(command.end(), data.begin(), data.end());
  return command;
}

Error WindowsError(const winrt::hresult_error& error) {
  if (error.code() == E_ACCESSDENIED) {
    return Error("permission_denied", "Allow Bluetooth access in Windows Settings, then try again.");
  }
  if (error.code() == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
    return Error("cancelled", "The Ledger Bluetooth request was cancelled.");
  }
  if (error.code() == HRESULT_FROM_WIN32(ERROR_DEVICE_NOT_CONNECTED)) {
    return Error("disconnected", "The Ledger disconnected. Reconnect and try again.");
  }
  return Error("unavailable", "Windows Bluetooth: " + winrt::to_string(error.message()));
}

void RequireGatt(gatt::GattCommunicationStatus status) {
  if (status == gatt::GattCommunicationStatus::Success) return;
  if (status == gatt::GattCommunicationStatus::AccessDenied) {
    throw Error("permission_denied", "Windows denied access to the Ledger. Check Bluetooth pairing and permissions.");
  }
  if (status == gatt::GattCommunicationStatus::Unreachable) {
    throw Error("disconnected", "The Ledger disconnected. Keep it nearby and unlocked, then reconnect.");
  }
  throw Error("unavailable", "Windows could not exchange Bluetooth data with the Ledger.");
}

Value AppValue(const ledger_ble::AppInfo& app) {
  return Value(Map{{Value("name"), Value(app.name)},
                   {Value("version"), Value(app.version)}});
}

struct Session {
  bt::BluetoothLEDevice device{nullptr};
  gatt::GattDeviceService service{nullptr};
  gatt::GattSession gatt_session{nullptr};
  gatt::GattCharacteristic notify{nullptr};
  gatt::GattCharacteristic write{nullptr};
  winrt::event_token notify_token{};
  winrt::event_token disconnect_token{};
  std::mutex mutex;
  std::condition_variable changed;
  std::deque<Bytes> packets;
  bool connected = true;
  bool awaiting = false;
  std::optional<Error> failure;
  size_t mtu = 20;

  void Close() noexcept {
    {
      std::lock_guard lock(mutex);
      connected = false;
      awaiting = false;
      packets.clear();
    }
    changed.notify_all();
    try { if (notify && notify_token.value != 0) notify.ValueChanged(notify_token); } catch (...) {}
    try { if (device && disconnect_token.value != 0) device.ConnectionStatusChanged(disconnect_token); } catch (...) {}
    try { if (gatt_session) gatt_session.MaintainConnection(false); } catch (...) {}
    try { if (service) service.Close(); } catch (...) {}
    try { if (device) device.Close(); } catch (...) {}
    write = nullptr;
    notify = nullptr;
    service = nullptr;
    gatt_session = nullptr;
    device = nullptr;
  }
};
}  // namespace

class LedgerBleHandler::Impl : public std::enable_shared_from_this<Impl> {
 public:
  explicit Impl(HWND window)
      : window_(window), dispatch_message_(RegisterWindowMessageW(L"Vizor.Ledger.Ble.Dispatch")) {}

  void Initialize(flutter::BinaryMessenger* messenger) {
    const auto weak = weak_from_this();
    methods_ = std::make_unique<flutter::MethodChannel<Value>>(
        messenger, "com.zcash.wallet/ledger_mobile", &flutter::StandardMethodCodec::GetInstance());
    methods_->SetMethodCallHandler([weak](const auto& call, auto result) {
      if (const auto self = weak.lock()) {
        self->Handle(call, std::move(result));
      } else {
        result->Error("unavailable", "Ledger Bluetooth has closed.");
      }
    });
    events_ = std::make_unique<flutter::EventChannel<Value>>(
        messenger, "com.zcash.wallet/ledger_mobile/discovery", &flutter::StandardMethodCodec::GetInstance());
    events_->SetStreamHandler(std::make_unique<flutter::StreamHandlerFunctions<Value>>(
        [weak](const Value*, std::unique_ptr<flutter::EventSink<Value>>&& sink)
            -> std::unique_ptr<flutter::StreamHandlerError<Value>> {
          if (const auto self = weak.lock()) self->sink_ = std::move(sink);
          return nullptr;
        },
        [weak](const Value*) -> std::unique_ptr<flutter::StreamHandlerError<Value>> {
          if (const auto self = weak.lock()) {
            self->StopDiscovery();
            self->sink_.reset();
          }
          return nullptr;
        }));
  }

  void Close() {
    StopDiscovery();
    Cancel("cancelled", "Ledger Bluetooth has closed.");
    closed_ = true;
    if (!gate_.busy()) CloseSession();
    sink_.reset();
    methods_->SetMethodCallHandler(nullptr);
    events_->SetStreamHandler(nullptr);
    methods_.reset();
    events_.reset();
    std::lock_guard lock(ui_mutex_);
    ui_queue_.clear();
  }

  bool HandleWindowMessage(UINT message, WPARAM wparam) {
    if (message == WM_TIMER && wparam == ScanTimer()) {
      StopDiscovery();
      Emit(Map{{Value("type"), Value("ended")}});
      return true;
    }
    if (message != dispatch_message_) return false;
    std::deque<std::function<void()>> tasks;
    {
      std::lock_guard lock(ui_mutex_);
      tasks.swap(ui_queue_);
    }
    for (auto& task : tasks) {
      try {
        task();
      } catch (const winrt::hresult_error& error) {
        const auto mapped = WindowsError(error);
        StopDiscovery();
        DiscoveryError(mapped.code.c_str(), mapped.what());
      }
    }
    return true;
  }

 private:
  using Operation = std::function<Value(uint64_t)>;
  struct Device {
    std::string id;
    std::string name;
    std::string model;
  };

  void Post(std::function<void()> task) {
    std::lock_guard lock(ui_mutex_);
    if (closed_) return;
    ui_queue_.push_back(std::move(task));
    if (!PostMessageW(window_, dispatch_message_, 0, 0)) ui_queue_.clear();
  }

  void Check(uint64_t operation) const {
    if (closed_ || !gate_.IsActive(operation)) {
      throw Error("cancelled", "The Ledger operation was cancelled.");
    }
  }

  template <typename Factory>
  auto BeginOnMain(Factory factory, uint64_t operation) {
    using T = decltype(factory());
    auto promise = std::make_shared<std::promise<T>>();
    auto future = promise->get_future();
    const auto weak = weak_from_this();
    Post([weak, promise, factory = std::move(factory), operation] {
      try {
        const auto self = weak.lock();
        if (!self) throw Error("cancelled", "Ledger Bluetooth has closed.");
        self->Check(operation);
        promise->set_value(factory());
      } catch (...) {
        promise->set_exception(std::current_exception());
      }
    });
    while (future.wait_for(25ms) != std::future_status::ready) Check(operation);
    Check(operation);
    return future.get();
  }

  template <typename Async>
  auto Await(Async async, uint64_t operation,
             std::chrono::milliseconds timeout = 30s) {
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    while (async.Status() == winrt::Windows::Foundation::AsyncStatus::Started) {
      if (closed_ || !gate_.IsActive(operation)) {
        async.Cancel();
        Check(operation);
      }
      if (std::chrono::steady_clock::now() >= deadline) {
        async.Cancel();
        throw Error("unavailable", "The Ledger Bluetooth request timed out. Reconnect and try again.");
      }
      std::this_thread::sleep_for(25ms);
    }
    Check(operation);
    auto value = [&] {
      try {
        return async.GetResults();
      } catch (const winrt::hresult_error& error) {
        throw WindowsError(error);
      }
    }();
    Check(operation);
    return value;
  }

  void Run(Operation action, std::unique_ptr<Result> result) {
    const auto operation = gate_.Begin();
    if (!operation) {
      result->Error("unavailable", "Finish or reject the pending request on your Ledger, then try again.");
      return;
    }
    active_result_ = std::move(result);
    const auto self = shared_from_this();
    try {
      std::thread([self, action = std::move(action), operation = *operation] {
        std::optional<Value> value;
        std::optional<Error> error;
        bool apartment_initialized = false;
        try {
          winrt::init_apartment(winrt::apartment_type::multi_threaded);
          apartment_initialized = true;
          self->Check(operation);
          value = action(operation);
          self->Check(operation);
        } catch (const Error& failure) {
          error = failure;
        } catch (const winrt::hresult_error& failure) {
          error = WindowsError(failure);
        } catch (const std::exception&) {
          error = Error("unavailable", "Windows could not complete the Ledger Bluetooth request.");
        }
        if (error || self->closed_) self->CloseSession();
        self->Post([self, operation, value = std::move(value), error = std::move(error)] {
          if (self->active_result_) {
            if (!self->gate_.IsActive(operation)) {
              self->active_result_->Error("cancelled", "The Ledger operation was cancelled.");
            } else if (error) {
              self->active_result_->Error(error->code, error->what());
            } else {
              self->active_result_->Success(*value);
            }
            self->active_result_.reset();
          }
          self->gate_.Finish(operation);
        });
        if (apartment_initialized) winrt::uninit_apartment();
      }).detach();
    } catch (const std::system_error&) {
      gate_.Finish(*operation);
      active_result_->Error("unavailable", "Windows could not start the Ledger Bluetooth request.");
      active_result_.reset();
    }
  }

  void Cancel(const char* code, const char* message) {
    gate_.Cancel();
    if (active_result_) {
      active_result_->Error(code, message);
      active_result_.reset();
    }
    std::shared_ptr<Session> session;
    {
      std::lock_guard lock(session_mutex_);
      session = session_;
    }
    if (session) session->changed.notify_all();
  }

  void Handle(const flutter::MethodCall<Value>& call, std::unique_ptr<Result> result) {
    try {
      const auto& name = call.method_name();
      if (name == "requestPermissions") {
        Run([this](uint64_t operation) {
          const auto adapter = Await(BeginOnMain([] { return bt::BluetoothAdapter::GetDefaultAsync(); }, operation), operation);
          if (!adapter || !adapter.IsLowEnergySupported()) {
            throw Error("unavailable", "Windows has no Bluetooth LE adapter. Connect a supported Bluetooth adapter, then try again.");
          }
          const auto radio = Await(adapter.GetRadioAsync(), operation);
          if (!radio || radio.State() != radios::RadioState::On) {
            throw Error("bluetooth_off", "Turn on Bluetooth in Windows Settings to find your Ledger.");
          }
          return Value(true);
        }, std::move(result));
      } else if (name == "startDiscovery") {
        StartDiscovery();
        result->Success();
      } else if (name == "stopDiscovery") {
        StopDiscovery();
        result->Success();
      } else if (name == "cancelSigning") {
        Cancel("cancelled", "The Ledger operation was cancelled.");
        result->Success();
      } else if (name == "disconnect") {
        Cancel("disconnected", "The Ledger disconnected. Reconnect and try again.");
        Run([this](uint64_t) { CloseSession(); return Value(); }, std::move(result));
      } else if (name == "connect") {
        const auto* id = Field(call.arguments(), "deviceId");
        if (!id || !std::holds_alternative<std::string>(*id) || std::get<std::string>(*id).empty()) {
          throw Error("disconnected", "Select a Ledger before connecting.");
        }
        const auto device_id = std::get<std::string>(*id);
        StopDiscovery();
        Run([this, device_id](uint64_t operation) {
          Connect(device_id, operation);
          return Value();
        }, std::move(result));
      } else if (name == "currentApp") {
        Run([this](uint64_t operation) { return AppValue(ReadApp(operation)); }, std::move(result));
      } else if (name == "openZcashApp") {
        Run([this](uint64_t operation) { return AppValue(OpenZcash(operation)); }, std::move(result));
      } else if (name == "exchangeUfvk") {
        auto first = Command(Field(call.arguments(), "first"));
        auto continuation = Command(Field(call.arguments(), "continuation"));
        Run([this, first = std::move(first), continuation = std::move(continuation)](uint64_t operation) {
          List responses;
          auto response = Exchange(first, operation);
          responses.emplace_back(response);
          if (!ledger_ble::HasSuccessStatus(response) || response.size() < 4) return Value(responses);
          const size_t expected = 2 + ledger_ble::ReadU16(response, 0);
          if (expected > 8192) return Value(responses);
          size_t received = response.size() - 2;
          while (received < expected) {
            response = Exchange(continuation, operation);
            responses.emplace_back(response);
            if (!ledger_ble::HasSuccessStatus(response) || response.size() <= 2) break;
            received += response.size() - 2;
          }
          return Value(responses);
        }, std::move(result));
      } else if (name == "exchangeApdus") {
        const auto* value = Field(call.arguments(), "commands");
        const auto* list = value ? std::get_if<List>(value) : nullptr;
        if (!list || list->empty()) throw Error("unavailable", "Ledger signing APDU list is empty or invalid.");
        std::vector<Bytes> commands;
        for (const auto& item : *list) commands.push_back(Command(&item));
        Run([this, commands = std::move(commands)](uint64_t operation) {
          List responses;
          for (const auto& command : commands) {
            auto response = Exchange(command, operation);
            responses.emplace_back(response);
            if (!ledger_ble::HasSuccessStatus(response)) break;
          }
          return Value(responses);
        }, std::move(result));
      } else {
        result->NotImplemented();
      }
    } catch (const Error& error) {
      result->Error(error.code, error.what());
    } catch (const winrt::hresult_error& error) {
      const auto mapped = WindowsError(error);
      result->Error(mapped.code, mapped.what());
    }
  }

  UINT_PTR ScanTimer() const { return reinterpret_cast<UINT_PTR>(this); }

  void StopDiscovery() noexcept {
    ++discovery_generation_;
    KillTimer(window_, ScanTimer());
    if (watcher_) {
      try { watcher_.Received(received_token_); } catch (...) {}
      try { watcher_.Stopped(stopped_token_); } catch (...) {}
      try { watcher_.Stop(); } catch (...) {}
      watcher_ = nullptr;
    }
    resolving_addresses_.clear();
  }

  void StartDiscovery() {
    StopDiscovery();
    devices_.clear();
    watcher_ = adv::BluetoothLEAdvertisementWatcher();
    watcher_.ScanningMode(adv::BluetoothLEScanningMode::Active);
    // Match any supported service below, not a combined OS filter that could
    // require one advertisement to contain every Ledger model's service UUID.
    const auto weak = weak_from_this();
    const auto generation = discovery_generation_;
    received_token_ = watcher_.Received([weak, generation](const auto&, const adv::BluetoothLEAdvertisementReceivedEventArgs& args) {
      const auto self = weak.lock();
      if (!self) return;
      for (const auto& uuid : args.Advertisement().ServiceUuids()) {
        for (const auto& spec : ledger_ble::kServices) {
          if (uuid != winrt::guid(spec.service)) continue;
          auto name = winrt::to_string(args.Advertisement().LocalName());
          if (name.empty()) name = spec.model;
          self->Post([weak, generation, address = args.BluetoothAddress(), address_type = args.BluetoothAddressType(), name, model = std::string(spec.model)] {
            if (const auto owner = weak.lock()) owner->ResolveDevice(address, address_type, name, model, generation);
          });
          return;
        }
      }
    });
    stopped_token_ = watcher_.Stopped([weak, generation](const auto&, const adv::BluetoothLEAdvertisementWatcherStoppedEventArgs& args) {
      if (const auto self = weak.lock()) self->Post([weak, generation, error = args.Error()] {
        const auto owner = weak.lock();
        if (!owner || generation != owner->discovery_generation_) return;
        owner->StopDiscovery();
        if (error == bt::BluetoothError::Success) {
          owner->Emit(Map{{Value("type"), Value("ended")}});
        } else {
          const bool off = error == bt::BluetoothError::RadioNotAvailable || error == bt::BluetoothError::DisabledByUser;
          const bool denied = error == bt::BluetoothError::ConsentRequired || error == bt::BluetoothError::DisabledByPolicy;
          owner->DiscoveryError(off ? "bluetooth_off" : denied ? "permission_denied" : "unavailable",
              off ? "Turn on Bluetooth in Windows Settings to find your Ledger."
                  : denied ? "Allow Bluetooth access in Windows Settings."
                           : "Windows could not search for Ledger devices. Check your Bluetooth adapter.");
        }
      });
    });
    EmitDevices();
    watcher_.Start();
    SetTimer(window_, ScanTimer(), 15000, nullptr);
  }

  void ResolveDevice(uint64_t address, bt::BluetoothAddressType address_type,
                     const std::string& name, const std::string& model, uint64_t generation) {
    if (generation != discovery_generation_ || !resolving_addresses_.insert(address).second) return;
    const auto weak = weak_from_this();
    // Start device access on the platform/UI thread; Windows may ask for consent.
    auto operation = bt::BluetoothLEDevice::FromBluetoothAddressAsync(address, address_type);
    operation.Completed([weak, name, model, generation](const auto& completed, const auto&) {
      try {
        auto device = completed.GetResults();
        if (!device) return;
        const auto id = winrt::to_string(device.DeviceId());
        device.Close();
        if (const auto self = weak.lock()) self->Post([weak, id, name, model, generation] {
          const auto owner = weak.lock();
          if (!owner || generation != owner->discovery_generation_) return;
          owner->devices_[id] = Device{id, name, model};
          owner->EmitDevices();
        });
      } catch (const winrt::hresult_error& error) {
        const auto mapped = WindowsError(error);
        if (const auto self = weak.lock()) self->Post([weak, mapped, generation] {
          const auto owner = weak.lock();
          if (!owner || generation != owner->discovery_generation_) return;
          owner->StopDiscovery();
          owner->DiscoveryError(mapped.code.c_str(), mapped.what());
        });
      }
    });
  }

  void Emit(Map value) { if (sink_) sink_->Success(Value(std::move(value))); }
  void DiscoveryError(const char* code, const char* message) {
    Emit(Map{{Value("type"), Value("error")}, {Value("code"), Value(code)}, {Value("message"), Value(message)}});
  }
  void EmitDevices() {
    List devices;
    for (const auto& [id, device] : devices_) {
      devices.emplace_back(Map{{Value("id"), Value(id)}, {Value("name"), Value(device.name)}, {Value("model"), Value(device.model)}});
    }
    Emit(Map{{Value("type"), Value("devices")}, {Value("devices"), Value(devices)}});
  }

  std::shared_ptr<Session> CurrentSession() {
    std::lock_guard lock(session_mutex_);
    if (!session_) throw Error("disconnected", "Select and connect a Ledger first.");
    return session_;
  }

  void CloseSession() {
    std::shared_ptr<Session> session;
    {
      std::lock_guard lock(session_mutex_);
      session = std::exchange(session_, nullptr);
    }
    if (session) session->Close();
  }

  void Connect(const std::string& id, uint64_t operation) {
    Check(operation);
    CloseSession();
    auto session = std::make_shared<Session>();
    {
      std::lock_guard lock(session_mutex_);
      session_ = session;
    }
    session->device = Await(BeginOnMain([id] { return bt::BluetoothLEDevice::FromIdAsync(winrt::to_hstring(id)); }, operation), operation);
    if (!session->device) throw Error("disconnected", "Windows could not find that Ledger. Search again and select it.");
    const auto pairing = session->device.DeviceInformation().Pairing();
    if (!pairing.IsPaired()) {
      const auto paired = Await(BeginOnMain([pairing] {
        return pairing.PairAsync(devices::DevicePairingProtectionLevel::EncryptionAndAuthentication);
      }, operation), operation, 120s);
      if (paired.Status() != devices::DevicePairingResultStatus::Paired &&
          paired.Status() != devices::DevicePairingResultStatus::AlreadyPaired) {
        throw Error("pairing_rejected", "Ledger Bluetooth pairing was not completed. Confirm the matching code in Windows and on your Ledger, then try again.");
      }
    }
    session->gatt_session = Await(gatt::GattSession::FromDeviceIdAsync(session->device.BluetoothDeviceId()), operation);
    if (!session->gatt_session) throw Error("disconnected", "Windows could not open the Ledger Bluetooth session.");
    session->gatt_session.MaintainConnection(true);
    const auto services = Await(session->device.GetGattServicesAsync(bt::BluetoothCacheMode::Uncached), operation);
    RequireGatt(services.Status());
    const ledger_ble::ServiceSpec* profile = nullptr;
    for (const auto& service : services.Services()) {
      for (const auto& spec : ledger_ble::kServices) {
        if (service.Uuid() == winrt::guid(spec.service)) {
          session->service = service;
          profile = &spec;
          break;
        }
      }
      if (profile) break;
    }
    if (!profile) throw Error("unavailable", "This device does not expose a supported Ledger Bluetooth service.");
    auto notify = Await(session->service.GetCharacteristicsForUuidAsync(winrt::guid(profile->notify), bt::BluetoothCacheMode::Uncached), operation);
    auto write = Await(session->service.GetCharacteristicsForUuidAsync(winrt::guid(profile->write), bt::BluetoothCacheMode::Uncached), operation);
    RequireGatt(notify.Status());
    RequireGatt(write.Status());
    if (notify.Characteristics().Size() != 1 || write.Characteristics().Size() != 1) {
      throw Error("unavailable", "Ledger Bluetooth characteristics are missing.");
    }
    session->notify = notify.Characteristics().GetAt(0);
    session->write = write.Characteristics().GetAt(0);
    session->write.ProtectionLevel(gatt::GattProtectionLevel::EncryptionAndAuthenticationRequired);
    session->notify.ProtectionLevel(gatt::GattProtectionLevel::EncryptionAndAuthenticationRequired);
    const std::weak_ptr<Session> weak_session = session;
    session->notify_token = session->notify.ValueChanged([weak_session](const auto&, const gatt::GattValueChangedEventArgs& args) {
      const auto connected = weak_session.lock();
      if (!connected) return;
      try {
        const auto reader = streams::DataReader::FromBuffer(args.CharacteristicValue());
        const auto length = reader.UnconsumedBufferLength();
        if (length > 512) throw Error("unavailable", "Ledger Bluetooth packet exceeds its size limit.");
        Bytes packet(length);
        reader.ReadBytes(packet);
        {
          std::lock_guard lock(connected->mutex);
          if (!connected->connected || !connected->awaiting) return;
          if (connected->packets.size() >= 256) {
            connected->failure = Error("unavailable", "Ledger sent too many Bluetooth fragments.");
          } else {
            connected->packets.push_back(std::move(packet));
          }
        }
      } catch (const Error& error) {
        std::lock_guard lock(connected->mutex);
        connected->failure = error;
      } catch (const winrt::hresult_error& error) {
        std::lock_guard lock(connected->mutex);
        connected->failure = WindowsError(error);
      }
      connected->changed.notify_all();
    });
    session->disconnect_token = session->device.ConnectionStatusChanged([weak_session](const auto& device, const auto&) {
      if (device.ConnectionStatus() != bt::BluetoothConnectionStatus::Disconnected) return;
      if (const auto connected = weak_session.lock()) {
        {
          std::lock_guard lock(connected->mutex);
          connected->connected = false;
        }
        connected->changed.notify_all();
      }
    });
    RequireGatt(Await(session->notify.WriteClientCharacteristicConfigurationDescriptorAsync(
        gatt::GattClientCharacteristicConfigurationDescriptorValue::Notify), operation));
    // Ledger's MTU command reports the maximum ATT payload. Windows negotiates
    // its own ATT MTU, so use the smaller of the two advertised limits.
    session->mtu = ledger_ble::NegotiatedMtu(
        ExchangePackets(session, {{0x08, 0, 0, 0, 0}}, operation, true),
        session->gatt_session.MaxPduSize());
    Check(operation);
    connected_id_ = id;
  }

  Bytes ExchangePackets(const std::shared_ptr<Session>& session,
                        const std::vector<Bytes>& frames, uint64_t operation, bool mtu = false) {
    Check(operation);
    {
      std::lock_guard lock(session->mutex);
      if (!session->connected) throw Error("disconnected", "The Ledger disconnected. Reconnect and try again.");
      session->packets.clear();
      session->failure.reset();
      session->awaiting = true;
    }
    struct AwaitingGuard {
      std::shared_ptr<Session> session;
      ~AwaitingGuard() {
        std::lock_guard lock(session->mutex);
        session->awaiting = false;
        session->packets.clear();
      }
    } guard{session};
    for (const auto& frame : frames) {
      Check(operation);
      streams::DataWriter writer;
      writer.WriteBytes(frame);
      const auto result = Await(session->write.WriteValueWithResultAsync(
          writer.DetachBuffer(), gatt::GattWriteOption::WriteWithResponse), operation);
      RequireGatt(result.Status());
    }
    const auto deadline = std::chrono::steady_clock::now() + (mtu ? 10s : 300s);
    ledger_ble::ResponseAssembler assembler;
    for (;;) {
      Bytes packet;
      {
        std::unique_lock lock(session->mutex);
        if (!session->changed.wait_until(lock, deadline, [&] {
              return !session->packets.empty() || session->failure || !session->connected ||
                     closed_ || !gate_.IsActive(operation);
            })) {
          throw Error("unavailable", "Ledger did not respond. Finish or reject its pending request, then reconnect.");
        }
        Check(operation);
        if (session->failure) throw *session->failure;
        if (!session->connected) throw Error("disconnected", "The Ledger disconnected. Reconnect and try again.");
        packet = std::move(session->packets.front());
        session->packets.pop_front();
      }
      if (mtu) return packet;
      if (assembler.Add(packet)) return assembler.bytes();
    }
  }

  Bytes Exchange(const Bytes& command, uint64_t operation) {
    const auto session = CurrentSession();
    return ExchangePackets(session, ledger_ble::FrameApdu(command, session->mtu), operation);
  }

  ledger_ble::AppInfo ReadApp(uint64_t operation) {
    return ledger_ble::DecodeAppInfo(Exchange({0xb0, 0x01, 0, 0}, operation));
  }

  ledger_ble::AppInfo OpenZcash(uint64_t operation) {
    const auto id = connected_id_;
    if (id.empty()) throw Error("disconnected", "Connect a Ledger before opening Zcash.");
    try {
      ledger_ble::RequireSuccess(Exchange({0xe0, 0xd8, 0, 0, 5, 'Z', 'c', 'a', 's', 'h'}, operation));
    } catch (const Error& error) {
      Check(operation);
      if (error.code != "disconnected" && error.code != "device_busy") throw;
      if (error.code == "disconnected") CloseSession();
    }
    // Opening the app is sent exactly once. App switching may drop the link;
    // only reconnect and observe that same Windows device during recovery.
    const auto deadline = std::chrono::steady_clock::now() + 10s;
    while (std::chrono::steady_clock::now() < deadline) {
      Check(operation);
      try {
        bool connected = false;
        {
          std::lock_guard session_lock(session_mutex_);
          if (session_) {
            std::lock_guard lock(session_->mutex);
            connected = session_->connected;
          }
        }
        if (!connected) Connect(id, operation);
        const auto app = ReadApp(operation);
        if (app.name == "Zcash") return app;
      } catch (const Error& error) {
        if (error.code != "disconnected" && error.code != "device_busy") throw;
        if (error.code == "disconnected") CloseSession();
      }
      std::this_thread::sleep_for(200ms);
    }
    Check(operation);
    throw Error("unavailable", "Vizor could not resume after opening Zcash. Open Zcash on your Ledger and try again.");
  }

  HWND window_;
  UINT dispatch_message_;
  std::atomic<bool> closed_{false};
  std::mutex ui_mutex_;
  std::deque<std::function<void()>> ui_queue_;
  std::unique_ptr<flutter::MethodChannel<Value>> methods_;
  std::unique_ptr<flutter::EventChannel<Value>> events_;
  std::unique_ptr<flutter::EventSink<Value>> sink_;
  ledger_ble::OperationGate gate_;
  std::unique_ptr<Result> active_result_;
  std::mutex session_mutex_;
  std::shared_ptr<Session> session_;
  std::string connected_id_;
  adv::BluetoothLEAdvertisementWatcher watcher_{nullptr};
  winrt::event_token received_token_{};
  winrt::event_token stopped_token_{};
  uint64_t discovery_generation_ = 0;
  std::set<uint64_t> resolving_addresses_;
  std::map<std::string, Device> devices_;
};

LedgerBleHandler::LedgerBleHandler(HWND window, flutter::BinaryMessenger* messenger)
    : impl_(std::make_shared<Impl>(window)) {
  impl_->Initialize(messenger);
}

LedgerBleHandler::~LedgerBleHandler() { impl_->Close(); }

bool LedgerBleHandler::HandleWindowMessage(UINT message, WPARAM wparam) {
  return impl_->HandleWindowMessage(message, wparam);
}
