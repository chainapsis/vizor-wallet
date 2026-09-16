# Ledger Bluetooth on Windows

The Windows runner implements Ledger discovery, pairing, GATT connection,
Ledger BLE framing, app inspection and switching, UFVK exchange, cancellation,
and connection teardown through the shared Flutter Ledger channels.

`LedgerBleHandler` uses the platform-neutral protocol and operation gate from
`native/ledger`. The gate invalidates result delivery immediately on cancel but
keeps the native operation slot occupied until its worker finishes cleanup.
This prevents a late WinRT or GATT completion from overlapping a new request.

The runner owns the handler for the Flutter window lifetime. It forwards the
handler's registered dispatch message before other window messages and destroys
the handler before the Flutter controller. Windows links `windowsapp.lib` for
C++/WinRT Bluetooth APIs.

This slice supports discovery, connect, disconnect, current/open app, UFVK
exchange, and cancellation. Transaction-signing APDU batches are deferred to
the signing integration slice.

The shared host-only protocol and operation-gate test can be run from the
repository root:

```bash
clang++ -std=c++17 -Wall -Wextra -Werror \
  native/ledger/tests/ble_protocol_test.cpp \
  -o /tmp/vizor-ledger-ble-protocol-test && \
  /tmp/vizor-ledger-ble-protocol-test
```

This command does not compile or validate the Windows C++/WinRT runner. A
Windows Flutter toolchain is required for that build.
