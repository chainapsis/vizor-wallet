#!/usr/bin/env bash
# Prepare the exact compatibility dependency required by the experimental POC.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
checkout="$(dirname "$root")/ipir-sp-compat"
revision=79ca43b92c71bc33b99ba71a9841cc5da4d5e3b2
if [[ ! -e "$checkout" ]]; then
  git clone --branch adam/vizor-spiral-compat-20260927 --single-branch \
    https://github.com/valargroup/ipir-sp.git "$checkout"
  git -C "$checkout" checkout --detach "$revision"
fi
if [[ "$(git -C "$checkout" rev-parse HEAD)" != "$revision" ]] || \
   [[ -n "$(git -C "$checkout" status --porcelain)" ]]; then
  echo "Expected a clean ipir-sp-compat checkout at $revision; existing work was preserved." >&2
  exit 1
fi
echo "PIR compatibility checkout verified at $revision"
