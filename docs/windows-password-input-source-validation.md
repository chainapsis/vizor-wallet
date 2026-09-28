# Windows password input-source verification — 2026-09-28

Base: main `8566082a4`; branch: `codex/windows-password-input-source`.
Host: Windows 11 25H2, build 26200.9457, x64; Flutter 3.47.2 via FVM;
Visual Studio 2022 Build Tools 17.14.31. Installed sources exercised:
Microsoft Korean IME and US English.

## Findings and changes

The Windows native TSF/IMM implementation compiled and could restore sources,
but the Flutter wrapper skipped restoration while the initial lifecycle state
remained null. A pending preference read could also be cancelled by the Tab
release delivered to the newly focused password field.

Windows now uses window focus events plus a guarded initial focus query, waits
for the focus frame to finish before reading IMM state, and ignores Tab/Shift
releases caused by traversal. Text edits, IME composition, other keys, focus
loss, disposal and source changes still invalidate pending restoration.

The fix/review cycle found another native-only case: minimizing/restoring parks
Flutter focus at the root and then restores the same editor. This appeared to
be a fresh field entry and repeated restoration. Windows now recognizes that
view-focus transition. Two regression tests failed before the correction and
passed afterward, covering both native/window and Flutter/view event orders.

The Windows `restoreWithResult` call now exposes the native immediate readback
result. An unconfirmed result is logged without password text or identifiers;
it does not trigger a retry or prevent authentication.

macOS retains its lifecycle handling, key cancellation and void `restore`
channel contract. No macOS native files were changed. Existing macOS-style
tests and an explicit isolation regression test pass; this Windows session
does not constitute a native macOS runtime test.

## Validation

- `fvm flutter test --no-pub test/core/input test/features/onboarding/unlock_screen_payment_uri_test.dart test/app_ledger_first_account_onboarding_test.dart`: 43 passed.
- `fvm flutter analyze --no-pub`: no issues.
- `fvm flutter build windows --release --no-pub`: passed.
- `git diff --check`: passed.

The native checks used an isolated Flutter AOT Release host importing the actual
production password wrapper, service, password widget, native channel and
desktop bootstrap/window plugins. The preference store was a separate local
test file. No production wallet storage, unlock, account creation or payments
were exercised.

| Scenario | Result |
| --- | --- |
| First autofocus, lifecycle still null, initial Korean Hangul mode | Saved Korean Latin mode restored |
| Physical `a` key in the test field | ASCII `a` received |
| Hangul mode → password focus | Korean Latin mode restored |
| US keyboard → password focus | Korean profile and Latin mode restored |
| Manual Hangul selection while field remains focused | Preserved |
| Leaving the password field | No rollback |
| Deliberate re-entry into the field | Saved mode restored again |
| Minimize and restore with the same editor selected | No additional restore call |
| Tab and Shift+Tab releases, stale focus queries, duplicate events, cancellation races | Covered by widget regressions |

Local diagnostic artifacts are under ignored `build/ime-probe/`; the final
native trace is in `release-run/flutter-results.log`. Temporary hosts restore
their captured original input source on close.

## Scope and limits

This verifies the installed Korean/US configuration and the changed focus
behavior. Japanese/Chinese/third-party IMEs, removed profiles, and other keyboard
layouts were not exercised on this machine. IMM flags remain best effort:
Windows or an IME can change them after an immediate successful readback.
During investigation, native password-client initialization itself changed the
IME open flag; delaying capture until the focus frame ends avoids sampling
before that setup completes, without adding continuous enforcement.
