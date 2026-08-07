#!/usr/bin/env bash
# Orchestrate a local PIR + dummy voting-config smoke against this checkout.
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PIR_REPO="${PIR_REPO:-$(cd "${ROOT}/../vote-nullifier-pir" && pwd)}"
CONFIG_HOST="${CONFIG_HOST:-127.0.0.1}"
CONFIG_PORT="${CONFIG_PORT:-18080}"
PIR_HOST="${PIR_HOST:-127.0.0.1}"
PIR_PORT="${PIR_PORT:-13000}"
ZCASH_NETWORK="${ZCASH_NETWORK:-main}"
STATIC_IDENTITY_URL="${STATIC_IDENTITY_URL:-https://config.smoke.test/static-voting-config.json}"
DYNAMIC_IDENTITY_URL="${DYNAMIC_IDENTITY_URL:-https://config.smoke.test/dynamic-voting-config.json}"
PIR_IDENTITY_URL="${PIR_IDENTITY_URL:-https://pir.smoke.test}"
PRESENT_NF_HEX="${PRESENT_NF_HEX:-0700000000000000000000000000000000000000000000000000000000000000}"
ABSENT_NF_HEX="${ABSENT_NF_HEX:-6400000000000000000000000000000000000000000000000000000000000000}"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/pir-smoke.XXXXXX")"
PIR_DATA_DIR="${WORKDIR}/pir-data"
CONFIG_DIR="${WORKDIR}/config"
NULLIFIERS_BIN="${PIR_DATA_DIR}/nullifiers.bin"
CARGO_LOCK_BAK="${WORKDIR}/Cargo.lock.bak"
CONFIG_PID=""
PIR_PID=""
CLEANED=0

cleanup() {
  local code=$?
  if [[ "${CLEANED}" -eq 1 ]]; then
    return
  fi
  CLEANED=1
  if [[ -n "${CONFIG_PID}" ]] && kill -0 "${CONFIG_PID}" 2>/dev/null; then
    kill "${CONFIG_PID}" 2>/dev/null || true
    wait "${CONFIG_PID}" 2>/dev/null || true
  fi
  if [[ -n "${PIR_PID}" ]] && kill -0 "${PIR_PID}" 2>/dev/null; then
    kill "${PIR_PID}" 2>/dev/null || true
    wait "${PIR_PID}" 2>/dev/null || true
  fi
  if [[ -f "${CARGO_LOCK_BAK}" ]]; then
    cp -f "${CARGO_LOCK_BAK}" "${ROOT}/Cargo.lock"
  fi
  rm -rf "${WORKDIR}"
  exit "${code}"
}
trap cleanup EXIT INT TERM

log() { printf '[pir-smoke] %s\n' "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd cargo
require_cmd python3
require_cmd curl

if [[ ! -d "${PIR_REPO}" ]]; then
  echo "PIR_REPO does not exist: ${PIR_REPO}" >&2
  exit 1
fi
if [[ ! -f "${PIR_REPO}/pir/client/Cargo.toml" ]]; then
  echo "PIR_REPO does not look like vote-nullifier-pir: ${PIR_REPO}" >&2
  exit 1
fi

PIR_REPO="$(cd "${PIR_REPO}" && pwd)"
log "work dir: ${WORKDIR}"
log "PIR repo: ${PIR_REPO}"
mkdir -p "${PIR_DATA_DIR}" "${CONFIG_DIR}"
cp "${ROOT}/Cargo.lock" "${CARGO_LOCK_BAK}"

# Prefer the configured ports, but fall forward if a previous run left them busy.
pick_port() {
  local preferred="$1"
  python3 - <<PY
import socket
preferred = int("${preferred}")
for port in [preferred, *range(preferred + 1, preferred + 50)]:
    sock = socket.socket()
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("${CONFIG_HOST}", port))
        print(port)
        break
    except OSError:
        continue
    finally:
        sock.close()
else:
    raise SystemExit(f"no free port near {preferred}")
PY
}
CONFIG_PORT="$(pick_port "${CONFIG_PORT}")"
PIR_PORT="$(pick_port "${PIR_PORT}")"
log "config port: ${CONFIG_PORT}"
log "PIR port: ${PIR_PORT}"

# ── Synthetic nullifier dataset (one known-present nullifier) ────────────────
python3 - <<PY
from pathlib import Path
present = bytes.fromhex("${PRESENT_NF_HEX}")
if len(present) != 32:
    raise SystemExit(f"PRESENT_NF_HEX must decode to 32 bytes, got {len(present)}")
path = Path("${NULLIFIERS_BIN}")
path.write_bytes(present)
print(f"wrote {path} ({len(present)} bytes)")
PY

cat > "${PIR_DATA_DIR}/nullifiers.dataset.json" <<EOF
{
  "zcash_network": "${ZCASH_NETWORK}",
  "nullifier_pool": "ironwood",
  "dataset_version": 2
}
EOF

# Optional checkpoint so metadata carries a height.
python3 - <<PY
from pathlib import Path
height = 3_428_150
offset = 32
path = Path("${PIR_DATA_DIR}/nullifiers.checkpoint")
path.write_bytes(height.to_bytes(8, "little") + offset.to_bytes(8, "little"))
print(f"wrote {path} height={height}")
PY

# Point this workspace at the sibling PIR checkout without rewriting Cargo.toml.
# Cargo --config path keys override the git [patch.crates-io] entries.
run_pir_smoke() {
  cargo run --manifest-path "${ROOT}/Cargo.toml" \
    --config "patch.crates-io.pir-client.path=\"${PIR_REPO}/pir/client\"" \
    --config "patch.crates-io.pir-types.path=\"${PIR_REPO}/pir/types\"" \
    --config "patch.crates-io.imt-tree.path=\"${PIR_REPO}/imt-tree\"" \
    -p zcash_voting --example pir_smoke -- "$@"
}

# ── Export PIR tiers from the sibling tree ───────────────────────────────────
log "building/exporting PIR tiers"
(
  cd "${PIR_REPO}"
  cargo run --release -p pir-export --features cli -- \
    --nullifiers "${NULLIFIERS_BIN}" \
    --output-dir "${PIR_DATA_DIR}" \
    --checkpoint "${PIR_DATA_DIR}/nullifiers.checkpoint"
)

# ── Write hash-pinned dummy static/dynamic config ────────────────────────────
log "writing dummy voting config"
STATIC_SHA="$(
  run_pir_smoke prepare \
    --out-dir "${CONFIG_DIR}" \
    --static-identity-url "${STATIC_IDENTITY_URL}" \
    --dynamic-identity-url "${DYNAMIC_IDENTITY_URL}" \
    --pir-identity-url "${PIR_IDENTITY_URL}" \
    --print-static-sha256
)"
log "static sha256: ${STATIC_SHA}"

# ── Start local servers ──────────────────────────────────────────────────────
log "starting config HTTP server on ${CONFIG_HOST}:${CONFIG_PORT}"
(
  cd "${CONFIG_DIR}"
  python3 -m http.server "${CONFIG_PORT}" --bind "${CONFIG_HOST}"
) >"${WORKDIR}/config-server.log" 2>&1 &
CONFIG_PID=$!

log "starting PIR server on ${PIR_HOST}:${PIR_PORT}"
(
  cd "${PIR_REPO}"
  SVOTE_ZCASH_NETWORK="${ZCASH_NETWORK}" \
    cargo run --release -p pir-server -- \
      "${PIR_DATA_DIR}" \
      "${PIR_PORT}"
) >"${WORKDIR}/pir-server.log" 2>&1 &
PIR_PID=$!

wait_http() {
  local url="$1"
  local name="$2"
  local i
  for i in $(seq 1 120); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      log "${name} ready: ${url}"
      return 0
    fi
    if [[ -n "${CONFIG_PID}" ]] && ! kill -0 "${CONFIG_PID}" 2>/dev/null; then
      echo "config server exited early; log:" >&2
      cat "${WORKDIR}/config-server.log" >&2 || true
      exit 1
    fi
    if [[ -n "${PIR_PID}" ]] && ! kill -0 "${PIR_PID}" 2>/dev/null; then
      echo "PIR server exited early; log:" >&2
      cat "${WORKDIR}/pir-server.log" >&2 || true
      exit 1
    fi
    sleep 1
  done
  echo "timed out waiting for ${name}: ${url}" >&2
  echo "--- config server log ---" >&2
  cat "${WORKDIR}/config-server.log" >&2 || true
  echo "--- PIR server log ---" >&2
  cat "${WORKDIR}/pir-server.log" >&2 || true
  exit 1
}

wait_http "http://${CONFIG_HOST}:${CONFIG_PORT}/static-voting-config.json" "config server"
wait_http "http://${PIR_HOST}:${PIR_PORT}/health" "PIR server"

PINNED_SOURCE="${STATIC_IDENTITY_URL}?checksum=sha256:${STATIC_SHA}"
log "running smoke driver"
run_pir_smoke run \
  --fetch-base "http://${CONFIG_HOST}:${CONFIG_PORT}" \
  --static-source "${PINNED_SOURCE}" \
  --pir-url "http://${PIR_HOST}:${PIR_PORT}" \
  --present-nf "${PRESENT_NF_HEX}" \
  --absent-nf "${ABSENT_NF_HEX}"

log "PASS"
