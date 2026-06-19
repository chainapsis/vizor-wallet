#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.UI.h>
#include <winrt/base.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "utils.h"
#include "velopack_update.h"

namespace {

std::wstring DeviceOwnerAuthReason(
    const flutter::EncodableValue* arguments) {
  constexpr wchar_t kFallbackReason[] = L"Confirm reset Vizor";
  if (arguments == nullptr ||
      !std::holds_alternative<flutter::EncodableMap>(*arguments)) {
    return kFallbackReason;
  }

  const auto& map = std::get<flutter::EncodableMap>(*arguments);
  const auto reason = map.find(flutter::EncodableValue("reason"));
  if (reason == map.end() ||
      !std::holds_alternative<std::string>(reason->second)) {
    return kFallbackReason;
  }

  auto converted = Utf16FromUtf8(std::get<std::string>(reason->second));
  return converted.empty() ? std::wstring(kFallbackReason) : converted;
}

void VerifyDeviceOwner(
    const std::wstring& reason,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  namespace Credentials = winrt::Windows::Security::Credentials::UI;

  try {
    const auto verification_result =
        Credentials::UserConsentVerifier::RequestVerificationAsync(
            winrt::hstring(reason))
            .get();

    switch (verification_result) {
      case Credentials::UserConsentVerificationResult::Verified:
        result->Success(flutter::EncodableValue(true));
        return;
      case Credentials::UserConsentVerificationResult::Canceled:
        result->Success(flutter::EncodableValue(false));
        return;
      case Credentials::UserConsentVerificationResult::DeviceNotPresent:
      case Credentials::UserConsentVerificationResult::DisabledByPolicy:
      case Credentials::UserConsentVerificationResult::NotConfiguredForUser:
        result->Error("unavailable", "Device authentication is not available.");
        return;
      case Credentials::UserConsentVerificationResult::DeviceBusy:
      case Credentials::UserConsentVerificationResult::RetriesExhausted:
      default:
        result->Error("failed", "Device authentication failed.");
        return;
    }
  } catch (const winrt::hresult_error& error) {
    result->Error("failed", Utf8FromUtf16(error.message().c_str()));
  } catch (...) {
    result->Error("failed", "Device authentication failed.");
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
        VerifyDeviceOwner(DeviceOwnerAuthReason(call.arguments()),
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
