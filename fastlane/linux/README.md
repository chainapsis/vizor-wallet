# Linux AppImage fastlane

Fastlane configuration for building and packaging Linux AppImages for external
distribution through GitHub Actions.

Run:

```bash
bundle exec fastlane linux build
bundle exec fastlane linux package
bundle exec fastlane linux release
```

The `release` lane:

1. Builds a Linux Flutter bundle for each mainnet/testnet flavor.
2. Creates an AppDir for each flavor.
3. Creates an AppImage for each flavor.
4. Generates an embedded GPG signature, detached `.asc` signature, and `.sha256`
   checksum for each flavor.
5. Prepares the artifacts under `dist/linux`.

The deployment repository's `Release` workflow creates the GitHub Release,
uploads assets, generates the update feed for multiple architectures, and
publishes the draft release.

The AppImage uses the host's GTK/GLib and desktop/graphics dependencies.
`scripts/linux-appimage/host-libraries.txt` is shared by linuxdeploy, the GStreamer
dependency copier, and the final AppDir check. Forbidden bundled libraries,
missing dependencies, or incompatible dependency versions cause packaging to
fail before signing or creating the AppImage. The build environment requires
Python 3, `readelf` (binutils), and `ldd`.

The runtime launcher ignores inherited `LD_LIBRARY_PATH` values. It searches
the two AppDir library directories first, then uses the loader's normal system
paths for host libraries. AppDir paths containing `:` or `;` are rejected because
the loader interprets those characters as search-path separators.
Run the focused launcher regression checks on Linux
with Bash, Python 3, and a C compiler:

```bash
python3 scripts/linux-appimage/test_app_run.py
```

The runtime environment needs GTK 3, a Secret Service provider, udev, and
EGL/GLES/Mesa or the appropriate GPU drivers. Minimal and server installations
may need additional packages. Relevant Ubuntu packages include `libgtk-3-0`,
`libsecret-1-0`, `libudev1`, `libegl1`, `libgles2`, and `libgl1-mesa-dri`; newer
releases use t64 package names where applicable. On Fedora, check `gtk3`,
`libsecret`, `systemd-libs`, `libglvnd-egl`, `libglvnd-gles`, `libglvnd-glx`, and
`mesa-dri-drivers`. The private legacy ABI dependencies `libjpeg.so.8` and
`libbz2.so.1.0` remain bundled for GStreamer/camera support.

The default release flavors are `mainnet,testnet`. To package a single flavor
or explicitly select both for a release:

```bash
VIZOR_LINUX_FLAVOR=mainnet bundle exec fastlane linux package
VIZOR_LINUX_FLAVOR=testnet bundle exec fastlane linux package
VIZOR_LINUX_FLAVORS=mainnet,testnet bundle exec fastlane linux release
```

## Native build dependencies

Ledger USB uses HIDAPI's `linux-static-hidraw` backend. Install `libudev-dev`
and `pkg-config` in the Linux build environment (or distribution equivalents).
The release build script checks this before building; `libudev` remains a native
runtime dependency. The AppImage dependency collector includes linked libraries.
Bundles include the Ledger udev rule and host setup instructions under
`data/ledger-usb`; packaging never changes host USB permissions automatically.

## Required environment variables

- `RELEASE_REPOSITORY`
- `RELEASE_BUILD_NUMBER`
- `LINUX_APPIMAGE_GPG_PRIVATE_KEY`
- `LINUX_APPIMAGE_GPG_KEY_ID`

Workflows that are not triggered by a tag also require:

- `RELEASE_TAG`

## Optional environment variables

- `RELEASE_NAME`
- `GITHUB_RELEASE_PRERELEASE`
- `VIZOR_LINUX_FLAVOR`
- `VIZOR_LINUX_FLAVORS`
- `VIZOR_LINUX_ARCH`
- `FVM_BIN`
- `LINUXDEPLOY_BIN`
- `APPIMAGETOOL_BIN`
- `LINUX_APPIMAGE_GPG_PASSPHRASE`

## Asset names

mainnet:

- `Vizor-linux-x86_64.AppImage`
- `Vizor-linux-x86_64.AppImage.zsync`
- `Vizor-linux-x86_64.AppImage.sha256`
- `Vizor-linux-x86_64.AppImage.asc`
- `Vizor-linux-aarch64.AppImage`
- `Vizor-linux-aarch64.AppImage.zsync`
- `Vizor-linux-aarch64.AppImage.sha256`
- `Vizor-linux-aarch64.AppImage.asc`

testnet:

- `Vizor-Testnet-linux-x86_64.AppImage`
- `Vizor-Testnet-linux-x86_64.AppImage.zsync`
- `Vizor-Testnet-linux-x86_64.AppImage.sha256`
- `Vizor-Testnet-linux-x86_64.AppImage.asc`
- `Vizor-Testnet-linux-aarch64.AppImage`
- `Vizor-Testnet-linux-aarch64.AppImage.zsync`
- `Vizor-Testnet-linux-aarch64.AppImage.sha256`
- `Vizor-Testnet-linux-aarch64.AppImage.asc`

Stable AppImage update information uses GitHub Releases `latest` zsync entries
so stable AppImages can be updated by external AppImage update tools. Each
Linux CI job builds one native architecture by setting `VIZOR_LINUX_ARCH` to
`x86_64` or `aarch64`. Prerelease builds do not embed update information and do
not generate zsync assets.
