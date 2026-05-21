#include "velopack_update.h"

#include <windows.h>

#include <Velopack.h>

#include <algorithm>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#ifndef VIZOR_UPDATE_GITHUB_REPO_URL
#define VIZOR_UPDATE_GITHUB_REPO_URL "https://github.com/chainapsis/zcash-wallet"
#endif

#ifndef VIZOR_UPDATE_PRERELEASE
#define VIZOR_UPDATE_PRERELEASE 1
#endif

namespace {

enum class UpdateStatus {
  kUnavailable,
  kIdle,
  kChecking,
  kNoUpdate,
  kAvailable,
  kDownloading,
  kReady,
  kApplying,
  kFailed,
};

struct ManagerDeleter {
  void operator()(vpkc_update_manager_t* value) const {
    if (value != nullptr) {
      vpkc_free_update_manager(value);
    }
  }
};

struct UpdateInfoDeleter {
  void operator()(vpkc_update_info_t* value) const {
    if (value != nullptr) {
      vpkc_free_update_info(value);
    }
  }
};

struct AssetDeleter {
  void operator()(vpkc_asset_t* value) const {
    if (value != nullptr) {
      vpkc_free_asset(value);
    }
  }
};

using ManagerPtr = std::unique_ptr<vpkc_update_manager_t, ManagerDeleter>;
using UpdateInfoPtr = std::unique_ptr<vpkc_update_info_t, UpdateInfoDeleter>;
using AssetPtr = std::unique_ptr<vpkc_asset_t, AssetDeleter>;

std::mutex g_update_mutex;
ManagerPtr g_manager;
UpdateInfoPtr g_update_info;
AssetPtr g_pending_asset;
UpdateStatus g_status = UpdateStatus::kIdle;
bool g_supported = true;
bool g_busy = false;
bool g_pending_restart = false;
int32_t g_download_progress = 0;
std::string g_current_version = FLUTTER_VERSION;
std::string g_app_id;
std::string g_available_version;
std::string g_message;

std::string TrimCString(std::string value) {
  const auto terminator = std::find(value.begin(), value.end(), '\0');
  value.erase(terminator, value.end());
  return value;
}

std::string LastVelopackError() {
  char small_buffer[2048] = {};
  const size_t required = vpkc_get_last_error(small_buffer, sizeof(small_buffer));
  if (required <= sizeof(small_buffer)) {
    return TrimCString(std::string(small_buffer, sizeof(small_buffer)));
  }

  std::vector<char> buffer(required, '\0');
  vpkc_get_last_error(buffer.data(), buffer.size());
  return TrimCString(std::string(buffer.data(), buffer.size()));
}

std::string CoalesceMessage(std::string message) {
  if (!message.empty()) {
    return message;
  }
  return "Velopack update operation failed.";
}

using ManagerStringReader =
    size_t (*)(vpkc_update_manager_t* manager, char* output, size_t length);

std::string ReadManagerString(vpkc_update_manager_t* manager,
                              ManagerStringReader reader) {
  const size_t required = reader(manager, nullptr, 0);
  if (required == 0) {
    return "";
  }

  std::vector<char> buffer(required, '\0');
  const size_t written = reader(manager, buffer.data(), buffer.size());
  if (written > buffer.size()) {
    buffer.assign(written, '\0');
    reader(manager, buffer.data(), buffer.size());
  }
  return TrimCString(std::string(buffer.data(), buffer.size()));
}

std::string AssetVersion(const vpkc_asset_t* asset) {
  if (asset == nullptr || asset->Version == nullptr) {
    return "";
  }
  return asset->Version;
}

std::string StatusName(UpdateStatus status) {
  switch (status) {
    case UpdateStatus::kUnavailable:
      return "unavailable";
    case UpdateStatus::kIdle:
      return "idle";
    case UpdateStatus::kChecking:
      return "checking";
    case UpdateStatus::kNoUpdate:
      return "noUpdate";
    case UpdateStatus::kAvailable:
      return "available";
    case UpdateStatus::kDownloading:
      return "downloading";
    case UpdateStatus::kReady:
      return "ready";
    case UpdateStatus::kApplying:
      return "applying";
    case UpdateStatus::kFailed:
      return "failed";
  }
  return "failed";
}

void SetUnavailableLocked(const std::string& message) {
  g_supported = false;
  g_status = UpdateStatus::kUnavailable;
  g_busy = false;
  g_pending_restart = false;
  g_download_progress = 0;
  g_message = CoalesceMessage(message);
}

void RefreshPendingRestartLocked() {
  if (!g_manager || g_busy) {
    return;
  }

  vpkc_asset_t* pending = nullptr;
  if (vpkc_update_pending_restart(g_manager.get(), &pending) && pending != nullptr) {
    g_pending_asset.reset(pending);
    g_pending_restart = true;
    g_available_version = AssetVersion(g_pending_asset.get());
    g_status = UpdateStatus::kReady;
    g_message.clear();
    return;
  }

  if (pending != nullptr) {
    vpkc_free_asset(pending);
  }
  g_pending_restart = g_status == UpdateStatus::kReady;
}

bool EnsureManagerLocked() {
  if (g_manager) {
    return true;
  }

  vpkc_update_source_t* source = vpkc_new_source_github(
      VIZOR_UPDATE_GITHUB_REPO_URL, nullptr, VIZOR_UPDATE_PRERELEASE != 0);
  if (source == nullptr) {
    SetUnavailableLocked(LastVelopackError());
    return false;
  }

  vpkc_update_options_t options = {};
  options.AllowVersionDowngrade = false;
  options.ExplicitChannel = nullptr;
  options.MaximumDeltasBeforeFallback = -1;

  vpkc_update_manager_t* manager = nullptr;
  const bool created =
      vpkc_new_update_manager_with_source(source, &options, nullptr, &manager);
  vpkc_free_source(source);

  if (!created || manager == nullptr) {
    SetUnavailableLocked(LastVelopackError());
    return false;
  }

  g_manager.reset(manager);
  g_supported = true;
  g_status = UpdateStatus::kIdle;
  g_message.clear();
  g_current_version =
      ReadManagerString(g_manager.get(), vpkc_get_current_version);
  if (g_current_version.empty()) {
    g_current_version = FLUTTER_VERSION;
  }
  g_app_id = ReadManagerString(g_manager.get(), vpkc_get_app_id);
  RefreshPendingRestartLocked();
  return true;
}

flutter::EncodableMap BuildStateMapLocked() {
  if (g_supported && EnsureManagerLocked()) {
    RefreshPendingRestartLocked();
  }

  flutter::EncodableMap map;
  map[flutter::EncodableValue("supported")] = flutter::EncodableValue(g_supported);
  map[flutter::EncodableValue("busy")] = flutter::EncodableValue(g_busy);
  map[flutter::EncodableValue("status")] =
      flutter::EncodableValue(StatusName(g_status));
  map[flutter::EncodableValue("currentVersion")] =
      flutter::EncodableValue(g_current_version);
  map[flutter::EncodableValue("appId")] = flutter::EncodableValue(g_app_id);
  map[flutter::EncodableValue("repoUrl")] =
      flutter::EncodableValue(std::string(VIZOR_UPDATE_GITHUB_REPO_URL));
  map[flutter::EncodableValue("availableVersion")] =
      flutter::EncodableValue(g_available_version);
  map[flutter::EncodableValue("downloadProgress")] =
      flutter::EncodableValue(g_download_progress);
  map[flutter::EncodableValue("pendingRestart")] =
      flutter::EncodableValue(g_pending_restart);
  map[flutter::EncodableValue("message")] = flutter::EncodableValue(g_message);
  return map;
}

flutter::EncodableValue BuildStateValue() {
  std::lock_guard<std::mutex> lock(g_update_mutex);
  return flutter::EncodableValue(BuildStateMapLocked());
}

void DownloadProgress(void* user_data, size_t progress) {
  std::lock_guard<std::mutex> lock(g_update_mutex);
  g_download_progress =
      static_cast<int32_t>(std::min<size_t>(progress, 100));
}

void StartCheckForUpdates() {
  vpkc_update_manager_t* manager = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_update_mutex);
    if (!EnsureManagerLocked() || g_busy) {
      return;
    }
    RefreshPendingRestartLocked();
    if (g_status == UpdateStatus::kReady) {
      return;
    }
    g_busy = true;
    g_status = UpdateStatus::kChecking;
    g_message.clear();
    g_download_progress = 0;
    manager = g_manager.get();
  }

  std::thread([manager]() {
    vpkc_update_info_t* update = nullptr;
    const vpkc_update_check_t check = vpkc_check_for_updates(manager, &update);
    std::string error;
    if (check == UPDATE_ERROR) {
      error = LastVelopackError();
    }

    std::lock_guard<std::mutex> lock(g_update_mutex);
    g_busy = false;
    if (check == UPDATE_AVAILABLE && update != nullptr) {
      g_update_info.reset(update);
      g_pending_asset.reset();
      g_pending_restart = false;
      g_available_version = AssetVersion(g_update_info->TargetFullRelease);
      g_status = UpdateStatus::kAvailable;
      g_message.clear();
      return;
    }

    if (update != nullptr) {
      vpkc_free_update_info(update);
    }

    if (check == UPDATE_ERROR) {
      g_status = UpdateStatus::kFailed;
      g_message = CoalesceMessage(error);
      return;
    }

    g_update_info.reset();
    g_available_version.clear();
    g_status = UpdateStatus::kNoUpdate;
    g_message.clear();
  }).detach();
}

void StartDownloadUpdate() {
  vpkc_update_manager_t* manager = nullptr;
  vpkc_update_info_t* update = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_update_mutex);
    if (!EnsureManagerLocked() || g_busy) {
      return;
    }
    if (!g_update_info) {
      g_status = UpdateStatus::kFailed;
      g_message = "No update is ready to download.";
      return;
    }
    g_busy = true;
    g_status = UpdateStatus::kDownloading;
    g_message.clear();
    g_download_progress = 0;
    manager = g_manager.get();
    update = g_update_info.get();
  }

  std::thread([manager, update]() {
    const bool downloaded =
        vpkc_download_updates(manager, update, DownloadProgress, nullptr);
    std::string error;
    if (!downloaded) {
      error = LastVelopackError();
    }

    vpkc_asset_t* pending = nullptr;
    const bool has_pending =
        downloaded && vpkc_update_pending_restart(manager, &pending);

    std::lock_guard<std::mutex> lock(g_update_mutex);
    g_busy = false;
    if (!downloaded) {
      if (pending != nullptr) {
        vpkc_free_asset(pending);
      }
      g_status = UpdateStatus::kFailed;
      g_message = CoalesceMessage(error);
      return;
    }

    if (has_pending && pending != nullptr) {
      g_pending_asset.reset(pending);
      g_available_version = AssetVersion(g_pending_asset.get());
    } else {
      if (pending != nullptr) {
        vpkc_free_asset(pending);
      }
      g_available_version = AssetVersion(g_update_info->TargetFullRelease);
    }
    g_download_progress = 100;
    g_pending_restart = true;
    g_status = UpdateStatus::kReady;
    g_message.clear();
  }).detach();
}

void StartApplyUpdateAndRestart() {
  vpkc_update_manager_t* manager = nullptr;
  vpkc_asset_t* asset = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_update_mutex);
    if (!EnsureManagerLocked() || g_busy) {
      return;
    }
    if (g_pending_asset) {
      asset = g_pending_asset.get();
    } else if (g_update_info && g_update_info->TargetFullRelease != nullptr) {
      asset = g_update_info->TargetFullRelease;
    }

    if (asset == nullptr) {
      g_status = UpdateStatus::kFailed;
      g_message = "No downloaded update is ready to apply.";
      return;
    }

    g_busy = true;
    g_status = UpdateStatus::kApplying;
    g_message.clear();
    manager = g_manager.get();
  }

  std::thread([manager, asset]() {
    const bool started =
        vpkc_wait_exit_then_apply_updates(manager, asset, false, true, nullptr, 0);
    if (started) {
      ::ExitProcess(0);
      return;
    }

    const std::string error = LastVelopackError();
    std::lock_guard<std::mutex> lock(g_update_mutex);
    g_busy = false;
    g_status = UpdateStatus::kFailed;
    g_message = CoalesceMessage(error);
  }).detach();
}

}  // namespace

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateVelopackUpdateChannel(flutter::BinaryMessenger* messenger) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "com.zcash.wallet/windows_update",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler([](const auto& call, auto result) {
    const std::string& method = call.method_name();
    if (method == "getState") {
      result->Success(BuildStateValue());
      return;
    }
    if (method == "checkForUpdates") {
      StartCheckForUpdates();
      result->Success(BuildStateValue());
      return;
    }
    if (method == "downloadUpdate") {
      StartDownloadUpdate();
      result->Success(BuildStateValue());
      return;
    }
    if (method == "applyUpdateAndRestart") {
      StartApplyUpdateAndRestart();
      result->Success(BuildStateValue());
      return;
    }

    result->NotImplemented();
  });

  return channel;
}
