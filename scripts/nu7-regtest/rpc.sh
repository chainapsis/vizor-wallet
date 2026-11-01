#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Usage: rpc.sh METHOD [JSON_PARAMS_ARRAY], e.g. rpc.sh getrawtransaction '["<txid>", 1]'
if [[ $# -lt 1 ]]; then
  echo "usage: rpc.sh <method> [json-params-array]" >&2
  exit 1
fi
zebra_rpc "$1" "${2:-[]}"
