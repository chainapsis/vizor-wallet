# Desktop onboarding integration validation

The desktop UI slices are merged into `rowan/desktop-onboarding-umbrella`
through #852 (`3864582fb3180385aa9dcdee6c2e05b4955862b4`). This validation
slice aligns the existing native E2E entry paths with those production routes.

## Desktop entry corrections

Desktop Welcome and Add account now open `/import/method`. Software import
requires clicking **Import secret passphrase** before `/import` and its phrase
fields appear. The previous regtest tests clicked Welcome's import button and
immediately waited for the phrase field, so they would stop at the selector.

Each scenario traverses Welcome/Add account → import-method selector → phrase
input using its existing local tap helpers. All 19 first/additional-wallet
entry sites across 12 existing regtest scenarios and the pre-existing
`desktop_regtest_flow.dart` are updated. Desktop interaction helpers remain
per-file as required by `AGENTS.md`; no new shared route driver is introduced.
The scenario-specific mnemonics, birthdays, passwords, funding, balance, send,
and recovery assertions remain in their existing tests.

Native execution also found that the Welcome create key now belongs to a
`Semantics` wrapper. The two shield runners still cast that wrapper to
`AppButton`, so their enablement wait timed out before creation started.
Each runner now passes the wrapper's actual `AppButton` finder to its existing
local button helper and waits for the enabled action.

Four widget tests drive the production desktop onboarding controls. They verify
first/additional-account creation entry, phrase input, the `entry=import-method`
context, the additional-account origin, and Back returning to the correct
selector.
The native Welcome smoke test also checks the create, import, and Gift controls
using their stable keys.

## Widget and provider coverage

These checks exercise production screens/routes with deterministic dependencies.
They do not establish native secure-store persistence, real hardware responses,
or regtest chain behavior.

| Boundary | Automated coverage |
| --- | --- |
| Welcome, first/additional import, hardware choices, Back/Cancel | `app_desktop_onboarding_selection_test`, `app_desktop_onboarding_back_navigation_test`, `welcome_screen_test` |
| Ordinary creation/import, password draft, name/profile, submit/retry | `create_onboarding_mnemonic_test`, `customise_account_screen_test`, `import_secret_passphrase_screen_test`, `import_wallet_birthday_screen_test` |
| Gift into new/additional/imported accounts, recipient choice/cancellation | `gift_claim_desktop_test`, with fake claim operations and hardware connectors |
| Interrupted setup, lock and restart recovery | `gift_wallet_setup_test`, `gift_wallet_setup_restart_test`, `app_bootstrap_gift_setup_test` |
| Backup persistence, deferred Home actions, education completion | `settings_seed_phrase_screen_test`, `account_backup_reminder_test`, `desktop_home_setup_carousel_test`, `desktop_home_setup_use_cases_test`, `desktop_gift_education_screen_test` |
| External-action hold release/overlap and existing Home actions | `external_action_guard_provider_test`, `home_desktop_screen_test` |

Visual evidence remains attached to the respective UI slices #828, #844–#847,
#850–#852. This slice changes the test harness, not product layout. The desktop
initial-importing carousel differs from mobile and is deferred for a later
design decision at the user's request; it is unchanged here.

## Native validation — 2026-10-06

All six runners below passed, covering seven native test executions because
Gift restart uses separate prepare/resume processes. They ran serially against
fresh local regtest chains with the macOS window hidden, on code commit
`066de87fe2629f754bc0bfc92f5083fcc1389331`. The initial create-action failure
above was fixed, and the entire selection passed again after restoring per-file
interaction helpers. Temporary regtest containers/state were cleaned after
the run.

| Runner | Verified outcome |
| --- | --- |
| `flutter-macos-regtest-import-sync.sh` | Method selector, BIP39 passphrase, password/customisation, real sync, shielded 1.25 and transparent 0.75 TAZ |
| `flutter-macos-regtest-shield-transparent.sh` | Ordinary wallet creation, external funding, shielding and transaction history |
| `flutter-macos-regtest-multi-account-send.sh` | First/additional import, account switch, real inter-account send and history |
| `flutter-macos-regtest-payment-link-round-trip.sh` | Gift creation, funding, additional recipient import, actual claim and persisted receipt |
| `flutter-macos-regtest-payment-link.sh` | Two retained Gift claims recovered after a real process restart and native unlock |
| `flutter-macos-regtest-shield-transparent-retry.sh` | Ordinary creation plus failed shield broadcast, retry and confirmed history |

Logs and machine-readable results are in
`.regtest-logs/desktop-onboarding-validation/native/per-file-helpers/`. The
widget/provider regression suite passed 270 tests before the per-file correction.
After that correction, all 23 desktop route tests passed again and full Flutter
analysis found no issues. Reproduction commands:

```bash
# First-wallet software import, BIP39 passphrase, sync and fixed balances.
scripts/e2e/flutter-macos-regtest-import-sync.sh

# Ordinary creation through password/customisation, then a real shield send.
scripts/e2e/flutter-macos-regtest-shield-transparent.sh
scripts/e2e/flutter-macos-regtest-shield-transparent-retry.sh

# First/additional imports, account switching and a real send.
scripts/e2e/flutter-macos-regtest-multi-account-send.sh

# Existing-wallet Gift claim and process-restart claim recovery.
scripts/e2e/flutter-macos-regtest-payment-link-round-trip.sh
scripts/e2e/flutter-macos-regtest-payment-link.sh
```

## Native gates remaining

These existing Gift runners do not cover walletless desktop Gift setup. Before
the umbrella is considered fully validated, also verify desktop Gift first and
additional-account setup, setup interruption across a native process restart,
backup/education persistence after lock and restart, actual Keystone/Ledger
import, and Linux Secret Service ownership. Keep mnemonic text and bearer Gift
links hidden in exported recordings and screenshots. Report each native gate
separately rather than treating the widget suite as a full-flow native pass.
