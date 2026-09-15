#!/usr/bin/env bash
# FRB 2.11.1's syn parser cannot read rustc's expanded `super let` (emitted
# by std::pin::pin!). Normalize only cargo-expand's inspection text. Rust still
# compiles the original macro; this does not change application code or runtime
# lifetimes. Remove this shim once FRB accepts super-let expressions.
set -euo pipefail
cd "$(dirname "$0")/.."
export VIZOR_CODEGEN_REAL_CARGO
VIZOR_CODEGEN_REAL_CARGO="$(command -v cargo)"
shim_dir="$(mktemp -d "${TMPDIR:-/tmp}/vizor-frb-expand.XXXXXX")"
trap 'rm -rf "$shim_dir"' EXIT
cat > "$shim_dir/cargo" <<'PY'
#!/usr/bin/env python3
import os
import re
import subprocess
import sys

cargo = os.environ['VIZOR_CODEGEN_REAL_CARGO']
args = sys.argv[1:]
if args and args[0] == 'expand':
    result = subprocess.run([cargo, *args], stdout=subprocess.PIPE)
    # Parsing function bodies is incidental to FRB's API/type discovery.
    sys.stdout.buffer.write(re.sub(rb'\bsuper\s+let\b', b'let', result.stdout))
    sys.exit(result.returncode)
os.execv(cargo, [cargo, *args])
PY
chmod +x "$shim_dir/cargo"
PATH="$shim_dir:$PATH" flutter_rust_bridge_codegen generate "$@"
