#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_SUPPORT_DIR="$HOME/Library/Containers/com.keplr.vizor/Data/Library/Application Support/com.keplr.vizor"
db_path="${1:-${VIZOR_DB_PATH:-}}"

if [[ -z "$db_path" ]]; then
  db_path="$(
    find "$DEFAULT_SUPPORT_DIR" -maxdepth 1 -type f -name 'zcash_wallet_*.db' \
      -print0 2>/dev/null |
      xargs -0 stat -f '%m %N' 2>/dev/null |
      sort -nr |
      sed -n '1s/^[0-9]* //p'
  )"
fi

if [[ -z "$db_path" || ! -f "$db_path" ]]; then
  echo "wallet DB not found; pass its path or set VIZOR_DB_PATH" >&2
  exit 1
fi

echo "time=$(date '+%Y-%m-%d %H:%M:%S')"
echo "db=$db_path"

IRONWOOD_ACTIVATION_HEIGHT="${IRONWOOD_ACTIVATION_HEIGHT:-500}" \
  "$ROOT_DIR/scripts/ironwood-regtest/status.sh" |
  python3 -c 'import json,sys; d=json.load(sys.stdin); print("chain=" + json.dumps(d, separators=(",", ":")))'

mempool="$(
  IRONWOOD_ACTIVATION_HEIGHT="${IRONWOOD_ACTIVATION_HEIGHT:-500}" \
    "$ROOT_DIR/scripts/ironwood-regtest/rpc.sh" getrawmempool
)"
python3 - "$mempool" <<'PY'
import json
import sys

txids = json.loads(sys.argv[1])
print(f"mempool_count={len(txids)} txids={','.join(txids)}")
PY

sqlite3 -header -column "$db_path" <<'SQL'
.timeout 5000
SELECT
  (SELECT MAX(height) FROM blocks) AS wallet_height,
  run_id,
  phase,
  timing_policy,
  preparation_timing_policy,
  proof_retry_height,
  COALESCE(last_error, '') AS last_error
FROM vizor_migration_runs
ORDER BY created_at_ms DESC
LIMIT 1;

SELECT
  stage_index,
  status,
  target_height,
  scheduled_height,
  confirmed_mined_height,
  fee_zatoshi,
  expected_txid_hex
FROM vizor_migration_denomination_stages
WHERE run_id = (
  SELECT run_id FROM vizor_migration_runs ORDER BY created_at_ms DESC LIMIT 1
)
ORDER BY stage_index;

SELECT
  COUNT(*) AS prepared_notes,
  COALESCE(SUM(value_zatoshi), 0) AS prepared_value_zatoshi
FROM vizor_migration_prepared_notes
WHERE run_id = (
  SELECT run_id FROM vizor_migration_runs ORDER BY created_at_ms DESC LIMIT 1
);

SELECT
  COUNT(*) AS signed_children
FROM vizor_migration_signed_child_pczts
WHERE run_id = (
  SELECT run_id FROM vizor_migration_runs ORDER BY created_at_ms DESC LIMIT 1
);
SQL
