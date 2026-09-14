# Test execution

Read before selecting or running tests. The owning contract supplies relevant
files and behaviors; this guide owns commands and environment preparation.

## Prepare the environment

Run from the project root. Use `fvm flutter test` for Flutter-dependent tests,
including model tests importing `flutter_test`; `fvm dart test` cannot load
Flutter's `dart:ui`. Use `fvm dart` for formatting.

- Fresh checkout or changed dependency inputs: run `fvm flutter pub get` first.
- In an offline environment with the required packages already cached, use
  `fvm flutter pub get --offline`. Missing cached dependencies are a setup failure.
- Once dependencies are resolved for the current SDK and lockfile, use
  `fvm flutter test --no-pub` to skip redundant package resolution. Re-resolve
  after dependency changes; `--no-pub` does not install missing dependencies.
- `flutter test` has no `--offline` option. Skipping pub does not prevent a test
  itself from accessing the network; follow its fixtures and environment rules.

## Develop with focused checks

Start with the test for the changed behavior. After a failure, inspect the first
relevant error and rerun that case while fixing it:

```sh
fvm flutter test --no-pub <test-file> --plain-name '<group> <case>'
```

Once it passes, run the affected file and adjacent behavior checks, then the
complete applicable desktop/mobile set. Preserve regression assertions; change
an old expectation only when the product requirement directly changes it.

For noisy failures, keep the full output in a log and read the relevant error
and final summary. Preserve the command's exit status when filtering output;
an empty filter result does not prove the tests passed.

## Select the form factor and tests separately

The define selects compiled UI tokens; tags select which tests run.

Untagged tests with desktop tokens (mobile-tagged tests skip by default):

```sh
fvm flutter test --no-pub <test-files>
```

Mobile-tagged tests with mobile tokens:

```sh
fvm flutter test --no-pub --tags mobile --run-skipped \
  --dart-define=VIZOR_FORM_FACTOR=mobile <mobile-tagged-test-files>
```

Untagged tests explicitly checked with mobile tokens:

```sh
fvm flutter test --no-pub --dart-define=VIZOR_FORM_FACTOR=mobile <untagged-test-files>
```

Do not add `--tags mobile` to that last command: it excludes untagged tests.
A mobile-sized viewport alone does not select mobile tokens or tag a test.
`--run-skipped` lifts all skips in the selected tests; do not park broken mobile
tests behind `skip:`. A run selecting no tests provides no validation evidence.

For lane configuration changes, include [mobile lane sanity](../../../test/mobile_lane_sanity_test.dart).
See [required PR checks](../../../CONTRIBUTING.md#testing) for the final scope.
Regtest/integration runs require an explicit request and their [E2E guide](../../../scripts/e2e/README.md).
