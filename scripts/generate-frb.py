#!/usr/bin/env python3
"""Generate FRB 2.11 bindings with cargo-expand's newer pin! syntax.

Rust's expanded `pin!` uses `super let` to extend a temporary's lifetime. FRB's
syn parser cannot read that expansion. For codegen inspection only, normalize
this to `let`. The compiled Rust sources and their lifetime semantics are never
changed. Remove this adapter when FRB can parse `super let`.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
cargo = shutil.which('cargo')
if cargo is None:
    raise SystemExit('cargo is required')
with tempfile.TemporaryDirectory(prefix='vizor-frb-') as temporary:
    wrapper = Path(temporary) / 'cargo'
    wrapper.write_text('''#!/usr/bin/env python3
import os, subprocess, sys
cargo = os.environ['VIZOR_FRB_REAL_CARGO']
if len(sys.argv) > 1 and sys.argv[1] == 'expand':
    result = subprocess.run([cargo, *sys.argv[1:]], stdout=subprocess.PIPE)
    sys.stdout.buffer.write(result.stdout.replace(b'super let ', b'let '))
    sys.exit(result.returncode)
os.execv(cargo, [cargo, *sys.argv[1:]])
''')
    wrapper.chmod(0o755)
    environment = dict(os.environ, VIZOR_FRB_REAL_CARGO=cargo)
    environment['PATH'] = temporary + os.pathsep + environment['PATH']
    raise SystemExit(subprocess.run(['flutter_rust_bridge_codegen', 'generate'], cwd=root, env=environment).returncode)
