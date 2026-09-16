# Ledger native BLE core

This slice provides the platform-neutral Ledger BLE primitives shared by the
native desktop transports:

- `native/ledger/ble_protocol.h` defines Ledger service UUIDs, APDU framing and
  response assembly, MTU negotiation, status mapping, and app-info decoding.
- `native/ledger/ble_operation_gate.h` keeps a cancelled operation's slot owned
  until its worker finishes cleanup, while preventing late result delivery.
- `native/ledger/tests/ble_protocol_test.cpp` exercises both headers without a
  platform SDK or a Ledger device.

Platform discovery, connection, GATT I/O, Flutter channel registration, and
lifecycle teardown remain in each platform runner. Transaction-signing APDU
exchange is deferred to the signing integration slice; the operation gate and
UFVK response framing already preserve generation-based late-result draining.

Run the standalone native test from the repository root:

```bash
clang++ -std=c++17 -Wall -Wextra -Werror \
  native/ledger/tests/ble_protocol_test.cpp \
  -o /tmp/vizor-ledger-ble-protocol-test && \
  /tmp/vizor-ledger-ble-protocol-test
```
