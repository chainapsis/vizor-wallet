# Native payment-request E2E

Run on macOS with Xcode, CocoaPods and the repository's FVM SDK installed:

```sh
python3 scripts/e2e/flutter-macos-cross-chain-payment-request.py
```

The runner builds a separate, ad-hoc-signed app with a unique bundle ID. It
opens the app through macOS Launch Services with a Bitcoin URI, then delivers
an Ethereum token URI to the running app. It targets the test app explicitly;
it does not change the user's default URL handler. The app window is hidden.

The native `AppDelegate`, pending-URI buffer, MethodChannel handshake, Dart
intake, Rust URI parser, production router, password verification, request card,
SwapNotifier and Pay review screens all run. The test verifies:

1. A cold-launch URL stays behind the lock screen and reaches the card after
   entering the password.
2. Tor and token loading keep the action disabled and show placeholders, then
   resolve the Bitcoin amount and identity. Cancel does not request a quote.
3. A warm Ethereum URL survives a Tor failure and retry, resolves Base USDC,
   and reaches review with the exact recipient and amount. Back preserves the
   Pay composer. Starting or broadcasting a payment fails the test fixture.

Wallet/account data, storage, balances, token/quote responses and Tor connection
outcomes are controlled fixtures. Password verification still uses the real
security provider and Rust implementation. This suite does not validate a
persisted wallet database, Keychain storage, a live Tor bootstrap, the remote
quote API, signing or broadcasting. Other operating systems need their own
native URL-delivery runs.

The app reports milestones and test results to a loopback-only driver.
`build/payment-request-native-e2e/<run-id>/` contains the build log, temporary
entitlements and `result.json`. A missing result, timeout, failed assertion,
missing packaged URL registration or non-isolated bundle ID fails the runner.
The runner restores its temporary flavor override and unregisters only its own
app from Launch Services. The `_app.dart` entrypoint is deliberately separate
from ordinary `*_test.dart` discovery.
