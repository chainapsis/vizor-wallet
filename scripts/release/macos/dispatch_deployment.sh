#!/usr/bin/env bash

set -euo pipefail

token="${DEPLOYMENT_DISPATCH_TOKEN:?DEPLOYMENT_DISPATCH_TOKEN is required}"
source_repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
source_ref="${GITHUB_REF:?GITHUB_REF is required}"
source_ref_name="${GITHUB_REF_NAME:?GITHUB_REF_NAME is required}"
source_sha="${GITHUB_SHA:?GITHUB_SHA is required}"
target_owner="${DEPLOYMENT_REPOSITORY_OWNER:?DEPLOYMENT_REPOSITORY_OWNER is required}"
target_repo="${DEPLOYMENT_REPOSITORY_NAME:?DEPLOYMENT_REPOSITORY_NAME is required}"

if [[ ! "${source_ref_name}" =~ ^release/v([0-9]+)\.([0-9]+)\.([0-9]+)(-rc\.([0-9]+))?$ ]]; then
  echo "Unsupported tag: ${source_ref_name}. Expected release/v<major>.<minor>.<patch> or release/v<major>.<minor>.<patch>-rc.<number>."
  exit 1
fi

version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
prerelease_suffix="${BASH_REMATCH[4]:-}"
asset_version="${version}${prerelease_suffix}"
is_prerelease="false"
if [[ -n "${prerelease_suffix}" ]]; then
  is_prerelease="true"
fi
release_name="${RELEASE_NAME:-v${asset_version}}"

payload="$(cat <<JSON
{
  "event_type": "vizor_macos_release",
  "client_payload": {
    "source_repository": "${source_repo}",
    "ref": "${source_ref}",
    "ref_name": "${source_ref_name}",
    "sha": "${source_sha}",
    "target_tag": "${source_ref_name}",
    "version": "${version}",
    "asset_version": "${asset_version}",
    "is_prerelease": ${is_prerelease},
    "release_name": "${release_name}"
  }
}
JSON
)"

curl --fail-with-body --silent --show-error \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${token}" \
  "https://api.github.com/repos/${target_owner}/${target_repo}/dispatches" \
  -d "${payload}"

echo "Dispatched ${source_ref_name} (${source_sha}) to deployment workflow"
