#include "velopack_update.h"

#include <windows.h>

#include <bcrypt.h>
#include <wincrypt.h>
#include <winhttp.h>

#include <Velopack.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cwchar>
#include <cstring>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#ifndef VIZOR_UPDATE_GITHUB_REPO_URL
#define VIZOR_UPDATE_GITHUB_REPO_URL "https://github.com/chainapsis/vizor-wallet"
#endif

#ifndef VIZOR_UPDATE_FEED_PUBLIC_KEY_B64
#define VIZOR_UPDATE_FEED_PUBLIC_KEY_B64 ""
#endif

#ifndef VIZOR_UPDATE_RELEASE_BASE_URL
#define VIZOR_UPDATE_RELEASE_BASE_URL ""
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
std::mutex g_source_error_mutex;
std::string g_source_error;

void SetSourceError(std::string message) {
  std::lock_guard<std::mutex> lock(g_source_error_mutex);
  g_source_error = std::move(message);
}

std::string LastSourceOrVelopackError(std::string velopack_error) {
  if (!velopack_error.empty()) {
    return velopack_error;
  }

  std::lock_guard<std::mutex> lock(g_source_error_mutex);
  return g_source_error;
}

std::string TrimCString(std::string value) {
  const auto terminator = std::find(value.begin(), value.end(), '\0');
  value.erase(terminator, value.end());
  return value;
}

std::string TrimAsciiWhitespace(std::string value) {
  value.erase(value.begin(), std::find_if(value.begin(), value.end(), [](char c) {
                return !std::isspace(static_cast<unsigned char>(c));
              }));
  value.erase(std::find_if(value.rbegin(), value.rend(), [](char c) {
                return !std::isspace(static_cast<unsigned char>(c));
              }).base(),
              value.end());
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

std::wstring WideFromUtf8(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }

  const int size = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) {
    return std::wstring();
  }

  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::string UrlEncodePathSegment(const std::string& value) {
  std::ostringstream out;
  out << std::uppercase << std::hex;
  for (const unsigned char c : value) {
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' ||
        c == '~') {
      out << static_cast<char>(c);
    } else {
      out << '%' << static_cast<char>("0123456789ABCDEF"[c >> 4])
          << static_cast<char>("0123456789ABCDEF"[c & 0x0F]);
    }
  }
  return out.str();
}

std::string ReleaseBaseUrl() {
  std::string base_url = VIZOR_UPDATE_RELEASE_BASE_URL;
  if (base_url.empty()) {
    base_url = std::string(VIZOR_UPDATE_GITHUB_REPO_URL) +
               "/releases/latest/download";
  }
  while (!base_url.empty() && base_url.back() == '/') {
    base_url.pop_back();
  }
  return base_url;
}

std::string ReleaseAssetUrl(const std::string& file_name) {
  return ReleaseBaseUrl() + "/" + UrlEncodePathSegment(file_name);
}

std::vector<uint8_t> DecodeBase64(std::string value) {
  value = TrimAsciiWhitespace(std::move(value));
  if (value.empty()) {
    return {};
  }

  DWORD output_size = 0;
  if (!CryptStringToBinaryA(
          value.c_str(), static_cast<DWORD>(value.size()), CRYPT_STRING_BASE64,
          nullptr, &output_size, nullptr, nullptr)) {
    return {};
  }

  std::vector<uint8_t> output(output_size);
  if (!CryptStringToBinaryA(
          value.c_str(), static_cast<DWORD>(value.size()), CRYPT_STRING_BASE64,
          output.data(), &output_size, nullptr, nullptr)) {
    return {};
  }
  output.resize(output_size);
  return output;
}

std::vector<uint8_t> Sha256(const std::string& data) {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_HASH_HANDLE hash = nullptr;
  std::vector<uint8_t> result;

  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA256_ALGORITHM, nullptr,
                                  0) != 0) {
    return result;
  }

  DWORD object_length = 0;
  DWORD hash_length = 0;
  DWORD bytes_read = 0;
  if (BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH,
                        reinterpret_cast<PUCHAR>(&object_length),
                        sizeof(object_length), &bytes_read, 0) != 0 ||
      BCryptGetProperty(algorithm, BCRYPT_HASH_LENGTH,
                        reinterpret_cast<PUCHAR>(&hash_length),
                        sizeof(hash_length), &bytes_read, 0) != 0) {
    BCryptCloseAlgorithmProvider(algorithm, 0);
    return result;
  }

  std::vector<uint8_t> hash_object(object_length);
  result.assign(hash_length, 0);
  if (BCryptCreateHash(algorithm, &hash, hash_object.data(), object_length,
                       nullptr, 0, 0) != 0 ||
      BCryptHashData(hash, reinterpret_cast<PUCHAR>(
                               const_cast<char*>(data.data())),
                     static_cast<ULONG>(data.size()), 0) != 0 ||
      BCryptFinishHash(hash, result.data(), hash_length, 0) != 0) {
    result.clear();
  }

  if (hash != nullptr) {
    BCryptDestroyHash(hash);
  }
  BCryptCloseAlgorithmProvider(algorithm, 0);
  return result;
}

bool VerifyReleaseFeedSignature(const std::string& feed,
                                const std::string& signature_base64) {
  const std::vector<uint8_t> public_key =
      DecodeBase64(VIZOR_UPDATE_FEED_PUBLIC_KEY_B64);
  if (public_key.size() != 64) {
    SetSourceError("Signed update feed public key is not configured.");
    return false;
  }

  const std::vector<uint8_t> signature = DecodeBase64(signature_base64);
  if (signature.size() != 64) {
    SetSourceError("Signed update feed signature is missing or invalid.");
    return false;
  }

  const std::vector<uint8_t> hash = Sha256(feed);
  if (hash.size() != 32) {
    SetSourceError("Could not hash the signed update feed.");
    return false;
  }

  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_KEY_HANDLE key = nullptr;
  if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_ECDSA_P256_ALGORITHM,
                                  nullptr, 0) != 0) {
    SetSourceError("Could not initialize update feed signature verifier.");
    return false;
  }

  struct EcdsaP256PublicBlob {
    BCRYPT_ECCKEY_BLOB header;
    std::array<uint8_t, 32> x;
    std::array<uint8_t, 32> y;
  };

  EcdsaP256PublicBlob blob = {};
  blob.header.dwMagic = BCRYPT_ECDSA_PUBLIC_P256_MAGIC;
  blob.header.cbKey = 32;
  std::copy(public_key.begin(), public_key.begin() + 32, blob.x.begin());
  std::copy(public_key.begin() + 32, public_key.end(), blob.y.begin());

  bool verified = false;
  if (BCryptImportKeyPair(
          algorithm, nullptr, BCRYPT_ECCPUBLIC_BLOB, &key,
          reinterpret_cast<PUCHAR>(&blob), sizeof(blob), 0) == 0) {
    verified = BCryptVerifySignature(
                   key, nullptr,
                   const_cast<PUCHAR>(hash.data()),
                   static_cast<ULONG>(hash.size()),
                   const_cast<PUCHAR>(signature.data()),
                   static_cast<ULONG>(signature.size()), 0) == 0;
  }

  if (key != nullptr) {
    BCryptDestroyKey(key);
  }
  BCryptCloseAlgorithmProvider(algorithm, 0);

  if (!verified) {
    SetSourceError("Signed update feed verification failed.");
  }
  return verified;
}

struct HttpResponse {
  bool ok = false;
  std::string body;
};

bool CrackUrl(const std::string& url,
              std::wstring* scheme,
              std::wstring* host,
              INTERNET_PORT* port,
              std::wstring* path) {
  const std::wstring wide_url = WideFromUtf8(url);
  if (wide_url.empty()) {
    return false;
  }

  URL_COMPONENTS components = {};
  components.dwStructSize = sizeof(components);
  components.dwSchemeLength = static_cast<DWORD>(-1);
  components.dwHostNameLength = static_cast<DWORD>(-1);
  components.dwUrlPathLength = static_cast<DWORD>(-1);
  components.dwExtraInfoLength = static_cast<DWORD>(-1);

  if (!WinHttpCrackUrl(wide_url.c_str(), static_cast<DWORD>(wide_url.size()), 0,
                       &components)) {
    return false;
  }

  *scheme = std::wstring(components.lpszScheme, components.dwSchemeLength);
  *host = std::wstring(components.lpszHostName, components.dwHostNameLength);
  *port = components.nPort;
  *path = std::wstring(components.lpszUrlPath, components.dwUrlPathLength);
  if (components.dwExtraInfoLength > 0) {
    path->append(components.lpszExtraInfo, components.dwExtraInfoLength);
  }
  return !host->empty() && !path->empty();
}

bool QueryStatusOk(HINTERNET request) {
  DWORD status_code = 0;
  DWORD status_size = sizeof(status_code);
  if (!WinHttpQueryHeaders(request,
                           WINHTTP_QUERY_STATUS_CODE |
                               WINHTTP_QUERY_FLAG_NUMBER,
                           WINHTTP_HEADER_NAME_BY_INDEX, &status_code,
                           &status_size, WINHTTP_NO_HEADER_INDEX)) {
    return false;
  }
  return status_code >= 200 && status_code < 300;
}

uint64_t QueryContentLength(HINTERNET request) {
  wchar_t length_buffer[64] = {};
  DWORD length_size = sizeof(length_buffer);
  if (!WinHttpQueryHeaders(request, WINHTTP_QUERY_CONTENT_LENGTH,
                           WINHTTP_HEADER_NAME_BY_INDEX, length_buffer,
                           &length_size, WINHTTP_NO_HEADER_INDEX)) {
    return 0;
  }
  return std::wcstoull(length_buffer, nullptr, 10);
}

template <typename ChunkWriter>
bool HttpGetStream(const std::string& url, ChunkWriter writer) {
  std::wstring scheme;
  std::wstring host;
  std::wstring path;
  INTERNET_PORT port = 0;
  if (!CrackUrl(url, &scheme, &host, &port, &path)) {
    SetSourceError("Could not parse update URL.");
    return false;
  }

  const bool secure = scheme == L"https";
  HINTERNET session = WinHttpOpen(
      L"Vizor Update/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
      WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
  if (session == nullptr) {
    SetSourceError("Could not initialize update HTTP client.");
    return false;
  }

  HINTERNET connection =
      WinHttpConnect(session, host.c_str(), port, 0);
  if (connection == nullptr) {
    WinHttpCloseHandle(session);
    SetSourceError("Could not connect to update host.");
    return false;
  }

  HINTERNET request = WinHttpOpenRequest(
      connection, L"GET", path.c_str(), nullptr, WINHTTP_NO_REFERER,
      WINHTTP_DEFAULT_ACCEPT_TYPES, secure ? WINHTTP_FLAG_SECURE : 0);
  if (request == nullptr) {
    WinHttpCloseHandle(connection);
    WinHttpCloseHandle(session);
    SetSourceError("Could not create update HTTP request.");
    return false;
  }

  DWORD redirect_policy = WINHTTP_OPTION_REDIRECT_POLICY_ALWAYS;
  WinHttpSetOption(request, WINHTTP_OPTION_REDIRECT_POLICY, &redirect_policy,
                   sizeof(redirect_policy));

  const wchar_t* headers = L"Accept: application/octet-stream\r\n";
  bool ok = WinHttpSendRequest(
                request, headers, static_cast<DWORD>(-1), WINHTTP_NO_REQUEST_DATA,
                0, 0, 0) &&
            WinHttpReceiveResponse(request, nullptr) && QueryStatusOk(request);

  const uint64_t total = ok ? QueryContentLength(request) : 0;
  uint64_t received = 0;
  if (ok) {
    std::array<uint8_t, 64 * 1024> buffer;
    while (true) {
      DWORD available = 0;
      if (!WinHttpQueryDataAvailable(request, &available)) {
        ok = false;
        break;
      }
      if (available == 0) {
        break;
      }

      while (available > 0) {
        const DWORD to_read =
            std::min<DWORD>(available, static_cast<DWORD>(buffer.size()));
        DWORD read = 0;
        if (!WinHttpReadData(request, buffer.data(), to_read, &read)) {
          ok = false;
          break;
        }
        if (read == 0) {
          available = 0;
          break;
        }
        received += read;
        if (!writer(buffer.data(), read, received, total)) {
          ok = false;
          break;
        }
        available -= read;
      }
      if (!ok) {
        break;
      }
    }
  }

  WinHttpCloseHandle(request);
  WinHttpCloseHandle(connection);
  WinHttpCloseHandle(session);

  if (!ok) {
    SetSourceError("Could not download update data.");
  }
  return ok;
}

bool HttpGetString(const std::string& url, std::string* body) {
  body->clear();
  return HttpGetStream(url, [body](const uint8_t* data, DWORD size,
                                   uint64_t received, uint64_t total) {
    body->append(reinterpret_cast<const char*>(data), size);
    return true;
  });
}

bool HttpDownloadFile(const std::string& url,
                      const std::string& local_path,
                      size_t progress_callback_id) {
  FILE* file = nullptr;
  const std::wstring wide_path = WideFromUtf8(local_path);
  if (wide_path.empty() ||
      _wfopen_s(&file, wide_path.c_str(), L"wb") != 0 ||
      file == nullptr) {
    SetSourceError("Could not open update package destination.");
    return false;
  }

  int16_t last_progress = -1;
  const bool ok = HttpGetStream(
      url, [file, progress_callback_id, &last_progress](
               const uint8_t* data, DWORD size, uint64_t received,
               uint64_t total) {
        if (std::fwrite(data, 1, size, file) != size) {
          SetSourceError("Could not write update package.");
          return false;
        }
        if (total > 0) {
          const int16_t progress = static_cast<int16_t>(
              std::min<uint64_t>((received * 100) / total, 100));
          if (progress != last_progress) {
            vpkc_source_report_progress(progress_callback_id, progress);
            last_progress = progress;
          }
        }
        return true;
      });

  std::fclose(file);
  if (!ok) {
    DeleteFileW(wide_path.c_str());
  }
  return ok;
}

char* SignedReleaseFeedCallback(void* user_data,
                                const char* releases_name) {
  if (releases_name == nullptr || std::strlen(releases_name) == 0) {
    SetSourceError("Velopack did not request a release feed name.");
    return nullptr;
  }

  const std::string feed_url = ReleaseAssetUrl(releases_name);
  const std::string signature_url = feed_url + ".sig";

  std::string feed;
  std::string signature;
  if (!HttpGetString(feed_url, &feed) ||
      !HttpGetString(signature_url, &signature)) {
    return nullptr;
  }

  if (!VerifyReleaseFeedSignature(feed, signature)) {
    return nullptr;
  }

  char* result = static_cast<char*>(std::malloc(feed.size() + 1));
  if (result == nullptr) {
    SetSourceError("Could not allocate update release feed.");
    return nullptr;
  }
  std::memcpy(result, feed.data(), feed.size());
  result[feed.size()] = '\0';
  SetSourceError("");
  return result;
}

void FreeSignedReleaseFeedCallback(void* user_data, char* feed) {
  std::free(feed);
}

bool SignedDownloadAssetCallback(void* user_data,
                                 const vpkc_asset_t* asset,
                                 const char* local_path,
                                 size_t progress_callback_id) {
  if (asset == nullptr || asset->FileName == nullptr ||
      std::strlen(asset->FileName) == 0 || local_path == nullptr) {
    SetSourceError("Velopack did not provide an update package filename.");
    return false;
  }

  return HttpDownloadFile(ReleaseAssetUrl(asset->FileName), local_path,
                          progress_callback_id);
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

  if (DecodeBase64(VIZOR_UPDATE_FEED_PUBLIC_KEY_B64).size() != 64) {
    SetUnavailableLocked("Signed update feed public key is not configured.");
    return false;
  }

  vpkc_update_source_t* source = vpkc_new_source_custom_callback(
      SignedReleaseFeedCallback, FreeSignedReleaseFeedCallback,
      SignedDownloadAssetCallback, nullptr);
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
      g_message = CoalesceMessage(LastSourceOrVelopackError(error));
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
      g_message = CoalesceMessage(LastSourceOrVelopackError(error));
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
