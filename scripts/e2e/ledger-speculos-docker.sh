#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LANE="${1:-desktop}"
case "$LANE" in
  -h|--help)
    echo 'Usage: scripts/e2e/ledger-speculos-docker.sh [desktop|mobile|smoke|signing-smoke|voting-tally]'
    echo 'Optional: VIZOR_LEDGER_SPECULOS_ELF, VIZOR_LEDGER_E2E_SCENARIO, FLUTTER_DEVICE'
    echo 'See docs/ledger/speculos.md for setup, pinned versions, and limitations.'
    exit 0 ;;
  desktop|mobile|smoke|signing-smoke|voting-tally) ;;
  *) echo "Unknown lane: $LANE" >&2; exit 2 ;;
esac
source "$ROOT_DIR/scripts/e2e/ledger-speculos-scenarios.sh"
if [[ "$LANE" == desktop || "$LANE" == mobile ]]; then
  for cmd in cargo fvm base64 gzip; do
    command -v "$cmd" >/dev/null || { echo "Missing command: $cmd" >&2; exit 1; }
  done
  if [[ "$LANE" == mobile && -z "${FLUTTER_DEVICE:-}" ]]; then
    echo "Set FLUTTER_DEVICE to an iOS or Android simulator device id" >&2
    exit 2
  fi
  # Reject misspelled filters before pulling images or compiling the app.
  MATCHED=false
  run_flutter_scenario() {
    if [[ -z "${VIZOR_LEDGER_E2E_SCENARIO:-}" || "$1" == "$VIZOR_LEDGER_E2E_SCENARIO" ]]; then MATCHED=true; fi
  }
  ledger_speculos_scenarios "$LANE"
  if [[ "$MATCHED" != true ]]; then
    echo "No matching scenario: $VIZOR_LEDGER_E2E_SCENARIO" >&2
    exit 2
  fi
fi
if [[ "$LANE" == signing-smoke ]]; then
  command -v cargo >/dev/null || { echo "Missing command: cargo" >&2; exit 1; }
fi
for cmd in docker git curl jq; do
  command -v "$cmd" >/dev/null || { echo "Missing command: $cmd" >&2; exit 1; }
done
ANDROID_DEVICE=""
if [[ "$LANE" == mobile ]]; then
  TARGET_PLATFORM="$(fvm flutter devices --machine | jq -er --arg id "$FLUTTER_DEVICE" '
    .[] | select(.id == $id and .emulator == true) | .targetPlatform')" || {
    echo "FLUTTER_DEVICE must exactly match a connected iOS simulator or Android emulator id" >&2
    exit 2
  }
  case "$TARGET_PLATFORM" in
    android-*)
      command -v adb >/dev/null || { echo "Add Android SDK platform-tools (adb) to PATH" >&2; exit 1; }
      ANDROID_DEVICE="$FLUTTER_DEVICE"
      ;;
    ios) ;;
    *) echo "Unsupported mobile platform: $TARGET_PLATFORM" >&2; exit 2 ;;
  esac
fi
docker info >/dev/null

APP_COMMIT=1a0f6495458ecb77abf97c8cff25b0a1a344daaa
BUILDER_IMAGE="${VIZOR_LEDGER_BUILDER_IMAGE:-ghcr.io/ledgerhq/ledger-app-builder/ledger-app-builder@sha256:2e085afbe636098763e34ef6eca6069ea1a0f702805f6b14870c0f952262da6d}"
SPECULOS_IMAGE="${VIZOR_LEDGER_SPECULOS_IMAGE:-ghcr.io/ledgerhq/speculos@sha256:6ed9eefd51cddd862b746719af4cd7a3265fe43d0588c388359753cab8d46d11}"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vizor-speculos.XXXXXX")"
RESOURCE="vizor-speculos-$(basename "$RUN_DIR" | tr '[:upper:]' '[:lower:]')"
VOLUME=""
CONTAINERS=()
REVERSE_PORT=""
stop_containers() {
  local id
  if [[ -n "$REVERSE_PORT" ]]; then
    adb -s "$ANDROID_DEVICE" reverse --remove "tcp:$REVERSE_PORT" || true
    REVERSE_PORT=""
  fi
  for id in ${CONTAINERS[@]+"${CONTAINERS[@]}"}; do
    docker rm -f "$id" >/dev/null 2>&1 || true
  done
  CONTAINERS=()
}
cleanup() {
  local result=$?
  trap - EXIT
  stop_containers
  if [[ -n "$VOLUME" ]]; then docker volume rm "$VOLUME" >/dev/null || true; fi
  echo "Ledger Speculos artifacts retained: $RUN_DIR"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$RUN_DIR/elf"
echo "Ledger Speculos artifacts: $RUN_DIR"
printf 'app_commit=%s\nbuilder=%s\nspeculos=%s\n' "$APP_COMMIT" "$BUILDER_IMAGE" "$SPECULOS_IMAGE" > "$RUN_DIR/versions.txt"
ELF="${VIZOR_LEDGER_SPECULOS_ELF:-}"
if [[ "$LANE" == voting-tally ]]; then
  ELF="${VIZOR_LEDGER_SPECULOS_TESTNET_ELF:-}"
fi
if [[ -n "$ELF" ]]; then
  cp "$ELF" "$RUN_DIR/elf/zcash-nanosplus.elf"
  printf 'external_elf=%s\n' "$ELF" >> "$RUN_DIR/versions.txt"
else
  git clone https://github.com/LedgerHQ/app-zcash.git "$RUN_DIR/app-zcash" > "$RUN_DIR/clone.log" 2>&1
  git -C "$RUN_DIR/app-zcash" checkout --detach "$APP_COMMIT" >> "$RUN_DIR/clone.log" 2>&1
  build_features=()
  if [[ "$LANE" == voting-tally ]]; then
    # The testnet feature changes the app coin type, but not its OS path permissions.
    python3 - "$RUN_DIR/app-zcash/Cargo.toml" <<'PYTHON'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = 'path = ["44\'/133\'", "32\'/133\'"]'
assert s.count(old) == 1
p.write_text(s.replace(old, 'path = ["44\'/1\'", "32\'/1\'"]'))
PYTHON
    build_features=(-- --features testnet)
    echo 'test_variant=coin_type_1,load_prefix_44h_1h_and_32h_1h' >> "$RUN_DIR/versions.txt"
  fi
  VOLUME="$(docker volume create "$RESOURCE-target")"
  CONTAINERS+=("$RESOURCE-build")
  echo "Building Zcash 3.9.4 Nano S+ ELF; log: $RUN_DIR/build.log"
  docker run --rm --name "$RESOURCE-build" \
    -v "$RUN_DIR/app-zcash:/app" -v "$VOLUME:/app/target" \
    -w /app "$BUILDER_IMAGE" cargo ledger build nanosplus ${build_features[@]+"${build_features[@]}"} > "$RUN_DIR/build.log" 2>&1
  CONTAINERS+=("$RESOURCE-copy")
  docker run --rm --name "$RESOURCE-copy" -v "$VOLUME:/t" -v "$RUN_DIR/elf:/out" \
    "$BUILDER_IMAGE" cp /t/nanosplus/release/zcash /out/zcash-nanosplus.elf
fi

start_instance() {
  local purpose="$1" id port attempt
  id="$RESOURCE-$purpose"
  CONTAINERS+=("$id")
  local seed_args=()
  if [[ "$LANE" == voting-tally ]]; then
    # Same disposable mnemonic used by desktop_regtest_flow.dart for funding.
    seed_args=(--seed 'winter shiver fetch refuse absurd mail pistol eight market lounge manual roast miracle ethics found child scare curve congress renew salute pig better used')
  fi
  docker run -d --name "$id" -p 127.0.0.1::5000 \
    -v "$RUN_DIR/elf:/apps:ro" "$SPECULOS_IMAGE" \
    --model nanosp --display headless --api-port 5000 ${seed_args[@]+"${seed_args[@]}"} /apps/zcash-nanosplus.elf >/dev/null
  port="$(docker inspect --format '{{(index (index .NetworkSettings.Ports "5000/tcp") 0).HostPort}}' "$id")"
  INSTANCE_URL="http://127.0.0.1:$port"
  for ((attempt=0; attempt<60; attempt++)); do
    if curl --max-time 2 -fsS "$INSTANCE_URL/events?currentscreenonly=true" 2>/dev/null |
      jq -e 'any(.events[]?; (.text // "") | contains("app is ready"))' >/dev/null; then
      if [[ -n "$ANDROID_DEVICE" ]]; then
        # Keep host-side fixture URLs and app-side URLs identical. Never replace
        # an existing mapping; cleanup removes only this scenario's mapping.
        adb -s "$ANDROID_DEVICE" reverse --no-rebind "tcp:$port" "tcp:$port"
        REVERSE_PORT="$port"
      fi
      return 0
    fi
    sleep 1
  done
  docker logs "$id" >&2
  echo "Speculos did not become ready: $purpose" >&2
  return 1
}

FILTER="${VIZOR_LEDGER_E2E_SCENARIO:-}"
COUNT=0
RESULT=0
run_flutter_scenario() {
  local name="$1" code=0
  if [[ -n "$FILTER" && "$name" != "$FILTER" ]]; then return; fi
  COUNT=$((COUNT + 1))
  stop_containers
  start_instance device
  export VIZOR_LEDGER_SPECULOS_UFVK_API_URL="$INSTANCE_URL"
  export VIZOR_LEDGER_SPECULOS_SIGNING_API_URL="$INSTANCE_URL"
  echo "Running $name (log: $RUN_DIR/scenario-$COUNT.log)"
  if [[ "$LANE" == smoke ]]; then
    echo "Speculos instance ready." > "$RUN_DIR/scenario-$COUNT.log"
  elif [[ "$LANE" == signing-smoke ]]; then
    cargo run --manifest-path "$ROOT_DIR/rust/Cargo.toml" \
      --example ledger_zcash_speculos_poc -- desktop-smoke \
      --api-url "$INSTANCE_URL" --signing-api-url "$INSTANCE_URL" \
      > "$RUN_DIR/scenario-$COUNT.log" 2>&1 || code=$?
  else
    local runner=macos
    if [[ "$LANE" == mobile ]]; then runner=mobile; fi
    VIZOR_LEDGER_E2E_SCENARIO="$name" \
      bash "$ROOT_DIR/scripts/e2e/flutter-$runner-ledger-speculos.sh" \
      > "$RUN_DIR/scenario-$COUNT.log" 2>&1 || code=$?
  fi
  docker logs "$RESOURCE-device" > "$RUN_DIR/scenario-$COUNT-device.log" 2>&1 || true
  printf '%s\t%s\n' "$code" "$name" | tee -a "$RUN_DIR/results.tsv"
  if ((code != 0)); then RESULT=1; fi
  stop_containers
}
if [[ "$LANE" == voting-tally ]]; then
  cargo build --manifest-path "$ROOT_DIR/rust/Cargo.toml" --example ledger_zcash_speculos_poc
  export VIZOR_LEDGER_REGTEST_HELPER="$ROOT_DIR/rust/target/debug/examples/ledger_zcash_speculos_poc"
  export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-${RESOURCE//./-}-vote}"
  case "${E2E_LEDGER_VOTING:-}" in
    ''|true|false) ;;
    *) echo 'E2E_LEDGER_VOTING must be true or false' >&2; exit 2 ;;
  esac
  for ledger in ${E2E_LEDGER_VOTING:-false true}; do
    stop_containers
    start_instance device
    export VIZOR_LEDGER_SPECULOS_UFVK_API_URL="$INSTANCE_URL"
    export VIZOR_LEDGER_SPECULOS_SIGNING_API_URL="$INSTANCE_URL"
    export VIZOR_LEDGER_REGTEST_ACCOUNT="$RUN_DIR/ledger-account.json"
    "$VIZOR_LEDGER_REGTEST_HELPER" regtest-export "$INSTANCE_URL" unused "$VIZOR_LEDGER_REGTEST_ACCOUNT" \
      > "$RUN_DIR/account-export-$ledger.log" 2>&1
    echo "Running desktop final tally: ledger=$ledger"
    E2E_LEDGER_VOTING="$ledger" E2E_FINAL_TALLY=true \
      E2E_VOTE_WINDOW_SECS="${E2E_VOTE_WINDOW_SECS:-300}" \
      FLUTTER_DEVICE=macos VIZOR_FORM_FACTOR=desktop \
      E2E_VOTING_TEST_FILE=integration_test/regtest_voting_test.dart \
      bash "$ROOT_DIR/scripts/e2e/flutter-macos-regtest-voting.sh" \
      > "$RUN_DIR/voting-tally-$ledger.log" 2>&1 || {
        docker logs "$RESOURCE-device" > "$RUN_DIR/voting-tally-$ledger-device.log" 2>&1 || true
        echo "Desktop final tally failed: $RUN_DIR/voting-tally-$ledger.log" >&2
        exit 1
      }
    cp "$ROOT_DIR/.regtest-voting/logs/final-tally-$ledger.json" "$RUN_DIR/"
    docker logs "$RESOURCE-device" > "$RUN_DIR/voting-tally-$ledger-device.log" 2>&1 || true
    echo "Desktop final tally passed: ledger=$ledger"
  done
  exit 0
elif [[ "$LANE" == smoke ]]; then
  FILTER=""
  run_flutter_scenario 'Speculos startup smoke'
elif [[ "$LANE" == signing-smoke ]]; then
  FILTER=""
  run_flutter_scenario 'UFVK export then signing on one device'
else
  ledger_speculos_scenarios "$LANE"
fi
if ((COUNT == 0)); then echo "No matching scenario: $FILTER" >&2; exit 2; fi
exit "$RESULT"
