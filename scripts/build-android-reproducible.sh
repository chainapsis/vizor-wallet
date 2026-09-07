#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build-android-reproducible.sh \
  --build-name X.Y.Z \
  --build-number CODE \
  --release-version VERSION \
  --signing required|unsigned \
  [--target-abi all|arm64-v8a|armeabi-v7a|x86_64] [--offline] [--dry-run]

Builds Android APKs from a clean copy of HEAD under Vizor's canonical Linux
build path. The default target is all three ABIs. Direct Release and F-Droid
must both use this entry point so Flutter and Rust embed the same source/cache
paths.

Set FLUTTER_BIN to an absolute Flutter executable in F-Droid. It defaults to
the repository's required `fvm flutter` command for Direct/local builds.
EOF
}

build_name=""
build_number=""
release_version=""
signing=""
target_abi="all"
offline="false"
dry_run="false"

while (($# > 0)); do
  case "$1" in
    --build-name)
      build_name="${2:-}"
      shift 2
      ;;
    --build-number)
      build_number="${2:-}"
      shift 2
      ;;
    --release-version)
      release_version="${2:-}"
      shift 2
      ;;
    --signing)
      signing="${2:-}"
      shift 2
      ;;
    --target-abi)
      target_abi="${2:-}"
      shift 2
      ;;
    --offline)
      offline="true"
      shift
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! "${build_name}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "--build-name must be an X.Y.Z version: ${build_name:-<missing>}" >&2
  exit 2
fi
if [[ ! "${build_number}" =~ ^[0-9]+$ ]] || ((10#${build_number} <= 0)); then
  echo "--build-number must be a positive integer: ${build_number:-<missing>}" >&2
  exit 2
fi
if [[ ! "${release_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
  echo "--release-version must start with an X.Y.Z version: ${release_version:-<missing>}" >&2
  exit 2
fi
if [[ "${signing}" != "required" && "${signing}" != "unsigned" ]]; then
  echo "--signing must be required or unsigned: ${signing:-<missing>}" >&2
  exit 2
fi

case "${target_abi}" in
  all)
    target_platforms="android-arm64,android-arm,android-x64"
    output_abis=(arm64-v8a armeabi-v7a x86_64)
    ;;
  arm64-v8a)
    target_platforms="android-arm64"
    output_abis=(arm64-v8a)
    ;;
  armeabi-v7a)
    target_platforms="android-arm"
    output_abis=(armeabi-v7a)
    ;;
  x86_64)
    target_platforms="android-x64"
    output_abis=(x86_64)
    ;;
  *)
    echo "--target-abi must be all, arm64-v8a, armeabi-v7a, or x86_64: ${target_abi:-<missing>}" >&2
    exit 2
    ;;
esac

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "${script_dir}/.." && pwd)"
canonical_root="/tmp/vizor-android-reproducible"
canonical_source="${canonical_root}/source"
canonical_pub_cache="${canonical_root}/pub-cache"
canonical_cargo_home="${canonical_root}/cargo-home"
canonical_gradle_home="${canonical_root}/gradle-home"

flutter_command=(fvm flutter)
if [[ -n "${FLUTTER_BIN:-}" ]]; then
  if [[ "${FLUTTER_BIN}" != /* ]]; then
    echo "FLUTTER_BIN must be an absolute path: ${FLUTTER_BIN}" >&2
    exit 2
  fi
  flutter_command=("${FLUTTER_BIN}")
fi

build_args=(
  build apk
  --release
  --split-per-abi
  --target-platform "${target_platforms}"
  --build-name "${build_name}"
  --build-number "${build_number}"
  --dart-define=VIZOR_FORM_FACTOR=mobile
  --dart-define="VIZOR_RELEASE_VERSION=${release_version}"
  --dart-define=VIZOR_COINGECKO_PRICE_BASE_URL=https://functions.vizor.cash/api/v3
  --dart-define=VIZOR_WALLET_LINK_BACKEND_URL=https://functions.vizor.cash
)

printf 'Reproducible Android build: name=%s number=%s release=%s signing=%s targetAbi=%s offline=%s\n' \
  "${build_name}" "${build_number}" "${release_version}" "${signing}" "${target_abi}" "${offline}"
printf 'Canonical source: %s\n' "${canonical_source}"
printf 'Command:'
printf ' %q' "${flutter_command[@]}" "${build_args[@]}"
printf '\n'

if [[ "${dry_run}" == "true" ]]; then
  exit 0
fi

cd "${repository_root}"
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "The reproducible build requires a Git checkout with a valid HEAD." >&2
  exit 1
fi

umask 077
if [[ -L "${canonical_root}" ]]; then
  echo "Canonical build root must not be a symlink: ${canonical_root}" >&2
  exit 1
fi
if [[ -e "${canonical_root}" && ! -d "${canonical_root}" ]]; then
  echo "Canonical build root is not a directory: ${canonical_root}" >&2
  exit 1
fi
mkdir -p -m 700 "${canonical_root}"
if [[ ! -O "${canonical_root}" ]]; then
  echo "Canonical build root is not owned by the current user: ${canonical_root}" >&2
  exit 1
fi
chmod 700 "${canonical_root}"

fallback_lock=""
if command -v flock >/dev/null 2>&1; then
  exec 9>"${canonical_root}/build.lock"
  flock 9
else
  fallback_lock="${canonical_root}/build.lock.d"
  if ! mkdir "${fallback_lock}" 2>/dev/null; then
    echo "Another reproducible Android build holds ${fallback_lock}." >&2
    exit 1
  fi
  trap 'rmdir "${fallback_lock}" 2>/dev/null || true' EXIT
fi

for cache_dir in "${canonical_pub_cache}" "${canonical_cargo_home}" "${canonical_gradle_home}"; do
  if [[ -L "${cache_dir}" ]]; then
    echo "Canonical cache must not be a symlink: ${cache_dir}" >&2
    exit 1
  fi
  mkdir -p -m 700 "${cache_dir}"
  if [[ ! -O "${cache_dir}" ]]; then
    echo "Canonical cache is not owned by the current user: ${cache_dir}" >&2
    exit 1
  fi
  chmod 700 "${cache_dir}"
done

if [[ -L "${canonical_source}" ]]; then
  echo "Canonical source must not be a symlink: ${canonical_source}" >&2
  exit 1
fi
if [[ -e "${canonical_source}" && ! -O "${canonical_source}" ]]; then
  echo "Canonical source is not owned by the current user: ${canonical_source}" >&2
  exit 1
fi
rm -rf -- "${canonical_source}"
mkdir -m 700 "${canonical_source}"
git archive --format=tar HEAD | tar -xf - -C "${canonical_source}"

source_date_epoch="$(git show -s --format=%ct HEAD)"
export SOURCE_DATE_EPOCH="${source_date_epoch}"
export PUB_CACHE="${canonical_pub_cache}"
export CARGO_HOME="${canonical_cargo_home}"
export GRADLE_USER_HOME="${canonical_gradle_home}"
export CI=true

# rustc stores dependency and workspace paths in native debug/provenance data.
# Use stable virtual paths as a second line of defense beyond the canonical
# checkout/cache locations. Cargokit preserves and extends this flag list.
export CARGO_ENCODED_RUSTFLAGS="--remap-path-prefix=${canonical_source}=/vizor/source"$'\x1f'"--remap-path-prefix=${canonical_cargo_home}=/vizor/cargo"

if [[ "${signing}" == "unsigned" ]]; then
  unset ANDROID_KEYSTORE_PATH
  unset ANDROID_KEYSTORE_PASSWORD
  unset ANDROID_KEY_ALIAS
  unset ANDROID_KEY_PASSWORD
  unset ANDROID_REQUIRE_RELEASE_SIGNING
  export ANDROID_ALLOW_UNSIGNED_RELEASE=true
else
  unset ANDROID_ALLOW_UNSIGNED_RELEASE
  export ANDROID_REQUIRE_RELEASE_SIGNING=true
fi

pub_get_args=(pub get --enforce-lockfile)
cargo_fetch_args=(fetch --locked --manifest-path rust/Cargo.toml)
if [[ "${offline}" == "true" ]]; then
  pub_get_args+=(--offline)
  cargo_fetch_args+=(--offline)
fi

cd "${canonical_source}"
"${flutter_command[@]}" "${pub_get_args[@]}"
cargo "${cargo_fetch_args[@]}"
"${canonical_source}/scripts/run-with-android-reproducible-rust.sh" \
  "${flutter_command[@]}" "${build_args[@]}"

output_dir="${repository_root}/build/app/outputs/flutter-apk"
mkdir -p "${output_dir}"
for abi in "${output_abis[@]}"; do
  apk="app-${abi}-release.apk"
  source_apk="${canonical_source}/build/app/outputs/flutter-apk/${apk}"
  if [[ ! -s "${source_apk}" ]]; then
    echo "Expected APK is missing or empty: ${source_apk}" >&2
    exit 1
  fi
  cp -f -- "${source_apk}" "${output_dir}/${apk}"
done

printf 'Copied reproducible APKs to %s\n' "${output_dir}"
