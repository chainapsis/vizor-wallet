# App password input source

Windows and macOS desktop builds remember the input source captured when the
user submits a password. A snapshot is persisted only after the first account's
password setup commits or the startup unlock password succeeds. The onboarding
snapshot survives navigation to account customisation; that later screen's input
source is not learned. Other app-password gates only restore the preference.
Linux and mobile perform no input-source operations.

`AppPasswordInput` is an explicit wrapper at app-password call sites, outside the
generic password widget. On focus it requests a single restoration. Blur,
backgrounding, disposal, key events or editor changes invalidate a pending
restoration. Native handlers additionally require the app's active window and
compare the current source with the pre-read snapshot to avoid overwriting a
manual switch while settings load. There is no blur rollback or continuous
input-source enforcement. Startup autofocus before window activation is deferred
until activation; ordinary app reactivation does not repeat a completed attempt. Password validation and exact string comparison are
unchanged; no password characters are transformed.

The versioned `app_password_input_source_v1` local preference contains only
source identifiers and supported mode flags, never password text or native
pointers. It is readable before unlock. Wallet reset invalidates outstanding
candidates and serialises deletion after earlier writes. A failed capture does
not erase a previously learned value.

## Native behavior and limits

- macOS: capture the current TIS input-source ID, and select an enabled,
  selectable keyboard source with the same ID. An IME's internal mode is restored
  only insofar as it is exposed as a distinct TIS source ID.
- Windows: capture the TSF profile identity (type, language, CLSID, profile GUID),
  a stable KLID for a keyboard layout, and available IMM open/conversion/sentence
  state. Resolve an enabled profile and an already loaded layout on each restore.
  No raw HKL is persisted. Ambiguous layout identities or unreadable TIP modes
  are not learned. Third-party/modern IMEs may not expose or honor IMM mode APIs;
  restoration is best effort, not a guarantee for every IME.
- Removed, disabled or unresolvable sources are skipped. Nothing installs or
  enables a source, chooses an arbitrary English layout, detaches an IME,
  intercepts input, or blocks manual switching. Partial native mode failure may
  leave the selected source active, with normal keyboard input still available.
- OS settings can propagate an active input-source change beyond a single
  field/window. This feature does not override those settings.

## Manual native verification

Run on Windows and macOS; widget tests do not emulate real OS input methods.

1. With no saved preference, focus onboarding's password fields: no automatic
   English fallback. Submit an ASCII password with a chosen layout/mode. Change
   input source on the account-name screen, complete account creation, then
   confirm the next password focus selects the original submission source.
2. Fail unlock with a different source, then succeed: only success replaces the
   preference. Restart the app and verify restoration before unlocking.
3. Exercise Korean IME in Latin mode, Japanese IME in direct mode, a Chinese IME,
   US English and a non-US Latin layout (for example French or German). Include
   a Windows alternate layout such as Dvorak and a third-party IME where available.
   Unsupported modes must leave manual typing and switching usable.
4. Remove/disable the learned source in OS settings. Focus password fields and
   verify no source is enabled or installed and manual entry/switching still works.
5. Switch source manually while focused, then leave the field: no forced switch
   or rollback. Quickly type/paste, change focus or background the app while
   restoration is pending: a late preference read must not switch the source.
6. Check settings password gates, password change fields, account deletion,
   Wallet Link and the Ironwood unlock gate. Unrelated text fields and seed
   passphrases must not restore a source. Reset the wallet and verify no learned
   preference remains for new onboarding.
