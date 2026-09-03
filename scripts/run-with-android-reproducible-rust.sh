#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
version_file="${script_dir}/release-config/android-reproducible-rust-version.txt"

if [[ ! -f "${version_file}" ]]; then
  echo "Android reproducible-build Rust version file is missing: ${version_file}" >&2
  exit 1
fi

rust_toolchain="$(<"${version_file}")"
if [[ ! "${rust_toolchain}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Android reproducible-build Rust version must be exact X.Y.Z: ${rust_toolchain:-<empty>}" >&2
  exit 1
fi

if [[ "${1:-}" == "--print-toolchain" ]]; then
  printf '%s\n' "${rust_toolchain}"
  exit 0
fi

if (($# == 0)); then
  echo "Usage: scripts/run-with-android-reproducible-rust.sh COMMAND [ARG ...]" >&2
  exit 2
fi

toolchain_installed="false"
while IFS= read -r installed_line; do
  installed_name="${installed_line%% *}"
  if [[ "${installed_name}" == "${rust_toolchain}" ||
        "${installed_name}" == "${rust_toolchain}-"* ]]; then
    toolchain_installed="true"
    break
  fi
done < <(rustup toolchain list)

if [[ "${toolchain_installed}" != "true" ]]; then
  rustup toolchain install "${rust_toolchain}" --profile minimal
fi

actual_rust_version="$(rustup run "${rust_toolchain}" rustc --version)"
if [[ "${actual_rust_version}" != "rustc ${rust_toolchain} "* ]]; then
  echo "Expected Rust ${rust_toolchain}, got: ${actual_rust_version}" >&2
  exit 1
fi

export VIZOR_RUST_TOOLCHAIN="${rust_toolchain}"
exec "$@"
