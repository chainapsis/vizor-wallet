#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$ROOT_DIR/.regtest-voting"
DEPS_DIR="$STATE_DIR/deps"
LOG_DIR="$STATE_DIR/logs"
CONFIG_DIR="$STATE_DIR/config"
PIR_DATA_DIR="$STATE_DIR/pir-data"
VOTE_HOME="$STATE_DIR/vote-home"
SHIM_DIR="$STATE_DIR/shims"

VOTE_SDK_URL="https://github.com/valargroup/vote-sdk.git"
VOTE_SDK_REV="6a10c073baae3c2003ada402d7c5c513ee6b90ce"
PIR_URL="https://github.com/valargroup/vote-nullifier-pir.git"
PIR_REV="20356d14f61a825ef28726f38270c37d604cc268"
VOTE_SDK_DIR="$DEPS_DIR/vote-sdk-$VOTE_SDK_REV"
PIR_DIR="$DEPS_DIR/vote-nullifier-pir-$PIR_REV"

ACTIVATION_HEIGHT=500
LWD_PORT="${E2E_IRONWOOD_LIGHTWALLETD_PORT:-19067}"
PIR_PORT="${E2E_PIR_PORT:-13000}"
VOTE_PORT="${E2E_VOTE_PORT:-1317}"
GATEWAY_PORT="${E2E_VOTING_GATEWAY_PORT:-18080}"
SLOW_HELPER_DELAY="${E2E_SLOW_HELPER_DELAY:-2.0}"
SLOW_HELPER_MODE="${E2E_SLOW_HELPER_MODE:-0}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
VIZOR_FORM_FACTOR="${VIZOR_FORM_FACTOR:-desktop}"
VOTING_TEST_FILE="${E2E_VOTING_TEST_FILE:-integration_test/regtest_voting_test.dart}"
# Deterministic secp256k1 scalar 1, used only by the disposable local chain.
VOTE_MANAGER_PRIVATE_KEY="0000000000000000000000000000000000000000000000000000000000000001"

pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
  if [[ "${KEEP_VOTING_REGTEST:-0}" != "1" ]]; then
    IRONWOOD_ACTIVATION_HEIGHT="$ACTIVATION_HEIGHT" \
      IRONWOOD_LIGHTWALLETD_PORT="$LWD_PORT" \
      "$ROOT_DIR/scripts/ironwood-regtest/down.sh" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

fetch_exact_revision() {
  local url="$1" revision="$2" destination="$3"
  if [[ -d "$destination/.git" ]] &&
    [[ "$(git -C "$destination" rev-parse HEAD)" == "$revision" ]]; then
    assert_clean_dependency_checkout "$destination"
    return
  fi
  mkdir -p "$(dirname "$destination")"
  if [[ ! -d "$destination/.git" ]]; then
    git clone --filter=blob:none --no-checkout "$url" "$destination"
  fi
  git -C "$destination" fetch --depth 1 origin "$revision"
  git -C "$destination" checkout --detach "$revision"
  [[ "$(git -C "$destination" rev-parse HEAD)" == "$revision" ]]
  assert_clean_dependency_checkout "$destination"
}

assert_clean_dependency_checkout() {
  local destination="$1" dirty
  # vote-sdk's build writes these binaries at the repository root. All other
  # tracked or untracked changes would make the supposedly pinned build local.
  dirty="$(git -C "$destination" status --porcelain --untracked-files=all |
    grep -Ev '^\?\? (svoted|voting-config)$' || true)"
  if [[ -n "$dirty" ]]; then
    echo "cached dependency checkout is dirty: $destination" >&2
    echo "$dirty" >&2
    exit 1
  fi
}

wait_http() {
  local url="$1" label="$2"
  for _ in $(seq 1 180); do
    if curl -fsS "$url" >/dev/null 2>&1; then return; fi
    sleep 1
  done
  echo "timed out waiting for $label at $url" >&2
  exit 1
}

require_cmd cargo
require_cmd curl
require_cmd docker
require_cmd fvm
require_cmd git
require_cmd grpcurl
require_cmd jq
require_cmd make
require_cmd python3

mkdir -p "$DEPS_DIR" "$LOG_DIR" "$CONFIG_DIR" "$SHIM_DIR"
fetch_exact_revision "$VOTE_SDK_URL" "$VOTE_SDK_REV" "$VOTE_SDK_DIR"
fetch_exact_revision "$PIR_URL" "$PIR_REV" "$PIR_DIR"

echo "building pinned vote-sdk and PIR services"
make -C "$VOTE_SDK_DIR" build-ffi build-voting-config
cargo build --release --manifest-path "$PIR_DIR/Cargo.toml" \
  -p pir-export --features cli -p nf-server --features serve

echo "creating voting power through the real Orchard-to-Ironwood migration"
IRONWOOD_ACTIVATION_HEIGHT="$ACTIVATION_HEIGHT" \
  IRONWOOD_LIGHTWALLETD_PORT="$LWD_PORT" \
  FLUTTER_DEVICE=macos \
  VIZOR_FORM_FACTOR=desktop \
  E2E_TEST_FILE=integration_test/regtest_voting_ironwood_setup_test.dart \
  E2E_LIGHTWALLETD_URL="http://127.0.0.1:$LWD_PORT" \
  E2E_ORCHARD_FUNDING_AMOUNT=0.13 \
  E2E_ORCHARD_FUNDING_ZATOSHI=13000000 \
  VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}" \
  "$ROOT_DIR/scripts/e2e/flutter-macos-ironwood-migration.sh"

SNAPSHOT_HEIGHT="$(IRONWOOD_ACTIVATION_HEIGHT="$ACTIVATION_HEIGHT" \
  IRONWOOD_LIGHTWALLETD_PORT="$LWD_PORT" \
  "$ROOT_DIR/scripts/ironwood-regtest/rpc.sh" getblockcount)"
rm -rf "$PIR_DATA_DIR"
mkdir -p "$PIR_DATA_DIR"
python3 "$ROOT_DIR/scripts/e2e/export-regtest-ironwood-nullifiers.py" \
  --proto-dir "$ROOT_DIR/protos" \
  --endpoint "127.0.0.1:$LWD_PORT" \
  --activation-height "$ACTIVATION_HEIGHT" \
  --snapshot-height "$SNAPSHOT_HEIGHT" \
  --output "$PIR_DATA_DIR/nullifiers.bin" \
  >"$LOG_DIR/nullifier-export.json"
python3 - "$PIR_DATA_DIR" "$SNAPSHOT_HEIGHT" <<'PY'
import json, pathlib, struct, sys
directory = pathlib.Path(sys.argv[1])
height = int(sys.argv[2])
(directory / "nullifiers.dataset.json").write_text(json.dumps({
    "zcash_network": "test", "nullifier_pool": "ironwood", "dataset_version": 2
}, indent=2) + "\n")
offset = (directory / "nullifiers.bin").stat().st_size
(directory / "nullifiers.checkpoint").write_bytes(struct.pack("<QQ", height, offset))
PY
"$PIR_DIR/target/release/pir-export" \
  --nullifiers "$PIR_DATA_DIR/nullifiers.bin" \
  --checkpoint "$PIR_DATA_DIR/nullifiers.checkpoint" \
  --output-dir "$PIR_DATA_DIR" 2>"$LOG_DIR/pir-export.log"

SVOTE_PIR_CONFIG_URL='' SVOTE_PIR_PRECOMPUTED_BASE_URL='' \
  "$PIR_DIR/target/release/nf-server" serve \
  --zcash-network test --port "$PIR_PORT" \
  --pir-data-dir "$PIR_DATA_DIR" --lwd-url "http://127.0.0.1:$LWD_PORT" \
  --stale-threshold-secs 0 >"$LOG_DIR/pir-server.log" 2>&1 &
pids+=("$!")
wait_http "http://127.0.0.1:$PIR_PORT/ready" "PIR server"
jq -e --argjson height "$SNAPSHOT_HEIGHT" \
  '.height == $height and .nullifier_pool == "ironwood" and .dataset_version == 2' \
  < <(curl -fsS "http://127.0.0.1:$PIR_PORT/root") >/dev/null

echo "starting pinned single-validator vote chain and helper"
rm -rf "$VOTE_HOME"
PATH="$VOTE_SDK_DIR:$PATH" SVOTED_HOME="$VOTE_HOME" \
  VM_PRIVKEYS="$VOTE_MANAGER_PRIVATE_KEY" \
  SVOTE_ADMIN_DISABLE=true SVOTE_HELPER_EXPOSE_QUEUE_STATUS=true \
  bash "$VOTE_SDK_DIR/scripts/init.sh" >"$LOG_DIR/vote-init.log" 2>&1
"$VOTE_SDK_DIR/svoted" start --home "$VOTE_HOME" \
  --api.address "tcp://127.0.0.1:$VOTE_PORT" \
  >"$LOG_DIR/vote-server.log" 2>&1 &
pids+=("$!")
wait_http "http://127.0.0.1:$VOTE_PORT/shielded-vote/v1/rounds" "vote chain"

REAL_GRPCURL="$(command -v grpcurl)"
cat >"$SHIM_DIR/grpcurl" <<EOF
#!/usr/bin/env bash
exec "$REAL_GRPCURL" -plaintext -import-path "$ROOT_DIR/protos" -proto service.proto "\$@"
EOF
chmod +x "$SHIM_DIR/grpcurl"
PATH="$SHIM_DIR:$VOTE_SDK_DIR:$PATH" \
  VM_PRIVKEYS="$VOTE_MANAGER_PRIVATE_KEY" \
  SVOTE_HOME="$VOTE_HOME" SVOTE_PALLAS_PK_PATH="$VOTE_HOME/pallas.pk" \
  SVOTE_API_URL="http://127.0.0.1:$VOTE_PORT" \
  ZASHI_LIGHTWALLETD="127.0.0.1:$LWD_PORT" \
  ZASHI_PIR_URL="http://127.0.0.1:$PIR_PORT" \
  ZASHI_SNAPSHOT_HEIGHT="$SNAPSHOT_HEIGHT" ZASHI_VOTE_WINDOW_SECS=7200 \
  cargo test --manifest-path "$VOTE_SDK_DIR/e2e-tests/Cargo.toml" \
  --test create_round_for_zashi create_round_for_zashi -- --ignored --nocapture \
  >"$LOG_DIR/create-round.log" 2>&1

ROUND_JSON="$(curl -fsS "http://127.0.0.1:$VOTE_PORT/shielded-vote/v1/rounds/active")"
read -r ROUND_ID EA_PK < <(python3 -c '
import base64, json, sys
round_data = json.load(sys.stdin)["round"]
print(
    base64.b64decode(round_data["vote_round_id"], validate=True).hex(),
    round_data["ea_pk"],
)
' <<<"$ROUND_JSON")

KEY_OUTPUT="$("$VOTE_SDK_DIR/voting-config" keygen \
  --signer-id vizor-regtest-e2e --out "$CONFIG_DIR/signing.seed" --force)"
TRUSTED_KEY="$(sed -n 's/^trusted_keys_entry: //p' <<<"$KEY_OUTPUT")"
cat >"$CONFIG_DIR/static-voting-config.json" <<EOF
{
  "static_config_version": 1,
  "dynamic_config_url": "https://config.vizor-vote.invalid/dynamic-voting-config.json",
  "trusted_keys": [$TRUSTED_KEY]
}
EOF
if [[ "$SLOW_HELPER_MODE" == "1" ]]; then
  VOTE_SERVERS='[
    {"url":"https://slow.vizor-vote.invalid","label":"delayed regtest helper"},
    {"url":"https://vote.vizor-vote.invalid","label":"healthy regtest helper"}
  ]'
else
  VOTE_SERVERS='[
    {"url":"https://vote.vizor-vote.invalid","label":"healthy regtest helper"}
  ]'
fi
cat >"$CONFIG_DIR/dynamic-voting-config.json" <<EOF
{
  "config_version": 1,
  "vote_servers": $VOTE_SERVERS,
  "pir_endpoints": [
    {"url":"https://pir.vizor-vote.invalid","label":"regtest PIR"}
  ],
  "pir_layout": {"pir_depth":19,"tier0_layers":12,"tier1_layers":7,"poly_len":4096},
  "supported_versions": {"pir":["v0"],"vote_protocol":"v0","tally":"v0","vote_server":"v1"},
  "rounds": {}
}
EOF
"$VOTE_SDK_DIR/voting-config" sign --round-id "$ROUND_ID" --ea-pk "$EA_PK" \
  --signer-id vizor-regtest-e2e --privkey-file "$CONFIG_DIR/signing.seed" \
  --pir-depth 19 --tier0-layers 12 --tier1-layers 7 --poly-len 4096 \
  --merge "$CONFIG_DIR/dynamic-voting-config.json"
"$VOTE_SDK_DIR/voting-config" verify \
  --config "$CONFIG_DIR/dynamic-voting-config.json" \
  --static-config "$CONFIG_DIR/static-voting-config.json"

python3 "$ROOT_DIR/scripts/e2e/voting-regtest-gateway.py" \
  --port "$GATEWAY_PORT" --config-dir "$CONFIG_DIR" \
  --pir-target "http://127.0.0.1:$PIR_PORT" \
  --vote-target "http://127.0.0.1:$VOTE_PORT" \
  --slow-helper-delay "$SLOW_HELPER_DELAY" \
  >"$LOG_DIR/gateway.log" 2>&1 &
pids+=("$!")
wait_http "http://127.0.0.1:$GATEWAY_PORT/health" "voting gateway"

STATIC_SHA="$(shasum -a 256 "$CONFIG_DIR/static-voting-config.json" | awk '{print $1}')"
STATIC_URL="https://config.vizor-vote.invalid/static-voting-config.json?checksum=sha256:$STATIC_SHA"

echo "running real-proof Flutter voting E2E for round $ROUND_ID"
cd "$ROOT_DIR"
flutter_test_command=(
  fvm flutter test "$VOTING_TEST_FILE" -d "$FLUTTER_DEVICE"
)
if [[ "$VIZOR_FORM_FACTOR" == "mobile" ]]; then
  flutter_test_command+=(--dart-define=VIZOR_FORM_FACTOR=mobile)
fi
"${flutter_test_command[@]}" \
  --dart-define=ZCASH_DEFAULT_NETWORK=regtest \
  --dart-define=ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT="$ACTIVATION_HEIGHT" \
  --dart-define=ZCASH_E2E_LIGHTWALLETD_URL="http://127.0.0.1:$LWD_PORT" \
  --dart-define=ZCASH_E2E_VOTING_GATEWAY_URL="http://127.0.0.1:$GATEWAY_PORT" \
  --dart-define=ZCASH_E2E_VOTING_STATIC_CONFIG_URL="$STATIC_URL" \
  --dart-define=ZCASH_E2E_VOTE_ROUND_ID="$ROUND_ID" \
  --dart-define=ZCASH_E2E_REUSE_MIGRATED_WALLET=true \
  --dart-define=ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN=true \
  --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"

METRICS="$(curl -fsS "http://127.0.0.1:$GATEWAY_PORT/metrics")"
if [[ "$SLOW_HELPER_MODE" == "1" ]]; then
  jq -e '.slow_share_requests > 0 and .slow_share_max_inflight > 1' \
    <<<"$METRICS" >/dev/null || {
      echo "slow-helper E2E did not observe concurrent share submission: $METRICS" >&2
      exit 1
    }
fi
jq -e '.tree.next_index > 0' < <(curl -fsS \
  "http://127.0.0.1:$VOTE_PORT/shielded-vote/v1/commitment-tree/$ROUND_ID/latest") \
  >/dev/null
echo "voting E2E passed; round=$ROUND_ID snapshot=$SNAPSHOT_HEIGHT metrics=$METRICS"
