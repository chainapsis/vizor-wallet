# Native E2E runtime contract

This layer lets a reusable debug regtest app bind its mutable state to one case
at launch. It is a prerequisite for worker ownership and build-once execution,
not an executor. Catalog entries remain pending: no fixtures, port reservation,
simulator allocation, cleanup implementation, or scenario migration is added.

## Build profile and launch identity

Compile exactly one profile with `ZCASH_DEFAULT_NETWORK=regtest`:

- `VIZOR_E2E_MACOS_COHORT=true` for macOS debug builds.
- `VIZOR_E2E_IOS_COHORT=true` for iOS debug Simulator builds. Physical devices
  and release builds reject the native isolation profile.

iOS builds also require the existing `VIZOR_FORM_FACTOR=mobile` define.

The iOS build derives the native `VizorE2eIosCohort` boolean in the processed
app `Info.plist` from that same `VIZOR_E2E_IOS_COHORT` entry in `DART_DEFINES`.
The stamp runs after Flutter embedding and before code signing; it is not a
separate configuration knob. Native startup requires this build marker and
rejects a cohort build with missing or partial launch identity before the
fresh-install Keychain cleaner or any background registration can run.
Ordinary builds stamp `false` and reject stray E2E launch configuration.

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
For iOS, use `context_path: "app-support"`; Dart resolves it inside the case's
support directory. macOS requires an absolute path ending in
`/e2e/<namespace>/native-context.json`, with no `.` or `..` segments. Its parent
must already exist and belong to the launching worker.

The app validates identity before configuring preferences, opening wallet
storage, or initializing Rust. Missing or invalid cohort configuration fails
startup; stray configuration also fails in a non-cohort process. A process can
reinstall the same manifest but cannot switch to another case. With no profile
and no launch configuration, ordinary storage names, paths, preference keys,
endpoint presets, and activation defaults remain unchanged.

## Owned state and platform limits

| State | Isolated identity |
| --- | --- |
| Wallet support directory | `<ApplicationSupport>/e2e/<namespace>` |
| Wallet Keychain service | `<regtest wallet service>.e2e.<namespace>` |
| macOS mnemonic service | `<isolated wallet service>.mnemonic` |
| iOS recovery staging | `<isolated wallet service>.accessibility-migration-v1` |
| iOS biometric, migration credentials, outbox key | Each base service plus `.e2e.<namespace>` |
| Flutter legacy preferences | `flutter.vizor_e2e_<namespace>.` prefix |
| Async app-review preference | Explicit case-prefixed key |
| iOS native preferences | `com.keplr.vizor.regtest.e2e.<namespace>` suite |
| iOS notification identifiers | `vizor_e2e_<namespace>.` prefix |

The support directory covers existing consumers, including wallet databases,
Tor, Sapling parameters, and Gift state. Dart and Rust share macOS Keychain
names; Dart and Swift share iOS credential names. The iOS fresh-install cleaner
is skipped for isolated cases, and native migration allowlisting stays strict.

Isolated iOS processes do not register, submit, or cancel OS background tasks.
Fixed task identifiers are not per-case scheduler resources. Positive OS
background scheduling is outside this profile's coverage. A future worker must
own a fresh disposable simulator for remaining simulator-global state.

`native-context.json` is written atomically before ordinary wallet initialization.
It declares the PID, support directory, Keychain services, preference identities,
and notification prefix. It is not proof of native storage I/O or cleanup.
`storage_cleanup_completed` and `os_background_scheduling_enabled` are false;
the file grants no cleanup or recovery permission.

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
Swift policy tests can run on the host: compile `E2eRuntimeProfile.swift` with
`E2eRuntimeProfileHostTests.swift` into an owned temporary executable. XCTest
tests are wired into RunnerTests but require separate Xcode test execution.

Concurrent app execution, real Keychain persistence, process restart, simulator
teardown, native cleanup receipts, and fixture readiness remain worker/executor
validation gates. This slice makes no efficiency claim and changes no CI.
