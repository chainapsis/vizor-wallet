#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <roapi.h>
#include <shellapi.h>
#include <UserConsentVerifierInterop.h>
#include <windows.h>
#include <windows.security.credentials.ui.h>
#include <wincred.h>
#include <wrl.h>

#include <memory>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "payment_uri_handoff.h"
#include "utils.h"
#include "velopack_update.h"

namespace {

namespace credentials_ui = ABI::Windows::Security::Credentials::UI;
namespace foundation = ABI::Windows::Foundation;
namespace wrl = Microsoft::WRL;

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

class ScopedHString {
 public:
  explicit ScopedHString(const std::wstring& value) {
    hr_ = ::WindowsCreateString(value.c_str(),
                                static_cast<UINT32>(value.size()), &value_);
  }

  ~ScopedHString() {
    if (value_ != nullptr) {
      ::WindowsDeleteString(value_);
    }
  }

  ScopedHString(const ScopedHString&) = delete;
  ScopedHString& operator=(const ScopedHString&) = delete;

  HRESULT hr() const { return hr_; }
  HSTRING get() const { return value_; }

 private:
  HSTRING value_ = nullptr;
  HRESULT hr_ = E_FAIL;
};

using VerificationResult =
    credentials_ui::UserConsentVerificationResult;
using VerificationOperation =
    foundation::IAsyncOperation<VerificationResult>;
using VerificationCompletedHandler =
    foundation::IAsyncOperationCompletedHandler<VerificationResult>;
using MethodResult =
    flutter::MethodResult<flutter::EncodableValue>;
using MethodResultPtr = std::unique_ptr<MethodResult>;
using SharedMethodResult = std::shared_ptr<MethodResultPtr>;

void CompleteVerificationError(SharedMethodResult result,
                               const std::string& code,
                               const std::string& message) {
  if (result == nullptr || *result == nullptr) {
    return;
  }
  (*result)->Error(code, message);
  result->reset();
}

class ScopedHandle {
 public:
  explicit ScopedHandle(HANDLE handle = nullptr) : handle_(handle) {}

  ~ScopedHandle() {
    if (handle_ != nullptr) {
      ::CloseHandle(handle_);
    }
  }

  ScopedHandle(const ScopedHandle&) = delete;
  ScopedHandle& operator=(const ScopedHandle&) = delete;

  HANDLE get() const { return handle_; }
  HANDLE* put() { return &handle_; }

 private:
  HANDLE handle_ = nullptr;
};

bool ReadTokenUserSid(HANDLE token, std::vector<BYTE>* sid) {
  DWORD token_user_size = 0;
  ::GetTokenInformation(token, TokenUser, nullptr, 0, &token_user_size);
  if (::GetLastError() != ERROR_INSUFFICIENT_BUFFER ||
      token_user_size == 0) {
    return false;
  }

  std::vector<BYTE> token_user_buffer(token_user_size);
  if (!::GetTokenInformation(token, TokenUser, token_user_buffer.data(),
                             token_user_size, &token_user_size)) {
    return false;
  }

  const auto* token_user =
      reinterpret_cast<const TOKEN_USER*>(token_user_buffer.data());
  const DWORD sid_size = ::GetLengthSid(token_user->User.Sid);
  sid->resize(sid_size);
  return ::CopySid(sid_size, sid->data(), token_user->User.Sid) != FALSE;
}

bool IsCurrentUserToken(HANDLE token) {
  ScopedHandle current_token;
  if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY,
                          current_token.put())) {
    return false;
  }

  std::vector<BYTE> current_sid;
  std::vector<BYTE> candidate_sid;
  if (!ReadTokenUserSid(current_token.get(), &current_sid) ||
      !ReadTokenUserSid(token, &candidate_sid)) {
    return false;
  }

  return ::EqualSid(current_sid.data(), candidate_sid.data()) != FALSE;
}

enum class PasswordVerificationResult {
  kVerified,
  kWrongCredential,
  kUnavailable,
};

PasswordVerificationResult VerifyPasswordForCurrentUser(
    const std::wstring& username,
    const std::wstring& domain,
    const std::wstring& password) {
  std::wstring logon_username = username;
  std::wstring logon_domain = domain;
  if (logon_domain.empty()) {
    if (const size_t separator = logon_username.find(L'\\');
        separator != std::wstring::npos) {
      logon_domain = logon_username.substr(0, separator);
      logon_username = logon_username.substr(separator + 1);
    } else if (logon_username.find(L'@') == std::wstring::npos) {
      logon_domain = L".";
    }
  }

  ScopedHandle token;
  const BOOL ok = ::LogonUserW(
      logon_username.c_str(),
      logon_domain.empty() ? nullptr : logon_domain.c_str(), password.c_str(),
      LOGON32_LOGON_INTERACTIVE, LOGON32_PROVIDER_DEFAULT, token.put());
  if (ok) {
    return IsCurrentUserToken(token.get())
               ? PasswordVerificationResult::kVerified
               : PasswordVerificationResult::kWrongCredential;
  }

  switch (::GetLastError()) {
    case ERROR_LOGON_FAILURE:
    case ERROR_NO_SUCH_USER:
      return PasswordVerificationResult::kWrongCredential;
    case ERROR_ACCOUNT_RESTRICTION:
    case ERROR_ACCOUNT_DISABLED:
    case ERROR_PASSWORD_EXPIRED:
    case ERROR_PASSWORD_MUST_CHANGE:
    case ERROR_INVALID_LOGON_HOURS:
      return PasswordVerificationResult::kUnavailable;
    default:
      return PasswordVerificationResult::kUnavailable;
  }
}

void CompleteNoLocalCredential(SharedMethodResult result) {
  CompleteVerificationError(
      result, "no_local_credential",
      "Windows local credential verification is not available.");
}

void PromptForWindowsPassword(HWND window,
                              SharedMethodResult result) {
  DWORD auth_error = ERROR_SUCCESS;
  for (;;) {
    CREDUI_INFOW ui_info = {};
    ui_info.cbSize = sizeof(ui_info);
    ui_info.hwndParent = window;
    ui_info.pszCaptionText = L"Confirm reset Vizor";
    ui_info.pszMessageText =
        L"Enter your Windows account password to reset Vizor.";

    ULONG auth_package = 0;
    LPVOID auth_buffer = nullptr;
    ULONG auth_buffer_size = 0;
    BOOL save = FALSE;
    const DWORD prompt_result = ::CredUIPromptForWindowsCredentialsW(
        &ui_info, auth_error, &auth_package, nullptr, 0, &auth_buffer,
        &auth_buffer_size, &save, CREDUIWIN_GENERIC);
    if (prompt_result == ERROR_CANCELLED) {
      if (*result != nullptr) {
        (*result)->Success(flutter::EncodableValue(false));
        result->reset();
      }
      return;
    }
    if (prompt_result != ERROR_SUCCESS || auth_buffer == nullptr) {
      CompleteNoLocalCredential(result);
      return;
    }

    std::vector<wchar_t> username(CREDUI_MAX_USERNAME_LENGTH + 1);
    std::vector<wchar_t> domain(CREDUI_MAX_DOMAIN_TARGET_LENGTH + 1);
    std::vector<wchar_t> password(CREDUI_MAX_PASSWORD_LENGTH + 1);
    DWORD username_length = static_cast<DWORD>(username.size());
    DWORD domain_length = static_cast<DWORD>(domain.size());
    DWORD password_length = static_cast<DWORD>(password.size());
    const BOOL unpacked = ::CredUnPackAuthenticationBufferW(
        0, auth_buffer, auth_buffer_size, username.data(), &username_length,
        domain.data(), &domain_length, password.data(), &password_length);
    ::SecureZeroMemory(auth_buffer, auth_buffer_size);
    ::CoTaskMemFree(auth_buffer);

    if (!unpacked) {
      CompleteNoLocalCredential(result);
      return;
    }

    const PasswordVerificationResult verification =
        VerifyPasswordForCurrentUser(username.data(), domain.data(),
                                     password.data());
    ::SecureZeroMemory(password.data(),
                       password.size() * sizeof(wchar_t));

    if (verification == PasswordVerificationResult::kVerified) {
      if (*result != nullptr) {
        (*result)->Success(flutter::EncodableValue(true));
        result->reset();
      }
      return;
    }
    if (verification == PasswordVerificationResult::kUnavailable) {
      CompleteNoLocalCredential(result);
      return;
    }

    auth_error = ERROR_LOGON_FAILURE;
  }
}

void CompleteVerification(SharedMethodResult result,
                          HWND window,
                          VerificationResult verification_result) {
  if (result == nullptr || *result == nullptr) {
    return;
  }

  switch (verification_result) {
    case credentials_ui::UserConsentVerificationResult_Verified:
      (*result)->Success(flutter::EncodableValue(true));
      break;
    case credentials_ui::UserConsentVerificationResult_Canceled:
      (*result)->Success(flutter::EncodableValue(false));
      break;
    case credentials_ui::UserConsentVerificationResult_RetriesExhausted:
      (*result)->Error("failed", "Device authentication failed.");
      break;
    case credentials_ui::UserConsentVerificationResult_DeviceNotPresent:
    case credentials_ui::UserConsentVerificationResult_NotConfiguredForUser:
    case credentials_ui::UserConsentVerificationResult_DisabledByPolicy:
    case credentials_ui::UserConsentVerificationResult_DeviceBusy:
      PromptForWindowsPassword(window, result);
      return;
    default:
      (*result)->Error("failed", "Device authentication failed.");
      break;
  }
  result->reset();
}

void VerifyDeviceOwner(
    HWND window,
    std::wstring reason,
    MethodResultPtr result) {
  if (window == nullptr) {
    result->Error("unavailable", "Windows device authentication is unavailable.");
    return;
  }

  if (reason.empty()) {
    reason = L"Confirm reset Vizor";
  }

  ScopedHString message(reason);
  if (FAILED(message.hr())) {
    result->Error("failed", "Device authentication failed.");
    return;
  }

  ScopedHString class_name(
      RuntimeClass_Windows_Security_Credentials_UI_UserConsentVerifier);
  if (FAILED(class_name.hr())) {
    result->Error("failed", "Device authentication failed.");
    return;
  }

  wrl::ComPtr<IUserConsentVerifierInterop> verifier;
  HRESULT hr = ::RoGetActivationFactory(class_name.get(),
                                        IID_PPV_ARGS(&verifier));
  if (FAILED(hr) || !verifier) {
    PromptForWindowsPassword(
        window, std::make_shared<MethodResultPtr>(std::move(result)));
    return;
  }

  wrl::ComPtr<VerificationOperation> operation;
  hr = verifier->RequestVerificationForWindowAsync(
      window, message.get(), IID_PPV_ARGS(&operation));
  if (FAILED(hr) || !operation) {
    PromptForWindowsPassword(
        window, std::make_shared<MethodResultPtr>(std::move(result)));
    return;
  }

  auto shared_result = std::make_shared<MethodResultPtr>(std::move(result));
  auto completed = wrl::Callback<VerificationCompletedHandler>(
      [shared_result, window](VerificationOperation* completed_operation,
                              AsyncStatus status) -> HRESULT {
        if (status == Completed) {
          VerificationResult verification_result =
              credentials_ui::UserConsentVerificationResult_Canceled;
          const HRESULT result_hr =
              completed_operation->GetResults(&verification_result);
          if (FAILED(result_hr)) {
            CompleteVerificationError(shared_result, "failed",
                                      "Device authentication failed.");
          } else {
            CompleteVerification(shared_result, window, verification_result);
          }
        } else if (status == Canceled) {
          if (*shared_result != nullptr) {
            (*shared_result)->Success(flutter::EncodableValue(false));
            shared_result->reset();
          }
        } else {
          PromptForWindowsPassword(window, shared_result);
        }
        return S_OK;
      });
  if (!completed) {
    CompleteVerificationError(shared_result, "failed",
                              "Device authentication failed.");
    return;
  }

  hr = operation->put_Completed(completed.Get());
  if (FAILED(hr)) {
    CompleteVerificationError(shared_result, "failed",
                              "Device authentication failed.");
  }
}

}  // namespace

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
  device_owner_auth_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "com.zcash.wallet/device_owner_auth",
          &flutter::StandardMethodCodec::GetInstance());
  device_owner_auth_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() != "verify") {
          result->NotImplemented();
          return;
        }
        VerifyDeviceOwner(GetHandle(), StringArg(call.arguments(), "reason"),
                          std::move(result));
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
    device_owner_auth_channel_.reset();
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
  if (message == WM_COPYDATA) {
    std::string payment_uri;
    if (TryReadPaymentUriCopyData(lparam, &payment_uri)) {
      pending_payment_uris_.push_back(std::move(payment_uri));
      FlushPendingPaymentUris();
      return TRUE;
    }
  }

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
