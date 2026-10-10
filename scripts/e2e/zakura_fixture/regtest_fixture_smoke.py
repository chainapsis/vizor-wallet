#!/usr/bin/env python3
"""Mine and verify an owned regtest fixture without a wallet or test runner."""

from __future__ import annotations

import argparse
import json
import math
import os
from pathlib import Path
import tempfile
from typing import Any, Sequence

from regtest_fixture import (
    CONTROLLED_ACTIVATION_PROFILE,
    DIRECT_HEIGHT1_PROFILE,
    FixtureError,
    NU62_BRANCH_ID,
    NU63_BRANCH_ID,
    RegtestFixture,
)


def _blocks(value: str) -> int:
    try:
        result = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("blocks must be an integer from 1 to 1000") from error
    if not 1 <= result <= 1000:
        raise argparse.ArgumentTypeError("blocks must be an integer from 1 to 1000")
    return result


def _timeout(value: str) -> float:
    try:
        result = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("timeout must be finite and greater than 0, up to 300 seconds") from error
    if not math.isfinite(result) or not 0 < result <= 300:
        raise argparse.ArgumentTypeError("timeout must be finite and greater than 0, up to 300 seconds")
    return result


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--grpcurl", required=True, type=Path, help="existing grpcurl executable")
    parser.add_argument("--proto-dir", required=True, type=Path, help="existing compatible lightwalletd descriptors")
    parser.add_argument("--artifacts-dir", type=Path, help="new output directory under an existing parent; never overwritten")
    parser.add_argument("--profile", choices=(DIRECT_HEIGHT1_PROFILE, CONTROLLED_ACTIVATION_PROFILE), default=DIRECT_HEIGHT1_PROFILE)
    parser.add_argument("--network-subnet", help="explicit private IPv4 CIDR; overlaps fail without deleting existing networks")
    parser.add_argument("--blocks", type=_blocks, default=2, help="additional blocks after the height-1 bootstrap (1..1000; default: 2)")
    parser.add_argument("--timeout", type=_timeout, default=60.0, help="timeout per fixture phase in seconds (greater than 0, up to 300; default: 60)")
    return parser.parse_args(argv)


def _artifacts(path: Path | None) -> Path:
    if path is None:
        return Path(tempfile.mkdtemp(prefix="zakura-regtest-smoke-")).resolve(strict=True)
    raw = Path(path).expanduser().absolute()
    # Inspect the supplied spelling before resolving a final-component symlink.
    if raw.is_symlink() or raw.exists():
        raise FixtureError("artifacts directory must not already exist")
    parent = raw.parent.resolve(strict=True)
    if not parent.is_dir() or parent.stat().st_uid != os.getuid():
        raise FixtureError("artifacts parent must be an existing owned directory")
    target = parent / raw.name
    target.mkdir(mode=0o700)
    return target.resolve(strict=True)


def _check_parity(parity: Any, height: int, profile: str) -> None:
    activation = 1 if profile == DIRECT_HEIGHT1_PROFILE else 500
    active = height >= activation
    pools = {"sapling", "orchard", "ironwood"} if active else {"sapling", "orchard"}
    if (
        not isinstance(parity, dict)
        or type(parity.get("height")) is not int or parity["height"] != height
        or parity.get("consensus_branch_id") != (NU63_BRANCH_ID if active else NU62_BRANCH_ID)
        or not isinstance(parity.get("trees"), dict) or set(parity["trees"]) != pools
    ):
        raise FixtureError("fixture parity does not match the requested height and profile")
    block_hash = parity.get("hash")
    if (
        not isinstance(block_hash, str) or len(block_hash) != 64
        or any(char not in "0123456789abcdef" for char in block_hash)
    ):
        raise FixtureError("fixture parity did not identify an exact block hash")


def _error(phase: str, error: BaseException) -> dict[str, str]:
    return {"phase": phase, "type": type(error).__name__, "message": str(error)}


def _check_cleanup(cleanup: Any, run_id: str) -> None:
    if (
        not isinstance(cleanup, dict)
        or type(cleanup.get("schema_version")) is not int
        or cleanup["schema_version"] != 1
        or cleanup.get("run_id") != run_id
        or not isinstance(run_id, str) or len(run_id) != 32
        or any(char not in "0123456789abcdef" for char in run_id)
        or type(cleanup.get("complete")) is not bool
        or not isinstance(cleanup.get("errors"), list)
        or any(not isinstance(error, str) for error in cleanup["errors"])
        or cleanup["complete"] != (not cleanup["errors"])
        or not isinstance(cleanup.get("removed"), list)
    ):
        raise FixtureError("fixture returned an invalid cleanup proof")
    for resource in cleanup["removed"]:
        if (
            not isinstance(resource, dict)
            or resource.get("kind") not in ("container", "network", "volume")
            or not isinstance(resource.get("name"), str) or not resource["name"]
            or not isinstance(resource.get("id"), str) or not resource["id"]
        ):
            raise FixtureError("fixture returned an invalid removed-resource proof")


def run(args: argparse.Namespace) -> int:
    report: dict[str, Any] = {
        "schema_version": 1, "status": "failed", "exit_code": 1,
        "artifacts": None, "profile": args.profile, "blocks": args.blocks,
        "error": None, "report_error": None, "start_proof": None,
        "mining": None, "final_parity": None,
        "cleanup": {"complete": True, "errors": [], "removed": []},
    }
    artifacts: Path | None = None
    fixture: RegtestFixture | None = None
    phase = "artifacts"
    try:
        artifacts = _artifacts(args.artifacts_dir)
        report["artifacts"] = str(artifacts)
        phase = "fixture"
        fixture = RegtestFixture(artifacts, args.grpcurl, args.proto_dir,
                                 timeout=args.timeout, profile=args.profile,
                                 network_subnet=args.network_subnet)
        phase = "start"
        start = fixture.start()
        report["start_proof"] = start
        phase = "bootstrap"
        _check_parity(start.get("parity"), 1, args.profile)
        profile = start.get("profile", {})
        activation = 1 if args.profile == DIRECT_HEIGHT1_PROFILE else 500
        if (
            not isinstance(profile, dict) or profile.get("name") != args.profile
            or type(profile.get("nu6_3_activation_height")) is not int
            or profile["nu6_3_activation_height"] != activation
            or fixture.rpc("getpeerinfo") != []
        ):
            raise FixtureError("fixture bootstrap does not match the isolated profile")
        phase = "mine"
        mined = fixture.mine(args.blocks)
        report["mining"] = mined
        _check_parity(mined.get("tip"), 1 + args.blocks, args.profile)
        hashes = mined.get("hashes")
        if (
            not isinstance(hashes, list) or len(hashes) != args.blocks
            or any(not isinstance(value, str) or len(value) != 64
                   or any(char not in "0123456789abcdef" for char in value) for value in hashes)
            or len(set(hashes)) != args.blocks or hashes[-1] != mined["tip"]["hash"]
        ):
            raise FixtureError("fixture did not mine the exact requested block range")
        phase = "parity"
        parity = fixture.wait_synced()
        report["final_parity"] = parity
        _check_parity(parity, 1 + args.blocks, args.profile)
        if parity["hash"] != hashes[-1] or fixture.rpc("getpeerinfo") != []:
            raise FixtureError("final node/lightwalletd identity or isolation changed")
        report.update(status="passed", exit_code=0)
    except KeyboardInterrupt as error:
        report.update(status="interrupted", exit_code=130, error=_error(phase, error))
    except Exception as error:
        report["error"] = _error(phase, error)
    finally:
        if fixture is not None:
            try:
                cleanup = fixture.close()
                _check_cleanup(cleanup, fixture.run_id)
                report["cleanup"] = cleanup
            except (Exception, KeyboardInterrupt) as error:
                report["cleanup"] = {"complete": False, "errors": [f"{type(error).__name__}: {error}"], "removed": []}
                if report["error"] is None:
                    report["error"] = _error("cleanup", error)
                    if isinstance(error, KeyboardInterrupt):
                        report.update(status="interrupted", exit_code=130)
            if report["cleanup"]["complete"] is not True:
                if report["error"] is None:
                    report["error"] = {"phase": "cleanup", "type": "FixtureError", "message": "fixture cleanup was incomplete"}
                if report["exit_code"] == 0:
                    report.update(status="failed", exit_code=1)
        if artifacts is not None:
            try:
                encoded = json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n"
                descriptor = os.open(artifacts / "smoke-report.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(descriptor, "w", encoding="utf-8") as output:
                    output.write(encoded)
            except Exception as error:
                report["report_error"] = _error("report", error)
                if report["error"] is None:
                    report["error"] = report["report_error"]
                    report.update(status="failed", exit_code=1)
        print(json.dumps(report, sort_keys=True, allow_nan=False))
    return report["exit_code"]


def main(argv: Sequence[str] | None = None) -> int:
    return run(parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())
