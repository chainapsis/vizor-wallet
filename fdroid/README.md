# F-Droid packaging

Vizor is intended to use the same Vizor Direct signing certificate for GitHub
and F-Droid. F-Droid must therefore use its reproducible-build `binary` flow:
it builds an unsigned APK from source, verifies it against the corresponding
upstream-signed APK, and publishes the upstream APK only when they match.

## Prepare the first submission

1. Publish a stable Android Direct Release from the same signed mobile source
   tag. The release must contain all three APKs and
   `Vizor-android-metadata.json`.
2. Download that metadata file and generate the fdroiddata entry:

   ```bash
   python3 scripts/generate-fdroid-metadata.py \
     --release-metadata /path/to/Vizor-android-metadata.json \
     --output fdroid/com.keplr.vizor.yml
   ```

   The generator verifies the package name, source tag and SHA, three ABI
   version codes, filenames, checksums, and Direct signing fingerprint. It also
   verifies that the signed source tag resolves to the recorded commit.
3. Copy the generated `fdroid/com.keplr.vizor.yml` into
   `metadata/com.keplr.vizor.yml` in a fork of
   [fdroiddata](https://gitlab.com/fdroid/fdroiddata).
4. Run `fdroid lint com.keplr.vizor`, then build all three entries using the
   fdroiddata CI or a local F-Droid build server.
5. Compare each F-Droid-produced unsigned APK with its `binary` URL. F-Droid
   publishes the Vizor-signed APK only after the reproducibility check passes.

The generated metadata follows the Direct Release ABI/version-code contract:

| ABI | Direct asset | Version-code offset |
| --- | --- | ---: |
| `armeabi-v7a` | `Vizor-android-armeabi-v7a.apk` | 1,000 |
| `arm64-v8a` | `Vizor-android.apk` | 2,000 |
| `x86_64` | `Vizor-android-x86_64.apk` | 4,000 |

F-Droid auto-update reads `Vizor-android-metadata.json` from the latest stable
mobile release and maps the reported base version code to those three builds.

## Local unsigned build

Use the final version code for the ABI that will be selected by a build block:

```bash
scripts/build-android-fdroid.sh \
  --version 0.0.35 \
  --expected-abi arm64-v8a \
  --expected-version-code 352999
```

The script deliberately builds all three ABIs in one invocation, matching the
Direct Release build shape. It removes Android signing variables from its
environment, enables the explicit unsigned-release Gradle path, and sets the
opt-in `VIZOR_RUST_TOOLCHAIN` override through
`scripts/run-with-android-reproducible-rust.sh`. Its version comes from the
clearly scoped `scripts/release-config/android-reproducible-rust-version.txt`;
it is not a rustup project-toolchain file. Normal development and Play/App
Store builds do not use this override. The build
fails if the stable version and ABI-specific version code do not agree. After
building, it also verifies the package ID, version name, version code, single
ABI contents, and absence of an APK signature using Android Build Tools 36.0.0.

Both Direct Release and F-Droid call
`scripts/build-android-reproducible.sh`. The shared entry point exports the
source commit into `/tmp/vizor-android-reproducible/source`, uses fixed Pub,
Cargo, and Gradle cache paths, pins the source timestamp, and remaps Rust source
paths. Builds on one host are serialized because the canonical directory is
shared. The directory is private to its owner and symlinks are rejected before
it is cleaned or used.

The Direct Release workflow must use the same public endpoint values embedded
by this script:

- `VIZOR_COINGECKO_PRICE_BASE_URL=https://functions.vizor.cash/api/v3`
- `VIZOR_WALLET_LINK_BACKEND_URL=https://functions.vizor.cash`

Changing either value changes the Dart snapshot and breaks reproducibility.

## Android developer verification

The Vizor Direct signing key is already registered for `com.keplr.vizor`.
`adi-registration.properties` is a key-ownership challenge used only when the
Android developer verification flow asks for one. Do not add a stale token to
normal releases; if Google issues a new challenge, add the exact token for the
verification APK and remove it after verification succeeds.
