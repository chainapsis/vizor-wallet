# User-Facing Release Notes

This directory stores the canonical user-facing changelog for each Vizor
release. These notes are used by Sparkle on macOS and may also be reused by
GitHub Releases or future platform release flows.

## File Naming

Create one Markdown file per stable release:

```text
release_notes/vX.Y.Z.md
```

The file corresponds to the signed release tag:

```text
release/vX.Y.Z
```

Do not create platform-specific, mainnet-specific, or testnet-specific files
unless the release process is explicitly changed to support them.

## Format

Use this structure:

```markdown
# Vizor Wallet vX.Y.Z

One short paragraph summarizing the release in user-facing terms.

## What's New

- ...

## Improvements

- ...

## Fixes

- ...

## Notes

- ...
```

Omit empty sections. Keep bullets concise and user-facing.

## Writing Guidelines

- Include changes that users can observe or need to know about.
- Explain bugs only when they matter to users. Prefer the user-visible symptom
  and outcome over implementation details.
- Exclude minor fixes that are unlikely to matter to release-note readers.
- Exclude internal refactors, CI/CD changes, Fastlane changes, dependency
  bumps, and implementation details unless they directly affect users.
- Prefer short, concrete bullets over broad summaries.
- Put installation, reinstallation, migration, compatibility, or beta-program
  caveats under `Notes`.
- Do not overstate certainty. If a change is experimental or beta-only, say so.
- Keep the document in English.

## Suggested AI Request

Before tagging a release, ask an AI assistant to draft the notes from the
previous stable release to the target release commit:

```text
Review the changes from release/vA.B.C to the current HEAD and create
release_notes/vX.Y.Z.md following release_notes/README.md.

Include only user-facing changes. Exclude internal implementation details,
refactors, CI/CD changes, Fastlane changes, and dependency bumps unless they
directly affect users. Omit minor fixes that are unlikely to matter to users.
Keep the notes concise and in English.
```

Review the generated file manually before tagging the release.

## Example

```markdown
# Vizor Wallet v0.0.14

This release improves wallet reliability, network recovery, account
personalization, and several setup and sending edge cases.

## What's New

- Added profile picture selection, with new avatar artwork shown in account
  settings and the sidebar.
- The About screen now shows the installed app version.

## Improvements

- Added automatic fallback for built-in network endpoints. If a preset endpoint
  becomes slow or unavailable, Vizor can switch to another preset and notify
  you.
- Custom endpoints remain private and are never silently replaced by another
  server.
- Wallet imports now scan a wider safety window around the selected birthday
  date to reduce the chance of missing earlier activity.
- Testnet builds now display TAZ instead of ZEC where appropriate.
- Improved wording across onboarding, home, receive, send, activity, and
  settings screens.

## Fixes

- Fixed a fee calculation issue that could cause shielding to fail for wallets
  with many transparent funds.
- Improved shield failure messages so support details are easier to access when
  something goes wrong.
```
