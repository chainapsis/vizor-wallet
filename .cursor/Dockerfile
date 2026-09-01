# Cloud Agent base image for Vizor (Flutter + Rust, Linux desktop target).
#
# Holds the slow, stable system toolchain: the Flutter Linux desktop build
# dependencies, the LLVM/Clang toolchain the Rust FFI plugin links through, a
# modern Rust toolchain (the workspace pulls crates that require the
# `edition2024` Cargo feature, i.e. Rust >= 1.85), and a headless GUI stack so
# the built desktop app can actually be launched and screenshotted.
#
# Repo-dependent work (Flutter SDK via FVM, `pub get`) lives in the install
# script instead, so it tracks the checked-out .fvmrc / pubspec.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip zip xz-utils sudo \
      # Flutter Linux desktop + C/C++ build toolchain
      clang cmake ninja-build pkg-config g++ \
      # clang-18 on Ubuntu 24.04 selects the gcc-14 toolchain dir, so it needs
      # the matching libstdc++ dev package to find -lstdc++.
      libstdc++-14-dev \
      # The Rust FFI plugin's native build (native_toolchain_c) links through
      # ld.lld / llvm-ar in /usr/lib/llvm-*/bin.
      lld llvm \
      # GTK / GLib and other native plugin deps
      libgtk-3-dev libglib2.0-dev liblzma-dev \
      # flutter_secure_storage_linux -> libsecret + jsoncpp
      libsecret-1-dev libjsoncpp-dev \
      # Software OpenGL for headless rendering under Xvfb (no GPU)
      libgl1-mesa-dri libegl1 \
      # Headless GUI stack for launching / capturing the desktop app
      xvfb x11-utils dbus-x11 openbox wmctrl xdotool gnome-keyring \
      imagemagick ffmpeg \
 && rm -rf /var/lib/apt/lists/*

# Ensure an 'ubuntu' user (present by default on ubuntu:24.04) with passwordless
# sudo so the agent can install extra packages at runtime if needed.
RUN if ! id ubuntu >/dev/null 2>&1; then useradd -m -s /bin/bash -u 1000 ubuntu; fi \
 && echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu \
 && chmod 0440 /etc/sudoers.d/ubuntu

# System-wide Rust toolchain (stable). rustfmt/clippy for the documented checks.
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --profile minimal --default-toolchain stable \
 && rustup component add rustfmt clippy \
 && chmod -R a+w "$RUSTUP_HOME" "$CARGO_HOME"

USER ubuntu
