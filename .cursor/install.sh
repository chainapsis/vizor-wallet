#!/usr/bin/env bash
# Repo bootstrap for the Vizor Cloud Agent environment. Idempotent and
# non-interactive: safe to run on every setup and against a warm cache.
#
# System packages and the Rust toolchain come from .cursor/Dockerfile; this
# script only prepares repo-derived state (the FVM-pinned Flutter SDK and Dart
# packages) tied to the checked-out .fvmrc / pubspec.
set -euo pipefail

export PATH="/usr/local/cargo/bin:$HOME/fvm/bin:$PATH"

# Make sure the modern Rust toolchain is the default (edition2024 crates).
if command -v rustup >/dev/null 2>&1; then
  rustup default stable >/dev/null 2>&1 || true
fi

# Install FVM (Flutter Version Manager) if it is not already present.
if ! command -v fvm >/dev/null 2>&1; then
  curl -fsSL https://fvm.app/install.sh | bash
fi
export PATH="$HOME/fvm/bin:$PATH"

# Install the Flutter SDK version pinned in .fvmrc, enable the Linux desktop
# target, and resolve Dart packages.
fvm install
fvm flutter config --enable-linux-desktop >/dev/null
fvm flutter pub get

# Print versions without the tokenized Flutter git remote (avoids leaking the
# ephemeral checkout token into setup logs).
echo "Vizor environment ready."
echo "Flutter SDK: $(cat .fvmrc | grep -o '\"flutter\": *\"[^\"]*\"' || true)"
echo "Dart/Flutter: $(fvm dart --version 2>/dev/null || echo 'n/a')"
echo "Rust: $(rustc --version 2>/dev/null || echo 'n/a')"
