#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <optional>
#include <utility>

#include "flutter/generated_plugin_registrant.h"
#include "velopack_update.h"

FlutterWindow::FlutterWindow(
    const flutter::DartProject& project,
    std::vector<std::string> initial_payment_uris)
    : project_(project),
      pending_payment_uris_(std::move(initial_payment_uris)) {}

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
  velopack_update_channel_ =
      CreateVelopackUpdateChannel(flutter_controller_->engine()->messenger());
  payment_uri_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.zcash.wallet/payment_uri",
          &flutter::StandardMethodCodec::GetInstance());
  payment_uri_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "takePendingUris") {
          result->Success(TakePendingPaymentUris());
          return;
        }
        if (call.method_name() == "ready") {
          payment_uri_dart_ready_ = true;
          FlushPendingPaymentUris();
          result->Success();
          return;
        }
        result->NotImplemented();
      });

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
    velopack_update_channel_.reset();
    payment_uri_channel_.reset();
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

flutter::EncodableValue FlutterWindow::TakePendingPaymentUris() {
  flutter::EncodableList uris;
  uris.reserve(pending_payment_uris_.size());
  for (const auto& uri : pending_payment_uris_) {
    uris.emplace_back(uri);
  }
  pending_payment_uris_.clear();
  return flutter::EncodableValue(uris);
}

void FlutterWindow::FlushPendingPaymentUris() {
  if (!payment_uri_dart_ready_ || !payment_uri_channel_ ||
      pending_payment_uris_.empty()) {
    return;
  }

  payment_uri_channel_->InvokeMethod(
      "onUris", std::make_unique<flutter::EncodableValue>(
                    TakePendingPaymentUris()));
}
