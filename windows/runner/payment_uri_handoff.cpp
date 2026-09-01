#include "payment_uri_handoff.h"

#include <string>

#include "single_instance.h"
#include "utils.h"

namespace {

constexpr wchar_t kFlutterWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr ULONG_PTR kPaymentUriCopyDataId = 0x5A43555249;  // "ZCURI"

bool IsFlutterRunnerWindow(HWND hwnd) {
  wchar_t class_name[256];
  const int length = ::GetClassNameW(hwnd, class_name, 256);
  return length > 0 && std::wstring(class_name, length) == kFlutterWindowClassName;
}

// Returns true when |hwnd| answers the registered activation message with the
// single-instance acknowledgement, which only a Vizor primary sharing this
// process's instance boundary does. Identifying the target this way instead of
// by comparing executable paths keeps working when the running instance was
// started through a junction, a subst drive, an 8.3 short path, or a directory
// an update has since replaced -- cases where the instance lock still matches
// but the image paths do not, and the payment URI used to be swallowed.
bool IsVizorPrimaryWindow(HWND hwnd, UINT activation_message) {
  DWORD_PTR response = 0;
  return ::SendMessageTimeoutW(hwnd, activation_message, 0, 0,
                               SMTO_ABORTIFHUNG | SMTO_BLOCK,
                               kSingleInstanceActivationMessageTimeoutMs,
                               &response) != 0 &&
         response ==
             static_cast<DWORD_PTR>(kSingleInstanceActivationAcknowledged);
}

// Returns true when |value| is something the Dart side can actually decode.
// The channel carries the URI through StandardMessageCodec, which throws on
// malformed UTF-8; a bad payload that arrives before Dart is ready aborts
// takePendingUris and wedges the payment-URI channel for the rest of the
// session. Control characters are rejected too: no ZIP-321 URI contains one,
// and they have no business reaching the send screen.
bool IsDecodablePaymentUriPayload(const std::string& value) {
  if (value.empty()) {
    return false;
  }

  for (const char raw_byte : value) {
    const auto byte = static_cast<unsigned char>(raw_byte);
    if (byte < 0x20 || byte == 0x7F) {
      return false;
    }
  }

  return ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                               static_cast<int>(value.size()), nullptr,
                               0) != 0;
}

bool SendPaymentUri(HWND hwnd, const std::string& uri) {
  if (!IsZcashUri(uri)) {
    return false;
  }

  COPYDATASTRUCT copy_data;
  copy_data.dwData = kPaymentUriCopyDataId;
  copy_data.cbData = static_cast<DWORD>(uri.size() + 1);
  copy_data.lpData = const_cast<char*>(uri.c_str());

  DWORD_PTR result = 0;
  return ::SendMessageTimeoutW(hwnd, WM_COPYDATA, 0,
                               reinterpret_cast<LPARAM>(&copy_data),
                               SMTO_ABORTIFHUNG, 3000, &result) != 0;
}

bool SendPaymentUris(HWND hwnd, const std::vector<std::string>& uris) {
  bool delivered_any = false;
  for (const auto& uri : uris) {
    if (SendPaymentUri(hwnd, uri)) {
      delivered_any = true;
    }
  }
  return delivered_any;
}

struct ForwardContext {
  const std::vector<std::string>* uris = nullptr;
  UINT activation_message = 0;
  bool delivered = false;
};

BOOL CALLBACK ForwardToMatchingWindow(HWND hwnd, LPARAM lparam) {
  auto* context = reinterpret_cast<ForwardContext*>(lparam);
  if (context == nullptr) {
    return FALSE;
  }
  if (!IsFlutterRunnerWindow(hwnd)) {
    return TRUE;
  }

  DWORD process_id = 0;
  ::GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id == 0 || process_id == ::GetCurrentProcessId()) {
    return TRUE;
  }

  // Grant the candidate the right to take the foreground before probing it:
  // the probe itself makes a Vizor primary present its window, and without
  // this grant that first presentation degrades to a taskbar flash.
  ::AllowSetForegroundWindow(process_id);
  if (!IsVizorPrimaryWindow(hwnd, context->activation_message)) {
    return TRUE;
  }

  context->delivered = SendPaymentUris(hwnd, *context->uris);
  return context->delivered ? FALSE : TRUE;
}

}  // namespace

bool ForwardPaymentUrisToRunningInstance(const std::vector<std::string>& uris,
                                        UINT activation_message) {
  if (uris.empty() || activation_message == 0) {
    return false;
  }

  ForwardContext context;
  context.uris = &uris;
  context.activation_message = activation_message;

  // The primary claims the single-instance lock before it creates its window,
  // so a zcash: launch that arrives during startup finds no target on the
  // first pass. Retry on the same schedule ActivateExistingInstance uses;
  // otherwise the secondary falls back to a bare activation, the window comes
  // to the front on someone else's screen, and the payment URI is lost.
  const ULONGLONG deadline =
      ::GetTickCount64() + kSingleInstanceActivationRetryWindowMs;
  do {
    ::EnumWindows(ForwardToMatchingWindow, reinterpret_cast<LPARAM>(&context));
    if (context.delivered) {
      return true;
    }
    ::Sleep(kSingleInstanceActivationRetryDelayMs);
  } while (::GetTickCount64() < deadline);

  return false;
}

bool TryReadPaymentUriCopyData(LPARAM lparam, std::string* uri) {
  if (uri == nullptr) {
    return false;
  }

  const auto* copy_data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
  if (copy_data == nullptr || copy_data->dwData != kPaymentUriCopyDataId ||
      copy_data->lpData == nullptr || copy_data->cbData == 0 ||
      copy_data->cbData > kMaxZcashUriBytes + 1) {
    return false;
  }

  const auto* raw = static_cast<const char*>(copy_data->lpData);
  if (raw[copy_data->cbData - 1] != '\0') {
    return false;
  }

  std::string value(raw, copy_data->cbData - 1);
  if (!IsZcashUri(value) || !IsDecodablePaymentUriPayload(value)) {
    return false;
  }

  *uri = std::move(value);
  return true;
}
