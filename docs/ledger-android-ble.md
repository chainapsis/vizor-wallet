# Ledger Bluetooth on Android

C05 implements the C03 Ledger mobile channel on Android with Ledger Device
Management Kit (DMK) 0.0.4. It supports Bluetooth discovery, permission
requests, connection and disconnection, current-app inspection, opening the
Zcash app, UFVK APDU exchange, and cancellation.

DMK 0.0.4 requires Android API 30. This changes Vizor's whole Android app
minimum from API 24 to API 30; it is not limited to Ledger users. The manifest
declares scan/connect permissions for Android 12 and newer, location for API 30,
and Bluetooth LE as an optional device feature.

The handler rechecks permissions before discovery, connection, and connected
operations so a runtime revocation becomes a typed `permission_denied` result.
Connection teardown is serialized, and a connection is not reusable until both
DMK session state and Android GATT state report it closed. Activity destruction
also requests that teardown. A DMK connection exception caused by a nullable
Android device name follows the same cleanup path before the device can be
discovered again.

The generic multi-APDU transaction-signing channel from the source branch is
deferred to C08 with the PCZT signer contract. C05 exposes only the C03 channel,
including UFVK exchange. Mobile USB remains outside this change.

The JVM tests use the official DMK interface with fakes. They do not prove
physical-device pairing, Android permission UI, radio behavior, or GATT closure
on a particular phone and Ledger firmware combination.
