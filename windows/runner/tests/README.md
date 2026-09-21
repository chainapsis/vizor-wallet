# Windows runner lifecycle regression

After `fvm flutter build windows` has populated the Flutter engine files:

```powershell
cmake -S windows/runner/tests -B build/runner-tests -A x64
cmake --build build/runner-tests --config Release
ctest --test-dir build/runner-tests -C Release --output-on-failure
```

Use `-DFLUTTER_EPHEMERAL_DIR=<absolute-path>` at configure time to reuse
another checkout's `windows/flutter/ephemeral` engine files. CMake is also
available in the Visual Studio C++ build tools installation.

This test creates only hidden Win32 windows, without a Dart engine, wallet,
storage, or network. It covers recursive cleanup, native `WM_DESTROY`, object
detachment before `WM_NCDESTROY`, recreation, and repeated destruction.
It complements (and does not replace) full release-app close/reentrancy tests
that exercise Flutter, plugins, method channels, and the COM apartment.
