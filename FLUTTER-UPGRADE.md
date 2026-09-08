# Flutter 3.47.2 upgrade validation

## Scope

Upgrade from Flutter 3.41.6 / Dart 3.11.4 to Flutter 3.47.2 / Dart 3.13.2.
Framework revision: `d3b14c876900e553bc736ca19295fc09e3853e8e`.
The branch includes the existing Windows ARM64 packaging changes.

- Keep Windows x64 installer names, package IDs, channels and install paths.
- Keep FRB 2.11.1, the Rust lockfile, plugin fork revisions and secure storage formats.
- Preserve CocoaPods/Cargokit integration through a project-level SwiftPM opt-out.
- Keep AGP 8.11.1, Gradle 8.14, Kotlin 2.2.20, Java 17 and the pinned SDK/NDK.
- Raise the macOS deployment target from 11 to 12; retain the existing architecture configuration.
- Validate the current Sparkle full update's minimum OS against the built app.
- Pin F-Droid's Flutter framework revision with a version consistency check.

## Automated verification

| Check | Flutter 3.41.6 baseline | Flutter 3.47.2 |
| --- | --- | --- |
| Analyze | 1 script filename lint | No issues |
| Desktop lane | 2,580 passed, 89 skipped | 2,580 passed, 89 skipped |
| Mobile lane | 912 passed, 20 failed | 912 passed, same 20 failed |
| F-Droid tools | Not rerun before upgrade | 13 tests passed |
| Windows release metadata | Existing contract | 4 tests / 72 assertions passed |
| Windows packaging (mocked) | Existing contract | 9 cases passed |
| Sparkle OS compatibility | New guard | 4 tests passed |

The desktop lane skips mobile-tagged tests by configuration. The mobile lane
uses `--tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile`.
No mobile failures were skipped or changed to make the upgrade pass.

The new analyzer exposed unawaited returns inside try/catch and try/finally.
Those calls now await completion, including keeping mnemonic bytes alive until
the asynchronous migration operation finishes before wiping the buffer.
An existing migration test now checks the buffer after an asynchronous yield.

A new desktop regression asserted in Flutter's semantics tree when a dismissed
Windows update prompt reappeared. Keeping semantics included through zero-opacity
fade frames fixes it; the existing repeat-failure test and full desktop suite pass.

## Visual comparison

Captured the existing deterministic `pay-recipient` and `mobile-pay-recipient`
scenarios before and after the upgrade, in dark and light themes.

- Mobile, 393 × 852: identical pixels in both themes.
- Desktop, 1080 × 720: dark has 188 differing pixels (maximum channel delta 12);
  light has 23 (maximum delta 1). Differences are confined to sidebar edges.
- No layout or text wrapping differences were observed in these samples.
- Widget captures do not validate actual desktop GPU rendering, camera textures,
  native window composition, or hardware-wallet scan reliability.

## Native build and execution verification

Verified locally on macOS with Xcode 26.6 and Java 17:

| Target | Result |
| --- | --- |
| macOS release | Built successfully with local signing disabled; Runner, App.framework and FlutterMacOS.framework all contain x86_64 + arm64; minimum macOS 12.0 |
| Android debug | Built successfully with the mobile define and ARM64 Flutter target; ARM64 Flutter and Rust libraries present; package ID unchanged, min SDK 24 / target SDK 36 |
| iOS simulator debug | Built successfully with the mobile define and no signing; Runner and Flutter.framework contain x86_64 + arm64; minimum iOS 15.0 |
| macOS native fixture | Ran the deterministic pay-recipient fixture under Impeller MetalSDF; inspected the rendered window and restoration from minimized state, then closed it |

The first macOS release attempt stopped because a distribution provisioning
profile was unavailable. Compilation/linking was then verified using a temporary
`XCODE_XCCONFIG_FILE` with `CODE_SIGNING_ALLOWED=NO` and
`CODE_SIGNING_REQUIRED=NO`; committed signing settings were not changed.
The native fixture used an ad-hoc local signature. The existing capture controller
is debug-only, so its release-mode automated capture was rejected; the running
release window was instead inspected through the app UI. The ordinary unsigned
release app was restored to the build output after fixture inspection.

Native builds still emit existing plugin API deprecation warnings, SwiftPM
migration warnings, and Android build-tool support warnings. These are follow-up
maintenance items, not successful verification of those future toolchains.

## Verification limits and follow-up

- Windows and Linux native compilation/execution were not run on this macOS host.
  Windows tests above exercise packaging logic with mocks, not actual installers.
- Android release signing, APK reproducibility against a Direct Release, Apple
  distribution signing/notarization and actual Sparkle feed generation were not run.
- Camera permission/device behavior, physical Keystone QR round trips, and actual
  wallet upgrade/import/sync E2E remain unverified. Provider/widget tests use mocks;
  the native visual fixture deliberately does not initialize wallet data or Rust.
- The existing 20 mobile test failures below still need their own investigation.
- No deployment workflow, tag, push, or production release was performed.

## Pre-existing mobile failures

These exact failures occur on both SDKs and remain outside the SDK compatibility fixes:

- `test/widgetbook/mobile_keystone_use_cases_test.dart: mobile Keystone signing ready use case enters scanner step`
- `test/widgetbook/mobile_receive_use_cases_test.dart: receive mobile transparent sheet use case opens info sheet`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: reconciles a scheduled migration even when local height is behind`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: manual retry uses the due native outbox recovery lane`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: manual retry recovers a due outbox before sync reports a height`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: due native outbox recovers in foreground without a signing permit`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: global outbox acceptance for another account retries the due account`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: noWork is successful when reconciliation cleared the due status`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: temporary native contention retries without showing an error`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: global needs-user-action outcome is not attached to the due account`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: matching needs-user-action outcome becomes immediately actionable`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: global waiting outcome does not throttle the due account`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: matching waiting outcome throttles the due account`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: matching native retry delay does not become a due-account error`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: a new scheduled batch is not throttled by the previous batch`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: due native outbox failure becomes immediately actionable`
- `test/features/migration/ironwood_migration_coordinator_provider_test.dart: one account failure does not block another account recovery`
- `test/features/onboarding/mobile_onboarding_progress_test.dart: import progress includes the review step`
- `test/features/onboarding/mobile_import_birthday_screen_test.dart: the date field is not typeable and opens the calendar`
- `test/features/onboarding/mobile_import_birthday_screen_test.dart: tapping the date field still opens the calendar`

## Windows packaging probe follow-up

The first internal run passed each runner's FVM ABI check, but both Windows
packaging jobs stopped in the script's second ABI probe before compilation.
The catch handler discarded the original exception, so the exact triggering
stderr message could not be recovered from that run.

The packaging script now preserves the host Dart PATH used to activate FVM,
logs the shell and resolved command paths, and captures probe diagnostics.
Redirected native stderr is tolerated only during the probe; a nonzero or missing
exit code, missing/duplicate ABI marker, or requested/actual ABI mismatch still
stops packaging. Existing x64 naming, package IDs, and ARM64 runtime selection
are unchanged.

Validation: 13 packaging cases passed in each of the mocked and real-child-process
modes on macOS PowerShell 7, plus 4 release metadata tests / 72 assertions.
The child-process cases cover stderr with success, stderr with nonzero exit,
missing/duplicate ABI output, architecture mismatches, and host Dart PATH
preservation. Windows PowerShell 5.1, Windows PowerShell 7, and actual Windows
builds still require runner verification. Run both modes on each Windows shell:

```powershell
./scripts/test-windows-packaging.ps1
./scripts/test-windows-packaging.ps1 -NativeProbe
```

No new internal tag or workflow run was created for this follow-up.
