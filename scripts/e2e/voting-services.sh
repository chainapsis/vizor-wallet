#!/usr/bin/env bash
# The vote chain, nullifier PIR server and voting gateway of the voting E2E
# scenarios, run against the scenario's Zakura regtest chain by zakura-run.py.
#
#   voting-services.sh build          fetch and build the pinned vote-sdk and PIR
#   voting-services.sh start READY    start the services after the setup phase
#                                     migrated the voting power, write the voting
#                                     test's defines to READY and keep serving
#   voting-services.sh check READY    require discovery, helper and vote traffic,
#                                     and with E2E_FINAL_TALLY=1 the final tally
#
# The chain's lightwalletd and control come from VOTING_LIGHTWALLETD and
# ZCASH_E2E_DRIVER_URL. VOTING_DEVICE is `macos` or the simulator UDID. With
# E2E_LEDGER_VOTING=1, the Ledger signer bridge uses the helper, Speculos API and
# exported account in VIZOR_LEDGER_REGTEST_HELPER,
# VIZOR_LEDGER_SPECULOS_SIGNING_API_URL and VIZOR_LEDGER_REGTEST_ACCOUNT.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEPS_DIR="$ROOT_DIR/.regtest-voting/deps"
VOTE_SDK_URL="https://github.com/valargroup/vote-sdk.git"
VOTE_SDK_REV="36f5d828fc5be42d9a80baa38d1145c5541b229e"
PIR_URL="https://github.com/valargroup/vote-nullifier-pir.git"
PIR_REV="20356d14f61a825ef28726f38270c37d604cc268"
VOTE_SDK_DIR="$DEPS_DIR/vote-sdk-$VOTE_SDK_REV"
PIR_DIR="$DEPS_DIR/vote-nullifier-pir-$PIR_REV"
ACTIVATION_HEIGHT=500
PIR_PORT=13000
VOTE_PORT=1317
VOTE_RPC_PORT=26657
GATEWAY_PORT=18080
SLOW_HELPER_DELAY="${E2E_SLOW_HELPER_DELAY:-2.0}"
VOTE_MANAGER_PRIVATE_KEY="0000000000000000000000000000000000000000000000000000000000000001"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

assert_clean_dependency_checkout() {
  local destination="$1" dirty
  dirty="$(git -C "$destination" status --porcelain --untracked-files=all |
    grep -Ev '^\?\? (svoted|voting-config)$' || true)"
  if [[ -n "$dirty" ]]; then
    echo "cached dependency checkout is dirty: $destination" >&2
    echo "$dirty" >&2
    exit 1
  fi
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

wait_http() {
  local url="$1" label="$2"
  for _ in $(seq 1 180); do
    if curl -fsS "$url" >/dev/null 2>&1; then return; fi
    sleep 1
  done
  echo "timed out waiting for $label at $url" >&2
  exit 1
}

build_services() {
  require_cmd cargo
  require_cmd git
  require_cmd go
  require_cmd make
  fetch_exact_revision "$VOTE_SDK_URL" "$VOTE_SDK_REV" "$VOTE_SDK_DIR"
  fetch_exact_revision "$PIR_URL" "$PIR_REV" "$PIR_DIR"
  make -C "$VOTE_SDK_DIR" build-ffi build-voting-config
  cargo build --release --manifest-path "$PIR_DIR/Cargo.toml" \
    -p pir-export --features cli -p nf-server --features serve
}

start_services() {
  local ready="$1"
  require_cmd cargo
  require_cmd curl
  require_cmd grpcurl
  require_cmd jq
  require_cmd python3
  local state_dir log_dir config_dir pir_data_dir vote_home shim_dir
  state_dir="$(dirname "$ready")"
  log_dir="$state_dir/logs"
  config_dir="$state_dir/config"
  pir_data_dir="$state_dir/pir-data"
  vote_home="$state_dir/vote-home"
  shim_dir="$state_dir/shims"
  mkdir -p "$log_dir" "$config_dir" "$pir_data_dir" "$shim_dir"
  local lwd="${VOTING_LIGHTWALLETD:?}" control="${ZCASH_E2E_DRIVER_URL:?}"
  local device="${VOTING_DEVICE:?}"

  pids=()
  # Reap the services before exiting, so none is left a zombie for launchd.
  trap 'kill "${pids[@]:-}" >/dev/null 2>&1 || true; wait || true' EXIT
  trap 'exit 0' TERM INT

  local snapshot_height
  snapshot_height="$(curl -fsS "$control/status" | jq -er '.zcashdHeight')"
  python3 "$ROOT_DIR/scripts/e2e/export-regtest-ironwood-nullifiers.py" \
    --proto-dir "$ROOT_DIR/protos" \
    --endpoint "$lwd" \
    --activation-height "$ACTIVATION_HEIGHT" \
    --snapshot-height "$snapshot_height" \
    --output "$pir_data_dir/nullifiers.bin" \
    >"$log_dir/nullifier-export.json"
  python3 - "$pir_data_dir" "$snapshot_height" <<'PY'
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
    --nullifiers "$pir_data_dir/nullifiers.bin" \
    --checkpoint "$pir_data_dir/nullifiers.checkpoint" \
    --output-dir "$pir_data_dir" 2>"$log_dir/pir-export.log"
  SVOTE_PIR_CONFIG_URL='' SVOTE_PIR_PRECOMPUTED_BASE_URL='' \
    "$PIR_DIR/target/release/nf-server" serve \
    --zcash-network test --port "$PIR_PORT" \
    --pir-data-dir "$pir_data_dir" --lwd-url "http://$lwd" \
    --stale-threshold-secs 0 >"$log_dir/pir-server.log" 2>&1 &
  pids+=("$!")
  wait_http "http://127.0.0.1:$PIR_PORT/ready" "PIR server"
  jq -e --argjson height "$snapshot_height" \
    '.height == $height and .nullifier_pool == "ironwood" and .dataset_version == 2' \
    < <(curl -fsS "http://127.0.0.1:$PIR_PORT/root") >/dev/null

  rm -rf "$vote_home"
  PATH="$VOTE_SDK_DIR:$PATH" SVOTED_HOME="$vote_home" \
    VM_PRIVKEYS="$VOTE_MANAGER_PRIVATE_KEY" \
    SVOTE_ADMIN_DISABLE=true SVOTE_HELPER_EXPOSE_QUEUE_STATUS=true \
    bash "$VOTE_SDK_DIR/scripts/init.sh" >"$log_dir/vote-init.log" 2>&1
  "$VOTE_SDK_DIR/svoted" start --home "$vote_home" \
    --rpc.laddr "tcp://127.0.0.1:$VOTE_RPC_PORT" \
    --api.address "tcp://127.0.0.1:$VOTE_PORT" \
    >"$log_dir/vote-server.log" 2>&1 &
  pids+=("$!")
  wait_http "http://127.0.0.1:$VOTE_PORT/shielded-vote/v1/rounds" "vote chain"

  local real_grpcurl
  real_grpcurl="$(command -v grpcurl)"
  cat >"$shim_dir/grpcurl" <<EOF
#!/usr/bin/env bash
exec "$real_grpcurl" -plaintext -import-path "$ROOT_DIR/protos" -proto service.proto "\$@"
EOF
  chmod +x "$shim_dir/grpcurl"
  create_voting_round() {
    PATH="$shim_dir:$VOTE_SDK_DIR:$PATH" \
      VM_PRIVKEYS="$VOTE_MANAGER_PRIVATE_KEY" \
      SVOTE_HOME="$vote_home" SVOTE_PALLAS_PK_PATH="$vote_home/pallas.pk" \
      SVOTE_API_URL="http://127.0.0.1:$VOTE_PORT" \
      ZASHI_LIGHTWALLETD="$lwd" \
      ZASHI_PIR_URL="http://127.0.0.1:$PIR_PORT" \
      ZASHI_SNAPSHOT_HEIGHT="$snapshot_height" ZASHI_VOTE_WINDOW_SECS="${E2E_VOTE_WINDOW_SECS:-7200}" \
      cargo test --manifest-path "$VOTE_SDK_DIR/e2e-tests/Cargo.toml" \
      --test create_round_for_zashi create_round_for_zashi -- --ignored --nocapture \
      >"$log_dir/$1" 2>&1
  }
  create_voting_round create-round.log
  local round_json round_id ea_pk
  round_json="$(curl -fsS "http://127.0.0.1:$VOTE_PORT/shielded-vote/v1/rounds/active")"
  read -r round_id ea_pk < <(python3 -c '
import base64, json, sys
round_data = json.load(sys.stdin)["round"]
print(
    base64.b64decode(round_data["vote_round_id"], validate=True).hex(),
    round_data["ea_pk"],
)
' <<<"$round_json")

  local key_output trusted_key vote_servers
  key_output="$("$VOTE_SDK_DIR/voting-config" keygen \
    --signer-id vizor-regtest-e2e --out "$config_dir/signing.seed" --force)"
  trusted_key="$(sed -n 's/^trusted_keys_entry: //p' <<<"$key_output")"
  cat >"$config_dir/static-voting-config.json" <<EOF
{
  "static_config_version": 1,
  "dynamic_config_url": "https://config.vizor-vote.invalid/dynamic-voting-config.json",
  "trusted_keys": [$trusted_key]
}
EOF
  if [[ "${E2E_SLOW_HELPER_MODE:-0}" == "1" ]]; then
    vote_servers='[
      {"url":"https://slow.vizor-vote.invalid","label":"delayed regtest helper"},
      {"url":"https://vote.vizor-vote.invalid","label":"healthy regtest helper"}
    ]'
  else
    vote_servers='[
      {"url":"https://vote.vizor-vote.invalid","label":"healthy regtest helper"}
    ]'
  fi
  cat >"$config_dir/dynamic-voting-config.json" <<EOF
{
  "config_version": 1,
  "vote_servers": $vote_servers,
  "pir_endpoints": [
    {"url":"https://pir.vizor-vote.invalid","label":"regtest PIR"}
  ],
  "pir_layout": {"pir_depth":19,"tier0_layers":12,"tier1_layers":7,"poly_len":4096},
  "supported_versions": {"pir":["v0"],"vote_protocol":"v0","tally":"v0","vote_server":"v1"},
  "rounds": {}
}
EOF
  "$VOTE_SDK_DIR/voting-config" sign --round-id "$round_id" --ea-pk "$ea_pk" \
    --signer-id vizor-regtest-e2e --privkey-file "$config_dir/signing.seed" \
    --pir-depth 19 --tier0-layers 12 --tier1-layers 7 --poly-len 4096 \
    --merge "$config_dir/dynamic-voting-config.json"
  "$VOTE_SDK_DIR/voting-config" verify \
    --config "$config_dir/dynamic-voting-config.json" \
    --static-config "$config_dir/static-voting-config.json"

  # A second real round is created up front but authenticated only on
  # publication. Its ID comes from its transaction: /rounds/active returns the
  # first round.
  local next_round_id="" next_ea_pk
  if [[ "${E2E_VOTING_DISCOVERY_TRANSITION:-0}" == "1" ]]; then
    cp "$config_dir/dynamic-voting-config.json" "$config_dir/initial.json"
    create_voting_round create-next-round.log
    next_round_id="$(sed -n 's/^\[create-round\] round_id: //p' "$log_dir/create-next-round.log")"
    [[ "$next_round_id" =~ ^[0-9a-f]{64}$ && "$next_round_id" != "$round_id" ]]
    next_ea_pk="$(curl -fsS "http://127.0.0.1:$VOTE_PORT/shielded-vote/v1/round/$next_round_id" | jq -r '.round.ea_pk')"
    "$VOTE_SDK_DIR/voting-config" sign --round-id "$next_round_id" --ea-pk "$next_ea_pk" \
      --signer-id vizor-regtest-e2e --privkey-file "$config_dir/signing.seed" \
      --pir-depth 19 --tier0-layers 12 --tier1-layers 7 --poly-len 4096 \
      --merge "$config_dir/dynamic-voting-config.json"
    "$VOTE_SDK_DIR/voting-config" verify \
      --config "$config_dir/dynamic-voting-config.json" \
      --static-config "$config_dir/static-voting-config.json"
    mv "$config_dir/dynamic-voting-config.json" "$config_dir/new-round.json"
    cp "$config_dir/initial.json" "$config_dir/dynamic-voting-config.json"
    # A label update changes the backend's canonical revision, without new rights.
    jq '.vote_servers[0].label = "updated regtest helper"' \
      "$config_dir/initial.json" > "$config_dir/same-round.json"
  fi

  local gateway_args=(--screenshot-dir "$log_dir/screenshots")
  if [[ "${E2E_VOTING_DISCOVERY_TRANSITION:-0}" == "1" ]]; then
    gateway_args+=(--discovery-transition)
  fi
  if [[ "$device" != "macos" ]]; then
    gateway_args+=(--simulator "$device" --zcash-control "$control")
  fi
  python3 "$ROOT_DIR/scripts/e2e/voting-regtest-gateway.py" "${gateway_args[@]}" \
    --port "$GATEWAY_PORT" --config-dir "$config_dir" \
    --pir-target "http://127.0.0.1:$PIR_PORT" \
    --vote-target "http://127.0.0.1:$VOTE_PORT" \
    --rpc-target "http://127.0.0.1:$VOTE_RPC_PORT" \
    --slow-helper-delay "$SLOW_HELPER_DELAY" \
    >"$log_dir/gateway.log" 2>&1 &
  pids+=("$!")
  wait_http "http://127.0.0.1:$GATEWAY_PORT/health" "voting gateway"

  local signer_url=""
  if [[ "${E2E_LEDGER_VOTING:-0}" == "1" ]]; then
    local port_file="$state_dir/ledger-signer.port"
    python3 "$ROOT_DIR/scripts/e2e/ledger-regtest-signer.py" \
      --helper "${VIZOR_LEDGER_REGTEST_HELPER:?}" \
      --speculos-url "${VIZOR_LEDGER_SPECULOS_SIGNING_API_URL:?}" \
      --account "${VIZOR_LEDGER_REGTEST_ACCOUNT:?}" --port-file "$port_file" \
      >"$log_dir/ledger-signer.log" 2>&1 &
    pids+=("$!")
    for _ in $(seq 1 50); do
      [[ -s "$port_file" ]] && break
      kill -0 "${pids[${#pids[@]}-1]}" 2>/dev/null || {
        cat "$log_dir/ledger-signer.log" >&2
        exit 1
      }
      sleep 0.1
    done
    [[ -s "$port_file" ]] || { echo "the Ledger signer bridge did not start" >&2; exit 1; }
    signer_url="http://127.0.0.1:$(cat "$port_file")"
  fi

  local static_sha commit_json
  static_sha="$(shasum -a 256 "$config_dir/static-voting-config.json" | awk '{print $1}')"
  # The anchor belongs to this freshly initialized local chain, not a public RPC.
  commit_json="$(curl -fsS "http://127.0.0.1:$VOTE_RPC_PORT/commit")"
  jq -n \
    --arg gateway "http://127.0.0.1:$GATEWAY_PORT" \
    --arg static "https://config.vizor-vote.invalid/static-voting-config.json?checksum=sha256:$static_sha" \
    --arg round "$round_id" --arg next "$next_round_id" \
    --arg chain "$(jq -r '.result.signed_header.header.chain_id' <<<"$commit_json")" \
    --arg validators "$(jq -r '.result.signed_header.header.validators_hash' <<<"$commit_json")" \
    --arg snapshot "$snapshot_height" \
    --arg tally "${E2E_FINAL_TALLY:-0}" --arg signer "$signer_url" \
    '{defines: ({
        ZCASH_E2E_VOTING_GATEWAY_URL: $gateway,
        ZCASH_E2E_VOTING_STATIC_CONFIG_URL: $static,
        ZCASH_E2E_VOTE_ROUND_ID: $round,
        ZCASH_E2E_VOTE_NEXT_ROUND_ID: $next,
        ZCASH_E2E_VOTE_CHAIN_ID: $chain,
        ZCASH_E2E_VOTE_VALIDATOR_HASH: $validators}
        + (if $tally == "1" then {ZCASH_E2E_FINAL_TALLY: "true"} else {} end)
        + (if $signer != "" then {ZCASH_E2E_LEDGER_VOTING: "true",
            VIZOR_LEDGER_REGTEST_SIGNER_URL: $signer} else {} end)),
      snapshot_height: ($snapshot | tonumber)}' >"$ready.tmp"
  mv "$ready.tmp" "$ready"
  echo "voting services ready for round $round_id at snapshot $snapshot_height"
  wait
}

check_services() {
  local ready="$1" round_id metrics
  require_cmd curl
  require_cmd jq
  round_id="$(jq -er '.defines.ZCASH_E2E_VOTE_ROUND_ID' "$ready")"
  metrics="$(curl -fsS "http://127.0.0.1:$GATEWAY_PORT/metrics")"
  jq -e '.discovery_successes > 0 and .config_requests > 0 and .round_list_requests > 0' \
    <<<"$metrics" >/dev/null || { echo "discovery was not exercised: $metrics" >&2; exit 1; }
  if [[ "${E2E_SLOW_HELPER_MODE:-0}" == "1" ]]; then
    jq -e '.slow_share_requests > 0 and .slow_share_max_inflight > 1' \
      <<<"$metrics" >/dev/null || {
        echo "slow-helper E2E did not observe concurrent share submission: $metrics" >&2
        exit 1
      }
  fi
  jq -e '.tree.next_index > 0' < <(curl -fsS \
    "http://127.0.0.1:$VOTE_PORT/shielded-vote/v1/commitment-tree/$round_id/latest") \
    >/dev/null
  echo "voting E2E recorded votes; round=$round_id metrics=$metrics"
  if [[ "${E2E_FINAL_TALLY:-0}" == "1" ]]; then
    require_cmd python3
    python3 "$ROOT_DIR/scripts/e2e/assert-voting-final-tally.py" \
      --api-url "http://127.0.0.1:$VOTE_PORT" --round-id "$round_id" \
      --output "$(dirname "$ready")/logs/final-tally.json"
  fi
}

case "${1:-}" in
  build) build_services ;;
  start) start_services "${2:?READY file}" ;;
  check) check_services "${2:?READY file}" ;;
  *)
    echo "usage: $0 build | start READY | check READY" >&2
    exit 2
    ;;
esac
