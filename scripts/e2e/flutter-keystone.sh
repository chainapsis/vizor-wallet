#!/usr/bin/env bash
set -euo pipefail

: "${FLUTTER_DEVICE:?set FLUTTER_DEVICE to macos or a booted iOS simulator UDID}"
cd "$(dirname "$0")/../.."
unset KEYSTONE_IOS_SIMULATOR_UDID
if [[ $# -ne 0 ]]; then
  echo "Usage: FLUTTER_DEVICE=macos|<simulator-udid> $0" >&2
  exit 2
fi
if [[ "$FLUTTER_DEVICE" == macos ]]; then
  target=desktop
  flags=(--tags desktop --dart-define=VIZOR_E2E_HIDDEN_WINDOW=false)
else
  target=mobile
  xcrun simctl list devices booted -j | jq -e --arg id "$FLUTTER_DEVICE" \
    'any(.devices | to_entries[] | select(.key | contains("iOS")) | .value[]; .udid == $id)' >/dev/null
  export KEYSTONE_IOS_SIMULATOR_UDID="$FLUTTER_DEVICE"
  flags=(--tags mobile --run-skipped --dart-define=VIZOR_FORM_FACTOR=mobile)
fi
work="$(mktemp -d "${TMPDIR:-/tmp}/vizor-keystone.XXXXXX")"
pid=""
chain="$work/chain"
compose_file="$chain/docker-compose.zcash-nu7-regtest.yml"
cleanup() {
  if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  if [[ -f "$compose_file" ]]; then
    docker compose -f "$compose_file" down --volumes
  fi
  rm -rf "$work"
}
trap cleanup EXIT
mkdir "$work/gui"
scripts/e2e/keystone-signer/build.sh "$work/gui/vote" stock
scripts/e2e/keystone-signer/build.sh "$work/gui/payment" regtest
fixture_tool="$(cargo build --locked --quiet --manifest-path rust/Cargo.toml --example keystone_signer_fixture --message-format=json-render-diagnostics |
  jq -r 'select(.target.name == "keystone_signer_fixture" and .executable != null) | .executable')"
export COMPOSE_PROJECT_NAME="vizor-$(basename "$work" | tr '[:upper:].' '[:lower:]-')"
export NU7_REGTEST_RPC_PORT="${NU7_REGTEST_RPC_PORT:-49242}"
export NU7_REGTEST_LIGHTWALLETD_PORT="${NU7_REGTEST_LIGHTWALLETD_PORT:-49177}"
export NU7_REGTEST_NU63_HEIGHT=300 NU7_REGTEST_NU7_HEIGHT=600
export LIGHTWALLETD_HOST=127.0.0.1
mkdir -p "$chain/scripts"
cp -R scripts/nu7-regtest "$chain/scripts/"
ln -s "$PWD/protos" "$chain/protos"
cp docker-compose.zcash-nu7-regtest.yml "$compose_file"
"$chain/scripts/nu7-regtest/up.sh"
"$fixture_tool" regtest-account "$work/wallet.db" < "$work/gui/payment/account.ur" > "$work/account.json"
funding="$(jq -er .fundingAddress "$work/account.json")"
# Fund before and after NU6.3, then mature both coinbase pools.
"$chain/scripts/nu7-regtest/fund.sh" "$funding" 4
"$chain/scripts/nu7-regtest/mine.sh" "$((NU7_REGTEST_NU63_HEIGHT - 4))"
"$chain/scripts/nu7-regtest/fund.sh" "$funding" 4
"$chain/scripts/nu7-regtest/mine.sh" 110
lwd="http://127.0.0.1:$NU7_REGTEST_LIGHTWALLETD_PORT"
"$fixture_tool" regtest-sync "$work/wallet.db" "$lwd" "$NU7_REGTEST_NU63_HEIGHT" "$NU7_REGTEST_NU7_HEIGHT"
mkdir -p "$work/voting"
"$fixture_tool" prepare-voting "$work/voting/wallet.db" < "$work/gui/vote/account.ur"
python3 scripts/e2e/keystone-signer/server.py --fixture-tool "$fixture_tool" \
  --gui-dir "$work/gui" --fixture-dir "$work/voting" --port-file "$work/port" &
pid=$!
for ((i=0; i<100; i++)); do
  [[ -s "$work/port" ]] && break
  kill -0 "$pid"
  sleep 0.1
done
url="http://127.0.0.1:$(cat "$work/port")"
gzip -c "$work/wallet.db" | base64 | tr -d '\n' > "$work/wallet.b64"
jq -n --slurpfile account "$work/account.json" --arg url "$url" --rawfile db "$work/wallet.b64" \
  --arg lwd "$lwd" --arg rpc "http://127.0.0.1:$NU7_REGTEST_RPC_PORT" \
  --arg ironwood "$NU7_REGTEST_NU63_HEIGHT" --arg nu7 "$NU7_REGTEST_NU7_HEIGHT" \
  '{KEYSTONE_ZEBRA_LIGHTWALLETD:$lwd, KEYSTONE_ZEBRA_RPC:$rpc, ZCASH_DEFAULT_NETWORK:"regtest",
    ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT:$ironwood, ZCASH_REGTEST_NU7_ACTIVATION_HEIGHT:$nu7,
    KEYSTONE_SIGNER_URL:$url, KEYSTONE_ACCOUNT_UUID:$account[0].accountUuid,
    KEYSTONE_TEX_ADDRESS:$account[0].texAddress, KEYSTONE_SEND_ADDRESS:$account[0].address, KEYSTONE_WALLET_DB:$db}' > "$work/fixture.json"
# Do not pass a host-only CARGO_TARGET_DIR into the iOS plugin build.
unset CARGO_TARGET_DIR
fvm flutter test "integration_test/keystone_signer_${target}_test.dart" -d "$FLUTTER_DEVICE" \
  "${flags[@]}" --dart-define-from-file="$work/fixture.json"
