#include "payment_uri_handoff.h"

#include <algorithm>
#include <cwctype>
#include <string>

#include "utils.h"

namespace {

constexpr wchar_t kFlutterWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr ULONG_PTR kPaymentLinkCopyDataId = 0x565A504C;  // "VZPL"
constexpr ULONGLONG kCleanLaunchForwardTimeoutMs = 15'000;

struct ScopedProcessInformation {
  PROCESS_INFORMATION value{};

  ~ScopedProcessInformation() {
    if (value.hThread != nullptr) {
      ::CloseHandle(value.hThread);
    }
    if (value.hProcess != nullptr) {
      ::CloseHandle(value.hProcess);
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

std::wstring ProcessImagePath(DWORD process_id) {
  HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE,
                                 process_id);
  if (process == nullptr) {
    return L"";
  }

  std::wstring image_path(MAX_PATH, L'\0');
  DWORD length = static_cast<DWORD>(image_path.size());
  while (true) {
    if (::QueryFullProcessImageNameW(process, 0, image_path.data(), &length)) {
      ::CloseHandle(process);
      image_path.resize(length);
      return image_path;
    }
    if (::GetLastError() != ERROR_INSUFFICIENT_BUFFER) {
      ::CloseHandle(process);
      return L"";
    }
    image_path.resize(image_path.size() * 2);
    length = static_cast<DWORD>(image_path.size());
  }
}

bool IsFlutterRunnerWindow(HWND window) {
  wchar_t class_name[256];
  const int length = ::GetClassNameW(window, class_name, 256);
  return length > 0 &&
         std::wstring(class_name, length) == kFlutterWindowClassName;
}

bool SendPaymentLink(HWND window, const std::string& uri) {
  if (!IsPaymentLinkUri(uri)) {
    return false;
  }
  COPYDATASTRUCT copy_data;
  copy_data.dwData = kPaymentLinkCopyDataId;
  copy_data.cbData = static_cast<DWORD>(uri.size() + 1);
  copy_data.lpData = const_cast<char*>(uri.c_str());
  DWORD_PTR result = 0;
  return ::SendMessageTimeoutW(window, WM_COPYDATA, 0,
                               reinterpret_cast<LPARAM>(&copy_data),
                               SMTO_ABORTIFHUNG, 3000, &result) != 0;
}

struct ForwardContext {
  std::wstring module_path;
  const std::vector<std::string>* uris;
  bool delivered = false;
};

bool SendAllPaymentLinks(HWND window,
                         const std::vector<std::string>& uris) {
  bool delivered = true;
  for (const auto& uri : uris) {
    delivered = SendPaymentLink(window, uri) && delivered;
  }
  return delivered;
}

BOOL CALLBACK ForwardToMatchingWindow(HWND window, LPARAM lparam) {
  auto* context = reinterpret_cast<ForwardContext*>(lparam);
  if (!IsFlutterRunnerWindow(window)) {
    return TRUE;
  }

  DWORD process_id = 0;
  ::GetWindowThreadProcessId(window, &process_id);
  if (process_id == 0 || process_id == ::GetCurrentProcessId()) {
    return TRUE;
  }
  const std::wstring process_path = ToLower(ProcessImagePath(process_id));
  if (process_path.empty() || process_path != context->module_path) {
    return TRUE;
  }

  ::AllowSetForegroundWindow(process_id);
  context->delivered = SendAllPaymentLinks(window, *context->uris);
  return context->delivered ? FALSE : TRUE;
}

struct ProcessForwardContext {
  DWORD process_id;
  const std::vector<std::string>* uris;
  bool delivered = false;
};

BOOL CALLBACK ForwardToProcessWindow(HWND window, LPARAM lparam) {
  auto* context = reinterpret_cast<ProcessForwardContext*>(lparam);
  if (!IsFlutterRunnerWindow(window)) {
    return TRUE;
  }
  DWORD process_id = 0;
  ::GetWindowThreadProcessId(window, &process_id);
  if (process_id != context->process_id) {
    return TRUE;
  }
  ::AllowSetForegroundWindow(process_id);
  context->delivered = SendAllPaymentLinks(window, *context->uris);
  return context->delivered ? FALSE : TRUE;
}

bool ForwardPaymentLinksToProcess(DWORD process_id,
                                  const std::vector<std::string>& uris) {
  ProcessForwardContext context{process_id, &uris};
  ::EnumWindows(ForwardToProcessWindow, reinterpret_cast<LPARAM>(&context));
  return context.delivered;
}

}  // namespace

bool ForwardPaymentLinksToRunningInstance(
    const std::vector<std::string>& uris) {
  if (uris.empty()) {
    return false;
  }
  ForwardContext context;
  context.module_path = ToLower(ModuleFileName());
  context.uris = &uris;
  if (context.module_path.empty()) {
    return false;
  }
  ::EnumWindows(ForwardToMatchingWindow, reinterpret_cast<LPARAM>(&context));
  return context.delivered;
}

bool LaunchCleanInstanceAndForwardPaymentLinks(
    const std::vector<std::string>& uris) {
  if (uris.empty()) {
    return false;
  }
  const std::wstring module_path = ModuleFileName();
  if (module_path.empty()) {
    return false;
  }

  std::wstring command_line = L"\"" + module_path + L"\"";
  std::vector<wchar_t> command_line_buffer(command_line.begin(),
                                            command_line.end());
  command_line_buffer.push_back(L'\0');
  STARTUPINFOW startup_info{};
  startup_info.cb = sizeof(startup_info);
  ScopedProcessInformation process_info;
  if (!::CreateProcessW(module_path.c_str(), command_line_buffer.data(),
                        nullptr, nullptr, FALSE, 0, nullptr, nullptr,
                        &startup_info, &process_info.value)) {
    return false;
  }

  const ULONGLONG deadline =
      ::GetTickCount64() + kCleanLaunchForwardTimeoutMs;
  while (::GetTickCount64() < deadline) {
    if (ForwardPaymentLinksToProcess(process_info.value.dwProcessId, uris)) {
      return true;
    }
    if (::WaitForSingleObject(process_info.value.hProcess, 100) ==
        WAIT_OBJECT_0) {
      return false;
    }
  }
  return false;
}

bool TryReadPaymentLinkCopyData(LPARAM lparam, std::string* uri) {
  if (uri == nullptr) {
    return false;
  }
  const auto* copy_data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
  if (copy_data == nullptr || copy_data->dwData != kPaymentLinkCopyDataId ||
      copy_data->lpData == nullptr || copy_data->cbData == 0 ||
      copy_data->cbData > kMaxIncomingUriBytes + 1) {
    return false;
  }
  const auto* raw = static_cast<const char*>(copy_data->lpData);
  if (raw[copy_data->cbData - 1] != '\0') {
    return false;
  }
  std::string value(raw, copy_data->cbData - 1);
  if (!IsPaymentLinkUri(value)) {
    return false;
  }
  *uri = std::move(value);
  return true;
}
