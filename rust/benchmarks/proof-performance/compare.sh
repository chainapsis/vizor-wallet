#!/usr/bin/env bash
set -euo pipefail

benchmark_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
samples=${SAMPLES:-5}
warmups=${WARMUPS:-1}
order=${ORDER:-ab}

if ! [[ $samples =~ ^[1-9][0-9]*$ ]]; then
  echo "SAMPLES must be a positive integer" >&2
  exit 2
fi
if ! [[ $warmups =~ ^[0-9]+$ ]]; then
  echo "WARMUPS must be a non-negative integer" >&2
  exit 2
fi
if [[ $order != "ab" && $order != "ba" ]]; then
  echo "ORDER must be ab or ba" >&2
  exit 2
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
results_dir=${RESULTS_DIR:-"$benchmark_dir/results/$timestamp"}
mkdir -p "$results_dir"
jq -n \
  --arg timestamp "$timestamp" \
  --arg order "$order" \
  --argjson samples "$samples" \
  --argjson warmups "$warmups" \
  '{timestamp_utc: $timestamp, order: $order, samples: $samples, warmups: $warmups}' \
  > "$results_dir/run.json"

upstream_manifest="$benchmark_dir/upstream/Cargo.toml"
zakura_manifest="$benchmark_dir/zakura/Cargo.toml"
upstream_target="$benchmark_dir/target/upstream"
zakura_target="$benchmark_dir/target/zakura"

build_variant() {
  local manifest=$1
  local target_dir=$2
  CARGO_TARGET_DIR="$target_dir" cargo build \
    --quiet \
    --release \
    --locked \
    --manifest-path "$manifest"
}

record_sources() {
  local manifest=$1
  local target_dir=$2
  local output=$3
  CARGO_TARGET_DIR="$target_dir" cargo metadata \
    --locked \
    --format-version 1 \
    --manifest-path "$manifest" \
    | jq '[.packages[] | select(.name == "voting-circuits" or .name == "halo2_proofs" or .name == "orchard" or .name == "pasta_curves") | {name, version, source}]' \
    > "$output"
}

run_variant() {
  local variant=$1
  local target_dir=$2
  local circuit=$3
  local output=$4
  "$target_dir/release/voting-proof-benchmark" \
    --circuit "$circuit" \
    --samples "$samples" \
    --warmups "$warmups" \
    --label "$variant" \
    > "$output"
  jq -e '.status == "ok"' "$output" >/dev/null
}

echo "Building both release variants before timing..."
build_variant "$upstream_manifest" "$upstream_target"
build_variant "$zakura_manifest" "$zakura_target"
record_sources "$upstream_manifest" "$upstream_target" "$results_dir/upstream-sources.json"
record_sources "$zakura_manifest" "$zakura_target" "$results_dir/zakura-sources.json"

echo "Running proof benchmarks sequentially..."
if [[ $order == "ab" ]]; then
  run_variant upstream "$upstream_target" zkp1 "$results_dir/upstream-zkp1.json"
  run_variant zakura "$zakura_target" zkp1 "$results_dir/zakura-zkp1.json"
  run_variant zakura "$zakura_target" zkp2 "$results_dir/zakura-zkp2.json"
  run_variant upstream "$upstream_target" zkp2 "$results_dir/upstream-zkp2.json"
else
  run_variant zakura "$zakura_target" zkp1 "$results_dir/zakura-zkp1.json"
  run_variant upstream "$upstream_target" zkp1 "$results_dir/upstream-zkp1.json"
  run_variant upstream "$upstream_target" zkp2 "$results_dir/upstream-zkp2.json"
  run_variant zakura "$zakura_target" zkp2 "$results_dir/zakura-zkp2.json"
fi

jq -s '
  def report($circuit; $variant):
    map(select(.report.circuit == $circuit and .report.label == $variant))[0].report;
  . as $reports |
  ["zkp1", "zkp2"] | map(
    . as $circuit |
    ($reports | report($circuit; "upstream")) as $upstream |
    ($reports | report($circuit; "zakura")) as $zakura |
    {
      circuit: $circuit,
      upstream_median_ms: $upstream.proof.median_ms,
      zakura_median_ms: $zakura.proof.median_ms,
      change_percent: (($zakura.proof.median_ms / $upstream.proof.median_ms - 1) * 100),
      proof_size_bytes: $zakura.proof_size_bytes
    }
  ) | {results: .}
' "$results_dir"/*-zkp*.json > "$results_dir/comparison.json"

printf '\n%-6s %14s %14s %11s\n' "Proof" "Upstream ms" "Zakura ms" "Change"
printf '%-6s %14s %14s %11s\n' "------" "-----------" "---------" "------"
for circuit in zkp1 zkp2; do
  upstream_ms=$(jq -r '.report.proof.median_ms' "$results_dir/upstream-$circuit.json")
  zakura_ms=$(jq -r '.report.proof.median_ms' "$results_dir/zakura-$circuit.json")
  change=$(awk -v upstream="$upstream_ms" -v zakura="$zakura_ms" 'BEGIN { printf "%+.1f%%", ((zakura / upstream) - 1) * 100 }')
  printf '%-6s %14.2f %14.2f %11s\n' "$circuit" "$upstream_ms" "$zakura_ms" "$change"
done

printf '\nRaw reports: %s\n' "$results_dir"
