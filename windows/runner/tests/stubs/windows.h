#ifndef VIZOR_TEST_WINDOWS_H_
#define VIZOR_TEST_WINDOWS_H_

#include <cstdint>

using DWORD = uint32_t;
using LSTATUS = int32_t;
using BYTE = unsigned char;
struct TestRegistryKey;
using HKEY = TestRegistryKey*;

extern HKEY HKEY_CURRENT_USER;
extern HKEY HKEY_CLASSES_ROOT;

constexpr DWORD MAX_PATH = 260;
constexpr LSTATUS ERROR_SUCCESS = 0;
constexpr LSTATUS ERROR_FILE_NOT_FOUND = 2;
constexpr LSTATUS ERROR_PATH_NOT_FOUND = 3;
constexpr LSTATUS ERROR_ACCESS_DENIED = 5;
constexpr LSTATUS ERROR_INVALID_NAME = 123;
constexpr LSTATUS ERROR_MORE_DATA = 234;
constexpr DWORD INVALID_FILE_ATTRIBUTES = 0xffffffff;
constexpr DWORD KEY_SET_VALUE = 2;
constexpr DWORD REG_SZ = 1;
constexpr DWORD RRF_RT_REG_SZ = 2;

DWORD GetModuleFileNameW(void*, wchar_t*, DWORD);
LSTATUS RegCloseKey(HKEY);
LSTATUS RegCreateKeyExW(HKEY, const wchar_t*, DWORD, wchar_t*, DWORD, DWORD,
                        void*, HKEY*, DWORD*);
LSTATUS RegSetValueExW(HKEY, const wchar_t*, DWORD, DWORD, const BYTE*, DWORD);
LSTATUS RegGetValueW(HKEY, const wchar_t*, const wchar_t*, DWORD, DWORD*, void*,
                     DWORD*);
LSTATUS RegDeleteTreeW(HKEY, const wchar_t*);
DWORD GetFileAttributesW(const wchar_t*);
DWORD GetLastError();

#endif
