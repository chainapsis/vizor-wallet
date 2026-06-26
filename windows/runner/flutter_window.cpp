#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <windows.h>
#include <lmcons.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"
#include "velopack_update.h"

namespace {

std::wstring StringArg(const flutter::EncodableValue* arguments,
                       const char* key) {
  if (arguments == nullptr ||
      !std::holds_alternative<flutter::EncodableMap>(*arguments)) {
    return std::wstring();
  }
  const auto& map = std::get<flutter::EncodableMap>(*arguments);
  const auto it = map.find(flutter::EncodableValue(std::string(key)));
  if (it == map.end() || !std::holds_alternative<std::string>(it->second)) {
    return std::wstring();
  }
  return Utf16FromUtf8(std::get<std::string>(it->second));
}

// Passcode/password-only by design: this NEVER invokes Windows Hello. There is
// no Windows consent API that requires the device password while excluding Hello
// biometrics, so the reset gate collects the Windows account password in the
// Flutter UI and we validate it here with LogonUserW. LogonUserW consumes a
// plaintext password and can never be satisfied by a face/fingerprint, so the
// biometrics-excluded guarantee holds by construction.
void VerifyDeviceOwner(
    std::wstring password,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  wchar_t username[UNLEN + 1];
  DWORD username_length = UNLEN + 1;
  if (!::GetUserNameW(username, &username_length)) {
    result->Error("failed", "Could not resolve the current Windows user.");
    return;
  }

  HANDLE token = nullptr;
  // L"." validates against the local account database only.
  const BOOL ok =
      ::LogonUserW(username, L".", password.c_str(), LOGON32_LOGON_NETWORK,
                   LOGON32_PROVIDER_DEFAULT, &token);
  const DWORD error = ok ? ERROR_SUCCESS : ::GetLastError();
  if (token != nullptr) {
    ::CloseHandle(token);
  }
  if (!password.empty()) {
    // Best-effort: scrubs only this by-value copy. The inbound EncodableMap
    // string and any UTF-8->UTF-16 conversion temporary are not scrubbed
    // (defense-in-depth limitation, not a threat-model gap).
    ::SecureZeroMemory(password.data(), password.size() * sizeof(wchar_t));
  }

  if (ok) {
    result->Success(flutter::EncodableValue(true));
    return;
  }
  switch (error) {
    case ERROR_LOGON_FAILURE:
      // Wrong password - let the user retry.
      result->Success(flutter::EncodableValue(false));
      return;
    case ERROR_ACCOUNT_RESTRICTION:
    case ERROR_ACCOUNT_DISABLED:
    case ERROR_NO_SUCH_USER:
    case ERROR_PASSWORD_EXPIRED:
    case ERROR_PASSWORD_MUST_CHANGE:
    case ERROR_INVALID_LOGON_HOURS:
      // No usable account password: a blank-password local account, a
      // passwordless / Microsoft-account sign-in, or a correct-but-unusable
      // password (expired, must-change, or outside permitted logon hours).
      // The Dart layer surfaces a graceful "can't verify" state instead of a
      // misleading "wrong password" retry the user could never satisfy.
      result->Error("unavailable",
                    "This Windows account can't be verified by password.");
      return;
    default:
      result->Error("failed", "Device authentication failed.");
      return;
  }
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  camera_permission_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.zcash.wallet/camera_permission",
          &flutter::StandardMethodCodec::GetInstance());
  camera_permission_channel_->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() != "openSettings") {
          result->NotImplemented();
          return;
        }
        const auto shell_result = reinterpret_cast<intptr_t>(ShellExecuteW(
            nullptr, L"open", L"ms-settings:privacy-webcam", nullptr, nullptr,
            SW_SHOWNORMAL));
        result->Success(flutter::EncodableValue(shell_result > 32));
      });
  device_owner_auth_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.zcash.wallet/device_owner_auth",
          &flutter::StandardMethodCodec::GetInstance());
  device_owner_auth_channel_->SetMethodCallHandler(
      [](const auto& call, auto result) {
        if (call.method_name() != "verify") {
          result->NotImplemented();
          return;
        }
        VerifyDeviceOwner(StringArg(call.arguments(), "password"),
                          std::move(result));
      });
  velopack_update_channel_ =
      CreateVelopackUpdateChannel(flutter_controller_->engine()->messenger());

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    camera_permission_channel_.reset();
    device_owner_auth_channel_.reset();
    velopack_update_channel_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
