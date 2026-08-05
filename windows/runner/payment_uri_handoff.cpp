#include "payment_uri_handoff.h"

#include <algorithm>
#include <cwctype>
#include <string>

#include "utils.h"

namespace {

constexpr wchar_t kFlutterWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr ULONG_PTR kPaymentLinkCopyDataId = 0x565A504C;  // "VZPL"

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
  for (const auto& uri : *context->uris) {
    context->delivered = SendPaymentLink(window, uri) || context->delivered;
  }
  return context->delivered ? FALSE : TRUE;
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
