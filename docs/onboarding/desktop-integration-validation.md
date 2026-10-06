# Desktop onboarding integration validation

The desktop UI slices are merged into `rowan/desktop-onboarding-umbrella`
through #852 (`3864582fb3180385aa9dcdee6c2e05b4955862b4`). This validation
slice aligns the existing native E2E entry paths with those production routes.

## Import entry correction

Desktop Welcome and Add account now open `/import/method`. Software import
requires clicking **Import secret passphrase** before `/import` and its phrase
fields appear. The previous regtest tests clicked Welcome's import button and
immediately waited for the phrase field, so they would stop at the selector.

`integration_test/support/desktop_onboarding_flow.dart` owns
`openDesktopSecretPassphraseImport`. It drives both screens through their real
controls, waits for each action, and preserves the production routing context.
It is used at all 20 first/additional-wallet entry sites across 12 existing
regtest scenarios and `desktop_regtest_flow.dart`. The scenario-specific
mnemonics, birthdays, passwords, funding, balance, send, and recovery assertions
remain in their existing tests.

Two widget tests execute that exact E2E helper against the production desktop
onboarding routes. They verify phrase input, the `entry=import-method` context,
the additional-account origin, and Back returning to the correct selector.
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

## Native validation remaining

Native regtest execution has not been performed for this validation slice.
`AGENTS.md` requires an explicit request to run these heavy integration tests.
The runners use network-scoped disposable wallet state and reset the local
regtest chain by default. Once execution is requested, run them serially with
the macOS window hidden unless a visible walkthrough is required:

```bash
# First-wallet software import, BIP39 passphrase, sync and fixed balances.
scripts/e2e/flutter-macos-regtest-import-sync.sh

# Ordinary creation through password/customisation, then a real shield send.
scripts/e2e/flutter-macos-regtest-shield-transparent.sh

# First/additional imports, account switching and a real send.
scripts/e2e/flutter-macos-regtest-multi-account-send.sh

# Existing-wallet Gift claim and process-restart claim recovery.
scripts/e2e/flutter-macos-regtest-payment-link-round-trip.sh
scripts/e2e/flutter-macos-regtest-payment-link.sh
```

These existing Gift runners do not cover walletless desktop Gift setup. Before
the umbrella is considered fully validated, also verify desktop Gift first and
additional-account setup, setup interruption across a native process restart,
backup/education persistence after lock and restart, actual Keystone/Ledger
import, and Linux Secret Service ownership. Keep mnemonic text and bearer Gift
links hidden in exported recordings and screenshots. Report each native gate
separately rather than treating the widget suite as a full-flow native pass.
