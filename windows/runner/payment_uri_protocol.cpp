#include "payment_uri_protocol.h"

#include <windows.h>

#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <cwctype>
#include <string>

namespace {

constexpr wchar_t kProtocolKeyPath[] = L"Software\\Classes\\vizor";
constexpr wchar_t kProtocolCommandKeyPath[] =
    L"Software\\Classes\\vizor\\shell\\open\\command";
constexpr wchar_t kEffectiveProtocolCommandKeyPath[] =
    L"vizor\\shell\\open\\command";

struct RegistryKey {
  HKEY value = nullptr;

  ~RegistryKey() {
    if (value != nullptr) {
      ::RegCloseKey(value);
    }
  }
};

std::wstring ToLower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t ch) { return static_cast<wchar_t>(towlower(ch)); });
  return value;
}

std::wstring ModuleFileName() {
  std::wstring file_name(MAX_PATH, L'\0');
  while (true) {
    const DWORD length = ::GetModuleFileNameW(
        nullptr, file_name.data(), static_cast<DWORD>(file_name.size()));
    if (length == 0) {
      return L"";
    }
    if (length < file_name.size() - 1) {
      file_name.resize(length);
      return file_name;
    }
    file_name.resize(file_name.size() * 2);
  }
}

bool CreateCurrentUserKey(const wchar_t* key_path, RegistryKey* key) {
  return ::RegCreateKeyExW(HKEY_CURRENT_USER, key_path, 0, nullptr, 0,
                           KEY_SET_VALUE, nullptr, &key->value,
                           nullptr) == ERROR_SUCCESS;
}

void SetStringValue(HKEY key, const wchar_t* name, const std::wstring& value) {
  ::RegSetValueExW(
      key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
}

std::wstring ReadDefaultCommand() {
  DWORD type = 0;
  DWORD size = 0;
  if (::RegGetValueW(HKEY_CLASSES_ROOT, kEffectiveProtocolCommandKeyPath,
                     nullptr, RRF_RT_REG_SZ, &type, nullptr, &size) !=
          ERROR_SUCCESS ||
      size == 0) {
    return L"";
  }

  std::wstring value(size / sizeof(wchar_t), L'\0');
  if (::RegGetValueW(HKEY_CLASSES_ROOT, kEffectiveProtocolCommandKeyPath,
                     nullptr, RRF_RT_REG_SZ, &type, value.data(), &size) !=
      ERROR_SUCCESS) {
    return L"";
  }
  while (!value.empty() && value.back() == L'\0') {
    value.pop_back();
  }
  return value;
}

void NotifyAssociationChanged() {
  ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

}  // namespace

void RegisterVizorProtocolHandler() {
  const std::wstring module_path = ModuleFileName();
  if (module_path.empty()) {
    return;
  }

  RegistryKey protocol_key;
  if (!CreateCurrentUserKey(kProtocolKeyPath, &protocol_key)) {
    return;
  }
  SetStringValue(protocol_key.value, nullptr, L"URL:Vizor Payment Link");
  SetStringValue(protocol_key.value, L"URL Protocol", L"");

  RegistryKey icon_key;
  if (CreateCurrentUserKey(L"Software\\Classes\\vizor\\DefaultIcon",
                           &icon_key)) {
    SetStringValue(icon_key.value, nullptr, L"\"" + module_path + L"\",0");
  }

  RegistryKey command_key;
  if (!CreateCurrentUserKey(kProtocolCommandKeyPath, &command_key)) {
    return;
  }
  SetStringValue(command_key.value, nullptr,
                 L"\"" + module_path + L"\" \"%1\"");
  NotifyAssociationChanged();
}

void RegisterVizorProtocolHandlerIfUnclaimed() {
  const std::wstring module_path = ToLower(ModuleFileName());
  if (module_path.empty()) {
    return;
  }
  const std::wstring command = ToLower(ReadDefaultCommand());
  if (!command.empty() && command.find(module_path) == std::wstring::npos) {
    return;
  }
  RegisterVizorProtocolHandler();
}

void UnregisterVizorProtocolHandler() {
  const std::wstring module_path = ToLower(ModuleFileName());
  const std::wstring command = ToLower(ReadDefaultCommand());
  if (module_path.empty() || command.find(module_path) == std::wstring::npos) {
    return;
  }
  ::RegDeleteTreeW(HKEY_CURRENT_USER, kProtocolKeyPath);
  NotifyAssociationChanged();
}
