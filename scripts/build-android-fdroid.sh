#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/build-android-fdroid.sh \
  --version X.Y.Z \
  --expected-abi arm64-v8a|armeabi-v7a|x86_64 \
  --expected-version-code CODE [--dry-run]

Builds one unsigned Android APK using the same inputs as Vizor's Direct
Release. F-Droid invokes one build block per ABI, and each block builds only
the APK it will compare with the corresponding upstream-signed APK.

Set FLUTTER_BIN to an absolute Flutter executable in F-Droid. It defaults to
the repository's required `fvm flutter` command for local builds.
EOF
}

version=""
expected_abi=""
expected_version_code=""
dry_run="false"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "${script_dir}/.." && pwd)"
cd "${repository_root}"
release_rust_toolchain="$("${script_dir}/run-with-android-reproducible-rust.sh" --print-toolchain)"

while (($# > 0)); do
  case "$1" in
    --version)
      version="${2:-}"
      shift 2
      ;;
    --expected-abi)
      expected_abi="${2:-}"
      shift 2
      ;;
    --expected-version-code)
      expected_version_code="${2:-}"
      shift 2
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

if [[ ! "${version}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "--version must be a stable X.Y.Z version: ${version:-<missing>}" >&2
  exit 2
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

case "${expected_abi}" in
  armeabi-v7a)
    abi_offset=1000
    selected_apk="build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
    ;;
  arm64-v8a)
    abi_offset=2000
    selected_apk="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    ;;
  x86_64)
    abi_offset=4000
    selected_apk="build/app/outputs/flutter-apk/app-x86_64-release.apk"
    ;;
  *)
    echo "Unsupported --expected-abi: ${expected_abi:-<missing>}" >&2
    exit 2
    ;;
esac

if [[ ! "${expected_version_code}" =~ ^[0-9]+$ ]]; then
  echo "--expected-version-code must be a positive integer." >&2
  exit 2
fi

version_code_base=$((
  10#${major} * 100000000 +
  10#${minor} * 1000000 +
  10#${patch} * 10000 +
  999
))
calculated_version_code=$((version_code_base + abi_offset))
if ((calculated_version_code != 10#${expected_version_code})); then
  echo "Version code mismatch for ${version} ${expected_abi}: expected ${calculated_version_code}, got ${expected_version_code}." >&2
  exit 2
fi
if ((calculated_version_code > 2100000000)); then
  echo "Calculated version code exceeds Android's supported range: ${calculated_version_code}" >&2
  exit 2
fi

printf 'F-Droid build: version=%s baseVersionCode=%s selectedAbi=%s selectedVersionCode=%s rust=%s\n' \
  "${version}" "${version_code_base}" "${expected_abi}" "${calculated_version_code}" \
  "${release_rust_toolchain}"

if [[ "${dry_run}" == "true" ]]; then
  exec "${script_dir}/build-android-reproducible.sh" \
    --build-name "${version}" \
    --build-number "${version_code_base}" \
    --release-version "${version}" \
    --signing unsigned \
    --target-abi "${expected_abi}" \
    --offline \
    --dry-run
fi

"${script_dir}/build-android-reproducible.sh" \
  --build-name "${version}" \
  --build-number "${version_code_base}" \
  --release-version "${version}" \
  --signing unsigned \
  --target-abi "${expected_abi}" \
  --offline

android_sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "${android_sdk}" ]]; then
  echo "ANDROID_SDK_ROOT or ANDROID_HOME is required to verify the APKs." >&2
  exit 1
fi
build_tools="${android_sdk}/build-tools/36.0.0"
aapt="${build_tools}/aapt"
apksigner="${build_tools}/apksigner"
for tool in "${aapt}" "${apksigner}"; do
  if [[ ! -x "${tool}" ]]; then
    echo "Required Android Build Tools 36.0.0 executable is missing: ${tool}" >&2
    exit 1
  fi
done

if [[ ! -s "${selected_apk}" ]]; then
  echo "Expected ${expected_abi} APK is missing or empty: ${selected_apk}" >&2
  exit 1
fi
badging="$("${aapt}" dump badging "${selected_apk}")"
expected_badging="package: name='com.keplr.vizor' versionCode='${calculated_version_code}' versionName='${version}'"
if [[ "${badging}" != "${expected_badging}"* ]]; then
  echo "Unexpected package/version metadata in ${selected_apk}." >&2
  printf '%s\n' "${badging}" | sed -n '1p' >&2
  exit 1
fi
packaged_abis="$(
  unzip -Z1 "${selected_apk}" |
    sed -n 's#^lib/\([^/]*\)/.*#\1#p' |
    sort -u
)"
if [[ "${packaged_abis}" != "${expected_abi}" ]]; then
  echo "Expected only ${expected_abi} native libraries in ${selected_apk}; found: ${packaged_abis:-<none>}" >&2
  exit 1
fi
if "${apksigner}" verify "${selected_apk}" >/dev/null 2>&1; then
  echo "F-Droid output must be unsigned, but a valid APK signature was found: ${selected_apk}" >&2
  exit 1
fi

printf 'Selected F-Droid output: %s\n' "${selected_apk}"
