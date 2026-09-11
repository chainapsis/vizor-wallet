// Exercises the production registration code against an in-memory registry.
// The stub Windows APIs never read or write the host registry or filesystem.
#include <windows.h>

#include <algorithm>
#include <cassert>
#include <cstring>
#include <iostream>
#include <map>
#include <set>
#include <string>

#include "../payment_uri_protocol.h"

struct TestRegistryKey {
  std::wstring path;
};

TestRegistryKey user_root, classes_root;
HKEY HKEY_CURRENT_USER = &user_root;
HKEY HKEY_CLASSES_ROOT = &classes_root;
std::wstring module_path = L"C:\\Vizor\\vizor.exe";
std::map<std::wstring, std::wstring> registry;
std::set<std::wstring> unreadable;
std::set<std::wstring> files;
std::set<std::wstring> deleted;
int writes = 0;

DWORD GetModuleFileNameW(void*, wchar_t* output, DWORD capacity) {
  const size_t length = std::min(module_path.size(), size_t(capacity - 1));
  module_path.copy(output, length);
  output[length] = L'\0';
  return static_cast<DWORD>(length);
}

LSTATUS RegCloseKey(HKEY key) {
  delete key;
  return ERROR_SUCCESS;
}

LSTATUS RegCreateKeyExW(HKEY root, const wchar_t* path, DWORD, wchar_t*, DWORD,
                        DWORD, void*, HKEY* key, DWORD*) {
  assert(root == HKEY_CURRENT_USER);
  *key = new TestRegistryKey{path};
  return ERROR_SUCCESS;
}

LSTATUS RegSetValueExW(HKEY key, const wchar_t* name, DWORD, DWORD,
                       const BYTE* value, DWORD size) {
  ++writes;
  if (name == nullptr) {
    registry[key->path] = std::wstring(
        reinterpret_cast<const wchar_t*>(value), size / sizeof(wchar_t) - 1);
  }
  return ERROR_SUCCESS;
}

LSTATUS RegGetValueW(HKEY root, const wchar_t* path, const wchar_t*, DWORD,
                     DWORD*, void* output, DWORD* size) {
  assert(root == HKEY_CLASSES_ROOT);
  const std::wstring absolute = std::wstring(L"Software\\Classes\\") + path;
  if (unreadable.count(absolute)) return ERROR_ACCESS_DENIED;
  const auto found = registry.find(absolute);
  if (found == registry.end()) return ERROR_FILE_NOT_FOUND;
  const DWORD needed = static_cast<DWORD>(
      (found->second.size() + 1) * sizeof(wchar_t));
  if (output == nullptr) {
    *size = needed;
    return ERROR_SUCCESS;
  }
  if (*size < needed) {
    *size = needed;
    return ERROR_MORE_DATA;
  }
  std::memcpy(output, found->second.c_str(), needed);
  *size = needed;
  return ERROR_SUCCESS;
}

LSTATUS RegDeleteTreeW(HKEY root, const wchar_t* path) {
  assert(root == HKEY_CURRENT_USER);
  deleted.insert(path);
  return ERROR_SUCCESS;
}

DWORD GetFileAttributesW(const wchar_t* path) {
  return files.count(path) ? 0 : INVALID_FILE_ATTRIBUTES;
}
DWORD GetLastError() { return ERROR_FILE_NOT_FOUND; }
void SHChangeNotify(long, unsigned int, const void*, const void*) {}

std::wstring SchemePath(const wchar_t* scheme) {
  return std::wstring(L"Software\\Classes\\") + scheme;
}
std::wstring CommandPath(const wchar_t* scheme) {
  return SchemePath(scheme) + L"\\shell\\open\\command";
}
std::wstring OurCommand() { return L"\"" + module_path + L"\" \"%1\""; }

void Reset() {
  registry.clear();
  unreadable.clear();
  files.clear();
  deleted.clear();
  writes = 0;
}

int main() {
  constexpr const wchar_t* schemes[] = {
      L"zcash", L"bitcoin", L"litecoin", L"ethereum", L"solana"};
  Reset();
  RegisterPaymentProtocolHandlersIfUnclaimed();
  for (const wchar_t* scheme : schemes) {
    assert(registry.at(CommandPath(scheme)) == OurCommand());
  }
  const int initial_writes = writes;
  RegisterPaymentProtocolHandlersIfUnclaimed();
  assert(writes == initial_writes);
  std::cout << "PASS: all schemes register, and normal startup does not rewrite them\n";

  for (const wchar_t* scheme : schemes) {
    Reset();
    const auto command_path = CommandPath(scheme);
    // The unquoted path deliberately contains spaces: it must remain owned.
    const std::wstring competitor = L"C:\\Program Files\\Other Wallet\\wallet.exe";
    const std::wstring command = competitor + L" \"%1\"";
    registry[command_path] = command;
    files.insert(competitor);
    RegisterPaymentProtocolHandlersIfUnclaimed();
    assert(registry.at(command_path) == command);
    UnregisterPaymentProtocolHandlers();
    assert(!deleted.count(SchemePath(scheme)));

    Reset();
    unreadable.insert(command_path);
    RegisterPaymentProtocolHandlersIfUnclaimed();
    assert(!registry.count(command_path));
    UnregisterPaymentProtocolHandlers();
    assert(!deleted.count(SchemePath(scheme)));

    Reset();
    registry[command_path] = L"\"C:\\RemovedWallet\\wallet.exe\" \"%1\"";
    RegisterPaymentProtocolHandlersIfUnclaimed();
    assert(registry.at(command_path) == OurCommand());
  }
  std::cout << "PASS: live and unreadable owners survive; dangling owners are repaired\n";

  Reset();
  const std::wstring competitor_command = L"\"C:\\OtherWallet\\wallet.exe\" \"%1\"";
  files.insert(L"C:\\OtherWallet\\wallet.exe");
  for (const wchar_t* scheme : schemes) {
    registry[CommandPath(scheme)] = competitor_command;
  }
  RegisterPaymentProtocolHandlers();
  assert(registry.at(CommandPath(L"zcash")) == OurCommand());
  for (const wchar_t* scheme : {L"bitcoin", L"litecoin", L"ethereum", L"solana"}) {
    assert(registry.at(CommandPath(scheme)) == competitor_command);
  }
  std::cout << "PASS: install keeps new schemes' other-wallet choices\n";

  Reset();
  RegisterPaymentProtocolHandlersIfUnclaimed();
  registry[CommandPath(L"ethereum")] = competitor_command;
  registry[CommandPath(L"solana")] = L"\"C:\\Wrapper\\wrapper.exe\" " + OurCommand();
  UnregisterPaymentProtocolHandlers();
  assert(deleted == std::set<std::wstring>({
      SchemePath(L"zcash"), SchemePath(L"bitcoin"), SchemePath(L"litecoin")}));
  std::cout << "PASS: uninstall removes only this install's effective handlers\n";
}
