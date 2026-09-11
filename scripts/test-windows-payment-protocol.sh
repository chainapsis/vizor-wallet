#!/usr/bin/env bash
set -euo pipefail

# Portable native contract test. All Windows APIs are in-memory test doubles;
# this script does not register a URI handler or open a wallet.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner_dir="$repo_root/windows/runner"
test_output="$(mktemp -d "${TMPDIR:-/tmp}/vizor-payment-protocol.XXXXXX")"

"${CXX:-c++}" -std=c++17 -Wall -Wextra -Werror \
  -I"$runner_dir/tests/stubs" \
  "$runner_dir/payment_uri_protocol.cpp" \
  "$runner_dir/tests/payment_uri_protocol_test.cpp" \
  -o "$test_output/payment-uri-protocol-test"
"$test_output/payment-uri-protocol-test"
