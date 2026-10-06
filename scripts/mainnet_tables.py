"""Shared helpers for the compiled-in mainnet table generators.

The wallet ships tables of mainnet chain data so it can answer questions about
wallet-derived heights without asking lightwalletd. Each generator appends
entries fetched from two independent endpoints and requires them to agree.
"""

from __future__ import annotations

import concurrent.futures
import json
import subprocess
import time
from pathlib import Path
from typing import Callable, TypeVar

REPO_ROOT = Path(__file__).resolve().parent.parent
PROTO_DIR = REPO_ROOT / "protos"

DEFAULT_ENDPOINTS = ("zec.rocks:443", "eu.zec.stardust.rest:443")
# Entries stay this many blocks below the lower endpoint tip.
REORG_MARGIN = 1_000
# Existing entries re-read from both endpoints on every update.
RECHECK_EXISTING = 3
RPC_TIMEOUT_SECONDS = 30
RPC_ATTEMPTS = 3
WORKERS = 8

T = TypeVar("T")


class UpdateError(Exception):
    pass


def grpc(endpoint: str, method: str, payload: dict) -> dict:
    command = [
        "grpcurl",
        "-max-time",
        str(RPC_TIMEOUT_SECONDS),
        "-import-path",
        str(PROTO_DIR),
        "-proto",
        "service.proto",
        "-d",
        json.dumps(payload),
        endpoint,
        f"cash.z.wallet.sdk.rpc.CompactTxStreamer/{method}",
    ]
    last_error = ""
    for attempt in range(RPC_ATTEMPTS):
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode == 0:
            return json.loads(result.stdout)
        last_error = result.stderr.strip()
        time.sleep(2**attempt)
    raise UpdateError(f"{endpoint} {method} {payload}: {last_error}")


def tip_height(endpoint: str) -> int:
    return int(grpc(endpoint, "GetLatestBlock", {})["height"])


def safe_tip(endpoints: tuple[str, str]) -> tuple[int, list[int]]:
    """The highest height both endpoints are at least `REORG_MARGIN` past."""
    tips = [tip_height(endpoint) for endpoint in endpoints]
    return min(tips) - REORG_MARGIN, tips


def agreed(
    endpoints: tuple[str, str],
    heights: list[int],
    fetch: Callable[[str, int], T],
) -> dict[int, T]:
    """Fetch each height from both endpoints and require identical values."""
    jobs = [(endpoint, height) for height in heights for endpoint in endpoints]
    results: dict[tuple[str, int], T] = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futures = {
            pool.submit(fetch, endpoint, height): (endpoint, height)
            for endpoint, height in jobs
        }
        for future in concurrent.futures.as_completed(futures):
            results[futures[future]] = future.result()
    values = {}
    for height in heights:
        first, second = (results[(endpoint, height)] for endpoint in endpoints)
        if first != second:
            raise UpdateError(
                f"endpoints disagree at height {height}: "
                f"{endpoints[0]}={first} {endpoints[1]}={second}"
            )
        values[height] = first
    return values


def endpoints_from_args(values: list[str] | None) -> tuple[str, str]:
    endpoints = tuple(values or DEFAULT_ENDPOINTS)
    if len(endpoints) != 2 or endpoints[0] == endpoints[1]:
        raise UpdateError("exactly two distinct endpoints are required")
    return endpoints  # type: ignore[return-value]
