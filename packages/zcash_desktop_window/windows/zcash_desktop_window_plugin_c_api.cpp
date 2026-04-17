#include "include/zcash_desktop_window/zcash_desktop_window_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "zcash_desktop_window_plugin.h"

void ZcashDesktopWindowPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  zcash_desktop_window::ZcashDesktopWindowPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
