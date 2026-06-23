#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <roapi.h>
#include <windows.h>

#include "flutter_window.h"
#include "payment_uri_protocol.h"
#include "utils.h"
#include "velopack_uninstall.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  RunVelopackHooks();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize WinRT/COM, so that it is available for use in the library and/or
  // plugins.
  const HRESULT ro_init = ::RoInitialize(RO_INIT_SINGLETHREADED);
  const bool ro_initialized = SUCCEEDED(ro_init);
  // Conditional: don't steal the zcash: handler from another wallet/channel on
  // every launch. Install/update hooks (RunVelopackHooks) still claim it.
  RegisterZcashProtocolHandlerIfUnclaimed();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  std::vector<std::string> initial_payment_uris =
      GetZcashUriArguments(command_line_arguments);

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, std::move(initial_payment_uris));
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1095, 726);
  if (!window.Create(L"Vizor", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (ro_initialized) {
    ::RoUninitialize();
  }
  return EXIT_SUCCESS;
}
