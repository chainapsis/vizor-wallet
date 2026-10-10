# Case-scoped native storage observations

The standalone macOS CLI is **not connected to ordinary app startup**. No
package dependencies or CI changes. iOS cases need no native helper: each owns
a fresh Simulator that is deleted after a successful case.

## macOS contract

The non-UI macOS helper deletes or verifies only one canonical case's
two macOS regtest Keychain services and `flutter.vizor_e2e_<namespace>.` preference
keys. It is **not connected to ordinary app startup**.
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
modify `native-context.json`, delete simulators, or recover
failed reports. [Host case/launch binding](../README.md#bind-macos-cleanup-to-an-owned-case)
captures the actual signed artifacts and validates the owned terminal command's
output. The [macOS support owner](../README.md#own-macos-case-support-storage)
adds exclusive SDK-declared allocation and internally composed guarded removal;
the CLI itself owns/deletes no filesystem state. Executor integration remains a
later boundary. Catalog `runnable` flags stay false.

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
For the host binding, keep `CFBundleExecutable: vizor-native-cleanup` and set
`LSBackgroundOnly: true`; use only the minimal required entitlements (and the
exact default Keychain group, if explicit). Do not substitute the manual smoke
executable. The artifact builder remains responsible for trusted source/build
provenance; merely renaming/signing an arbitrary executable does not prove it.

`--support-location --namespace <case> --team <team>` only declares the actual
SDK user-domain application support location, after signing checks; it performs
no directory creation, native secret observation or deletion. The host validates
and exclusively allocates that path, then requires read-only `--verify` absence
before app writers. Neither a location receipt nor an existing directory is
ownership. The path calculation matches the pinned provider's macOS bundle-ID
suffix. Normal wallet builds do not link this package or invoke these modes.

## Optional real native smoke

`Tests/NativeCleanupSmoke/Smoke.swift` is manual fixture code, not a package
product or an automatically executed test. Compile it alongside `CaseNamespace.swift`,
`MacCleanup.swift` and `MacCleanupSystem.swift`, using
`swiftc -package-name VizorNativeCleanup ... -o <fresh-app>/Contents/MacOS/Smoke`,
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
[CFPreferencesCopyKeyList](https://developer.apple.com/documentation/corefoundation/cfpreferencescopykeylist(_:_:_:)),
[missing entitlement diagnosis](https://developer.apple.com/documentation/security/errsecmissingentitlement).
