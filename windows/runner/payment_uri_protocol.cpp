#include "payment_uri_protocol.h"

#include <windows.h>

#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <cwctype>
#include <string>

namespace {

constexpr wchar_t kProtocolKeyPath[] = L"Software\\Classes\\zcash";
constexpr wchar_t kProtocolCommandKeyPath[] =
    L"Software\\Classes\\zcash\\shell\\open\\command";
constexpr wchar_t kEffectiveProtocolCommandKeyPath[] =
    L"zcash\\shell\\open\\command";

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

// Whether the effective zcash: shell open command could be read, and if so
// whether one exists at all. Any failure we cannot attribute to "there is no
// registration" is kUnreadable: a REG_EXPAND_SZ whose expansion needs a
// second pass, a value of an unexpected type, a key an ACL keeps us out of.
// Callers must read kUnreadable as "somebody owns the scheme" -- reporting it
// as absent is how a failed read ends up overwriting another wallet's handler.
enum class DefaultCommandState {
  kAbsent,
  kPresent,
  kUnreadable,
};

// Reads the effective zcash: shell open command into |command|, which is left
// empty unless kPresent is returned. Only ERROR_FILE_NOT_FOUND -- no key, or
// no default value under it -- counts as kAbsent.
DefaultCommandState ReadDefaultCommand(std::wstring* command) {
  command->clear();

  DWORD size = 0;
  LSTATUS status =
      ::RegGetValueW(HKEY_CLASSES_ROOT, kEffectiveProtocolCommandKeyPath,
                     nullptr, RRF_RT_REG_SZ, nullptr, nullptr, &size);
  if (status == ERROR_FILE_NOT_FOUND) {
    return DefaultCommandState::kAbsent;
  }
  if (status != ERROR_SUCCESS) {
    return DefaultCommandState::kUnreadable;
  }

  // RRF_RT_REG_SZ expands a REG_EXPAND_SZ value into the caller's buffer, and
  // the size reported by the query above does not account for that expansion,
  // so the read itself can come back ERROR_MORE_DATA asking for more room.
  // Retry with the size the API reports, bounded, and only while that
  // requirement actually grows, so a value that keeps asking for more cannot
  // spin here.
  constexpr int kMaxReadAttempts = 4;
  for (int attempt = 0; attempt < kMaxReadAttempts; ++attempt) {
    std::wstring value(size / sizeof(wchar_t) + 1, L'\0');
    const DWORD capacity_bytes =
        static_cast<DWORD>(value.size() * sizeof(wchar_t));
    DWORD read_bytes = capacity_bytes;
    status =
        ::RegGetValueW(HKEY_CLASSES_ROOT, kEffectiveProtocolCommandKeyPath,
                       nullptr, RRF_RT_REG_SZ, nullptr, value.data(),
                       &read_bytes);
    if (status == ERROR_SUCCESS) {
      const size_t written = static_cast<size_t>(read_bytes) / sizeof(wchar_t);
      if (written < value.size()) {
        value.resize(written);
      }
      while (!value.empty() && value.back() == L'\0') {
        value.pop_back();
      }
      *command = std::move(value);
      return DefaultCommandState::kPresent;
    }
    if (status == ERROR_FILE_NOT_FOUND) {
      return DefaultCommandState::kAbsent;
    }
    if (status != ERROR_MORE_DATA || read_bytes <= capacity_bytes) {
      return DefaultCommandState::kUnreadable;
    }
    size = read_bytes;
  }
  return DefaultCommandState::kUnreadable;
}

// Extracts the executable from a shell open command the way the shell reads
// it: a command whose executable is quoted -- "C:\Vizor\vizor.exe" "%1" --
// yields the quoted token, and an unquoted one -- C:\Apps\Zashi\zashi.exe
// "%1" -- yields the token up to the first whitespace. Taking the first quoted
// token unconditionally used to parse the unquoted form as %1, which is not a
// rooted path, so an installed competitor read as "cannot tell" instead of
// "still there". Returns an empty string when neither form yields a token,
// which callers read as "assume the handler exists".
std::wstring CommandExecutable(const std::wstring& command) {
  constexpr wchar_t kWhitespace[] = L" \t";
  const std::wstring::size_type start = command.find_first_not_of(kWhitespace);
  if (start == std::wstring::npos) {
    return L"";
  }

  if (command[start] == L'"') {
    const std::wstring::size_type close_quote = command.find(L'"', start + 1);
    if (close_quote == std::wstring::npos || close_quote == start + 1) {
      return L"";
    }
    return command.substr(start + 1, close_quote - start - 1);
  }

  const std::wstring::size_type end = command.find_first_of(kWhitespace, start);
  if (end == std::wstring::npos) {
    return command.substr(start);
  }
  return command.substr(start, end - start);
}

// Returns whether |value| is a rooted path -- a drive-qualified path such as
// C:\Vizor\vizor.exe or a UNC path such as \\server\share\vizor.exe. A bare
// or relative token (vizor.exe, .\vizor.exe) is resolved against PATH and the
// working directory, which we cannot reproduce here, so it is not one.
bool IsAbsoluteWindowsPath(const std::wstring& value) {
  if (value.size() >= 2u && value[0] == L'\\' && value[1] == L'\\') {
    return true;
  }
  return value.size() >= 3u && value[1] == L':' &&
         (value[2] == L'\\' || value[2] == L'/');
}

// Returns whether |command| still names an executable that exists. Only a
// rooted path that Windows reports as genuinely missing counts as gone:
// GetFileAttributesW must fail with ERROR_FILE_NOT_FOUND, ERROR_PATH_NOT_FOUND
// or ERROR_INVALID_NAME. Anything else -- a command we cannot parse, a
// PATH-relative token, a removable drive that is unplugged (ERROR_NOT_READY),
// an ACL-restricted directory (ERROR_ACCESS_DENIED), an unreachable UNC share
// (ERROR_BAD_NETPATH) -- is reported as existing. A handler that is merely
// unreachable right now is still the user's chosen handler, and stealing the
// zcash: scheme from it is not something the user can undo by plugging the
// drive back in.
bool CommandExecutableExists(const std::wstring& command) {
  const std::wstring executable = CommandExecutable(command);
  if (executable.empty() || !IsAbsoluteWindowsPath(executable)) {
    return true;
  }
  if (::GetFileAttributesW(executable.c_str()) != INVALID_FILE_ATTRIBUTES) {
    return true;
  }
  const DWORD error = ::GetLastError();
  return error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND &&
         error != ERROR_INVALID_NAME;
}

void NotifyAssociationChanged() {
  ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
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
  if (module_path.empty()) {
    return;
  }
  // Delete only a registration we could actually read and that points at this
  // module. An unreadable command is not evidence the scheme is ours, so leave
  // it alone rather than tearing down a handler that may belong to someone
  // else.
  std::wstring command;
  if (ReadDefaultCommand(&command) != DefaultCommandState::kPresent) {
    return;
  }
  if (ToLower(command).find(module_path) == std::wstring::npos) {
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
  // Only claim the scheme at startup when nobody holds it, or when the handler
  // that holds it points at an executable that no longer exists. Registering on
  // every launch unconditionally would silently steal the zcash: handler back
  // from another wallet (or another Vizor channel) the user selected. Install
  // and update hooks still register unconditionally -- that is the intended
  // moment to claim the handler.
  std::wstring command;
  const DefaultCommandState state = ReadDefaultCommand(&command);
  // A read we could not complete says nothing about who owns the scheme, so
  // assume it is owned and write nothing. Treating a permissions error or an
  // ERROR_MORE_DATA expansion as "unclaimed" is what would let a plain launch
  // overwrite the handler another wallet is holding.
  if (state == DefaultCommandState::kUnreadable) {
    return;
  }
  if (state == DefaultCommandState::kPresent && !command.empty()) {
    // Already ours: return without writing. Rewriting the same four values and
    // firing SHChangeNotify on every launch is pure churn for an install that
    // owns the scheme.
    if (ToLower(command).find(module_path) != std::wstring::npos) {
      return;
    }
    // Someone else's handler, and it still exists -- leave it alone. A command
    // pointing at an executable that is gone is a dangling registration (a
    // moved or portable install), which nothing would ever repair, so treat it
    // as unclaimed and let this install take the scheme.
    if (CommandExecutableExists(command)) {
      return;
    }
  }
  RegisterZcashProtocolHandler();
}
