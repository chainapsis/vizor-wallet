---
name: release-librustvoting
description: Prepare, validate, publish, verify, and tag semver releases for the librustvoting Cargo workspace. Use when releasing zcash_voting or its vote-commitment-tree crates, publishing crates.io packages, bumping release versions, or creating release tags.
---

# Release librustvoting

Run the release end to end, but keep the human release manager in control of
ambiguous choices and irreversible actions.

## Packages

The publishable release chain is:

1. `vote-commitment-tree`
2. `vote-commitment-tree-client`
3. `zcash_voting`

Derive the actual subset and order from current path dependencies. Do not
publish `wallet-example`.

Use these tag forms:

- `zcash_voting`: `v<version>`
- Other crates: `<package-name>-v<version>`

## Hard guards

- Never expose a crates.io token or other credential.
- Never overwrite an existing version or tag.
- Never publish, tag, push, yank, or create a GitHub Release without explicit
  release-manager approval covering that action.
- Never use `cargo publish --allow-dirty` unless the release manager explicitly
  approves publishing the exact dirty diff. The default is a clean, committed,
  pushed release commit.
- Never commit unless the release manager explicitly approves committing.
- Never infer a breaking-change classification when evidence is mixed. Present
  the evidence and ask.
- Once any crate is published, stop and ask before making a change that alters
  the approved version matrix or package contents.
- A request to prepare a release does not authorize publishing. A request to
  publish or execute the release does authorize publishing only after the exact
  plan is confirmed.

## SemVer policy

Apply Semantic Versioning 2.0.0 independently to every published crate:

- `MAJOR`: incompatible public API, behavior, wire format, persisted format, or
  protocol changes.
- `MINOR`: backward-compatible functionality.
- `PATCH`: backward-compatible fixes or internal changes.
- For `0.y.z`, increment `MINOR` for incompatible changes and `PATCH` for
  backward-compatible changes.
- Prereleases preserve the intended core version and advance monotonically:
  `alpha.N` → `beta.N` → `rc.N` → stable. Increment the numeric suffix within
  a phase, such as `rc.3` → `rc.4`.
- Do not move backward from `rc` to `beta` or `alpha` for the same core version.
- Changing the core version, such as `2.0.0-rc.4` → `2.1.0-alpha.0`, starts a
  different release line and requires explicit confirmation.
- Build metadata does not create an acceptable replacement for a published
  crates.io version.

If the requested version conflicts with these rules, explain the conflict and
ask the release manager to choose the version. Do not silently normalize it.

## Ambiguity gate

Ask one consolidated question whenever possible. Require confirmation if any of
these are not unambiguous:

- exact version for each crate that must be republished
- whether a change is breaking, additive, or a fix
- prerelease phase, core version, or suffix
- whether an internal crate changed since its published version
- whether dependents with exact internal pins must also receive new versions
- target registry or crates.io account
- release commit, branch, remote, tag set, or whether tags should be pushed
- whether to commit, push commits, publish, or create a GitHub Release
- unexpected dirty files, missing tags, divergent history, or failed checks

When an already-published internal crate version differs from the local source,
bump that crate and every dependent whose exact pin must change. Propose the
smallest SemVer-valid version matrix and get it confirmed.

## Workflow

### 1. Inspect

Read, without mutating:

- `git status --short --branch`
- recent commits and all relevant release tags
- `CHANGELOG.md`
- workspace and package `Cargo.toml` files
- matching package entries in `Cargo.lock`
- changes since each package's previous release tag
- crates.io versions for every candidate package

Use `cargo metadata` or manifests to verify the internal dependency graph.
Compare local package manifests with the exact versions already on crates.io;
do not assume an unchanged package version can be republished.

### 2. Propose the release

Present a compact plan containing:

- release commit and branch
- package/version matrix
- why each bump is SemVer-correct
- publish order
- changelog heading and notable entries
- tags
- requested mutations: edit, commit, push, publish, and tag/push

If the user's request already supplies every choice and clearly requests
execution, avoid redundant questions. Otherwise get one explicit approval for
the complete plan.

### 3. Prepare

Update:

- each released package's `version`
- exact internal dependency versions in dependent manifests
- `Cargo.lock`
- the top changelog section

Use the heading `## v<zcash_voting-version>` for a primary release. Mention
supporting crate releases in that section when they are part of the release.
Do not rewrite historical sections.

Run:

```bash
cargo check
cargo test --locked
cargo test -p zcash_voting -p zcash-voting-wallet-example \
  --all-targets --no-default-features --features lrz \
  --locked
cargo test -p vote-commitment-tree -p vote-commitment-tree-client \
  --all-targets --features vote-commitment-tree-client/cli --locked
cargo test -p vote-commitment-tree -p vote-commitment-tree-client \
  --all-targets --no-default-features \
  --features vote-commitment-tree/lrz,vote-commitment-tree-client/lrz,vote-commitment-tree-client/cli \
  --locked
git diff --check
```

Do not combine the Zakura-default and LRZ package sets in one Cargo
invocation; their transitive cryptography features are mutually exclusive.
Also run focused or feature-specific tests indicated by the changed code or
repository documentation. Resolve failures before proceeding.

### 4. Freeze the release commit

Show the final diff, status, version matrix, publish order, and tags.

The default safe sequence is:

1. commit the complete release state, if explicitly approved
2. push the release commit, if explicitly approved
3. verify the branch is clean and the commit is present on the intended remote
4. publish crates in dependency order
5. verify every publication
6. create and push tags for the exact release commit, if explicitly approved

If commit or push approval is absent, stop and ask. Do not compensate with
`--allow-dirty`.

### 5. Publish

Immediately before the first upload, verify:

- exact HEAD and remote branch
- clean worktree
- versions do not already exist on crates.io
- all checks passed
- release-manager approval covers the exact package/version matrix

For each crate in dependency order:

```bash
cargo publish -p <crate> --dry-run --locked
cargo publish -p <crate> --locked
```

After publishing an internal dependency, verify its exact version through the
crates.io API before validating or publishing its dependent. Retry only for
normal index propagation. Do not alter versions or dependency requirements
without renewed approval.

### 6. Verify and tag

For every published crate, verify:

- exact name and version exist on crates.io
- it is not yanked
- dependencies match the approved matrix
- checksum and publisher metadata are returned

Create annotated tags on the approved release commit, then push them only if
approved. Before creating each tag, verify it does not exist locally or
remotely.

Do not create a GitHub Release unless requested. If requested, derive notes from
the approved changelog section and confirm any ambiguous title, prerelease
flag, or artifact expectations.

### 7. Report

Report:

- published crate versions with crates.io links
- release commit
- created and pushed tags
- validation results
- any action intentionally left for the release manager

If the release is partial, state exactly which immutable versions were already
published and stop before proposing corrective publication numbers.
