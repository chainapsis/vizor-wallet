#!/usr/bin/env python3
"""Export actual Ironwood nullifiers from a regtest lightwalletd snapshot."""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
from pathlib import Path


def decode_stream(raw: str) -> list[dict[str, object]]:
    decoder = json.JSONDecoder()
    values: list[dict[str, object]] = []
    offset = 0
    while offset < len(raw):
        while offset < len(raw) and raw[offset].isspace():
            offset += 1
        if offset == len(raw):
            break
        value, offset = decoder.raw_decode(raw, offset)
        if not isinstance(value, dict):
            raise ValueError("grpcurl stream contained a non-object value")
        values.append(value)
    return values


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--grpcurl", default="grpcurl")
    parser.add_argument("--proto-dir", type=Path, required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--activation-height", type=int, required=True)
    parser.add_argument("--snapshot-height", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if args.activation_height < 2 or args.snapshot_height < args.activation_height:
        raise SystemExit("snapshot must be at or after activation height")

    request = json.dumps(
        {
            "start": {"height": str(args.activation_height)},
            "end": {"height": str(args.snapshot_height)},
        }
    )
    command = [
        args.grpcurl,
        "-plaintext",
        "-import-path",
        str(args.proto_dir),
        "-proto",
        "service.proto",
        "-d",
        request,
        args.endpoint,
        "cash.z.wallet.sdk.rpc.CompactTxStreamer/GetBlockRange",
    ]
    completed = subprocess.run(command, capture_output=True, text=True)
    if completed.returncode != 0:
        raise SystemExit(f"grpcurl failed: {completed.stderr.strip()}")

    nullifiers: list[bytes] = []
    seen: set[bytes] = set()
    for block in decode_stream(completed.stdout):
        for transaction in block.get("vtx", []):
            if not isinstance(transaction, dict):
                raise ValueError("compact transaction is not an object")
            for action in transaction.get("ironwoodActions", []):
                if not isinstance(action, dict):
                    raise ValueError("Ironwood action is not an object")
                encoded = action.get("nullifier")
                if not isinstance(encoded, str):
                    raise ValueError("Ironwood action omitted its nullifier")
                nullifier = base64.b64decode(encoded, validate=True)
                if len(nullifier) != 32:
                    raise ValueError(f"Ironwood nullifier has {len(nullifier)} bytes")
                if nullifier in seen:
                    raise ValueError("duplicate Ironwood nullifier in snapshot")
                seen.add(nullifier)
                nullifiers.append(nullifier)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(b"".join(nullifiers))
    print(
        json.dumps(
            {
                "activation_height": args.activation_height,
                "snapshot_height": args.snapshot_height,
                "nullifier_count": len(nullifiers),
                "output": str(args.output),
            },
            separators=(",", ":"),
        )
    )


if __name__ == "__main__":
    main()
