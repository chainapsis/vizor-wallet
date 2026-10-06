# Recovered wallet-owned transfer activity

This change matches the public wallet's gross Sent/Received presentation for
recovered wallet-owned transparent outputs. It does not recover every mixed
transaction or external recipient. Output values, account movements, account-paid
fees and whole-transaction fees remain separate. A single known wallet funder is
an inferred display convention; outside shielded participants may exist.

Run the production-read comparisons and scope/withdrawal regressions:

```sh
cd rust
cargo test --locked --lib wallet::sync::transactions
```

Run desktop receipts and the mobile lane (the form-factor define is required):

```sh
fvm flutter test test/features/activity/transaction_completeness_test.dart test/features/activity/transaction_loading_test.dart test/features/activity/activity_row_mapper_test.dart test/features/activity/activity_transaction_status_screen_test.dart
fvm flutter test --tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile test/features/activity/mobile_transaction_loading_test.dart test/features/activity/mobile_transaction_status_screen_test.dart test/features/activity/mobile_activity_screen_test.dart
```

The native regression reads a fabricated private database through the actual
Rust bridge. It verifies the reported 0.0025 ZEC gross legs and -0.00015 ZEC
movement, Transparent labels, ordering, two receipts and incomplete details. It
uses no production wallet, recovery phrase, network lookup or service.

Use an isolated macOS bundle in this disposable worktree: put
`PRODUCT_BUNDLE_IDENTIFIER = com.keplr.vizor.owned-transfer-tests` and
`PRODUCT_NAME = VizorOwnedTransfers` in the ignored
`macos/Runner/Configs/FlavorOverrides.xcconfig`. Generate a fresh fixture inside
that bundle's sandbox container, then run the native test:

```sh
export VIZOR_OWNED_TRANSFER_FIXTURE_DIR="$HOME/Library/Containers/com.keplr.vizor.owned-transfer-tests/Data/tmp/owned-transfer-check"
# The generator refuses to replace an existing wallet.db. Use a fresh directory.
cargo test --locked --manifest-path rust/Cargo.toml --lib owned_transparent_native_fixture
fvm flutter test integration_test/owned_transparent_activity_test.dart -d macos --dart-define=VIZOR_OWNED_TRANSFER_FIXTURE_DIR="$VIZOR_OWNED_TRANSFER_FIXTURE_DIR" --dart-define=VIZOR_E2E_HIDDEN_WINDOW=true --dart-define=VIZOR_SECURE_STORE_SERVICE=vizor-owned-transfer-tests
```

Fixture and widget evidence do not establish production-wallet behavior on the
user's installed app. Native qualification must be reported separately, together
with the exact application and library revisions tested.
