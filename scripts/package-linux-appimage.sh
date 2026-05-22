#!/usr/bin/env bash
set -euo pipefail

BUNDLE_DIR=""
OUTPUT=""
APP_ID=""
APP_NAME=""
BINARY_NAME=""
ARCH="x86_64"
UPDATE_INFO=""
SIGN_KEY=""

usage() {
  cat <<USAGE
Usage: scripts/package-linux-appimage.sh [options]

Package a Flutter Linux bundle into a signed AppImage.

Required:
  --bundle-dir <path>       Flutter Linux bundle directory.
  --output <path>           Output .AppImage path.
  --app-id <id>             Linux application id, e.g. app.keplr.vizor.
  --app-name <name>         Display name.
  --binary-name <name>      Executable name inside the bundle.
  --sign-key <key-id>       GPG key id for AppImage signing.

Optional:
  --arch <arch>             AppImage architecture. Default: x86_64.
  --update-info <info>      AppImage update information. Enables zsync output.
  -h, --help                Show this help.

Environment:
  LINUXDEPLOY_BIN           Path to linuxdeploy. Default: linuxdeploy in PATH.
  APPIMAGETOOL_BIN          Path to appimagetool. Default: appimagetool in PATH.
  APPIMAGETOOL_SIGN_PASSPHRASE or LINUX_APPIMAGE_GPG_PASSPHRASE
                            Optional GPG passphrase for non-interactive signing.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle-dir)
      BUNDLE_DIR="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --app-id)
      APP_ID="$2"
      shift 2
      ;;
    --app-name)
      APP_NAME="$2"
      shift 2
      ;;
    --binary-name)
      BINARY_NAME="$2"
      shift 2
      ;;
    --arch)
      ARCH="$2"
      shift 2
      ;;
    --update-info)
      UPDATE_INFO="$2"
      shift 2
      ;;
    --sign-key)
      SIGN_KEY="$2"
      shift 2
      ;;
    --help|-h)
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

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "$name is required" >&2
    usage >&2
    exit 2
  fi
}

resolve_tool() {
  local env_name="$1"
  local command_name="$2"
  local configured="${!env_name:-}"

  if [[ -n "$configured" ]]; then
    if [[ ! -x "$configured" ]]; then
      echo "$env_name is not executable: $configured" >&2
      exit 1
    fi
    printf '%s\n' "$configured"
    return
  fi

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing $command_name. Set $env_name or add $command_name to PATH." >&2
    exit 1
  fi
  command -v "$command_name"
}

require_file() {
  local path="$1"
  local description="$2"
  if [[ ! -e "$path" ]]; then
    echo "Missing $description at $path" >&2
    exit 1
  fi
}

log_step() {
  printf '\n-- %s --\n' "$1"
}

require_value "--bundle-dir" "$BUNDLE_DIR"
require_value "--output" "$OUTPUT"
require_value "--app-id" "$APP_ID"
require_value "--app-name" "$APP_NAME"
require_value "--binary-name" "$BINARY_NAME"
require_value "--sign-key" "$SIGN_KEY"

BUNDLE_DIR="$(cd "$BUNDLE_DIR" && pwd)"
OUTPUT_DIR="$(mkdir -p "$(dirname "$OUTPUT")" && cd "$(dirname "$OUTPUT")" && pwd)"
OUTPUT="$OUTPUT_DIR/$(basename "$OUTPUT")"

require_file "$BUNDLE_DIR/$BINARY_NAME" "bundle executable"
require_file "$BUNDLE_DIR/data/applications/$APP_ID.desktop" "bundle desktop file"
require_file "$BUNDLE_DIR/data/icons/hicolor/256x256/apps/$APP_ID.png" "bundle icon"

LINUXDEPLOY_BIN="$(resolve_tool LINUXDEPLOY_BIN linuxdeploy)"
APPIMAGETOOL_BIN="$(resolve_tool APPIMAGETOOL_BIN appimagetool)"

APPDIR="$(mktemp -d "${OUTPUT_DIR}/${APP_ID}.AppDir.XXXXXX")"
cleanup() {
  rm -rf "$APPDIR"
}
trap cleanup EXIT

PAYLOAD_DIR="$APPDIR/usr/bin"
APPDIR_LIB_DIR="$APPDIR/usr/lib"
APPDIR_ICON_DIR="$APPDIR/usr/share/icons"
APPDIR_APPLICATIONS_DIR="$APPDIR/usr/share/applications"
mkdir -p "$PAYLOAD_DIR" "$APPDIR_LIB_DIR" "$APPDIR_ICON_DIR" "$APPDIR_APPLICATIONS_DIR"

cp -a "$BUNDLE_DIR/." "$PAYLOAD_DIR/"
cp -a "$BUNDLE_DIR/data/icons/." "$APPDIR_ICON_DIR/"

DESKTOP_FILE="$APPDIR/$APP_ID.desktop"
cp "$BUNDLE_DIR/data/applications/$APP_ID.desktop" "$DESKTOP_FILE"
sed -i \
  -e "s/^Name=.*/Name=$APP_NAME/" \
  -e "s/^Exec=.*/Exec=$BINARY_NAME/" \
  -e "s/^Icon=.*/Icon=$APP_ID/" \
  -e "s/^Categories=.*/Categories=Office;Finance;/" \
  -e "s/^StartupWMClass=.*/StartupWMClass=$APP_ID/" \
  "$DESKTOP_FILE"
cp "$DESKTOP_FILE" "$APPDIR_APPLICATIONS_DIR/$APP_ID.desktop"
cp "$BUNDLE_DIR/data/icons/hicolor/256x256/apps/$APP_ID.png" "$APPDIR/$APP_ID.png"

set_desktop_exec() {
  local exec_name="$1"
  local file
  for file in "$DESKTOP_FILE" "$APPDIR_APPLICATIONS_DIR/$APP_ID.desktop"; do
    if [[ -e "$file" ]]; then
      sed -i -e "s/^Exec=.*/Exec=$exec_name/" "$file"
    fi
  done
}

write_app_run() {
  rm -f "$APPDIR/AppRun"
  cat > "$APPDIR/AppRun" <<APPRUN
#!/usr/bin/env bash
set -euo pipefail

APPDIR="\${APPDIR:-\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)}"
export XDG_DATA_DIRS="\${APPDIR}/usr/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export LD_LIBRARY_PATH="\${APPDIR}/usr/bin/lib:\${APPDIR}/usr/lib:\${LD_LIBRARY_PATH:-}"
export GST_PLUGIN_SYSTEM_PATH_1_0="\${APPDIR}/usr/lib/gstreamer-1.0"
export GST_PLUGIN_PATH_1_0="\${APPDIR}/usr/lib/gstreamer-1.0"
if [[ -x "\${APPDIR}/usr/lib/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner" ]]; then
  export GST_PLUGIN_SCANNER="\${APPDIR}/usr/lib/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner"
fi

exec "\${APPDIR}/usr/bin/${BINARY_NAME}" "\$@"
APPRUN
  chmod +x "$APPDIR/AppRun"
}

should_skip_dependency() {
  local path="$1"
  local base
  base="$(basename "$path")"
  case "$base" in
    ld-linux*.so*|libc.so.*|libpthread.so.*|libdl.so.*|libm.so.*|librt.so.*|libresolv.so.*|libnsl.so.*|libutil.so.*)
      return 0
      ;;
  esac
  return 1
}

copy_dependency() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  should_skip_dependency "$path" && return 0

  local destination
  destination="$APPDIR_LIB_DIR/$(basename "$path")"
  if [[ ! -e "$destination" ]]; then
    cp -L "$path" "$destination"
  fi
}

copy_dependencies_for() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  while IFS= read -r dependency; do
    copy_dependency "$dependency"
  done < <(
    ldd "$file" 2>/dev/null |
      awk '
        /=> \// { print $3; next }
        /^[[:space:]]*\// { print $1; next }
      ' |
      sort -u
  )
}

copy_gstreamer_runtime() {
  local multiarch
  multiarch="$(gcc -print-multiarch)"
  local plugin_source_dir="/usr/lib/${multiarch}/gstreamer-1.0"
  local scanner_source="/usr/lib/${multiarch}/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner"
  local plugin_destination_dir="$APPDIR_LIB_DIR/gstreamer-1.0"
  local scanner_destination_dir="$APPDIR_LIB_DIR/gstreamer1.0/gstreamer-1.0"

  mkdir -p "$plugin_destination_dir" "$scanner_destination_dir"

  local copied_convert_plugin="false"
  local copied_scale_plugin="false"
  local plugin
  for plugin in \
    libgstapp.so \
    libgstautodetect.so \
    libgstcoreelements.so \
    libgstpipewire.so \
    libgstvideo4linux2.so \
    libgstvideoconvert.so \
    libgstvideoconvertscale.so \
    libgstvideoscale.so \
    libgstximagesrc.so; do
    local source_path="$plugin_source_dir/$plugin"
    if [[ -f "$source_path" ]]; then
      cp -L "$source_path" "$plugin_destination_dir/$plugin"
      copy_dependencies_for "$source_path"
      case "$plugin" in
        libgstvideoconvert.so)
          copied_convert_plugin="true"
          ;;
        libgstvideoconvertscale.so)
          copied_convert_plugin="true"
          copied_scale_plugin="true"
          ;;
        libgstvideoscale.so)
          copied_scale_plugin="true"
          ;;
      esac
    fi
  done

  if [[ "$copied_convert_plugin" != "true" || "$copied_scale_plugin" != "true" ]]; then
    echo "Missing GStreamer videoconvert/videoscale plugins in $plugin_source_dir" >&2
    exit 1
  fi

  if [[ -f "$scanner_source" ]]; then
    cp -L "$scanner_source" "$scanner_destination_dir/gst-plugin-scanner"
    chmod +x "$scanner_destination_dir/gst-plugin-scanner"
    copy_dependencies_for "$scanner_source"
  fi

  local library
  for library in libgstreamer-1.0.so.0 libgstapp-1.0.so.0 libgstbase-1.0.so.0 libgstvideo-1.0.so.0; do
    local source_library
    source_library="$(ldconfig -p | awk -v lib="$library" '$1 == lib { print $NF; exit }')"
    if [[ -n "$source_library" && -f "$source_library" ]]; then
      copy_dependency "$source_library"
      copy_dependencies_for "$source_library"
    fi
  done
}

install_appimage_root_icon() {
  rm -f "$APPDIR/$APP_ID.png" "$APPDIR/.DirIcon"
  cp "$BUNDLE_DIR/data/icons/hicolor/256x256/apps/$APP_ID.png" "$APPDIR/$APP_ID.png"
  ln -s "$APP_ID.png" "$APPDIR/.DirIcon"
}

export APPIMAGE_EXTRACT_AND_RUN=1

log_step "Running linuxdeploy"
"$LINUXDEPLOY_BIN" \
  --appdir "$APPDIR" \
  --executable "$PAYLOAD_DIR/$BINARY_NAME" \
  --desktop-file "$DESKTOP_FILE" \
  --icon-file "$APPDIR/$APP_ID.png"

log_step "Writing custom AppRun"
write_app_run
set_desktop_exec "AppRun"
install_appimage_root_icon

log_step "Copying GStreamer runtime"
copy_gstreamer_runtime

rm -f "$OUTPUT" "$OUTPUT.zsync" "$OUTPUT.sha256" "$OUTPUT.asc"

OUTPUT_BASENAME="$(basename "$OUTPUT")"
(
  cd "$OUTPUT_DIR"
  appimagetool_args=(
    --sign
    --sign-key "$SIGN_KEY"
  )
  if [[ -n "$UPDATE_INFO" ]]; then
    appimagetool_args+=(-u "$UPDATE_INFO")
  fi
  appimagetool_args+=(
    "$APPDIR"
    "$OUTPUT_BASENAME"
  )
  log_step "Running appimagetool"
  ARCH="$ARCH" "$APPIMAGETOOL_BIN" "${appimagetool_args[@]}"
)

chmod +x "$OUTPUT"

if [[ -n "$UPDATE_INFO" && ! -f "$OUTPUT.zsync" ]]; then
  echo "Expected zsync output at $OUTPUT.zsync" >&2
  exit 1
fi

PASSPHRASE="${LINUX_APPIMAGE_GPG_PASSPHRASE:-${APPIMAGETOOL_SIGN_PASSPHRASE:-}}"
GPG_ARGS=(--batch --yes --armor --local-user "$SIGN_KEY")
log_step "Signing detached AppImage signature"
if [[ -n "$PASSPHRASE" ]]; then
  GPG_ARGS+=(--pinentry-mode loopback --passphrase-fd 0)
  printf '%s\n' "$PASSPHRASE" | gpg "${GPG_ARGS[@]}" --detach-sign --output "$OUTPUT.asc" "$OUTPUT"
else
  gpg "${GPG_ARGS[@]}" --detach-sign --output "$OUTPUT.asc" "$OUTPUT"
fi

(
  cd "$OUTPUT_DIR"
  sha256sum "$(basename "$OUTPUT")" > "$(basename "$OUTPUT").sha256"
  sha256sum -c "$(basename "$OUTPUT").sha256"
)

log_step "Verifying AppImage signatures"
env -u APPIMAGE_EXTRACT_AND_RUN "$OUTPUT" --appimage-signature >/dev/null
gpg --batch --verify "$OUTPUT.asc" "$OUTPUT"

echo "AppImage written to $OUTPUT"
if [[ -n "$UPDATE_INFO" ]]; then
  echo "zsync written to $OUTPUT.zsync"
fi
echo "sha256 written to $OUTPUT.sha256"
echo "detached signature written to $OUTPUT.asc"
