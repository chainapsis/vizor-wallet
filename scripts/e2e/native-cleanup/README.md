# Case-scoped macOS native storage observations

This standalone, non-UI helper deletes or verifies only one canonical case's
two macOS regtest Keychain services and `flutter.vizor_e2e_<namespace>.` preference
keys. It is **not connected to ordinary app startup or the catalog executor**.
Requires macOS 13+ and Swift 6; no package dependencies or CI changes.

Before any storage observation, require a valid code signature, sandboxed
`com.keplr.vizor` bundle, explicit expected team, matching application identifier,
and no extra Keychain access groups. Namespace worker/case indices match the
runtime contract's canonical `0...1,000,000` bounds. Never accept service names,
preference prefixes, domains, or file paths from command arguments.

Keychain queries use the Data Protection Keychain with exact service/access
group and synchronization variants. They never request data, attributes or
references and disable authentication UI. Delete without a match limit, then
require `errSecItemNotFound`; authentication/entitlement/other errors are not
absence. Preferences enumerate key names in the helper's current application,
current-user/any-host domain, remove only the exact case prefix, synchronize and
check the remaining prefix count. No preference values or key names are emitted.
Partial observations/statuses remain in failed receipts.

The caller must own the case namespace, stop its native writers, verify the
helper's build/signing identity against the actual cohort, capture its owned
process/output completion and bind the receipt to that launch. A namespace,
JSON receipt or `completed: true` is **not ownership or deletion permission**.
These observations do not stop processes, remove wallet/support/workspace files,
modify `native-context.json`, delete simulators, implement iOS cleanup, or recover
failed reports. Host binding, support-directory cleanup and executor integration
are later boundaries. Catalog `runnable` flags stay false.

## Focused model tests

```sh
swift test --package-path scripts/e2e/native-cleanup
```

Swift Testing runs isolated per-invocation models concurrently. The tests cover
canonical scope, signing refusals before storage I/O, exact targets, sibling
survival, read-only verification, native errors, positive absence, failed writes,
partial receipts, SDK query construction and redaction. Passing models is not a
claim that real Keychain state was deleted.

## Signed helper

```sh
swift build --package-path scripts/e2e/native-cleanup
```

The generated `vizor-native-cleanup` executable is intentionally insufficient
on its own: wrap it as a background-only `com.keplr.vizor` `.app`, include the
cohort's public provisioning profile and sign with its matching development
identity. Entitlements require `com.apple.security.app-sandbox`,
`com.apple.application-identifier` and `com.apple.developer.team-identifier`.
Do not use another app/team to obtain misleading absence in a different group.
Unsigned or wrong-identity executions fail before storage access.

Arguments are `--namespace <owned-case> --team <actual-cohort-team>`;
prefix `--verify` to observe without item/preference deletion. Nonzero exit or
`completed: false` means retain failure/state evidence, never mark a case PASS.
The expected team must come from verified cohort signing, not a repository's
default Xcode setting. This slice does not build/sign/launch helper bundles for
workers. All such launch/recovery authority remains outside this CLI.

## Optional real native smoke

`Tests/NativeCleanupSmoke/Smoke.swift` is manual fixture code, not a package
product or an automatically executed test. Compile it alongside both library
sources, using `swiftc -package-name VizorNativeCleanup ... -o <fresh-app>/Contents/MacOS/Smoke`,
then wrap/sign the **fresh** background-only bundle as above. Invoke only that
new test executable with `--team <actual-team>`, with bounded owned-process
capture; never launch/modify an existing Vizor app. No app or backend build is
needed. It generates two random scopes, refuses pre-existing services/prefixes,
seeds four synthetic items and three synthetic preference keys, proves selective
cleanup and sibling survival, then removes/verifies only its own inserted state.
Keep namespaces/output on failure or interrupted/uncertain cleanup. No broad
Keychain/domain reset, credential prompt, or keychain unlock is part of the test.

Items use `afterFirstUnlock`, matching the app's regtest wallet and its existing
test mnemonic setting. This does not validate biometric/protected secrets or
the ordinary mnemonic's `whenUnlocked` availability in a locked/headless session.
Those paths must fail closed if authentication is unavailable.

Apple API references: [SecItemDelete](https://developer.apple.com/documentation/security/secitemdelete(_:)),
[CFPreferencesCopyKeyList](https://developer.apple.com/documentation/corefoundation/cfpreferencescopykeylist(_:_:_:)).
