#!/usr/bin/env bash
# Long-running headless display for launching the Vizor Linux desktop app.
# Runs as a Cloud Agent terminal: starts a virtual X server (Xvfb) plus a
# lightweight window manager (openbox) on DISPLAY=:99 and stays in the
# foreground so its logs and lifecycle remain visible/restartable.
set -euo pipefail

export DISPLAY=:99

# Deterministic restart: drop any stale server from a previous boot.
pkill -x Xvfb 2>/dev/null || true
sleep 1

Xvfb :99 -screen 0 1280x900x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!
sleep 2

openbox &

echo "Headless display ready on DISPLAY=:99 (Xvfb + openbox)."
echo "Run the built desktop app with: bash .cursor/run-linux-app.sh"

# Keep the terminal (and thus the display) alive.
wait "$XVFB_PID"
