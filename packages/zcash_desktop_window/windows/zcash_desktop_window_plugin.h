#ifndef FLUTTER_PLUGIN_ZCASH_DESKTOP_WINDOW_PLUGIN_H_
#define FLUTTER_PLUGIN_ZCASH_DESKTOP_WINDOW_PLUGIN_H_

#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace zcash_desktop_window {

class ZcashDesktopWindowPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit ZcashDesktopWindowPlugin(flutter::PluginRegistrarWindows* registrar);

  virtual ~ZcashDesktopWindowPlugin();

  // Disallow copy and assign.
  ZcashDesktopWindowPlugin(const ZcashDesktopWindowPlugin&) = delete;
  ZcashDesktopWindowPlugin& operator=(const ZcashDesktopWindowPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  HWND GetParentWindow() const;
  void ApplyDefaultAcrylic() const;

  flutter::PluginRegistrarWindows* registrar_;
};

}  // namespace zcash_desktop_window

#endif  // FLUTTER_PLUGIN_ZCASH_DESKTOP_WINDOW_PLUGIN_H_
