"""Flutter E2E scenarios on direct Zakura fixtures: catalog and commands.

A Flutter case serves the fixture on the app's default regtest ports, so the
app's endpoint presets and the tests' defaults need no override: the
lightwalletd shim on 9067, the HTTP control on 18232 and the in-test
lightwalletd proxy on 19068. Nothing may listen on 19067, the Unavailable
preset. Each phase is one `flutter test` run from the checkout root.
"""
from __future__ import annotations

import dataclasses
import re
import sys

import e2e_runtime as runtime

LIGHTWALLETD_PORT = 9067
CONTROL_PORT = 18232
PROXY_PORT = 19068
UNAVAILABLE_PORT = 19067
FIXED_PORTS = {"rpc": CONTROL_PORT, "lwd": LIGHTWALLETD_PORT, "proxy": PROXY_PORT}

DEFAULT_ACTIVATION = 1
MIGRATION_ACTIVATION = 500
INITIAL_BLOCKS = 100

DESKTOP_UA = ("uregtest1nu0qx0nca0ncpshm5x47ldc90835m2fy3gjuh3empp5js9qanzjwxppsw7x07a2ec3z52ute7d7f0z68ez90"
              "qlagx5ankjm4eyd6l90p")
IMPORT_UA = ("uregtest1ykjd398elks624qyz0d0vffn6vpqkl6atp2wsr9795eql4kw47hwlffxyyfakv0l2twj635fpmxmeu3tzyrfhf5s"
             "9eg9ea8gsa0srdfwjudp3fs0qaaqxvkxr364a8vjy3y9vglm7lf8rs0vsev9p5mzky52rq4wkr5lhc842vuf5lhn")
IMPORT_TRANSPARENT = "tmPTcChwqcza88W1mydzwkZ25C9qQm3ugiM"


@dataclasses.dataclass(frozen=True)
class Funding:
    """One payment from a mature coinbase, confirmed before the app starts."""
    address: str
    zatoshi: int
    pool: str
    source_height: int


@dataclasses.dataclass(frozen=True)
class Phase:
    """One `flutter test` run; `mine_before` blocks are mined while no app runs."""
    test: str
    mine_before: int = 0
    args: tuple[str, ...] = ()


@dataclasses.dataclass(frozen=True)
class FlutterScenario:
    id: str
    platform: str
    phases: tuple[Phase, ...]
    defines: tuple[tuple[str, str], ...] = ()
    env: tuple[tuple[str, str], ...] = ()
    funding: tuple[Funding, ...] = ()
    activation_height: int = DEFAULT_ACTIVATION
    initial_blocks: int = INITIAL_BLOCKS
    timeout_seconds: int = 1200


FLUTTER_SCENARIOS = (
    FlutterScenario(
        "flutter.macos.import-sync", "macos",
        (Phase("integration_test/regtest_import_sync_test.dart"),),
        defines=(("ZCASH_E2E_FIRST_UNLOCK_MNEMONIC_KEYCHAIN", "true"),),
        funding=(Funding(IMPORT_UA, 125_000_000, "ironwood", 1),
                 Funding(IMPORT_TRANSPARENT, 75_000_000, "transparent", 2))),
)

# Python moves into the checkout before `flutter test` replaces it, so the
# case keeps owning the process while Flutter finds the project's pubspec.
_IN_CHECKOUT = "import os, sys; os.chdir(sys.argv[1]); os.execvp(sys.argv[2], sys.argv[2:])"


def flutter_command(scenario, phase, *, flutter, device, source_root):
    """The phase's `flutter test` command line, run from the checkout root."""
    defines = {
        "ZCASH_DEFAULT_NETWORK": "regtest",
        "ZCASH_REGTEST_IRONWOOD_ACTIVATION_HEIGHT": str(scenario.activation_height),
        "ZCASH_E2E_LIGHTWALLETD_URL": f"http://127.0.0.1:{LIGHTWALLETD_PORT}",
        "ZCASH_E2E_DRIVER_URL": f"http://127.0.0.1:{CONTROL_PORT}",
    }
    if scenario.platform == "macos":
        defines["VIZOR_E2E_HIDDEN_WINDOW"] = "true"
    else:
        defines["VIZOR_FORM_FACTOR"] = "mobile"
    for name, value in scenario.defines:
        if name in defines:
            raise ValueError(f"{scenario.id} overrides the fixture define {name}")
        defines[name] = value
    return [sys.executable, "-c", _IN_CHECKOUT, str(source_root), str(flutter), "test", phase.test,
            "-d", device, *phase.args, *(f"--dart-define={name}={value}" for name, value in defines.items())]


_PASSED = re.compile(r"^\d{2}:\d{2} \+([1-9][0-9]*)(?: ~[0-9]+)?: All tests passed!$", re.MULTILINE)


def verify_flutter_output(lines):
    """Exit 0 alone is not a pass: Flutter must report at least one passing test."""
    output = "".join(lines)
    if not _PASSED.search(output) or "Some tests failed" in output:
        raise runtime.RunnerError("flutter test did not report its tests as passed")
