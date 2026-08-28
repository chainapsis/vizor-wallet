#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UFVK_API_URL="${VIZOR_LEDGER_SPECULOS_UFVK_API_URL:-}"
SIGNING_API_URL="${VIZOR_LEDGER_SPECULOS_SIGNING_API_URL:-}"
FLUTTER_DEVICE="${FLUTTER_DEVICE:-macos}"
SCENARIO_FILTER="${VIZOR_LEDGER_E2E_SCENARIO:-}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd cargo
require_cmd base64
require_cmd curl
require_cmd fvm
require_cmd gzip
require_cmd jq

if [[ -z "$UFVK_API_URL" || -z "$SIGNING_API_URL" ]]; then
  echo "set distinct VIZOR_LEDGER_SPECULOS_UFVK_API_URL and VIZOR_LEDGER_SPECULOS_SIGNING_API_URL" >&2
  exit 1
fi
if [[ "$UFVK_API_URL" == "$SIGNING_API_URL" ]]; then
  echo "Ledger UFVK and signing E2E endpoints must be different fresh Speculos instances" >&2
  exit 1
fi

curl -fsS "$UFVK_API_URL/events?currentscreenonly=true" >/dev/null
curl -fsS "$SIGNING_API_URL/events?currentscreenonly=true" >/dev/null

FIXTURE_DIR="$(mktemp -d /tmp/vizor-ledger-desktop-e2e.XXXXXX)"
FIXTURE_DB="$FIXTURE_DIR/wallet.db"
FIXTURE_PCZT="$FIXTURE_DIR/unsigned.pczt"
FIXTURE_JSON="$FIXTURE_DIR/fixture.json"

cd "$ROOT_DIR"

echo "preparing isolated Ledger fixture in $FIXTURE_DIR"
cargo run --manifest-path rust/Cargo.toml --quiet \
  --example ledger_zcash_speculos_poc -- \
  prepare-fixture \
  --api-url "$UFVK_API_URL" \
  --db-path "$FIXTURE_DB" \
  --pczt "$FIXTURE_PCZT" \
  --metadata "$FIXTURE_JSON"

FIXTURE_UFVK="$(jq -r '.ufvk' "$FIXTURE_JSON")"
FIXTURE_SEED_FINGERPRINT="$(jq -r '.seedFingerprint' "$FIXTURE_JSON")"
FIXTURE_ACCOUNT_UUID="$(jq -r '.accountUuid' "$FIXTURE_JSON")"
FIXTURE_TRANSPARENT_ADDRESS="$(jq -r '.transparentAddress' "$FIXTURE_JSON")"
FIXTURE_TEX_ADDRESS="$(jq -r '.texAddress' "$FIXTURE_JSON")"
FIXTURE_TEX_STEP_1_PCZT="$(jq -r '.texStep1PcztPath' "$FIXTURE_JSON")"
FIXTURE_TEX_STEP_2_PCZT="$(jq -r '.texStep2PcztPath' "$FIXTURE_JSON")"
FIXTURE_VOTING_BUNDLE_1_PCZT="$(jq -r '.votingBundle1PcztPath' "$FIXTURE_JSON")"
FIXTURE_VOTING_BUNDLE_2_PCZT="$(jq -r '.votingBundle2PcztPath' "$FIXTURE_JSON")"
FIXTURE_VOTING_BUNDLE_1_ACTION_INDEX="$(jq -r '.votingBundle1ActionIndex' "$FIXTURE_JSON")"
FIXTURE_VOTING_BUNDLE_2_ACTION_INDEX="$(jq -r '.votingBundle2ActionIndex' "$FIXTURE_JSON")"
FIXTURE_PCZT_BASE64="$(base64 -i "$FIXTURE_PCZT" | tr -d '\n')"
FIXTURE_TEX_STEP_1_PCZT_BASE64="$(base64 -i "$FIXTURE_TEX_STEP_1_PCZT" | tr -d '\n')"
FIXTURE_TEX_STEP_2_PCZT_BASE64="$(base64 -i "$FIXTURE_TEX_STEP_2_PCZT" | tr -d '\n')"
FIXTURE_VOTING_BUNDLE_1_PCZT_BASE64="$(base64 -i "$FIXTURE_VOTING_BUNDLE_1_PCZT" | tr -d '\n')"
FIXTURE_VOTING_BUNDLE_2_PCZT_BASE64="$(base64 -i "$FIXTURE_VOTING_BUNDLE_2_PCZT" | tr -d '\n')"
FIXTURE_DB_GZIP_BASE64="$(gzip -c "$FIXTURE_DB" | base64 | tr -d '\n')"

run_flutter_scenario() {
  local test_name="$1"
  if [[ -n "$SCENARIO_FILTER" && "$test_name" != "$SCENARIO_FILTER" ]]; then
    return
  fi
  echo "running Flutter macOS Ledger Speculos scenario: $test_name"
  fvm flutter test \
    integration_test/ledger_speculos_desktop_test.dart \
    -d "$FLUTTER_DEVICE" \
    --plain-name "$test_name" \
    --dart-define=VIZOR_LEDGER_E2E_UFVK="$FIXTURE_UFVK" \
    --dart-define=VIZOR_LEDGER_E2E_SEED_FINGERPRINT="$FIXTURE_SEED_FINGERPRINT" \
    --dart-define=VIZOR_LEDGER_E2E_ACCOUNT_UUID="$FIXTURE_ACCOUNT_UUID" \
    --dart-define=VIZOR_LEDGER_E2E_TRANSPARENT_ADDRESS="$FIXTURE_TRANSPARENT_ADDRESS" \
    --dart-define=VIZOR_LEDGER_E2E_TEX_ADDRESS="$FIXTURE_TEX_ADDRESS" \
    --dart-define=VIZOR_LEDGER_E2E_PCZT_BASE64="$FIXTURE_PCZT_BASE64" \
    --dart-define=VIZOR_LEDGER_E2E_TEX_STEP_1_PCZT_BASE64="$FIXTURE_TEX_STEP_1_PCZT_BASE64" \
    --dart-define=VIZOR_LEDGER_E2E_TEX_STEP_2_PCZT_BASE64="$FIXTURE_TEX_STEP_2_PCZT_BASE64" \
    --dart-define=VIZOR_LEDGER_E2E_VOTING_BUNDLE_1_PCZT_BASE64="$FIXTURE_VOTING_BUNDLE_1_PCZT_BASE64" \
    --dart-define=VIZOR_LEDGER_E2E_VOTING_BUNDLE_2_PCZT_BASE64="$FIXTURE_VOTING_BUNDLE_2_PCZT_BASE64" \
    --dart-define=VIZOR_LEDGER_E2E_VOTING_BUNDLE_1_ACTION_INDEX="$FIXTURE_VOTING_BUNDLE_1_ACTION_INDEX" \
    --dart-define=VIZOR_LEDGER_E2E_VOTING_BUNDLE_2_ACTION_INDEX="$FIXTURE_VOTING_BUNDLE_2_ACTION_INDEX" \
    --dart-define=VIZOR_LEDGER_E2E_DB_GZIP_BASE64="$FIXTURE_DB_GZIP_BASE64" \
    --dart-define=VIZOR_E2E_HIDDEN_WINDOW="${VIZOR_E2E_HIDDEN_WINDOW:-true}"
}

# Keep each wallet journey isolated so a failure identifies the exact product
# flow. The final scenario separately proves that two signatures can run in one
# native app lifecycle after the Ledger status-screen cooldown.
run_flutter_scenario "imports and sends with Ledger through Speculos"
run_flutter_scenario "sends to TEX with two Ledger approvals through Speculos"
run_flutter_scenario "shields transparent balance with Ledger through Speculos"
run_flutter_scenario "pays with Ledger through Speculos"
run_flutter_scenario "swaps with Ledger through Speculos"
run_flutter_scenario "signs sequential voting bundles with Ledger through Speculos"
run_flutter_scenario "signs sequential Ledger operations in one app lifecycle"

echo "Ledger Speculos fixture retained at $FIXTURE_DIR"
