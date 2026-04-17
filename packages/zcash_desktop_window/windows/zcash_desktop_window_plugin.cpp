#include "zcash_desktop_window_plugin.h"

#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace {

static constexpr auto kChannelName = "zcash_desktop_window/methods";

typedef enum _WINDOWCOMPOSITIONATTRIB {
  WCA_ACCENT_POLICY = 19,
} WINDOWCOMPOSITIONATTRIB;

typedef struct _WINDOWCOMPOSITIONATTRIBDATA {
  WINDOWCOMPOSITIONATTRIB Attrib;
  PVOID pvData;
  SIZE_T cbData;
} WINDOWCOMPOSITIONATTRIBDATA;

typedef enum _ACCENT_STATE {
  ACCENT_ENABLE_ACRYLICBLURBEHIND = 4,
} ACCENT_STATE;

typedef struct _ACCENT_POLICY {
  ACCENT_STATE AccentState;
  DWORD AccentFlags;
  DWORD GradientColor;
  DWORD AnimationId;
} ACCENT_POLICY;

typedef BOOL(WINAPI* SetWindowCompositionAttributeFn)(
    HWND, WINDOWCOMPOSITIONATTRIBDATA*);

}  // namespace

namespace zcash_desktop_window {

void ZcashDesktopWindowPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ZcashDesktopWindowPlugin>(registrar);

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

ZcashDesktopWindowPlugin::ZcashDesktopWindowPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

ZcashDesktopWindowPlugin::~ZcashDesktopWindowPlugin() {}

HWND ZcashDesktopWindowPlugin::GetParentWindow() const {
  return ::GetAncestor(registrar_->GetView()->GetNativeWindow(), GA_ROOT);
}

void ZcashDesktopWindowPlugin::ApplyDefaultAcrylic() const {
  const auto user32 = ::GetModuleHandleA("user32.dll");
  if (!user32) {
    return;
  }

  const auto set_window_composition_attribute =
      reinterpret_cast<SetWindowCompositionAttributeFn>(
          ::GetProcAddress(user32, "SetWindowCompositionAttribute"));
  if (!set_window_composition_attribute) {
    return;
  }

  ACCENT_POLICY accent = {
      ACCENT_ENABLE_ACRYLICBLURBEHIND,
      2,
      0xCC222222,
      0,
  };
  WINDOWCOMPOSITIONATTRIBDATA data = {
      WCA_ACCENT_POLICY,
      &accent,
      sizeof(accent),
  };
  set_window_composition_attribute(GetParentWindow(), &data);
}

void ZcashDesktopWindowPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "initialize") {
    ApplyDefaultAcrylic();
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "getTitlebarInset") {
    result->Success(flutter::EncodableValue(0.0));
  } else {
    result->NotImplemented();
  }
}

}  // namespace zcash_desktop_window
