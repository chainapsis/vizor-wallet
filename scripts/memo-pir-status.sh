#!/usr/bin/env bash
# Print the memo PIR snapshot the server is serving next to what a local Vizor
# wallet has done with it. Every number is an aggregate; nothing here names a
# transaction, position, or row.
#
# usage: scripts/memo-pir-status.sh [--db <wallet.db>] [--server <https url>]
#
# Defaults: the newest wallet database of the isolated "Vizor Build" app, and
# VIZOR_MEMO_PIR_URL or the deployed demo endpoint.
set -euo pipefail

server="${VIZOR_MEMO_PIR_URL:-https://memo-pir.167.99.42.60.sslip.io}"
db=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) db="$2"; shift 2 ;;
    --server) server="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$db" ]]; then
  container="$HOME/Library/Containers/com.keplr.vizor.build-vizor/Data/Library/Application Support/com.keplr.vizor.build-vizor"
  db="$(ls -t "$container"/zcash_wallet_*.db 2>/dev/null | head -1 || true)"
  [[ -n "$db" ]] || { echo "no wallet database found; pass --db" >&2; exit 1; }
fi

for tool in curl jq sqlite3; do
  command -v "$tool" >/dev/null || { echo "missing $tool" >&2; exit 1; }
done

# Read a consistent copy so the running app is never blocked.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$db" "$work/wallet.db"
[[ -f "$db-wal" ]] && cp "$db-wal" "$work/wallet.db-wal"
q() { sqlite3 -batch "$work/wallet.db" "$1"; }

echo "== Server: $server"
if health="$(curl -fsS --max-time 20 "$server/v1/health")" \
  && meta="$(curl -fsS --max-time 20 "$server/v1/generation")"; then
  jq -r --argjson h "$health" '
    "phase                 \($h.phase.phase // $h.phase)   generation \(.generation)   retained \($h.retained_generations)",
    "schema                \(.schema_version)   envelope v\(.envelope.protocol_version): \(.envelope.k_nf) nf pairs, \(.envelope.k_act) action rows, \(.envelope.k_wit) witness pairs per pass",
    "anchor height         \(.anchor_height)   tree size \(.ironwood_tree_size)   cold checkpoint \(.cold_checkpoint_height)",
    (.tables | to_entries[] | "table " + (.key | . + "               " | .[0:14]) + " record \(.value.record_bytes) B, \(.value.positions) positions, \(.value.shards | length) shards (\([.value.shards[] | select(.sealed)] | length) sealed), workers \($h.tables[.key].workers)")' <<<"$meta"
  anchor_height="$(jq -r .anchor_height <<<"$meta")"
else
  echo "unreachable"
  anchor_height=""
fi

echo
echo "== Wallet: $db"
scanned_max="$(q 'select coalesce(max(height), 0) from blocks;')"
unscanned="$(q 'select coalesce(sum(block_range_end - block_range_start), 0) from scan_queue where priority > 10;')"
echo "accounts              $(q 'select count(*) from accounts;')"
echo "scanned to            $scanned_max   (blocks still queued: $unscanned)"
if [[ -n "$anchor_height" ]]; then
  if q "select 1 from blocks where height = $anchor_height;" | grep -q 1; then
    echo "anchor block scanned  yes -> snapshot can be authenticated locally"
  else
    echo "anchor block scanned  not yet -> no PIR query is sent until it is"
  fi
fi

echo
echo "== Memo PIR (Ironwood notes)"
q "select
  '  notes ' || count(*) ||
  '   memo present ' || sum(r.memo is not null) ||
  '   pending ' || sum(r.memo is null) ||
  '   completed privately ' || sum(r.memo is not null and t.raw is null) ||
  '   completed via full tx ' || sum(r.memo is not null and t.raw is not null)
  from ironwood_received_notes r join transactions t on t.id_tx = r.transaction_id;"
echo "  queue (positions waiting for a PIR row): $(q 'select count(*) from ironwood_memo_retrieval_queue;')"
echo "  \"completed privately\" = memo stored while the wallet never fetched the transaction: only the PIR client writes that."

echo
echo "== DAG-sync (Ironwood notes, keyed by tree position)"
echo "  witnessed privately     $(q 'select count(*) from ironwood_pir_witnesses;')   (notes spendable from a PIR Merkle path; anchors: $(q 'select coalesce(group_concat(distinct anchor_height), "-") from ironwood_pir_witnesses;'))"
echo "  spends found privately  $(q 'select count(*) from ironwood_received_note_spends s join transactions t on t.id_tx = s.transaction_id where t.block is null and t.mined_height is not null;')   (spent notes whose spending transaction the wallet never scanned)"
echo "  change discovered       $(q 'select count(*) from ironwood_received_notes r join transactions t on t.id_tx = r.transaction_id where t.block is null and t.mined_height is not null;')   (notes learned from PIR action rows, memo included)"
echo "  Every pass issues the fixed server envelope; these counts never change the request pattern."

echo
echo "== Legacy txid enhancement (inert on mainnet)"
q "select
  '  transactions ' || count(*) ||
  '   fetched by txid ' || sum(raw is not null) ||
  '   never fetched ' || sum(raw is null)
  from transactions where block is not null;"
echo "  enhancement requests queued and suppressed: $(q "select count(*) from tx_retrieval_queue q where q.query_type = 1 and exists (select 1 from transactions t where t.txid = q.txid);")"
orphans="$(q "select count(*) from tx_retrieval_queue q where not exists (select 1 from transactions t where t.txid = q.txid);")"
[[ "$orphans" == 0 ]] || echo "  (plus $orphans stale queue rows for transactions that no longer exist, e.g. from a deleted account)"
echo "  Those transactions keep amounts from compact scanning but have no memo, fee, or sent-recipient details."
