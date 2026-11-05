#!/usr/bin/env python3
"""Authenticate voting validator changes and prepare reviewed trust-anchor updates.

Build tools/voting-validators first. --check validates checked-in data offline.
Online mode only writes after every selected network and proof has verified.
"""
from __future__ import annotations

import argparse
from datetime import date, datetime, timezone
import json
import os
import re
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
TRUST = Path("rust/src/wallet/voting/trust")
FIXTURES = Path("rust/tests/fixtures/voting-participation")
NETWORKS = {
    "main": ("zvote-1", "https://vote-rpc-primary.valargroup.org"),
    "test": ("svote-1", "https://stage.vote-rpc-primary.valargroup.org"),
}
START_MARKER = "<!-- voting-validator-anchors:start -->"
END_MARKER = "<!-- voting-validator-anchors:end -->"
EPOCH = date(2026, 11, 2)  # A Monday; do not use ISO-week parity across year 53.


class UpdateError(Exception):
    pass


def scheduled_week(today: date) -> bool:
    return (today - EPOCH).days // 7 % 2 == 0


def read(root: Path, path: Path):
    return json.loads((root / path).read_text())


def encode(value) -> str:
    return json.dumps(value, indent=2) + "\n"


def timestamp(commit) -> int:
    value = commit["result"]["signed_header"]["header"]["time"]
    return int(datetime.fromisoformat(re.sub(r"(\.\d{6})\d+", r"\1", value.replace("Z", "+00:00"))).timestamp())


def rpc(base: str, path: str, params: dict | None = None):
    url = base + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    last_error = None
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=15) as response:
                data = response.read(128 * 1024 + 1)
            if len(data) > 128 * 1024:
                raise UpdateError("RPC response exceeds size limit")
            value = json.loads(data)
            if not isinstance(value, dict) or "result" not in value or "error" in value:
                raise UpdateError("RPC returned no result")
            return value
        except (OSError, ValueError, UpdateError) as error:
            last_error = type(error).__name__
            if attempt < 2:
                time.sleep(2 ** attempt)
    # Never print the URL or governance identifiers in errors.
    raise UpdateError(f"RPC {path} failed ({last_error})")


def verifier(request):
    binary = Path(os.environ.get(
        "VOTING_VALIDATOR_VERIFIER", str(ROOT / "tools/voting-validators/target/debug/voting-validator-verifier")
    ))
    result = subprocess.run([str(binary)], input=json.dumps(request), text=True, capture_output=True, timeout=60)
    if result.returncode:
        raise UpdateError(result.stderr.strip() or "Evidence verifier failed")
    return json.loads(result.stdout)


def request(anchor, validators, fixture, now: int, with_proofs: bool = True):
    result = {
        "chain_id": anchor["chain_id"], "trusted_hash": anchor["validator_set_hash"],
        "trusted_validators": validators, "commit": fixture["commit"],
        "validators": fixture["validators"], "now": now,
    }
    if with_proofs:
        result.update(keys=fixture["keys"], queries=fixture["queries"])
    return result


def check_local(root: Path, verify=verifier):
    anchors = read(root, TRUST / "anchors.json")
    if set(anchors) != set(NETWORKS):
        raise UpdateError("Unexpected trust networks")
    for network, (chain, _) in NETWORKS.items():
        anchor = anchors[network]
        if anchor["chain_id"] != chain:
            raise UpdateError(f"Wrong chain for {network}")
        date.fromisoformat(anchor["captured_at"])
        validators = read(root, TRUST / f"{network}-validators.json")
        fixture = read(root, FIXTURES / f"{network}.json")
        checked = verify(request(anchor, validators, fixture, timestamp(fixture["commit"])))
        if checked["validator_set_hash"] != anchor["validator_set_hash"] or checked["height"] != anchor["height"]:
            raise UpdateError(f"Active fixture does not match {network} anchor")
        if checked["used"] != [True, False]:
            raise UpdateError(f"Expected membership and absence fixtures for {network}")
        transition_path = TRUST / f"{network}-transition.json"
        if (root / transition_path).exists():
            transition = read(root, transition_path)
            checked = verify(request(transition["previous_anchor"], transition["previous_validators"],
                                     transition, timestamp(transition["commit"]), with_proofs=False))
            if checked["validator_set_hash"] != anchor["validator_set_hash"]:
                raise UpdateError(f"Transition does not authenticate {network} anchor")
    return anchors


def candidate(root: Path, network: str, anchor, get=rpc, verify=verifier, clock=time.time):
    chain, base = NETWORKS[network]
    old = read(root, TRUST / f"{network}-validators.json")
    latest = get(base, "/commit")
    tip = int(latest["result"]["signed_header"]["header"]["height"])
    last_error = None
    for offset in (1, 2, 4, 8):
        height = tip - offset
        if height <= 1:
            raise UpdateError("Voting chain is not ready")
        try:
            commit = get(base, "/commit", {"height": str(height)})
            if commit["result"].get("canonical") is not True:
                raise UpdateError("Expected a canonical commit")
            header = commit["result"]["signed_header"]["header"]
            if int(header["height"]) != height or header["chain_id"] != chain:
                raise UpdateError("RPC returned the wrong height or chain")
            validators = get(base, "/validators", {"height": str(height), "per_page": "100"})
            result = validators["result"]
            count = len(result["validators"])
            if not 1 <= count <= 100 or int(result["total"]) != count or int(result["count"]) != count or int(result["block_height"]) != height:
                raise UpdateError("Incomplete validator set or wrong validator height")
            evidence = {"commit": commit, "validators": validators}
            checked = verify(request(anchor, old, evidence, int(clock()), with_proofs=False))
            break
        except (UpdateError, KeyError, ValueError) as error:
            last_error = str(error)
    else:
        raise UpdateError(f"{network}: no recent commit authenticated by both quorums: {last_error}")
    if checked["validator_set_hash"] == anchor["validator_set_hash"]:
        return None
    fixture = read(root, FIXTURES / f"{network}.json")
    evidence["keys"] = fixture["keys"]  # Public fixture keys, never wallet-derived.
    evidence["queries"] = [get(base, "/abci_query", {
        "path": '"/store/vote/key"', "data": "0x" + key,
        "height": str(height - 1), "prove": "true",
    }) for key in fixture["keys"]]
    checked = verify(request(anchor, old, evidence, int(clock())))
    if checked["used"] != [True, False]:
        raise UpdateError("Membership/absence fixture changed unexpectedly")
    updated = {"chain_id": chain, "validator_set_hash": checked["validator_set_hash"],
               "captured_at": datetime.fromtimestamp(clock(), timezone.utc).date().isoformat(), "height": height}
    transition = {"previous_anchor": anchor, "previous_validators": old,
                  "commit": commit, "validators": validators}
    return updated, checked, evidence, transition


def anchor_table(anchors) -> str:
    lines = [START_MARKER, "| Network | Chain | RPC | Captured | Validator-set hash |",
             "| --- | --- | --- | --- | --- |"]
    for network, (chain, endpoint) in NETWORKS.items():
        a = anchors[network]
        lines.append(f"| {network} | {chain} | {endpoint} | {a['captured_at']} | {a['validator_set_hash']} |")
    return "\n".join(lines + [END_MARKER])


def render_docs(text: str, anchors) -> str:
    if text.count(START_MARKER) != 1 or text.count(END_MARKER) != 1:
        raise UpdateError("Missing or duplicate generated anchor table markers")
    before, rest = text.split(START_MARKER)
    _, after = rest.split(END_MARKER)
    return before + anchor_table(anchors) + after


def update(root: Path, networks, get=rpc, verify=verifier, clock=time.time):
    anchors = check_local(root, verify)
    changes, details = {}, []
    for network in networks:
        result = candidate(root, network, anchors[network], get, verify, clock)
        if result is None:
            continue
        anchor, checked, evidence, transition = result
        old = {v["address"]: v for v in transition["previous_validators"]}
        new = {v["address"]: v for v in checked["validators"]}
        details += [f"### {network} ({anchor['chain_id']})", "",
                    f"- Hash: `{anchors[network]['validator_set_hash']}` → `{anchor['validator_set_hash']}`",
                    f"- Canonical height: {anchor['height']}; header time: {checked['header_time']}",
                    f"- Validators: {len(old)} → {len(new)}",
                    f"- Verified previous power: {checked['previous_power']['tallied']}/{checked['previous_power']['total']}",
                    f"- Verified current power: {checked['current_power']['tallied']}/{checked['current_power']['total']}"]
        for address in sorted(set(old) | set(new)):
            if address not in old:
                details.append(f"- Added `{address}` (power {new[address]['voting_power']}, key `{new[address]['pub_key']['value']}`)")
            elif address not in new:
                details.append(f"- Removed `{address}` (power {old[address]['voting_power']})")
            elif old[address]["voting_power"] != new[address]["voting_power"] or old[address]["pub_key"] != new[address]["pub_key"]:
                details.append(f"- Changed `{address}`: power {old[address]['voting_power']} → {new[address]['voting_power']}")
        details.append("")
        anchors[network] = anchor
        changes[TRUST / f"{network}-validators.json"] = encode(checked["validators"])
        changes[TRUST / f"{network}-transition.json"] = encode(transition)
        changes[FIXTURES / f"{network}.json"] = encode(evidence)
    if changes:
        changes[TRUST / "anchors.json"] = encode(anchors)
        doc_path = Path("docs/voting-participation.md")
        changes[doc_path] = render_docs((root / doc_path).read_text(), anchors)
        # Validate the complete candidate tree before publishing any file.
        with tempfile.TemporaryDirectory() as directory:
            staged = Path(directory)
            for path in [TRUST, FIXTURES]:
                shutil.copytree(root / path, staged / path)
            for path, text in changes.items():
                (staged / path).parent.mkdir(parents=True, exist_ok=True)
                (staged / path).write_text(text)
            check_local(staged, verify)
        for path, text in changes.items():
            target = root / path
            with tempfile.NamedTemporaryFile(mode="w", dir=target.parent, delete=False) as output:
                output.write(text)
                pending = output.name
            os.replace(pending, target)
    summary = "Authenticated validator trust-anchor update. Review and merge to include it in a release.\n\n"
    summary += "\n".join(details) if details else "No validator key or power changes.\n"
    return bool(changes), summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--network", choices=NETWORKS, action="append")
    parser.add_argument("--summary-file", type=Path)
    parser.add_argument("--schedule-due", action="store_true")
    args = parser.parse_args()
    try:
        if args.schedule_due:
            print("true" if scheduled_week(datetime.now(timezone.utc).date()) else "false")
            return 0
        if args.check:
            anchors = check_local(ROOT)
            text = (ROOT / "docs/voting-participation.md").read_text()
            if render_docs(text, anchors) != text:
                raise UpdateError("Generated anchor table is stale")
            print("Checked-in anchors and evidence verified offline")
            return 0
        changed, summary = update(ROOT, list(dict.fromkeys(args.network or NETWORKS)))
        if args.summary_file:
            args.summary_file.write_text(summary)
        print(json.dumps({"changed": changed}))
        return 0
    except (UpdateError, OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
