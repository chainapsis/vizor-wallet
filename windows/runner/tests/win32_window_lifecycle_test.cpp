#include "win32_window.h"

#include <cstdlib>
#include <iostream>

namespace {
void Check(bool condition, const char* message) {
  if (!condition) {
    std::cerr << message << '\n';
    std::exit(EXIT_FAILURE);
  }
}

class TestWindow : public Win32Window {
 public:
  int cleanup_calls = 0;
  int nonclient_destroy_calls = 0;
  bool reenter_cleanup = false;

 protected:
  void OnDestroy() override {
    ++cleanup_calls;
    if (reenter_cleanup) {
      // Real engine/plugin destruction may pump messages and call back here.
      // Disable this only to make a missing guard fail, rather than overflow.
      reenter_cleanup = false;
      Destroy();
    }
  }

  LRESULT MessageHandler(HWND hwnd, UINT message, WPARAM wparam,
                         LPARAM lparam) noexcept override {
    if (message == WM_NCDESTROY) {
      ++nonclient_destroy_calls;
      Check(GetWindowLongPtr(hwnd, GWLP_USERDATA) == 0,
            "WM_NCDESTROY must detach the object before dispatch");
    }
    return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }
};
}  // namespace

int main() {
  TestWindow window;
  Check(window.Create(L"runner lifecycle test", {0, 0}, {100, 100}),
        "Create failed");
  HWND hwnd = window.GetHandle();
  window.cleanup_calls = 0;
  window.reenter_cleanup = true;
  window.Destroy();
  Check(window.cleanup_calls == 1, "Reentrant Destroy ran cleanup twice");
  Check(window.nonclient_destroy_calls == 1, "Missing WM_NCDESTROY");
  Check(!IsWindow(hwnd) && window.GetHandle() == nullptr,
        "Destroy left a live HWND");

  Check(window.Create(L"runner lifecycle test", {0, 0}, {100, 100}),
        "Recreate failed");
  hwnd = window.GetHandle();
  window.cleanup_calls = 0;
  Check(DestroyWindow(hwnd) != FALSE, "Native DestroyWindow failed");
  Check(window.cleanup_calls == 1, "Native destruction ran cleanup twice");
  Check(window.nonclient_destroy_calls == 2, "Recreated HWND was not detached");
  Check(window.GetHandle() == nullptr, "Native destruction retained the HWND");
  window.Destroy();
  window.Destroy();
  std::cout << "PASS: reentrant cleanup, native destruction, HWND detachment, "
               "recreation and repeated destruction\n";
  return EXIT_SUCCESS;
}
