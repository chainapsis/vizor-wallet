#!/usr/bin/env bash
# Proxy delegation through the real Vizor app on a full local stack:
#
# - Zcash: the Ironwood regtest stack (zcashd and lightwalletd in Docker) and
#   a wallet funded through the real Orchard-to-Ironwood migration;
# - PIR: vote-nullifier-pir built from a local checkout, over the regtest
#   nullifiers at the round's snapshot;
# - vote chain: vote-sdk's isolated PROXY=1 localnet (svoted built with
#   -tags proxyenabled, proxy params, two vote managers), started through the
#   delegate verifier's dev stack scripts;
# - attester: the dev stack (docs/devstack.md in delegate-verifier) with two
#   delegates registered through its attester API on the fake X, and the
#   signed dynamic config with extensions.proxy_delegation_v1, all over HTTPS
#   under the stack's development CA;
# - a test Vizor wallet list (contracts-v1 section 12.3) with a row for every
#   live entry of the chain's registry, signed with a throwaway key and
#   served from the dev stack's config mirror;
# - a loopback gateway for the logical vote, PIR and participation hosts;
# - Vizor, built with VIZOR_PROXY_DELEGATION_ENABLED and zcash_voting's
#   dev-only unstable-proxy-delegation feature, driven by
#   integration_test/regtest_proxy_delegation_test.dart.
#
# Every checkout is local; nothing is cloned. See scripts/e2e/README.md,
# "Proxy delegation", for the commands, variables and ports.
#
#   flutter-macos-regtest-proxy-delegation.sh [--keep]   up, test, then down
#   flutter-macos-regtest-proxy-delegation.sh up         bring the stack up and leave it
#   flutter-macos-regtest-proxy-delegation.sh round      create and publish another proxy round, re-sign the list
#   flutter-macos-regtest-proxy-delegation.sh list       re-sign the wallet list from the chain's registry
#   flutter-macos-regtest-proxy-delegation.sh switch     restart the verifier dev stack in new provider modes
#   flutter-macos-regtest-proxy-delegation.sh test       run the Flutter test on the running stack
#   flutter-macos-regtest-proxy-delegation.sh ballots    post the delegates' ballots in the round
#   flutter-macos-regtest-proxy-delegation.sh app        run Vizor by hand against the stack
#   flutter-macos-regtest-proxy-delegation.sh status     show what runs
#   flutter-macos-regtest-proxy-delegation.sh down       stop and remove everything
#
# DEVSTACK_X and DEVSTACK_GITHUB pick each provider of the dev stack, real or
# fake, for up and switch, where both default to real. The full run and test
# register delegates and post through the fakes, so they run both fake and
# refuse either set to real. With real X, up registers no test delegates:
# register real ones in the app, then run list, whose re-signed list shows
# them in browse.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="${E2E_PROXY_STATE_DIR:-$ROOT_DIR/.regtest-proxy-delegation}"
mkdir -p "$STATE_DIR"
STATE_DIR="$(cd "$STATE_DIR" && pwd -P)"
LOG_DIR="$STATE_DIR/logs"
PID_DIR="$STATE_DIR/pids"
STACK_ENV="$STATE_DIR/stack.env"

VOTE_SDK_DIR="$(cd "${E2E_VOTE_SDK_DIR:-$ROOT_DIR/../vote-sdk}" && pwd)"
VERIFIER_DIR="$(cd "${E2E_DELEGATE_VERIFIER_DIR:-$ROOT_DIR/../delegate-verifier}" && pwd)"
PIR_DIR="${E2E_PIR_DIR:-$STATE_DIR/deps/vote-nullifier-pir}"
# vote-nullifier-pir v0.12.2, which builds from a warm cargo cache alone.
PIR_REV="${E2E_PIR_REV:-38a3ecd3b94653f0659fe39e62e11f9a352558e5}"

ACTIVATION_HEIGHT=500
export IRONWOOD_ACTIVATION_HEIGHT="$ACTIVATION_HEIGHT"
export IRONWOOD_REGTEST_STATE_DIR="$STATE_DIR/zcash"
export IRONWOOD_COMPOSE_PROJECT="${E2E_IRONWOOD_COMPOSE_PROJECT:-vizor-proxy-delegation-regtest}"
export IRONWOOD_LIGHTWALLETD_PORT="${E2E_IRONWOOD_LIGHTWALLETD_PORT:-29067}"
export IRONWOOD_ZCASHD_RPC_PORT="${E2E_IRONWOOD_ZCASHD_RPC_PORT:-29232}"
DRIVER_PORT="${E2E_DRIVER_PORT:-29078}"
PIR_PORT="${E2E_PIR_PORT:-23000}"
GATEWAY_PORT="${E2E_VOTING_GATEWAY_PORT:-28080}"
# The vote chain's listeners, off vote-sdk's and the dev stack's defaults.
VOTE_PORT="${E2E_VOTE_PORT:-23317}"
VOTE_RPC_PORT="${E2E_VOTE_RPC_PORT:-38657}"
VOTE_P2P_PORT="${E2E_VOTE_P2P_PORT:-38656}"
VOTE_ABCI_PORT="${E2E_VOTE_ABCI_PORT:-38658}"
VOTE_PROMETHEUS_PORT="${E2E_VOTE_PROMETHEUS_PORT:-38660}"
VOTE_GRPC_PORT="${E2E_VOTE_GRPC_PORT:-29190}"
VOTE_GRPC_WEB_PORT="${E2E_VOTE_GRPC_WEB_PORT:-29191}"
VOTE_PPROF_PORT="${E2E_VOTE_PPROF_PORT:-26260}"
DEVSTACK_PORT_BASE="${E2E_DEVSTACK_PORT_BASE:-27200}"
LOCALNET_DIR="$STATE_DIR/localnet"
# The devstack binary reads the running stack from DEVSTACK_DIR.
export DEVSTACK_DIR="$STATE_DIR/devstack"
PIR_DATA_DIR="$STATE_DIR/pir-data"
GATEWAY_CONFIG_DIR="$STATE_DIR/gateway-config"
DELEGATES_DIR="$STATE_DIR/delegates"
# The test wallet list's throwaway signing key and draft.
WALLET_LIST_DIR="$STATE_DIR/wallet-list"
WALLET_LIST_KEY_ID="vizor-regtest"

# The funded wallet: 1.01 ZEC migrates to eight 0.125 ZEC ballots.
FUNDING_AMOUNT="${E2E_PROXY_FUNDING_AMOUNT:-1.01}"
FUNDING_ZATOSHI="${E2E_PROXY_FUNDING_ZATOSHI:-101000000}"
# Voting opens when the round is created and the test waits for the close,
# so the window covers the app's build, delegation, the kept vote and the
# helpers' share reveal: about three minutes on a warm build. Set it longer
# for testing by hand.
VOTE_WINDOW_SECS="${E2E_PROXY_VOTE_WINDOW_SECS:-900}"
PROPOSAL_COUNT=2
# The delegates' ballots: one option per proposal.
DELEGATE_A_OPTIONS="${E2E_PROXY_DELEGATE_A_OPTIONS:-0,1}"
DELEGATE_B_OPTIONS="${E2E_PROXY_DELEGATE_B_OPTIONS:-1,0}"
TEST_FILE="${E2E_PROXY_TEST_FILE:-integration_test/regtest_proxy_delegation_test.dart}"
MANUAL_ENTRYPOINT="integration_test/support/regtest_proxy_delegation_manual_main.dart"

log() {
  echo "[proxy-regtest $(date +%H:%M:%S)] $*"
}

die() {
  echo "[proxy-regtest] ERROR: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# port_listening reports whether anything listens on TCP port $1.
port_listening() {
  lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

# check_ports_free refuses to start when any of the stack's ports is taken.
check_ports_free() {
  local port busy=""
  for port in "$IRONWOOD_LIGHTWALLETD_PORT" "$IRONWOOD_ZCASHD_RPC_PORT" "$DRIVER_PORT" \
    "$PIR_PORT" "$GATEWAY_PORT" "$VOTE_PORT" "$VOTE_RPC_PORT" "$VOTE_P2P_PORT" "$VOTE_ABCI_PORT" \
    "$VOTE_PROMETHEUS_PORT" "$VOTE_GRPC_PORT" "$VOTE_GRPC_WEB_PORT" "$VOTE_PPROF_PORT" \
    $(seq $((DEVSTACK_PORT_BASE + 1)) $((DEVSTACK_PORT_BASE + 50))); do
    if port_listening "$port"; then
      busy="$busy $port"
    fi
  done
  [[ -z "$busy" ]] || die "ports in use:$busy; stop their owners or move the stack's ports (see README)"
}

# wait_http waits up to three minutes for $1 to answer 2xx.
wait_http() {
  local url="$1" label="$2"
  for _ in $(seq 1 180); do
    if curl -fsS "$url" >/dev/null 2>&1; then return; fi
    sleep 1
  done
  die "timed out waiting for $label at $url"
}

# start_bg runs a command in the background with its log and pid file.
start_bg() {
  local name="$1"
  shift
  mkdir -p "$PID_DIR"
  nohup "$@" </dev/null >"$LOG_DIR/$name.log" 2>&1 &
  echo "$!" >"$PID_DIR/$name.pid"
}

# stop_bg stops a process start_bg started, only while its pid still runs
# the command it was started with.
stop_bg() {
  local name="$1" pattern="$2" pid command
  [[ -f "$PID_DIR/$name.pid" ]] || return 0
  pid="$(cat "$PID_DIR/$name.pid")"
  command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  if [[ -n "$command" && "$command" == *"$pattern"* ]]; then
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_DIR/$name.pid"
}

# STACK_X and STACK_GITHUB are the providers' modes the dev stack starts
# with: DEVSTACK_X and DEVSTACK_GITHUB, real unless set.
STACK_X="${DEVSTACK_X:-real}"
STACK_GITHUB="${DEVSTACK_GITHUB:-real}"

# devstack runs one of the verifier's dev stack scripts against this stack,
# with the providers' modes.
devstack() {
  local script="$1"
  shift
  DEVSTACK_DIR="$DEVSTACK_DIR" LOCALNET_DIR="$LOCALNET_DIR" VOTE_SDK_DIR="$VOTE_SDK_DIR" \
    DEVSTACK_PORT_BASE="$DEVSTACK_PORT_BASE" DEVSTACK_X="$STACK_X" DEVSTACK_GITHUB="$STACK_GITHUB" \
    bash "$VERIFIER_DIR/scripts/devstack/$script.sh" "$@"
}

# use_fake_providers runs the dev stack on both fakes for $1, which registers
# delegates and posts through them, refusing a request for a real provider.
use_fake_providers() {
  local name
  for name in DEVSTACK_X DEVSTACK_GITHUB; do
    [[ "${!name:-fake}" == fake ]] || die "$1 runs the dev stack on the fakes; unset $name (it is '${!name}')"
  done
  STACK_X=fake
  STACK_GITHUB=fake
}

# recorded_mode prints the mode the running dev stack records for $1
# (DEVSTACK_X or DEVSTACK_GITHUB); a stack recorded before the modes is fake.
recorded_mode() {
  local mode
  mode="$(sed -n "s/^$1=//p" "$DEVSTACK_DIR/devstack.env" 2>/dev/null | tail -n 1)"
  echo "${mode:-fake}"
}

# localnet_env prints the vote chain's test environment.
localnet_env() {
  LOCALNET_DIR="$LOCALNET_DIR" bash "$VOTE_SDK_DIR/scripts/localnet-isolated/env.sh"
}

# --- Bring-up steps ---------------------------------------------------------

# build_pir builds the PIR export tool and server from the local checkout,
# making that checkout from E2E_PIR_SOURCE (a local path) when it is absent.
build_pir() {
  if [[ ! -d "$PIR_DIR/.git" ]]; then
    [[ -n "${E2E_PIR_SOURCE:-}" ]] ||
      die "no vote-nullifier-pir checkout at $PIR_DIR; set E2E_PIR_DIR, or E2E_PIR_SOURCE to a local checkout to clone"
    [[ -d "$E2E_PIR_SOURCE" ]] || die "E2E_PIR_SOURCE must be a local directory, never a URL"
    git clone --quiet "$E2E_PIR_SOURCE" "$PIR_DIR"
    git -C "$PIR_DIR" checkout --quiet --detach "$PIR_REV"
  fi
  log "building the PIR server from $PIR_DIR ($(git -C "$PIR_DIR" rev-parse --short HEAD))"
  CARGO_TARGET_DIR="$STATE_DIR/build/pir" cargo build --release --offline \
    --manifest-path "$PIR_DIR/Cargo.toml" \
    -p pir-export --features cli -p nf-server --features serve >"$LOG_DIR/pir-build.log" 2>&1 ||
    { tail -n 30 "$LOG_DIR/pir-build.log" >&2; die "the PIR build failed"; }
}

# init_vote_chain writes a fresh PROXY=1 localnet with two vote managers.
init_vote_chain() {
  log "initializing the PROXY=1 vote chain in $LOCALNET_DIR"
  local skip=0
  [[ -x "$LOCALNET_DIR/bin/svoted" ]] && skip=1
  LOCALNET_SKIP_BUILD="${E2E_LOCALNET_SKIP_BUILD:-$skip}" \
    LOCALNET_API_PORT="$VOTE_PORT" LOCALNET_RPC_PORT="$VOTE_RPC_PORT" \
    LOCALNET_P2P_PORT="$VOTE_P2P_PORT" LOCALNET_ABCI_PORT="$VOTE_ABCI_PORT" \
    LOCALNET_PROMETHEUS_PORT="$VOTE_PROMETHEUS_PORT" LOCALNET_GRPC_PORT="$VOTE_GRPC_PORT" \
    LOCALNET_GRPC_WEB_PORT="$VOTE_GRPC_WEB_PORT" LOCALNET_PPROF_PORT="$VOTE_PPROF_PORT" \
    devstack localnet init >"$LOG_DIR/localnet-init.log" 2>&1 ||
    { tail -n 30 "$LOG_DIR/localnet-init.log" >&2; die "localnet init failed"; }
}

# fund_wallet resets the Ironwood chain and funds the deterministic wallet
# through the real migration, in a first Flutter run whose wallet the test
# reuses.
fund_wallet() {
  log "funding the wallet through the Orchard-to-Ironwood migration"
  E2E_LIGHTWALLETD_URL="http://127.0.0.1:$IRONWOOD_LIGHTWALLETD_PORT" \
    E2E_DRIVER_PORT="$DRIVER_PORT" \
    E2E_TEST_FILE=integration_test/regtest_voting_ironwood_setup_test.dart \
    E2E_ORCHARD_FUNDING_AMOUNT="$FUNDING_AMOUNT" \
    E2E_ORCHARD_FUNDING_ZATOSHI="$FUNDING_ZATOSHI" \
    E2E_ORCHARD_FUNDING_TEXT="$FUNDING_AMOUNT" \
    FLUTTER_DEVICE=macos VIZOR_FORM_FACTOR=desktop \
    VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}" \
    E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN=true \
    VIZOR_UNSTABLE_PROXY_DELEGATION=1 \
    "$ROOT_DIR/scripts/ironwood-regtest/run-flutter-test.sh" 2>&1 |
    tee "$LOG_DIR/fund-wallet.log"
}

# start_pir exports the regtest nullifiers at the snapshot height and serves
# them with the PIR server.
start_pir() {
  local height="$1"
  log "exporting Ironwood nullifiers at $height and starting the PIR server"
  rm -rf "$PIR_DATA_DIR"
  mkdir -p "$PIR_DATA_DIR"
  python3 "$ROOT_DIR/scripts/e2e/export-regtest-ironwood-nullifiers.py" \
    --proto-dir "$ROOT_DIR/protos" \
    --endpoint "127.0.0.1:$IRONWOOD_LIGHTWALLETD_PORT" \
    --activation-height "$ACTIVATION_HEIGHT" \
    --snapshot-height "$height" \
    --output "$PIR_DATA_DIR/nullifiers.bin" >"$LOG_DIR/nullifier-export.json"
  python3 - "$PIR_DATA_DIR" "$height" <<'PY'
import json, pathlib, struct, sys
directory = pathlib.Path(sys.argv[1])
height = int(sys.argv[2])
(directory / "nullifiers.dataset.json").write_text(json.dumps({
    "zcash_network": "test", "nullifier_pool": "ironwood", "dataset_version": 2
}, indent=2) + "\n")
offset = (directory / "nullifiers.bin").stat().st_size
(directory / "nullifiers.checkpoint").write_bytes(struct.pack("<QQ", height, offset))
PY
  "$STATE_DIR/build/pir/release/pir-export" \
    --nullifiers "$PIR_DATA_DIR/nullifiers.bin" \
    --checkpoint "$PIR_DATA_DIR/nullifiers.checkpoint" \
    --output-dir "$PIR_DATA_DIR" 2>"$LOG_DIR/pir-export.log"
  SVOTE_PIR_CONFIG_URL='' SVOTE_PIR_PRECOMPUTED_BASE_URL='' SENTRY_DSN='' \
    start_bg pir-server "$STATE_DIR/build/pir/release/nf-server" serve \
    --zcash-network test --port "$PIR_PORT" \
    --pir-data-dir "$PIR_DATA_DIR" --lwd-url "http://127.0.0.1:$IRONWOOD_LIGHTWALLETD_PORT" \
    --stale-threshold-secs 0
  wait_http "http://127.0.0.1:$PIR_PORT/ready" "PIR server"
  jq -e --argjson height "$height" \
    '.height == $height and .nullifier_pool == "ironwood" and .dataset_version == 2' \
    < <(curl -fsS "http://127.0.0.1:$PIR_PORT/root") >/dev/null ||
    die "the PIR server does not serve the snapshot at $height"
}

# start_verifier starts the vote chain and a fresh dev stack against it.
start_verifier() {
  log "starting the vote chain"
  devstack localnet start >"$LOG_DIR/localnet-start.log" 2>&1 ||
    { tail -n 30 "$LOG_DIR/localnet-start.log" >&2; die "localnet start failed"; }
  log "starting the verifier dev stack in $DEVSTACK_DIR (X $STACK_X, GitHub $STACK_GITHUB)"
  devstack clean >/dev/null
  devstack up >"$LOG_DIR/devstack-up.log" 2>&1 ||
    { tail -n 40 "$LOG_DIR/devstack-up.log" >&2; die "devstack up failed"; }
}

# register_delegates registers delegates A and B through the attester API on
# the fake X and waits until the chain's registry holds both entries under
# their handles. With real X there are none: the owner registers real
# delegates in the app.
register_delegates() {
  mkdir -p "$DELEGATES_DIR"
  rm -f "$DELEGATES_DIR/a.json" "$DELEGATES_DIR/b.json"
  if [[ "$STACK_X" == real ]]; then
    log "X is real: no test delegates; register real ones in the app, then run '$0 list'"
    return 0
  fi
  local name handle tag index
  # X handles are at most 15 characters of [a-z0-9_], and distinct per run
  # so each registers a new entry.
  tag="$(date +%s | tail -c 9)"
  for name in a b; do
    handle="alice_$tag"
    [[ "$name" == b ]] && handle="bob_$tag"
    log "registering delegate $name (@$handle) through the attester API"
    "$DEVSTACK_DIR/bin/devstack" delegate register \
      --handle "$handle" --out "$DELEGATES_DIR/$name.json" >/dev/null
    index="$(jq -r .delegate_index "$DELEGATES_DIR/$name.json")"
    for _ in $(seq 1 90); do
      curl -fsS "http://127.0.0.1:$VOTE_PORT/shielded-vote/v1/delegates/$index" 2>/dev/null |
        jq -e --arg handle "$handle" '(.delegate // .).handle == $handle' >/dev/null 2>&1 && continue 2
      sleep 2
    done
    die "the registry never held entry $index for @$handle"
  done
}

# create_round creates a proxy round over the regtest snapshot with two
# vote-manager approvals and publishes its config, then records it in the
# stack environment.
create_round() {
  # shellcheck disable=SC1090
  . "$STACK_ENV"
  local shim="$STATE_DIR/shims"
  mkdir -p "$shim"
  cat >"$shim/grpcurl" <<EOF
#!/usr/bin/env bash
exec "$(command -v grpcurl)" -plaintext -import-path "$ROOT_DIR/protos" -proto service.proto "\$@"
EOF
  chmod +x "$shim/grpcurl"
  log "creating a proxy round over snapshot $SNAPSHOT_HEIGHT (window ${VOTE_WINDOW_SECS}s)"
  (
    eval "$(localnet_env)"
    PATH="$shim:$PATH" \
      ZASHI_LIGHTWALLETD="127.0.0.1:$IRONWOOD_LIGHTWALLETD_PORT" \
      ZASHI_PIR_URL="http://127.0.0.1:$PIR_PORT" \
      ZASHI_SNAPSHOT_HEIGHT="$SNAPSHOT_HEIGHT" ZASHI_VOTE_WINDOW_SECS="$VOTE_WINDOW_SECS" \
      ZASHI_PROPOSAL_COUNT="$PROPOSAL_COUNT" ZASHI_PROXY_DELEGATION=1 \
      cargo test --release --manifest-path "$VOTE_SDK_DIR/e2e-tests/Cargo.toml" \
      --test create_round_for_zashi create_round_for_zashi -- --ignored --nocapture
  ) >"$LOG_DIR/create-round.log" 2>&1 ||
    { tail -n 40 "$LOG_DIR/create-round.log" >&2; die "round creation failed"; }
  local round
  round="$(sed -n 's/^\[create-round\] round_id: //p' "$LOG_DIR/create-round.log" | tail -n 1)"
  [[ "$round" =~ ^[0-9a-f]{64}$ ]] || die "no round id in $LOG_DIR/create-round.log"

  publish_round "$round"
  sed -i '' '/^ROUND_ID=/d' "$STACK_ENV"
  echo "ROUND_ID=$round" >>"$STACK_ENV"
  log "round $round is published"
}

# publish_round waits for round $1's ceremony to publish its ea_pk, signs
# the round's ordinary entry into the dynamic config and routes it to the
# gateway. There is no per-round proxy entry or vetting: every active entry
# can take delegations.
publish_round() {
  local round="$1" ea_pk=""
  log "waiting for round $round's ceremony"
  for _ in $(seq 1 150); do
    ea_pk="$(curl -fsS "http://127.0.0.1:$VOTE_PORT/shielded-vote/v1/round/$round" 2>/dev/null |
      jq -r '.round.ea_pk // ""' 2>/dev/null || true)"
    [[ -n "$ea_pk" ]] && break
    sleep 2
  done
  [[ -n "$ea_pk" ]] || die "round $round never published an ea_pk"
  log "signing round $round into the dynamic config"
  devstack config "$round" >"$LOG_DIR/config-$round.log" 2>&1 ||
    { tail -n 30 "$LOG_DIR/config-$round.log" >&2; die "config signing failed"; }
  route_config_to_gateway
}

# sign_wallet_list signs a Vizor wallet list (contracts-v1 section 12.3)
# with a row for every live entry of the chain's registry, carrying the
# entry's key, provider and handle, and serves it from the dev stack's config
# mirror at the path the config repo would host it. The key is a throwaway
# made once per stack; the app pins it through VIZOR_PROXY_WALLET_LIST_KEY.
# The list is checked as config CI does, with the chain check.
sign_wallet_list() {
  # shellcheck disable=SC1091
  . "$DEVSTACK_DIR/devstack.env"
  mkdir -p "$WALLET_LIST_DIR"
  local seed="$WALLET_LIST_DIR/signer.seed" public_key
  if [[ ! -f "$seed" ]]; then
    "$DEVSTACK_DIR/bin/voting-config" keygen --signer-id "$WALLET_LIST_KEY_ID" --out "$seed" |
      sed -n 's/^public_key_b64: //p' >"$seed.pub"
  fi
  public_key="$(cat "$seed.pub")"
  [[ -n "$public_key" ]] || die "no public key beside $seed"
  local draft="$WALLET_LIST_DIR/draft.json"
  python3 - "http://127.0.0.1:$VOTE_PORT" "$DEVSTACK_CHAIN_ID" "$(date +%s)" >"$draft" <<'PY'
import base64, json, sys, urllib.request

rest, chain_id, now = sys.argv[1], sys.argv[2], int(sys.argv[3])
CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
# Two 128 x 128 lossless WebP pictures, a checkerboard each.
PICTURES = [
    "UklGRjYAAABXRUJQVlA4TCkAAAAvf8AfAA/wvP+f/z/lf/7jAWTSNvFvuhrGnoj+v4ECqnYHqmB34P7vAAA=",
    "UklGRjYAAABXRUJQVlA4TCkAAAAvf8AfAA/wvP+n/P/8f/7jAWTSNvFvuhrGnoj+v4ECqnYHqmB34P7vAAA=",
]


def polymod(values):
    """The bech32 checksum polynomial over 5-bit values."""
    check = 1
    for value in values:
        top = check >> 25
        check = (check & 0x1FFFFFF) << 5 ^ value
        for bit, term in enumerate((0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3)):
            if (top >> bit) & 1:
                check ^= term
    return check


def zvdk(dk: bytes) -> str:
    """The key's canonical `zvdk1…` string: bech32m with zero padding."""
    hrp = "zvdk"
    bits = "".join(f"{byte:08b}" for byte in dk)
    bits += "0" * (-len(bits) % 5)
    data = [int(bits[i:i + 5], 2) for i in range(0, len(bits), 5)]
    expanded = [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp]
    check = polymod(expanded + data + [0] * 6) ^ 0x2BC830A3
    data += [(check >> 5 * (5 - i)) & 31 for i in range(6)]
    return hrp + "1" + "".join(CHARSET[value] for value in data)


rows, start_after = [], 0
while True:
    url = f"{rest}/shielded-vote/v1/delegates?start_after={start_after}&limit=1000"
    with urllib.request.urlopen(url) as response:
        page = json.load(response)
    for entry in page.get("delegates", []):
        # A retired entry (status 2) can't be reviewed.
        if int(entry.get("status", 0)) == 2:
            continue
        rows.append({
            "index": entry["index"],
            "provider": entry["provider"],
            "handle": entry["handle"],
            "dk": zvdk(base64.b64decode(entry["dk"])),
            "name": f"Regtest {entry['handle']}"[:50],
            "statement": f"Test delegate #{entry['index']} on the local proxy delegation stack.",
            "picture": PICTURES[len(rows) % len(PICTURES)],
        })
    start_after = int(page.get("next_start_after", 0))
    if start_after == 0:
        break
json.dump({
    "format": "zcash-vote-wallet-list/v1",
    "wallet_id": "vizor",
    "chain_id": chain_id,
    # A rising version, so an app that stored an earlier stack's list takes this one.
    "version": now,
    "issued_at": now,
    "reserved_names": [],
    "delegates": rows,
}, sys.stdout, indent=2)
PY
  local served="$DEVSTACK_CONFIG_REPO/stage/wallets/vizor/list.json"
  mkdir -p "$(dirname "$served")"
  "$DEVSTACK_DIR/bin/voting-config" wallet-list sign --list "$draft" \
    --signer-id "$WALLET_LIST_KEY_ID" --privkey-file "$seed" --out "$draft" \
    2>"$LOG_DIR/wallet-list-sign.log" ||
    { cat "$LOG_DIR/wallet-list-sign.log" >&2; die "signing the wallet list failed"; }
  "$DEVSTACK_DIR/bin/voting-config" wallet-list verify --list "$draft" \
    --wallet-id vizor --chain-id "$DEVSTACK_CHAIN_ID" \
    --allowed-key "$WALLET_LIST_KEY_ID=$public_key" \
    --chain-check "http://127.0.0.1:$VOTE_PORT" >"$LOG_DIR/wallet-list-verify.log" 2>&1 ||
    { cat "$LOG_DIR/wallet-list-verify.log" >&2; die "the wallet list does not verify"; }
  mv "$draft" "$served"
  sed -i '' '/^WALLET_LIST_/d' "$STACK_ENV"
  {
    echo "WALLET_LIST_URL=${DEVSTACK_CONFIG_URL%/*}/wallets/vizor/list.json"
    echo "WALLET_LIST_KEY=$WALLET_LIST_KEY_ID:$public_key"
  } >>"$STACK_ENV"
  log "signed the wallet list with $(jq '.delegates | length' "$served") delegates"
}

# route_config_to_gateway points the served dynamic config's unsigned vote
# server and PIR lists at the gateway's logical hosts, which Vizor's regtest
# endpoint mapper sends to the gateway, and checks the result as the config
# repository's CI does. Vizor's Rust transport, which posts to the vote
# servers and queries PIR, trusts only the platform's roots, so it reaches
# them through the plain loopback gateway rather than the stack's TLS fronts.
route_config_to_gateway() {
  # shellcheck disable=SC1091
  . "$DEVSTACK_DIR/devstack.env"
  local repo="$DEVSTACK_CONFIG_REPO/stage" staged
  staged="$(mktemp "$STATE_DIR/dynamic-XXXXXX")"
  jq '.vote_servers = [{url: "https://vote.vizor-vote.invalid", label: "regtest vote chain"}]
      | .pir_endpoints = [{url: "https://pir.vizor-vote.invalid", label: "regtest PIR"}]' \
    "$repo/dynamic-voting-config.json" >"$staged"
  "$DEVSTACK_DIR/bin/voting-config" verify --config "$staged" \
    --static-config "$repo/static-voting-config.json" \
    >"$LOG_DIR/config-verify.log" 2>&1 ||
    { cat "$LOG_DIR/config-verify.log" >&2; rm -f "$staged"; die "the routed config does not verify"; }
  mv "$staged" "$repo/dynamic-voting-config.json"
}

# start_gateway serves the logical vote and PIR hosts, the participation
# RPC, discovery and the delegates' ballot trigger on loopback.
start_gateway() {
  # shellcheck disable=SC1091
  . "$DEVSTACK_DIR/devstack.env"
  mkdir -p "$GATEWAY_CONFIG_DIR"
  ln -sf "$DEVSTACK_CONFIG_REPO/stage/v2-static-voting-config.json" \
    "$GATEWAY_CONFIG_DIR/static-voting-config.json"
  ln -sf "$DEVSTACK_CONFIG_REPO/stage/dynamic-voting-config.json" \
    "$GATEWAY_CONFIG_DIR/dynamic-voting-config.json"
  start_bg gateway python3 "$ROOT_DIR/scripts/e2e/voting-regtest-gateway.py" \
    --port "$GATEWAY_PORT" --config-dir "$GATEWAY_CONFIG_DIR" \
    --pir-target "http://127.0.0.1:$PIR_PORT" \
    --vote-target "http://127.0.0.1:$VOTE_PORT" \
    --rpc-target "http://127.0.0.1:$VOTE_RPC_PORT" \
    --delegate-ballot-command "$(printf '%q' "$ROOT_DIR/scripts/e2e/flutter-macos-regtest-proxy-delegation.sh") ballots"
  wait_http "http://127.0.0.1:$GATEWAY_PORT/health" "voting gateway"
}

# write_stack_env records what the test, the app and the other commands read.
write_stack_env() {
  # shellcheck disable=SC1091
  . "$DEVSTACK_DIR/devstack.env"
  {
    echo "# The running proxy delegation regtest stack."
    echo "SNAPSHOT_HEIGHT=$1"
    echo "LIGHTWALLETD_URL=http://127.0.0.1:$IRONWOOD_LIGHTWALLETD_PORT"
    echo "GATEWAY_URL=http://127.0.0.1:$GATEWAY_PORT"
    echo "VOTE_API_URL=http://127.0.0.1:$VOTE_PORT"
    echo "STATIC_CONFIG_SOURCE=$DEVSTACK_STATIC_CONFIG_SOURCE"
    echo "CHAIN_ID=$DEVSTACK_CHAIN_ID"
    echo "VALIDATOR_HASH=$DEVSTACK_VALIDATOR_HASH"
    echo "CA_CERT=$DEVSTACK_CA_CERT"
    local name upper
    for name in a b; do
      [[ -f "$DELEGATES_DIR/$name.json" ]] || continue
      upper="$(tr '[:lower:]' '[:upper:]' <<<"$name")"
      echo "DELEGATE_${upper}_INDEX=$(jq -r .delegate_index "$DELEGATES_DIR/$name.json")"
      echo "DELEGATE_${upper}_HANDLE=$(jq -r .handle "$DELEGATES_DIR/$name.json")"
      echo "DELEGATE_${upper}_KEY=$(jq -r .dk "$DELEGATES_DIR/$name.json")"
    done
  } >"$STACK_ENV"
}

# --- Commands ---------------------------------------------------------------

# cmd_up brings the whole stack up and leaves it running.
cmd_up() {
  require_cmd cargo
  require_cmd curl
  require_cmd docker
  require_cmd fvm
  require_cmd go
  require_cmd grpcurl
  require_cmd jq
  require_cmd lsof
  require_cmd python3
  [[ ! -f "$STACK_ENV" ]] || die "a stack is recorded in $STACK_ENV; run '$0 down' first"
  mkdir -p "$LOG_DIR"
  check_ports_free
  local started=$SECONDS
  build_pir
  init_vote_chain
  fund_wallet
  local height
  height="$("$ROOT_DIR/scripts/ironwood-regtest/rpc.sh" getblockcount)"
  start_pir "$height"
  start_verifier
  register_delegates
  write_stack_env "$height"
  sign_wallet_list
  start_gateway
  create_round
  log "stack up in $((SECONDS - started))s; settings in $STACK_ENV"
}

# cmd_test runs the Flutter integration test against the running stack.
cmd_test() {
  [[ -f "$STACK_ENV" ]] || die "no stack is up; run '$0 up' first"
  use_fake_providers "the test"
  local name
  for name in DEVSTACK_X DEVSTACK_GITHUB; do
    [[ "$(recorded_mode "$name")" == fake ]] ||
      die "the test needs the dev stack on the fakes, but it runs $name=real; run '$0 switch' with both fake"
  done
  # shellcheck disable=SC1090
  . "$STACK_ENV"
  [[ -n "${DELEGATE_A_INDEX:-}" ]] ||
    die "the stack has no test delegates (it came up with real X); bring it up again on the fakes"
  local started=$SECONDS
  log "running the Flutter proxy delegation test for round $ROUND_ID"
  cd "$ROOT_DIR"
  if ! VIZOR_UNSTABLE_PROXY_DELEGATION=1 fvm flutter test "$TEST_FILE" -d macos \
    "${app_defines[@]}" \
    --dart-define=ZCASH_E2E_REUSE_MIGRATED_WALLET=true \
    --dart-define=ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN=true \
    --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}" \
    --dart-define=ZCASH_E2E_SCREENSHOT_DIR="${E2E_PROXY_SCREENSHOT_DIR:-}" 2>&1 |
    tee "$LOG_DIR/flutter-test.log"; then
    die "the Flutter test failed; see $LOG_DIR/flutter-test.log"
  fi
  curl -fsS "http://127.0.0.1:$VOTE_PORT/shielded-vote/v1/vote-summary/$ROUND_ID" \
    >"$LOG_DIR/final-tally-$ROUND_ID.json"
  log "proxy delegation E2E passed in $((SECONDS - started))s; tally in $LOG_DIR/final-tally-$ROUND_ID.json"
}

# cmd_ballots posts both delegates' ballots in the stack's current round.
cmd_ballots() {
  # shellcheck disable=SC1090
  . "$STACK_ENV"
  [[ -n "${DELEGATE_A_INDEX:-}" ]] || die "the stack has no test delegates to ballot"
  local name options
  for name in a b; do
    options="$DELEGATE_A_OPTIONS"
    [[ "$name" == b ]] && options="$DELEGATE_B_OPTIONS"
    "$DEVSTACK_DIR/bin/devstack" delegate ballot \
      --delegate "$DELEGATES_DIR/$name.json" --round "$ROUND_ID" --options "$options"
  done
}

# cmd_app runs Vizor by hand, in a visible window, against the stack.
cmd_app() {
  [[ -f "$STACK_ENV" ]] || die "no stack is up; run '$0 up' first"
  # shellcheck disable=SC1090
  . "$STACK_ENV"
  cd "$ROOT_DIR"
  VIZOR_UNSTABLE_PROXY_DELEGATION=1 exec fvm flutter run -t "$MANUAL_ENTRYPOINT" -d macos \
    "${app_defines[@]}"
}

# cmd_switch restarts the verifier dev stack in DEVSTACK_X and
# DEVSTACK_GITHUB's modes, keeping its state, the round and everything else,
# and routes its rewritten config to the gateway again.
cmd_switch() {
  [[ -f "$STACK_ENV" ]] || die "no stack is up; run '$0 up' first"
  log "restarting the verifier dev stack with X $STACK_X, GitHub $STACK_GITHUB"
  devstack down >"$LOG_DIR/devstack-down.log" 2>&1 ||
    { tail -n 30 "$LOG_DIR/devstack-down.log" >&2; die "devstack down failed"; }
  devstack up >"$LOG_DIR/devstack-up.log" 2>&1 ||
    { tail -n 40 "$LOG_DIR/devstack-up.log" >&2; die "devstack up failed; the dev stack is down"; }
  route_config_to_gateway
  log "the verifier dev stack runs X $(recorded_mode DEVSTACK_X), GitHub $(recorded_mode DEVSTACK_GITHUB)"
}

# cmd_list re-signs the wallet list from the chain's registry, after
# delegates registered or retired. A running app takes it on its next list
# refresh, or when restarted.
cmd_list() {
  [[ -f "$STACK_ENV" ]] || die "no stack is up; run '$0 up' first"
  sign_wallet_list
}

# cmd_status shows what runs.
cmd_status() {
  local name
  for name in pir-server gateway; do
    if [[ -f "$PID_DIR/$name.pid" ]] && kill -0 "$(cat "$PID_DIR/$name.pid")" 2>/dev/null; then
      echo "$name: running (pid $(cat "$PID_DIR/$name.pid"))"
    else
      echo "$name: stopped"
    fi
  done
  if [[ -f "$LOCALNET_DIR/pids/val1.pid" ]] && kill -0 "$(cat "$LOCALNET_DIR/pids/val1.pid")" 2>/dev/null; then
    echo "vote chain: running (pid $(cat "$LOCALNET_DIR/pids/val1.pid"))"
  else
    echo "vote chain: stopped"
  fi
  [[ -d "$DEVSTACK_DIR" ]] && devstack status || true
  docker compose -p "$IRONWOOD_COMPOSE_PROJECT" -f "$ROOT_DIR/docker-compose.zcash-ironwood-regtest.yml" ps || true
  [[ -f "$STACK_ENV" ]] && cat "$STACK_ENV"
}

# cmd_down stops and removes everything this harness started.
cmd_down() {
  log "tearing the stack down"
  stop_bg gateway voting-regtest-gateway.py
  stop_bg pir-server nf-server
  [[ -d "$DEVSTACK_DIR" ]] && devstack down >/dev/null 2>&1 || true
  [[ -f "$LOCALNET_DIR/localnet.env" ]] && devstack localnet stop >/dev/null 2>&1 || true
  if [[ -d "$IRONWOOD_REGTEST_STATE_DIR" ]]; then
    "$ROOT_DIR/scripts/ironwood-regtest/reset.sh" >/dev/null 2>&1 || true
  fi
  rm -f "$STACK_ENV"
  log "down; logs are kept in $LOG_DIR"
}

# down_on_failure tears the stack down when the script exits non-zero.
down_on_failure() {
  local status=$?
  [[ $status == 0 ]] || cmd_down
}

# Every Flutter run's defines, read from the stack environment.
app_defines=()
if [[ -f "$STACK_ENV" ]]; then
  # shellcheck disable=SC1090
  . "$STACK_ENV"
  app_defines=(
    --dart-define=ZCASH_DEFAULT_NETWORK=regtest
    --dart-define=VIZOR_PROXY_DELEGATION_ENABLED=true
    --dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT="$ACTIVATION_HEIGHT"
    --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="$LIGHTWALLETD_URL"
    --dart-define=ZCASH_E2E_VOTING_GATEWAY_URL="$GATEWAY_URL"
    --dart-define=ZCASH_E2E_VOTING_STATIC_CONFIG_URL="$STATIC_CONFIG_SOURCE"
    --dart-define=ZCASH_E2E_VOTE_CHAIN_ID="$CHAIN_ID"
    --dart-define=ZCASH_E2E_VOTE_VALIDATOR_HASH="$VALIDATOR_HASH"
    --dart-define=ZCASH_E2E_VOTE_ROUND_ID="${ROUND_ID:-}"
    --dart-define=ZCASH_E2E_DEV_CA_PEM_BASE64="$(base64 <"$CA_CERT" | tr -d '\n')"
    --dart-define=VIZOR_PROXY_WALLET_LIST_URL="${WALLET_LIST_URL:-}"
    --dart-define=VIZOR_PROXY_WALLET_LIST_KEY="${WALLET_LIST_KEY:-}"
  )
  # Each delegate as <index>:<ballot options>:<handle>:<zvdk1 key>.
  if [[ -n "${DELEGATE_A_INDEX:-}" ]]; then
    app_defines+=(
      --dart-define=ZCASH_E2E_PROXY_DELEGATE_A="$DELEGATE_A_INDEX:$DELEGATE_A_OPTIONS:$DELEGATE_A_HANDLE:$DELEGATE_A_KEY"
      --dart-define=ZCASH_E2E_PROXY_DELEGATE_B="$DELEGATE_B_INDEX:$DELEGATE_B_OPTIONS:$DELEGATE_B_HANDLE:$DELEGATE_B_KEY"
    )
  fi
fi

case "${1:-}" in
  "" | --keep)
    use_fake_providers "the full run"
    # Without --keep, everything comes down however the run ends.
    [[ "${1:-}" == --keep ]] || trap cmd_down EXIT
    cmd_up
    # A fresh process reads the stack environment cmd_up wrote.
    "$ROOT_DIR/scripts/e2e/flutter-macos-regtest-proxy-delegation.sh" test
    ;;
  up)
    # A failed bring-up stops what it started.
    trap down_on_failure EXIT
    cmd_up
    ;;
  round)
    [[ -f "$STACK_ENV" ]] || die "no stack is up; run '$0 up' first"
    create_round
    sign_wallet_list
    ;;
  list) cmd_list ;;
  switch) cmd_switch ;;
  test) cmd_test ;;
  ballots) cmd_ballots ;;
  app) cmd_app ;;
  status) cmd_status ;;
  down) cmd_down ;;
  *) die "unknown command $1; see the header of $0" ;;
esac
