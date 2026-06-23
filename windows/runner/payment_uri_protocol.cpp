#include "payment_uri_protocol.h"

#include <windows.h>

#include <shellapi.h>

#include <algorithm>
#include <cwctype>
#include <string>

namespace {

constexpr wchar_t kProtocolKeyPath[] = L"Software\\Classes\\zcash";
constexpr wchar_t kProtocolCommandKeyPath[] =
    L"Software\\Classes\\zcash\\shell\\open\\command";

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

bool CreateCurrentUserKey(const wchar_t* path, RegistryKey* key) {
  return ::RegCreateKeyExW(HKEY_CURRENT_USER, path, 0, nullptr, 0,
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
  if (::RegGetValueW(HKEY_CURRENT_USER, kProtocolCommandKeyPath, nullptr,
                     RRF_RT_REG_SZ, &type, nullptr, &size) != ERROR_SUCCESS ||
      size == 0) {
    return L"";
  }

  std::wstring value(size / sizeof(wchar_t), L'\0');
  if (::RegGetValueW(HKEY_CURRENT_USER, kProtocolCommandKeyPath, nullptr,
                     RRF_RT_REG_SZ, &type, value.data(), &size) !=
      ERROR_SUCCESS) {
    return L"";
  }
  while (!value.empty() && value.back() == L'\0') {
    value.pop_back();
  }
  return value;
}

void NotifyAssociationChanged() {
  ::ShellChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

}  // namespace

void RegisterZcashProtocolHandler() {
  const std::wstring module_path = ModuleFileName();
  if (module_path.empty()) {
    return;
  }

  RegistryKey protocol_key;
  if (!CreateCurrentUserKey(kProtocolKeyPath, &protocol_key)) {
    return;
  }
  SetStringValue(protocol_key.value, nullptr, L"URL:Zcash Payment URI");
  SetStringValue(protocol_key.value, L"URL Protocol", L"");

  RegistryKey icon_key;
  if (CreateCurrentUserKey(L"Software\\Classes\\zcash\\DefaultIcon",
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

void UnregisterZcashProtocolHandler() {
  const std::wstring module_path = ToLower(ModuleFileName());
  const std::wstring command = ToLower(ReadDefaultCommand());
  if (module_path.empty() || command.find(module_path) == std::wstring::npos) {
    return;
  }

  ::RegDeleteTreeW(HKEY_CURRENT_USER, kProtocolKeyPath);
  NotifyAssociationChanged();
}

void RegisterZcashProtocolHandlerIfUnclaimed() {
  const std::wstring module_path = ToLower(ModuleFileName());
  if (module_path.empty()) {
    return;
  }
  // Only (re)register at startup when no handler is set yet, or when the
  // existing handler already points at this install. Registering on every
  // launch unconditionally would silently steal the zcash: handler back from
  // another wallet (or another Vizor channel) the user selected. Install and
  // update hooks still register unconditionally -- that is the intended moment
  // to claim the handler.
  const std::wstring command = ToLower(ReadDefaultCommand());
  if (!command.empty() && command.find(module_path) == std::wstring::npos) {
    return;
  }
  RegisterZcashProtocolHandler();
}
