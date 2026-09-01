#!/usr/bin/env bash
# Launch the Vizor Linux desktop app headlessly for manual/GUI testing.
#
# flutter_secure_storage_linux talks to the libsecret Secret Service, which
# otherwise pops a blocking "create keyring" GTK prompt on a fresh headless
# box. This script brings up a session D-Bus and an unlocked gnome-keyring so
# the app boots straight to onboarding. It builds the debug bundle on first run.
#
# Requires a display (start one with .cursor/xvfb.sh). Override the network with
# ZCASH_DEFAULT_NETWORK (default: test).
set -euo pipefail

export PATH="$HOME/fvm/bin:/usr/local/cargo/bin:$PATH"
export DISPLAY="${DISPLAY:-:99}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime}"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"

# Session bus for the Secret Service.
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  eval "$(dbus-launch --sh-syntax)"
  export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
fi

# Create + unlock the login keyring (password from stdin) and register the
# secrets component on the session bus so libsecret never prompts.
printf 'vizor-dev' | gnome-keyring-daemon --daemonize --login >/dev/null 2>&1 || true
eval "$(gnome-keyring-daemon --start --components=secrets,pkcs11,ssh 2>/dev/null \
        | grep -E '^[A-Z_]+=' || true)"
export SSH_AUTH_SOCK GNOME_KEYRING_CONTROL

NET="${ZCASH_DEFAULT_NETWORK:-test}"
BUNDLE="build/linux/x64/debug/bundle/vizor"
if [ ! -x "$BUNDLE" ]; then
  echo "Building Linux debug bundle (network=$NET) ..."
  fvm flutter build linux --debug --dart-define=ZCASH_DEFAULT_NETWORK="$NET"
fi

echo "Launching $BUNDLE on DISPLAY=$DISPLAY (network=$NET) ..."
exec "$BUNDLE"
