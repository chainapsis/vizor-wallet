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
  [[ "$(docker image inspect --format "{{ index .Config.Labels \"$GRANT_LABEL\" }}" "$IRONWOOD_ZCASHD_IMAGE" 2>/dev/null || true)" == "11000000" ]]; then
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
  :
else
  echo "the pinned faucet patch does not apply cleanly to $ZERO_SOURCE" >&2
  exit 1
fi

expected_index_dir="$(mktemp -d "$BUILD_ROOT/.expected-index.XXXXXX")"
expected_index="$expected_index_dir/index"
cleanup_expected_index() {
  if [[ -e "$expected_index" ]]; then
    unlink "$expected_index"
  fi
  rmdir "$expected_index_dir" 2>/dev/null || true
}
trap cleanup_expected_index EXIT
GIT_INDEX_FILE="$expected_index" git -C "$ZERO_SOURCE" read-tree HEAD
GIT_INDEX_FILE="$expected_index" git -C "$ZERO_SOURCE" apply \
  --cached \
  --directory=zcashd \
  "$PATCH_FILE"
untracked_files="$(git -C "$ZERO_SOURCE" ls-files --others --exclude-standard)"
if ! GIT_INDEX_FILE="$expected_index" git -C "$ZERO_SOURCE" diff \
  --quiet \
  --no-ext-diff ||
  [[ -n "$untracked_files" ]]; then
  echo "Zero source does not exactly match the pinned faucet patch: $ZERO_SOURCE" >&2
  GIT_INDEX_FILE="$expected_index" git -C "$ZERO_SOURCE" diff \
    --stat \
    --no-ext-diff >&2 || true
  if [[ -n "$untracked_files" ]]; then
    printf 'Untracked files:\n%s\n' "$untracked_files" >&2
  fi
  exit 1
fi
cleanup_expected_index
trap - EXIT

git -C "$ZERO_SOURCE" diff --check
docker build \
  --platform linux/amd64 \
  --label "$SOURCE_LABEL=$ZERO_REVISION" \
  --label "$GRANT_LABEL=11000000" \
  -f "$ZERO_SOURCE/docker/zcashd/Dockerfile" \
  -t "$IRONWOOD_ZCASHD_IMAGE" \
  "$ZERO_SOURCE/zcashd"

docker run --rm --platform linux/amd64 "$IRONWOOD_ZCASHD_IMAGE" --version
echo "built $IRONWOOD_ZCASHD_IMAGE from Zero $ZERO_REVISION"
