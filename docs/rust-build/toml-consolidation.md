# TOML dependency consolidation

Tor configuration currently compiles two TOML parser versions: its command-line
provider uses TOML 0.9, while Figment 0.10.19 uses TOML 0.8. Both also enable
writer support, although their production paths only deserialize.

The local patches share TOML 0.9 and select only `parse`, `serde`, and `std`.
Tor configuration enables the default TOML features for its own unit tests,
which exercise serialization. No Rust source files in either dependency are
modified. The exact manifest changes are in each `MANIFEST.patch`; hashes,
source revisions, and licenses are recorded beside them in `UPSTREAM.json`.

Production package counts (normal edges, excluding proc macros) decrease by
six on both targets:

| Target | Before | After | Build-only before/after |
| --- | ---: | ---: | ---: |
| aarch64-apple-darwin | 521 | 515 | 96 / 96 |
| x86_64-unknown-linux-gnu | 533 | 527 | 98 / 98 |

Removed: `toml` 0.8.23, `serde_spanned` 0.6.9, `toml_datetime` 0.6.11,
`toml_edit` 0.22.27, `toml_write` 0.1.2, and `toml_writer` 1.1.2.
No clean-build speedup is claimed for this isolated change.

## Compatibility

Vizor's Rust, C, and Dart API signatures are unchanged. Figment's existing
`providers::Toml` implementation of `Format` now uses TOML 0.9's `de::Error`
instead of TOML 0.8's error type. This patch is local to this application;
it is not a claim of a semver-compatible Figment library release. TOML 0.9
was already required by Tor configuration, so this adds no application MSRV
requirement.

Tor protocol, routing, compression, cryptography, ASM, and inlining code are
unchanged. Parsing uses the TOML version already used by Tor's command-line
configuration provider; Figment's file/string providers now share it.

## Upstream and removal plan

Figment's unreleased `master` already replaces `toml` with direct `toml_edit`
usage. See [the upstream change](https://github.com/SergioBenitez/Figment/commit/6a363a1f7ae9a4e9935cc7b95b780098053029b5)
and [the later parser update](https://github.com/SergioBenitez/Figment/commit/551e4b0f6036883b5ad0ef883bf6b7bd7d8a8f9c).
This application patch retains the currently pinned release's Rust sources.
After the relevant upstream release and Arti update, remove the corresponding
patches/vendors and repeat the graph and configuration checks.

## Reproduce validation

From the repository root:

```sh
python3 scripts/check-rust-vendor.py
python3 scripts/rust-dependency-audit.py --output /tmp/toml-mac.json \
  --target aarch64-apple-darwin
python3 scripts/rust-dependency-audit.py --output /tmp/toml-linux.json \
  --target x86_64-unknown-linux-gnu
cargo check --release --lib --locked --manifest-path rust/Cargo.toml
cargo test --release --lib --locked --manifest-path rust/Cargo.toml \
  network_privacy -- --test-threads=1
cargo test --manifest-path rust/vendor/figment/Cargo.toml --all-features
```

For Tor configuration's standalone tests, select the same Figment patch:

```sh
cd rust/vendor/tor-config
cargo test --lib --config 'patch.crates-io.figment.path="../figment"'
```

The standalone dependency tests may fetch their test-only dependencies.
Their local lockfiles and target directories are intentionally ignored.
