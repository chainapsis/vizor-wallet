# Native E2E runtime contract

This layer lets a reusable debug regtest app bind its mutable state to one case
at launch. It is a prerequisite for worker ownership and build-once execution,
not an executor. Catalog entries remain pending: no fixtures, port reservation,
simulator allocation, cleanup implementation, or scenario migration is added.

## Build profile and launch identity

Compile exactly one profile with `ZCASH_DEFAULT_NETWORK=regtest`:

- `VIZOR_E2E_MACOS_COHORT=true` for macOS debug builds.
- `VIZOR_E2E_IOS_COHORT=true` for iOS debug Simulator builds. Non-debug builds
  reject either profile. The app does not detect physical devices; the
  executor installs the iOS cohort only on a fresh case-owned Simulator.

iOS builds also require the existing `VIZOR_FORM_FACTOR=mobile` define.

The iOS profile is a Dart define only. No native build marker is stamped into
the app's `Info.plist`, and native iOS startup keeps its production behavior,
including the fresh-install Keychain cleaner and background registration.
A debug build without a profile rejects stray E2E launch configuration;
release builds never read it.

Pass both `VIZOR_E2E_CASE_MANIFEST` and `VIZOR_E2E_NAMESPACE` in the process
environment, not as per-case Dart defines. The manifest is ASCII JSON of at
most 2048 bytes with exactly these schema-1 fields:

```json
{
  "schema_version": 1,
  "scenario_id": "flutter.macos.contract-probe",
  "run_id": "a1b2c3d4e5",
  "worker_id": 2,
  "case_index": 17,
  "namespace": "vizor_a1b2c3d4e5_w2_17",
  "context_path": "/tmp/owned-run/e2e/vizor_a1b2c3d4e5_w2_17/native-context.json",
  "lightwalletd_port": 29067,
  "primary_proxy_port": 29068,
  "zcashd_rpc_port": 28232,
  "regtest_ironwood_activation_height": 500
}
```

`run_id` is ten lowercase hexadecimal digits; `worker_id` and `case_index` are
integers from 0 through 1,000,000. Both namespace values must equal
`vizor_<run_id>_w<worker_id>_<case_index>`. The environment namespace is bounded
to 64 ASCII bytes. Ports are distinct integers from 1 through 65535; endpoints
always use `http://127.0.0.1:<port>`. Activation is an explicit integer from 1
through `u32::MAX`: 1 for post-activation fixtures or 500 for pre-activation
Orchard funding. Scenario names do not infer activation or ports.

The scenario ID matches `flutter.ios.<hyphenated-id>` or
`flutter.macos.<hyphenated-id>` for the selected platform. This syntax check
does not replace catalog selection or execution-support validation.
For iOS, use `context_path: "app-support"`. It is a fixed iOS marker, not a
path: the iOS app publishes no runtime context. macOS requires an absolute path
ending in `/e2e/<namespace>/native-context.json`, with no `.` or `..` segments.
Its parent must already exist and belong to the launching worker.

The app validates identity before configuring preferences, opening wallet
storage, or initializing Rust. Missing or invalid cohort configuration fails
startup; stray configuration also fails in a non-cohort process. A process can
reinstall the same manifest but cannot switch to another case. With no profile
and no launch configuration, ordinary storage names, paths, preference keys,
endpoint presets, and activation defaults remain unchanged.

## Owned state and platform limits

A macOS case isolates its app state inside the shared user account:

| macOS state | Isolated identity |
| --- | --- |
| Wallet support directory | `<ApplicationSupport>/e2e/<namespace>` |
| Wallet Keychain service | `<regtest wallet service>.e2e.<namespace>` |
| Mnemonic service | `<isolated wallet service>.mnemonic` |
| Flutter legacy preferences | `flutter.vizor_e2e_<namespace>.` prefix |

The support directory covers existing consumers, including wallet databases,
Tor, Sapling parameters, and Gift state. Dart and Rust share these Keychain
names.

An iOS case owns one fresh Simulator instead. Inside it the app keeps its
production support directory, Keychain services, preferences, notification
identifiers and app-review state. The manifest namespace still names the case
but does not prefix storage. The executor proves a successful case's cleanup by
deleting that device and observing that its inventory entry and device
directory are gone; a failed case keeps the shut-down device.

iOS processes keep their production background-task registration, inside the
case's own Simulator. Positive OS background scheduling is outside this
profile's coverage.

On macOS the app keeps its runtime context in memory, and the original Driver
writes it to `native-context.json` only after its assertions complete. It
declares the PID, support directory, Keychain services and preference prefix.
It is not proof of native storage I/O or cleanup: `storage_cleanup_completed`
and `os_background_scheduling_enabled` are false, and the file grants no
cleanup or recovery permission. iOS publishes no runtime context. For a
`flutter.ios.*` case the Driver requires `runtime_context` to be null and
`context_path` to be `app-support`.

## Focused checks

Use the pinned FVM Flutter version. These checks do not launch an app, simulator,
regtest stack, or access the real Keychain:

```bash
fvm flutter pub get --offline --enforce-lockfile
fvm flutter test --no-pub test/core/config/e2e_runtime_case_manifest_test.dart test/core/config/e2e_namespace_test.dart test/core/config/e2e_runtime_endpoints_test.dart test/core/config/e2e_runtime_binding_test.dart
cargo test --manifest-path rust/Cargo.toml --offline --locked --lib wallet::secret_store::tests
cargo test --manifest-path rust/Cargo.toml --offline --locked --lib wallet::network::activation_tests
```

The binding test uses separate processes for ordinary startup, stray namespace,
stray manifest, and positive macOS launch. For the positive lane, export both
environment values from the example, create its owned context parent, and run:

```bash
fvm flutter test --no-pub --dart-define=VIZOR_E2E_MACOS_COHORT=true --dart-define=ZCASH_DEFAULT_NETWORK=regtest test/core/config/e2e_runtime_binding_test.dart
```

This reads the real native environment with mocked preferences and path-provider
storage. Other configuration lanes are explicitly skipped, not counted as passes.
No default lane compiles the iOS profile, so the iOS cohort's unprefixed
storage is exercised only by iOS executor runs.

Concurrent app execution, real Keychain persistence, process restart, simulator
teardown, fresh-device deletion proof, and fixture readiness remain worker/executor
validation gates. This slice makes no efficiency claim and changes no CI.
