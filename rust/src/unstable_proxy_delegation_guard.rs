//! Guards on the `unstable-proxy-delegation` feature, which forwards
//! zcash_voting's unstable, test-only proxy delegation switch to flag-on
//! development builds (see `Cargo.toml`). No default, profile or release
//! build may carry it.

use std::fs;
use std::path::{Path, PathBuf};

/// The repository root, above the Rust crate.
fn repository() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("the crate sits in the repository")
        .to_path_buf()
}

/// The text of `Cargo.toml`'s `[features]` table.
fn features_table(manifest: &str) -> String {
    let Some(start) = manifest.find("\n[features]\n") else {
        return String::new();
    };
    let body = &manifest[start + "\n[features]\n".len()..];
    let end = body.find("\n[").unwrap_or(body.len());
    body[..end].to_owned()
}

#[test]
fn the_feature_forwards_zcash_voting_s_switch() {
    assert_eq!(
        cfg!(feature = "unstable-proxy-delegation"),
        zcash_voting::proxy::PROXY_DELEGATION_ENABLED
    );
}

#[test]
fn no_default_build_enables_the_feature() {
    let manifest = fs::read_to_string(repository().join("rust/Cargo.toml")).unwrap();
    let features = features_table(&manifest);
    assert!(
        features
            .contains("unstable-proxy-delegation = [\"zcash_voting/unstable-proxy-delegation\"]"),
        "the feature forwards zcash_voting's switch and nothing else"
    );
    for line in features.lines() {
        let line = line.trim();
        if line.starts_with("default") {
            assert!(
                !line.contains("unstable-proxy-delegation"),
                "the default features must not carry it: {line}"
            );
        }
    }
    let outside_features = manifest.replace(&features, "");
    assert!(
        !outside_features.contains("unstable-proxy-delegation"),
        "no dependency entry may enable zcash_voting's switch directly"
    );
    assert!(
        !repository().join("rust/cargokit.yaml").exists(),
        "no cargokit options file may add cargo flags to every build"
    );
}

#[test]
fn no_release_script_or_workflow_asks_for_the_feature() {
    let root = repository();
    let mut stack: Vec<PathBuf> = [
        ".github", "scripts", "fastlane", "fdroid", "android", "ios", "macos", "linux", "windows",
    ]
    .iter()
    .map(|dir| root.join(dir))
    .filter(|dir| dir.exists())
    .collect();
    // The local regtest harnesses run debug builds against a throwaway stack, where
    // the feature is the point; release builds refuse it at compile time anyway.
    let dev_harnesses = root.join("scripts").join("e2e");
    let mut offending = Vec::new();
    while let Some(path) = stack.pop() {
        if path == dev_harnesses {
            continue;
        }
        if path.is_dir() {
            let name = path.file_name().and_then(|name| name.to_str());
            if matches!(name, Some("build" | "Pods" | ".gradle" | "ephemeral")) {
                continue;
            }
            for entry in fs::read_dir(&path).unwrap() {
                stack.push(entry.unwrap().path());
            }
            continue;
        }
        let Ok(text) = fs::read_to_string(&path) else {
            continue;
        };
        if text.contains("VIZOR_UNSTABLE_PROXY_DELEGATION")
            || text.contains("unstable-proxy-delegation")
        {
            offending.push(path);
        }
    }
    assert!(
        offending.is_empty(),
        "release tooling must not enable the dev feature: {offending:?}"
    );
}

#[test]
fn cargokit_adds_the_feature_to_debug_builds_only() {
    let builder = fs::read_to_string(
        repository().join("rust_builder/cargokit/build_tool/lib/src/builder.dart"),
    )
    .unwrap();
    let opt_in = builder
        .find("VIZOR_UNSTABLE_PROXY_DELEGATION")
        .expect("cargokit reads the opt-in");
    let rest = &builder[opt_in..];
    let refusal = rest
        .find("!environment.configuration.isDebug")
        .expect("a build that is not debug is refused");
    let feature = rest
        .find("'unstable-proxy-delegation'")
        .expect("the feature is added");
    assert!(
        refusal < feature,
        "the debug check comes before the feature is added"
    );
}
