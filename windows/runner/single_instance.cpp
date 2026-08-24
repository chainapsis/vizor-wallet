#include "single_instance.h"

#include <knownfolders.h>
#include <shlobj.h>

#include <cwchar>
#include <cwctype>
#include <filesystem>
#include <string>
#include <system_error>

#include "resource_values.h"
#include "utils.h"

namespace {

#ifndef VIZOR_WINDOWS_STORAGE_PREFIX
#define VIZOR_WINDOWS_STORAGE_PREFIX "Vizor"
#endif

#define VIZOR_WIDEN2(value) L##value
#define VIZOR_WIDEN(value) VIZOR_WIDEN2(value)

constexpr wchar_t kLockDirectoryName[] = L"VizorInstanceLocks";
constexpr DWORD kActivationRetryDelayMs = 50;
constexpr UINT kActivationMessageTimeoutMs = 100;

std::wstring SanitizedFileName(std::wstring value) {
  constexpr wchar_t kInvalidChars[] = L"<>:\"/\\|?*";
  for (auto& ch : value) {
    if (wcschr(kInvalidChars, ch) != nullptr || iswcntrl(ch)) {
      ch = L'_';
    }
  }
  while (!value.empty() &&
         (iswspace(value.back()) || value.back() == L'.')) {
    value.pop_back();
  }
  return value;
}

std::filesystem::path LocalAppDataPath() {
  PWSTR raw_path = nullptr;
  const HRESULT result = ::SHGetKnownFolderPath(
      FOLDERID_LocalAppData, KF_FLAG_DEFAULT, nullptr, &raw_path);
  if (FAILED(result) || raw_path == nullptr) {
    if (raw_path != nullptr) {
      ::CoTaskMemFree(raw_path);
    }
    return {};
  }

  std::filesystem::path path(raw_path);
  ::CoTaskMemFree(raw_path);
  return path;
}

std::filesystem::path LockFilePath(DWORD* error) {
  const std::filesystem::path local_app_data = LocalAppDataPath();
  if (local_app_data.empty()) {
    *error = ERROR_PATH_NOT_FOUND;
    return {};
  }

  std::wstring company_name = Utf16FromUtf8(VIZOR_WINDOWS_COMPANY_NAME);
  if (company_name.empty()) {
    company_name = L"com.keplr";
  }
  const std::wstring storage_prefix =
      SanitizedFileName(VIZOR_WIDEN(VIZOR_WINDOWS_STORAGE_PREFIX));
  if (storage_prefix.empty()) {
    *error = ERROR_INVALID_NAME;
    return {};
  }

  const std::filesystem::path lock_directory =
      local_app_data / company_name / kLockDirectoryName;
  std::error_code directory_error;
  std::filesystem::create_directories(lock_directory, directory_error);
  if (directory_error) {
    *error = static_cast<DWORD>(directory_error.value());
    return {};
  }

  *error = ERROR_SUCCESS;
  return lock_directory / (storage_prefix + L".lock");
}

std::wstring ActivationMessageName() {
  const std::wstring storage_prefix =
      SanitizedFileName(VIZOR_WIDEN(VIZOR_WINDOWS_STORAGE_PREFIX));
  if (storage_prefix.empty()) {
    return {};
  }
  return L"com.keplr.vizor." + storage_prefix + L".activate";
}

struct ActivationContext {
  UINT message = 0;
  bool acknowledged = false;
};

BOOL CALLBACK SendActivationMessage(HWND window, LPARAM parameter) {
  auto* context = reinterpret_cast<ActivationContext*>(parameter);
  if (context == nullptr || context->message == 0) {
    return FALSE;
  }

  DWORD_PTR response = 0;
  if (::SendMessageTimeoutW(
          window, context->message, 0, 0,
          SMTO_ABORTIFHUNG | SMTO_BLOCK, kActivationMessageTimeoutMs,
          &response) != 0 &&
      response ==
          static_cast<DWORD_PTR>(kSingleInstanceActivationAcknowledged)) {
    context->acknowledged = true;
    return FALSE;
  }
  return TRUE;
}

}  // namespace

SingleInstanceGuard::SingleInstanceGuard() = default;

SingleInstanceGuard::~SingleInstanceGuard() {
  if (lock_held_ && lock_file_ != INVALID_HANDLE_VALUE) {
    ::UnlockFileEx(lock_file_, 0, 1, 0, &lock_overlapped_);
  }
  if (lock_file_ != INVALID_HANDLE_VALUE) {
    ::CloseHandle(lock_file_);
  }
}

SingleInstanceAcquireResult SingleInstanceGuard::Acquire() {
  if (acquire_attempted_) {
    last_error_ = ERROR_ALREADY_INITIALIZED;
    return SingleInstanceAcquireResult::kError;
  }
  acquire_attempted_ = true;

  const std::wstring activation_name = ActivationMessageName();
  if (activation_name.empty()) {
    last_error_ = ERROR_INVALID_NAME;
    return SingleInstanceAcquireResult::kError;
  }
  activation_message_ = ::RegisterWindowMessageW(activation_name.c_str());
  if (activation_message_ == 0) {
    last_error_ = ::GetLastError();
    return SingleInstanceAcquireResult::kError;
  }

  DWORD path_error = ERROR_SUCCESS;
  const std::filesystem::path lock_path = LockFilePath(&path_error);
  if (lock_path.empty()) {
    last_error_ = path_error;
    return SingleInstanceAcquireResult::kError;
  }

  lock_file_ = ::CreateFileW(
      lock_path.c_str(), GENERIC_READ | GENERIC_WRITE,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
      FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_NOT_CONTENT_INDEXED, nullptr);
  if (lock_file_ == INVALID_HANDLE_VALUE) {
    last_error_ = ::GetLastError();
    return SingleInstanceAcquireResult::kError;
  }

  lock_overlapped_ = {};
  if (::LockFileEx(lock_file_,
                   LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0, 1,
                   0, &lock_overlapped_) != 0) {
    lock_held_ = true;
    last_error_ = ERROR_SUCCESS;
    return SingleInstanceAcquireResult::kPrimary;
  }

  last_error_ = ::GetLastError();
  ::CloseHandle(lock_file_);
  lock_file_ = INVALID_HANDLE_VALUE;
  if (last_error_ == ERROR_LOCK_VIOLATION ||
      last_error_ == ERROR_SHARING_VIOLATION) {
    return SingleInstanceAcquireResult::kSecondary;
  }
  return SingleInstanceAcquireResult::kError;
}

bool ActivateExistingInstance(UINT activation_message,
                              DWORD retry_window_ms) {
  if (activation_message == 0) {
    return false;
  }

  const ULONGLONG deadline = ::GetTickCount64() + retry_window_ms;
  do {
    ActivationContext context{activation_message, false};
    ::EnumWindows(SendActivationMessage,
                  reinterpret_cast<LPARAM>(&context));
    if (context.acknowledged) {
      return true;
    }
    ::Sleep(kActivationRetryDelayMs);
  } while (::GetTickCount64() < deadline);

  return false;
}
