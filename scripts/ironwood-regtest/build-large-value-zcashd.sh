#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/large-value-env.sh"

ZERO_REPOSITORY="https://github.com/ShieldedLabs/zero.git"
ZERO_REVISION="93a1d844c5e9f749b4b4a5a52de5c1ea8d02c523"
BUILD_ROOT="$ROOT_DIR/.ironwood-large-value-regtest-build"
ZERO_SOURCE="$BUILD_ROOT/zero"
PATCH_FILE="$SCRIPT_DIR/large-value/zero-regtest-faucet-grant.patch"
SOURCE_LABEL="org.vizor.regtest.zero-revision"
GRANT_LABEL="org.vizor.regtest.faucet-grant-zec"

for command in docker git; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "missing required command: $command" >&2
    exit 1
  fi
done

if [[ "$(dirname "$BUILD_ROOT")" != "$ROOT_DIR" ]] ||
  [[ "$(basename "$BUILD_ROOT")" != ".ironwood-large-value-regtest-build" ]] ||
  [[ -L "$BUILD_ROOT" ]]; then
  echo "refusing unmanaged large-value build directory: $BUILD_ROOT" >&2
  exit 1
fi

if [[ "${IRONWOOD_LARGE_VALUE_REBUILD:-false}" != "true" ]] &&
  [[ "$(docker image inspect --format "{{ index .Config.Labels \"$SOURCE_LABEL\" }}" "$IRONWOOD_ZCASHD_IMAGE" 2>/dev/null || true)" == "$ZERO_REVISION" ]] &&
  [[ "$(docker image inspect --format "{{ index .Config.Labels \"$GRANT_LABEL\" }}" "$IRONWOOD_ZCASHD_IMAGE" 2>/dev/null || true)" == "1100000" ]]; then
  echo "large-value zcashd image is already built: $IRONWOOD_ZCASHD_IMAGE"
  exit 0
fi

mkdir -p "$BUILD_ROOT"
if [[ ! -d "$ZERO_SOURCE/.git" ]]; then
  if [[ -e "$ZERO_SOURCE" ]]; then
    echo "refusing non-git Zero source path: $ZERO_SOURCE" >&2
    exit 1
  fi
  git clone --filter=blob:none --branch v15 --depth 1 "$ZERO_REPOSITORY" "$ZERO_SOURCE"
fi

if [[ "$(git -C "$ZERO_SOURCE" rev-parse HEAD)" != "$ZERO_REVISION" ]]; then
  echo "Zero source is not pinned to $ZERO_REVISION: $ZERO_SOURCE" >&2
  exit 1
fi

if git -C "$ZERO_SOURCE" apply --check --directory=zcashd "$PATCH_FILE"; then
  git -C "$ZERO_SOURCE" apply --directory=zcashd "$PATCH_FILE"
elif git -C "$ZERO_SOURCE" apply --reverse --check --directory=zcashd "$PATCH_FILE"; then
  changed_files="$(git -C "$ZERO_SOURCE" status --short | awk '{print $2}' | sort)"
  expected_files="$(printf '%s\n' zcashd/src/chainparams.cpp zcashd/src/consensus/params.cpp zcashd/src/consensus/params.h | sort)"
  if [[ "$changed_files" != "$expected_files" ]]; then
    echo "Zero source contains changes beyond the faucet patch: $ZERO_SOURCE" >&2
    git -C "$ZERO_SOURCE" status --short >&2
    exit 1
  fi
else
  echo "the pinned faucet patch does not apply cleanly to $ZERO_SOURCE" >&2
  exit 1
fi

git -C "$ZERO_SOURCE" diff --check
docker build \
  --platform linux/amd64 \
  --label "$SOURCE_LABEL=$ZERO_REVISION" \
  --label "$GRANT_LABEL=1100000" \
  -f "$ZERO_SOURCE/docker/zcashd/Dockerfile" \
  -t "$IRONWOOD_ZCASHD_IMAGE" \
  "$ZERO_SOURCE/zcashd"

docker run --rm --platform linux/amd64 "$IRONWOOD_ZCASHD_IMAGE" --version
echo "built $IRONWOOD_ZCASHD_IMAGE from Zero $ZERO_REVISION"
