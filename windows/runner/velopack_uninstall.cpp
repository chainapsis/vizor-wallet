#include "velopack_uninstall.h"

#include <windows.h>

#include <knownfolders.h>
#include <shlobj.h>
#include <shellapi.h>
#include <wincred.h>

#include <algorithm>
#include <cwchar>
#include <cwctype>
#include <filesystem>
#include <string>
#include <vector>

namespace {

constexpr wchar_t kVeloUninstallArg[] = L"--veloapp-uninstall";
constexpr wchar_t kSecureStoragePrefix[] =
    L"Vizor_VGhpcyBpcyB0aGUgcHJlZml4IGZv_";

std::wstring ToLower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t ch) { return static_cast<wchar_t>(towlower(ch)); });
  return value;
}

void DebugLog(const std::wstring& message) {
  ::OutputDebugStringW((L"[Vizor uninstall] " + message + L"\n").c_str());
}

bool HasVelopackUninstallArg() {
  int argc = 0;
  LPWSTR* argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return false;
  }

  bool found = false;
  for (int i = 1; i < argc; ++i) {
    if (std::wstring(argv[i]) == kVeloUninstallArg) {
      found = true;
      break;
    }
  }
  ::LocalFree(argv);
  return found;
}

std::wstring SanitizedDirectoryName(const std::wstring& raw) {
  std::wstring sanitized = raw;
  constexpr wchar_t kInvalidChars[] = L"<>:\"/\\|?*";
  for (auto& ch : sanitized) {
    if (wcschr(kInvalidChars, ch) != nullptr) {
      ch = L'_';
    }
  }

  while (!sanitized.empty() && iswspace(sanitized.back())) {
    sanitized.pop_back();
  }
  while (!sanitized.empty() && sanitized.back() == L'.') {
    sanitized.pop_back();
  }
  if (sanitized.length() > 255) {
    sanitized.resize(255);
  }
  return sanitized;
}

std::wstring QueryVersionString(void* info, const wchar_t* key) {
  const std::wstring cp1252_path =
      L"\\StringFileInfo\\040904e4\\" + std::wstring(key);
  const std::wstring unicode_path =
      L"\\StringFileInfo\\040904b0\\" + std::wstring(key);

  void* value = nullptr;
  UINT length = 0;
  if (::VerQueryValueW(info, cp1252_path.c_str(), &value, &length) != 0 &&
      value != nullptr) {
    return SanitizedDirectoryName(static_cast<const wchar_t*>(value));
  }
  if (::VerQueryValueW(info, unicode_path.c_str(), &value, &length) != 0 &&
      value != nullptr) {
    return SanitizedDirectoryName(static_cast<const wchar_t*>(value));
  }
  return L"";
}

std::wstring ModuleFileName() {
  std::wstring path(MAX_PATH, L'\0');
  DWORD length = 0;
  while (true) {
    length = ::GetModuleFileNameW(nullptr, path.data(),
                                  static_cast<DWORD>(path.size()));
    if (length == 0) {
      return L"";
    }
    if (length < path.size() - 1) {
      path.resize(length);
      return path;
    }
    path.resize(path.size() * 2);
  }
}

std::filesystem::path ApplicationSpecificSubdirectory() {
  const std::wstring module_path = ModuleFileName();
  if (module_path.empty()) {
    return {};
  }

  DWORD unused = 0;
  const DWORD info_size =
      ::GetFileVersionInfoSizeW(module_path.c_str(), &unused);
  std::wstring company_name;
  std::wstring product_name;
  if (info_size != 0) {
    std::vector<BYTE> info(info_size);
    if (::GetFileVersionInfoW(module_path.c_str(), 0, info_size,
                              info.data()) != 0) {
      company_name = QueryVersionString(info.data(), L"CompanyName");
      product_name = QueryVersionString(info.data(), L"ProductName");
    }
  }

  if (product_name.empty()) {
    product_name =
        SanitizedDirectoryName(std::filesystem::path(module_path).stem().wstring());
  }
  if (product_name.empty()) {
    return {};
  }

  return company_name.empty()
             ? std::filesystem::path(product_name)
             : std::filesystem::path(company_name) / product_name;
}

std::filesystem::path KnownFolderPath(const KNOWNFOLDERID& folder_id) {
  PWSTR raw_path = nullptr;
  const HRESULT result =
      ::SHGetKnownFolderPath(folder_id, KF_FLAG_DEFAULT, nullptr, &raw_path);
  if (FAILED(result) || raw_path == nullptr) {
    return {};
  }

  std::filesystem::path path(raw_path);
  ::CoTaskMemFree(raw_path);
  return path;
}

bool IsSafeChildPath(const std::filesystem::path& base,
                     const std::filesystem::path& target) {
  if (base.empty() || target.empty() || base == target) {
    return false;
  }

  const std::wstring base_text =
      ToLower(base.lexically_normal().wstring() + L"\\");
  const std::wstring target_text = ToLower(target.lexically_normal().wstring());
  return target_text.rfind(base_text, 0) == 0;
}

void RemoveDirectoryIfSafe(const std::filesystem::path& base,
                           const std::filesystem::path& relative_path) {
  if (relative_path.empty() || relative_path.is_absolute()) {
    DebugLog(L"refusing to delete invalid relative path");
    return;
  }

  const std::filesystem::path target = base / relative_path;
  if (!IsSafeChildPath(base, target)) {
    DebugLog(L"refusing to delete path outside app data root: " +
             target.wstring());
    return;
  }

  std::error_code exists_error;
  if (!std::filesystem::exists(target, exists_error)) {
    return;
  }

  std::error_code remove_error;
  std::filesystem::remove_all(target, remove_error);
  if (remove_error) {
    DebugLog(L"failed to delete " + target.wstring() + L": " +
             std::to_wstring(remove_error.value()));
  }
}

void DeleteLegacySecureStorageCredentials() {
  const std::wstring filter = std::wstring(kSecureStoragePrefix) + L"*";
  DWORD credential_count = 0;
  PCREDENTIALW* credentials = nullptr;
  if (::CredEnumerateW(filter.c_str(), 0, &credential_count, &credentials) !=
      0) {
    for (DWORD i = 0; i < credential_count; ++i) {
      ::CredDeleteW(credentials[i]->TargetName, CRED_TYPE_GENERIC, 0);
    }
    ::CredFree(credentials);
  } else if (::GetLastError() != ERROR_NOT_FOUND) {
    DebugLog(L"failed to enumerate legacy secure storage credentials");
  }

  const std::wstring key_target = L"key_" + std::wstring(kSecureStoragePrefix);
  if (::CredDeleteW(key_target.c_str(), CRED_TYPE_GENERIC, 0) == 0 &&
      ::GetLastError() != ERROR_NOT_FOUND) {
    DebugLog(L"failed to delete legacy secure storage encryption key");
  }
}

void DeleteUserData() {
  const std::filesystem::path app_subdir = ApplicationSpecificSubdirectory();
  if (app_subdir.empty()) {
    DebugLog(L"unable to resolve application support subdirectory");
    return;
  }

  RemoveDirectoryIfSafe(KnownFolderPath(FOLDERID_RoamingAppData), app_subdir);
  RemoveDirectoryIfSafe(KnownFolderPath(FOLDERID_LocalAppData), app_subdir);
  DeleteLegacySecureStorageCredentials();
}

}  // namespace

bool HandleVelopackUninstallHook() {
  if (!HasVelopackUninstallArg()) {
    return false;
  }

  DeleteUserData();
  return true;
}
