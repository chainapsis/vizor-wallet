#!/usr/bin/env bash
# Manage only the dedicated validator-update proposal after successful checks.
set -euo pipefail

: "${BRANCH:?}"
: "${CHANGED:?}"
case "$CHANGED" in
  true|false) ;;
  *) echo "CHANGED must be true or false" >&2; exit 1 ;;
esac

existing="$(gh pr list --head "$BRANCH" --base main --state open \
  --json number,isCrossRepository \
  --jq '[.[] | select(.isCrossRepository == false)][0].number // empty')"

if [ "$CHANGED" = false ]; then
  if [ -n "$existing" ]; then
    gh pr close "$existing" --comment \
      "The authenticated current validator sets match main. This generated proposal is superseded."
  fi
  exit 0
fi

: "${RUNNER_TEMP:?}"
: "${DATA_FILES:?}"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
expected="$(git ls-remote origin "refs/heads/$BRANCH" | cut -f1)"
git switch -C "$BRANCH"
# shellcheck disable=SC2086 # DATA_FILES is the workflow's fixed list of paths.
git add $DATA_FILES
git commit -m "Update voting validator trust anchors"
git push --force-with-lease="refs/heads/$BRANCH:$expected" origin "HEAD:refs/heads/$BRANCH"
if [ -n "$existing" ]; then
  gh pr edit "$existing" --body-file "$RUNNER_TEMP/voting-validator-update.md"
else
  gh pr create --base main --head "$BRANCH" \
    --title "Update voting validator trust anchors" \
    --body-file "$RUNNER_TEMP/voting-validator-update.md"
fi
