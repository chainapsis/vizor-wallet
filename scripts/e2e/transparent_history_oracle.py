#!/usr/bin/env python3
"""Independent oracle for the transparent history qualification suite (H01-H13).

Expected values come only from zcashd (verbose transactions, prevouts through
txindex, block headers, the insight address index) plus the harness-authored
ownership map and case manifest. Nothing here reads Vizor, the wallet
libraries, or the activity mapper.

Subcommands:
  derive    chain facts + owned ledger + profile expectations for a checkpoint
  compare   observed views vs expected views; nonzero exit on any mismatch
  gate      suite verdict: per-case matrix, negative controls, required cases
  manifest  frozen public fixture data, code pins, and checksums
  reprofile re-apply a changed profile to saved chain facts (development aid)

Mode-specific expectations live in transparent_history_profile_<mode>.py.
"""

import argparse
import base64
import copy
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))


# ----------------------------------------------------------------- RPC ------


class Rpc:
    def __init__(self, url):
        parsed = urllib.parse.urlparse(url)
        self.endpoint = f"http://{parsed.hostname}:{parsed.port}/"
        token = base64.b64encode(
            f"{parsed.username}:{parsed.password}".encode()
        ).decode()
        self.headers = {
            "Authorization": f"Basic {token}",
            "Content-Type": "application/json",
        }

    def __call__(self, method, *params):
        body = json.dumps(
            {"jsonrpc": "1.0", "id": "oracle", "method": method, "params": list(params)}
        ).encode()
        request = urllib.request.Request(self.endpoint, body, self.headers)
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as error:
            payload = json.load(error)
        if payload.get("error"):
            raise RpcError(method, payload["error"])
        return payload["result"]


class RpcError(Exception):
    def __init__(self, method, error):
        super().__init__(f"{method}: {error}")
        self.error = error


def load(path):
    with open(path) as handle:
        return json.load(handle)


def dump(path, value):
    with open(path, "w") as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write("\n")


def load_profile(name):
    path = os.path.join(HERE, f"transparent_history_profile_{name}.py")
    spec = importlib.util.spec_from_file_location(f"profile_{name}", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


# ---------------------------------------------------------- chain facts -----


class Chain:
    """Read-only view of zcashd at one moment."""

    def __init__(self, rpc):
        self.rpc = rpc
        self.tip = rpc("getblockcount")
        self.tip_hash = rpc("getbestblockhash")
        self.mempool = set(rpc("getrawmempool"))
        self._tx = {}
        self._headers = {}

    def header(self, block_hash):
        if block_hash not in self._headers:
            self._headers[block_hash] = self.rpc("getblockheader", block_hash)
        return self._headers[block_hash]

    def raw(self, txid, raw_hex=None):
        if txid in self._tx:
            return self._tx[txid]
        try:
            tx = self.rpc("getrawtransaction", txid, 1)
        except RpcError:
            if raw_hex is None:
                tx = None
            else:
                # Never reached the chain (e.g. withheld by the proxy): decode
                # the authored public bytes instead.
                tx = self.rpc("decoderawtransaction", raw_hex)
        self._tx[txid] = tx
        return tx

    def facts(self, txid, owner_of, raw_hex=None):
        tx = self.raw(txid, raw_hex)
        if tx is None:
            return {"txid": txid, "known_to_chain": False, "status": "absent"}
        inputs = []
        coinbase = False
        for vin in tx["vin"]:
            if "coinbase" in vin:
                coinbase = True
                continue
            parent = self.raw(vin["txid"])
            out = parent["vout"][vin["vout"]]
            script = out["scriptPubKey"]["hex"]
            owner, scope = owner_of(script)
            inputs.append(
                {
                    "txid": vin["txid"],
                    "index": vin["vout"],
                    "value": out["valueZat"],
                    "script": script,
                    "owner": owner,
                    "owner_scope": scope,
                }
            )
        outputs = []
        for vout in tx["vout"]:
            script = vout["scriptPubKey"]["hex"]
            owner, scope = owner_of(script)
            outputs.append(
                {
                    "index": vout["n"],
                    "value": vout["valueZat"],
                    "script": script,
                    "address": (vout["scriptPubKey"].get("addresses") or [None])[0],
                    "owner": owner,
                    "owner_scope": scope,
                }
            )
        sapling_balance = tx.get("valueBalanceZat", 0)
        orchard = tx.get("orchard") or {}
        orchard_balance = orchard.get("valueBalanceZat", 0)
        fee = None
        if not coinbase:
            fee = (
                sum(i["value"] for i in inputs)
                - sum(o["value"] for o in outputs)
                + sapling_balance
                + orchard_balance
            )
        status, height, block_hash, block_time = "absent", 0, None, 0
        if tx.get("blockhash"):
            header = self.header(tx["blockhash"])
            if header.get("confirmations", -1) >= 0:
                status, height = "mined", header["height"]
                block_hash, block_time = tx["blockhash"], header["time"]
        if status != "mined" and txid in self.mempool:
            status = "mempool"
        expiry = tx.get("expiryheight", 0) or 0
        return {
            "txid": txid,
            "known_to_chain": status != "absent" or raw_hex is None,
            "coinbase": coinbase,
            "inputs": inputs,
            "outputs": outputs,
            "input_count": len(tx["vin"]),
            "sapling_value_balance": sapling_balance,
            "orchard_value_balance": orchard_balance,
            "sapling_spends": len(tx.get("vShieldedSpend", [])),
            "sapling_outputs": len(tx.get("vShieldedOutput", [])),
            "orchard_actions": len(orchard.get("actions", [])),
            "has_shielded": bool(
                tx.get("vShieldedSpend")
                or tx.get("vShieldedOutput")
                or orchard.get("actions")
            ),
            "fee": fee,
            "status": status,
            "mined_height": height,
            "block_hash": block_hash,
            "block_time": block_time,
            "expiry_height": expiry,
            "expired": status != "mined" and 0 < expiry <= self.tip,
        }


def owner_index(ownership):
    scripts = ownership["scripts"]

    def owner_of(script):
        entry = scripts.get(script)
        return (entry["account"], entry["scope"]) if entry else (None, None)

    return owner_of


def mutate_ownership(ownership):
    """Negative control: reassign one active Alice A0 script to A1."""
    mutated = copy.deepcopy(ownership)
    for script, entry in sorted(mutated["scripts"].items()):
        if entry["account"] == "A0" and entry["scope"] == "external" and entry["index"] == 0:
            entry["account"] = "A1"
            return mutated
    raise SystemExit("mutate-ownership: no A0 external index 0 script")


def account_effect(facts, account, attribution):
    owned_in = [i for i in facts.get("inputs", []) if i["owner"] == account]
    owned_out = [o for o in facts.get("outputs", []) if o["owner"] == account]
    shielded = 0
    if account in attribution.get("shielded_net", {}):
        shielded = attribution["shielded_net"][account]
    elif attribution.get("shielded_owner") == account:
        shielded = (
            -(facts["sapling_value_balance"] + facts["orchard_value_balance"])
            - attribution.get("external_shielded_out", 0)
            + attribution.get("external_shielded_in", 0)
        )
    involved = bool(owned_in or owned_out or shielded) or (
        attribution.get("shielded_owner") == account
    )
    return {
        "involved": involved,
        "owned_inputs": owned_in,
        "owned_outputs": owned_out,
        "owned_input_count": len(owned_in),
        "shielded_net": shielded,
        "delta": sum(o["value"] for o in owned_out)
        - sum(i["value"] for i in owned_in)
        + shielded,
        "spent": bool(owned_in) or shielded < 0 or (
            attribution.get("shielded_owner") == account
            and (facts.get("sapling_spends", 0) > 0 or facts.get("orchard_value_balance", 0) > 0)
        ),
    }


def owned_ledger(chain, ownership, account):
    """Every transparent output the account received in the best chain, with
    the mined spend of each, from the insight address index."""
    scripts = {
        s: e for s, e in ownership["scripts"].items() if e["account"] == account
    }
    by_address = {e["address"]: (s, e) for s, e in scripts.items()}
    if not by_address:
        return [], []
    txids = chain.rpc("getaddresstxids", {"addresses": sorted(by_address)})
    received = {}
    spends = {}
    for txid in txids:
        tx = chain.raw(txid)
        for vout in tx["vout"]:
            script = vout["scriptPubKey"]["hex"]
            if script in scripts:
                entry = scripts[script]
                received[(txid, vout["n"])] = {
                    "txid": txid,
                    "index": vout["n"],
                    "value": vout["valueZat"],
                    "address": entry["address"],
                    "scope": entry["scope"],
                    "child_index": entry["index"],
                    "height": chain.header(tx["blockhash"])["height"],
                }
        for vin in tx["vin"]:
            if "coinbase" not in vin:
                spends[(vin["txid"], vin["vout"])] = txid
    ledger = []
    for key, entry in sorted(received.items()):
        entry["spent_by"] = spends.get(key)
        ledger.append(entry)
    active = sorted(
        {(e["scope"], e["child_index"], e["address"]) for e in ledger}
    )
    return ledger, [
        {"scope": s, "index": i, "address": a} for s, i, a in active
    ]


def derive(args):
    rpc = Rpc(args.rpc)
    ownership = load(args.ownership)
    if args.mutate_ownership:
        ownership = mutate_ownership(ownership)
    cases = load(args.cases)
    profile = load_profile(args.profile)
    chain = Chain(rpc)
    owner_of = owner_index(ownership)
    alice_accounts = sorted(
        {e["account"] for e in ownership["scripts"].values() if e["wallet"] == "alice"}
    )
    facts = {}
    for record in cases["txs"]:
        raw_hex = (record.get("links") or {}).get("raw_hex")
        facts[record["txid"]] = chain.facts(record["txid"], owner_of, raw_hex)
    accounts = {}
    for account in alice_accounts:
        ledger, active = owned_ledger(chain, ownership, account)
        utxos = [e for e in ledger if e["spent_by"] is None]
        accounts[account] = {
            "ledger": ledger,
            "utxos": utxos,
            "transparent_balance": sum(e["value"] for e in utxos),
            "active_scripts": active,
        }
    # Every chain tx touching Alice's scripts, and its direct parents: the
    # only txids a public-mode client has a reason to request.
    related = set(facts)
    parents = set()
    for account in accounts.values():
        for entry in account["ledger"]:
            related.add(entry["txid"])
            if entry["spent_by"]:
                related.add(entry["spent_by"])
    for txid in list(related):
        tx = chain.raw(txid)
        if tx:
            parents.update(v["txid"] for v in tx["vin"] if "txid" in v)
    effects = {}
    for record in cases["txs"]:
        for account in alice_accounts:
            effects[f"{record['txid']}:{account}"] = account_effect(
                facts[record["txid"]], account, record.get("attribution", {})
            )
    context = {
        "checkpoint": args.checkpoint,
        "tip": chain.tip,
        "tip_hash": chain.tip_hash,
        "cases": cases,
        "facts": facts,
        "effects": effects,
        "accounts": accounts,
        "alice_accounts": alice_accounts,
        "ownership": ownership,
    }
    expected = {
        "checkpoint": args.checkpoint,
        "profile": args.profile,
        "tip": chain.tip,
        "tip_hash": chain.tip_hash,
        "required_cases": cases["required_cases"],
        "cases": cases["cases"],
        "tx_case": {r["txid"]: r["case"] for r in cases["txs"]},
        "facts": facts,
        "effects": effects,
        "accounts": accounts,
        "activity": profile.activity(context),
        "account_checks": profile.account_checks(context),
        "requests": profile.request_policy(
            context,
            sorted(
                e["address"]
                for e in ownership["scripts"].values()
                if e["wallet"] == "alice"
            ),
            sorted(related | parents),
        ),
    }
    dump(args.out, expected)
    if args.ui_out:
        dump(
            args.ui_out,
            {"profile": args.profile, "tip": chain.tip, "rows": profile.ui_rows(context)},
        )
    print(
        f"derived {args.checkpoint}: tip={chain.tip} txs={len(facts)} "
        f"activity={len(expected['activity'])}"
    )


def reprofile(args):
    """Re-applies the profile to the chain facts saved at derive time.

    Development aid for profile changes. Its inputs are the oracle's own chain
    facts and the authored manifest, never an observation, so it cannot turn
    a candidate's output into an expectation.
    """
    expected = load(args.expected)
    cases = load(args.cases)
    cases["txs"] = [t for t in cases["txs"] if t["txid"] in expected["facts"]]
    profile = load_profile(expected["profile"])
    context = {
        "checkpoint": expected["checkpoint"],
        "tip": expected["tip"],
        "tip_hash": expected["tip_hash"],
        "cases": cases,
        "facts": expected["facts"],
        "effects": expected["effects"],
        "accounts": expected["accounts"],
        "alice_accounts": sorted(expected["accounts"]),
    }
    expected["cases"] = cases["cases"]
    expected["activity"] = profile.activity(context)
    expected["account_checks"] = profile.account_checks(context)
    dump(args.out, expected)
    print(f"reprofiled {expected['checkpoint']}: activity={len(expected['activity'])}")


# -------------------------------------------------------------- compare -----


def field_ok(expected, actual):
    if expected is None:
        return True
    if isinstance(expected, list):
        return actual in expected
    return expected == actual


ROW_FIELDS = [
    "tx_kind",
    "account_balance_delta",
    "display_amount",
    "display_pool",
    "fee_state",
    "fee",
    "details_complete",
    "provisional",
    "mined_height",
    "expired_unmined",
    "timestamp_source",
    "block_time",
]


def row_mismatches(expected_row, row):
    out = []
    for field in ROW_FIELDS:
        if field in expected_row and not field_ok(expected_row[field], row.get(field)):
            out.append(f"{field}: expected {expected_row[field]!r}, got {row.get(field)!r}")
    return out


def match_row_set(expected_rows, rows):
    """Bipartite match by tx_kind first; returns mismatch strings."""
    problems = []
    remaining = list(rows)
    for expected_row in expected_rows:
        best = None
        for candidate in remaining:
            if field_ok(expected_row.get("tx_kind"), candidate["tx_kind"]):
                misses = row_mismatches(expected_row, candidate)
                if best is None or len(misses) < len(best[1]):
                    best = (candidate, misses)
        if best is None:
            problems.append(f"missing row {expected_row}")
            continue
        remaining.remove(best[0])
        problems.extend(f"row {best[0]['tx_kind']}: {m}" for m in best[1])
    for extra in remaining:
        problems.append(
            f"unexpected row {extra['tx_kind']} amount={extra['display_amount']} "
            f"delta={extra['account_balance_delta']}"
        )
    return problems


def check_constraints(item, rows, view, expected):
    problems = []
    fee = item.get("fee")
    for constraint in item.get("constraints", []):
        name = constraint["name"]
        if name == "row_present" and not rows:
            problems.append("no row for a known effect")
        elif name == "absent_or_unconfirmed":
            for row in rows:
                if row["mined_height"] != 0 or row["timestamp_source"] == "block":
                    problems.append(
                        f"row claims confirmation (mined_height={row['mined_height']})"
                    )
        elif name == "absent" and rows:
            problems.append(f"unexpected rows {[r['tx_kind'] for r in rows]}")
        elif name == "known_fee_is_whole":
            for row in rows:
                if row["fee_state"] == "known" and row["fee"] not in constraint["values"]:
                    problems.append(
                        f"known fee {row['fee']} is not the whole fee {constraint['values']}"
                    )
        elif name == "row_present_if_known_spend":
            recorded = any(item["txid"] in e["all_spenders"] for e in view["ledger"])
            if recorded and not rows:
                problems.append("the wallet recorded this debit but shows no row")
        elif name == "created_time":
            for row in rows:
                if (row["created_time"] > 0) != constraint["present"]:
                    problems.append(
                        "retained creation time lost"
                        if constraint["present"]
                        else "restored row invents a local creation time"
                    )
        elif name == "fee_state_in":
            for row in rows:
                if row["fee_state"] not in constraint["values"]:
                    problems.append(f"fee_state {row['fee_state']} not in {constraint['values']}")
        elif name == "delta_is":
            for row in rows:
                if row["account_balance_delta"] not in constraint["values"]:
                    problems.append(
                        f"account_balance_delta {row['account_balance_delta']} "
                        f"not in {constraint['values']}"
                    )
        elif name == "amount_not_in":
            for row in rows:
                if row["display_amount"] in constraint["values"]:
                    problems.append(
                        f"display_amount {row['display_amount']} is a fabricated "
                        f"attribution ({constraint['why']})"
                    )
        elif name == "amount_le":
            for row in rows:
                if row["display_amount"] > constraint["value"]:
                    problems.append(
                        f"display_amount {row['display_amount']} exceeds {constraint['value']}"
                    )
        elif name == "amount_in_or_le":
            # A real amount, or no more than the movement: never an invented one.
            for row in rows:
                amount = row["display_amount"]
                if amount not in constraint["values"] and amount > constraint["value"]:
                    problems.append(
                        f"display_amount {amount} is neither a real amount "
                        f"{constraint['values']} nor at most {constraint['value']}"
                    )
        elif name == "amounts_in":
            for row in rows:
                if row["display_amount"] not in constraint["values"]:
                    problems.append(
                        f"display_amount {row['display_amount']} not a real output "
                        f"{constraint['values']}"
                    )
        elif name == "kinds_at_most_once":
            kinds = [r["tx_kind"] for r in rows]
            for kind in set(kinds):
                if kinds.count(kind) > 1:
                    problems.append(f"{kind} row counted {kinds.count(kind)} times")
        elif name == "row_count_le" and len(rows) > constraint["value"]:
            problems.append(f"{len(rows)} rows, at most {constraint['value']} allowed")
        elif name == "honest_if_final":
            # Anything claimed complete and final must be exactly true.
            for row in rows:
                if row["details_complete"] and not row["provisional"]:
                    misses = []
                    for option in constraint["final_rows"]:
                        if field_ok(option.get("tx_kind"), row["tx_kind"]):
                            misses.append(row_mismatches(option, row))
                    if not misses:
                        problems.append(
                            f"final {row['tx_kind']} row has no valid final form"
                        )
                    elif all(misses):
                        problems.append(
                            f"final {row['tx_kind']} row is false: {min(misses, key=len)}"
                        )
        elif name == "no_zero_known_fee":
            for row in rows:
                if row["fee_state"] == "known" and row["fee"] == 0 and (fee or 0) > 0:
                    problems.append("unknown fee shown as known zero")
        elif name == "owned_input_count":
            spent = [
                e for e in view["ledger"] if item["txid"] in e["all_spenders"]
            ]
            if len(spent) != constraint["value"]:
                problems.append(
                    f"wallet attributes {len(spent)} owned inputs, chain has {constraint['value']}"
                )
        elif name == "detail_outputs_real":
            real = constraint["outputs"]
            for row in rows:
                detail = row.get("detail") or {}
                for address, amount, _pool in detail.get("outputs", []):
                    if [address, amount] not in real and [None, amount] not in real:
                        if not any(amount == r[1] for r in real):
                            problems.append(
                                f"detail output {address} {amount} is not a real output"
                            )
        elif name == "timestamp_block":
            for row in rows:
                if row["block_time"] != constraint["value"]:
                    problems.append(
                        f"block_time {row['block_time']} != block {constraint['value']}"
                    )
    return problems


def compare_views(expected, observed):
    """Returns {case: {variant: [problems]}}, suite-level problems, and
    informational observations for cases asserted at other checkpoints."""
    results = {}
    suite = []
    info = []
    views = {(v["variant"], v["account"]): v for v in observed["views"]}
    tx_case = expected["tx_case"]

    def record(case, variant, problems):
        bucket = results.setdefault(case, {}).setdefault(variant, [])
        bucket.extend(problems)

    # Activity expectations.
    covered = set()
    for item in expected["activity"]:
        key = (item["variant"], item["account"])
        if key not in views:
            record(
                item["case"],
                item["variant"],
                [f"no observation of {item['variant']} {item['account']}"],
            )
            continue
        view = views[key]
        rows = [r for r in view["history"] if r["txid"] == item["txid"]]
        covered.add((item["variant"], item["account"], item["txid"]))
        problems = []
        if item.get("row_sets") is not None:
            options = [match_row_set(s, rows) for s in item["row_sets"]]
            best = min(options, key=len) if options else []
            problems.extend(best)
        problems.extend(check_constraints(item, rows, view, expected))
        record(
            item["case"],
            item["variant"],
            [f"{item['account']} {item['txid'][:12]} ({item['intent']}): {p}" for p in problems],
        )
        # Ensure the case shows as evaluated even when it passes.
        results.setdefault(item["case"], {}).setdefault(item["variant"], [])

    # Rows for txids outside the manifest, or unexpected for asserted txids.
    for (variant, account), view in views.items():
        for row in view["history"]:
            if row["txid"] not in tx_case:
                suite.append(
                    f"{variant} {account}: row for unmanifested tx {row['txid'][:12]} "
                    f"({row['tx_kind']})"
                )

    # Account-level checks (ledger, UTXO set, balance, coverage, sync claims).
    checkpoint = expected["checkpoint"]

    def asserts_variant(case, variant):
        spec = expected["cases"].get(case, {})
        return variant in spec.get("checkpoints", {}).get(checkpoint, [])

    for check in expected["account_checks"]:
        key = (check["variant"], check["account"])
        if key not in views:
            continue
        view = views[key]
        problems = account_problems(check, view, expected, observed, views)
        if check.get("case"):
            record(check["case"], check["variant"], [])
        for problem, txids in problems:
            owners = sorted({tx_case[t] for t in txids if t in tx_case})
            asserted = [c for c in owners if asserts_variant(c, check["variant"])]
            if check.get("case"):
                cases = [check["case"]]
            elif asserted:
                cases = asserted
            elif owners:
                # The owning cases are asserted at another checkpoint; record
                # the observation without failing this one.
                info.append(
                    f"{check['variant']} {check['account']} ({'/'.join(owners)}): {problem}"
                )
                continue
            else:
                cases = ["suite"]
            for case in cases:
                if case == "suite":
                    suite.append(f"{check['variant']} {check['account']}: {problem}")
                else:
                    record(case, check["variant"], [f"{check['account']}: {problem}"])

    # Request policy.
    policy = expected["requests"]
    for variant, requests in observed.get("requests", {}).items():
        allowed_sends = set(policy["send_txids"].get(variant, []))
        for request in requests:
            method = request["method"]
            if method not in policy["allowed_methods"]:
                suite.append(f"requests {variant}: method {method} outside the profile")
                continue
            subjects = request["subjects"]
            if method in policy["address_methods"]:
                foreign = [s for s in subjects if s not in policy["allowed_addresses"]]
                if foreign:
                    suite.append(
                        f"requests {variant}: {method} revealed non-owned addresses {foreign}"
                    )
            if method == "GetTransaction" and subjects:
                if not any(s in policy["allowed_txids"] for s in subjects):
                    suite.append(
                        f"requests {variant}: GetTransaction for unrelated txid {subjects[1][:16]}"
                    )
            if method == "SendTransaction":
                if not subjects or subjects[0] not in allowed_sends:
                    suite.append(
                        f"requests {variant}: SendTransaction of {subjects[:1]} not built by this wallet"
                    )
    return results, suite, info


def account_problems(check, view, expected, observed, views):
    problems = []
    if "variants_equal" in check["assert"]:
        other = views.get((check["other"], check["account"]))
        if other is None:
            problems.append((f"no {check['other']} view to compare", []))
        else:
            mine = {(r["txid"], r["tx_kind"]): r for r in view["history"]}
            theirs = {(r["txid"], r["tx_kind"]): r for r in other["history"]}
            for key in sorted(set(mine) | set(theirs)):
                if mine.get(key) != theirs.get(key):
                    problems.append(
                        (
                            f"{check['variant']} differs from {check['other']} for "
                            f"{key[0][:12]} {key[1]}",
                            [key[0]],
                        )
                    )
        return problems
    account = check["account"]
    exp = expected["accounts"][account]
    ledger = {(e["txid"], e["index"]): e for e in view["ledger"]}
    if "ledger" in check["assert"]:
        want = {(e["txid"], e["index"]): e for e in exp["ledger"]}
        for key, entry in want.items():
            got = ledger.get(key)
            if got is None:
                problems.append(
                    (f"ledger misses receive {key[0][:12]}:{key[1]} ({entry['value']})", [key[0]])
                )
                continue
            if got["value"] != entry["value"]:
                problems.append(
                    (f"ledger value {got['value']} != {entry['value']} for {key[0][:12]}", [key[0]])
                )
            spent_by = entry["spent_by"]
            mined = got["mined_spenders"]
            if spent_by and spent_by not in mined:
                problems.append(
                    (
                        f"ledger misses spend of {key[0][:12]}:{key[1]} by {spent_by[:12]}",
                        [key[0], spent_by],
                    )
                )
            if not spent_by and mined:
                problems.append(
                    (f"ledger records a spend of {key[0][:12]}:{key[1]} the chain lacks", [key[0]] + mined)
                )
        for key, got in ledger.items():
            if key not in want and got.get("receive_mined_height") is not None:
                problems.append(
                    (f"ledger has a mined receive {key[0][:12]}:{key[1]} the chain lacks", [key[0]])
                )
    if "utxos" in check["assert"]:
        want = {(e["txid"], e["index"]) for e in exp["utxos"]}
        got = {
            k
            for k, e in ledger.items()
            if e.get("receive_mined_height") is not None and not e["mined_spenders"]
        }
        for key in sorted(want - got):
            problems.append((f"UTXO set misses {key[0][:12]}:{key[1]}", [key[0]]))
        for key in sorted(got - want):
            problems.append((f"UTXO set has spent/absent {key[0][:12]}:{key[1]}", [key[0]]))
    if "balance" in check["assert"]:
        balance = view.get("balance")
        if balance is None:
            problems.append((f"balance unavailable: {view.get('balance_error')}", []))
        else:
            if balance["transparent"] != exp["transparent_balance"]:
                # Attribute to the outputs the wallet and the chain disagree
                # on: wallet-unspent (mined or not) versus chain UTXOs.
                wallet_unspent = {
                    (e["txid"], e["index"]) for e in view["ledger"] if not e["mined_spenders"]
                }
                chain_unspent = {(e["txid"], e["index"]) for e in exp["utxos"]}
                differing = sorted({t for t, _ in wallet_unspent ^ chain_unspent})
                problems.append(
                    (
                        f"transparent balance {balance['transparent']} != chain "
                        f"{exp['transparent_balance']}",
                        differing or [e["txid"] for e in exp["utxos"]],
                    )
                )
            if balance["transparent_authority"] not in check.get("authority", ["current"]):
                problems.append(
                    (f"transparent_authority {balance['transparent_authority']}", [])
                )
    if "coverage" in check["assert"]:
        known = {a[2] for a in view["addresses"]}
        for script in exp["active_scripts"]:
            if script["address"] not in known:
                problems.append(
                    (
                        f"coverage misses active {script['scope']} index {script['index']}",
                        [],
                    )
                )
    if "no_synchronized_claim" in check["assert"]:
        result = observed.get("sync_results", {}).get(check["variant"])
        if result is None:
            problems.append(
                ("sync reported success from incomplete evidence", check.get("txids", []))
            )
        if view.get("sync_complete"):
            problems.append(("sync status claims complete from incomplete evidence", []))
    if "no_spendable_claim" in check["assert"]:
        balance = view.get("balance") or {}
        authority = balance.get("transparent_authority")
        want = {(e["txid"], e["index"]): e for e in exp["ledger"]}
        stale = [
            k
            for k, e in ledger.items()
            if not e["mined_spenders"] and want.get(k, {}).get("spent_by")
        ]
        missing = [k for k in want if k not in ledger]
        if (stale or missing) and authority == "current":
            problems.append(
                (
                    f"transparent balance claims current authority with {len(stale)} "
                    f"undetected spends and {len(missing)} undiscovered receives",
                    [k[0] for k in stale + missing],
                )
            )
    return problems


def compare(args):
    expected = load(args.expected)
    observed = load(args.observed)
    if args.mutate:
        expected = apply_mutation(expected, args.mutate)
    results, suite, info = compare_views(expected, observed)
    failed = {
        case: {v: p for v, p in variants.items() if p}
        for case, variants in results.items()
    }
    failed = {c: v for c, v in failed.items() if v}
    report = {
        "checkpoint": expected["checkpoint"],
        "mutation": args.mutate,
        "evaluated": {c: sorted(v) for c, v in results.items()},
        "failures": failed,
        "suite_failures": suite,
        "informational": info,
    }
    for line in info[:10]:
        print(f"info: {line}")
    if args.report:
        dump(args.report, report)
    for case in sorted(results):
        for variant in sorted(results[case]):
            problems = results[case][variant]
            print(f"{case} {variant}: {'FAIL' if problems else 'pass'}")
            for problem in problems[:12]:
                print(f"    {problem}")
            if len(problems) > 12:
                print(f"    ... {len(problems) - 12} more")
    for problem in suite[:20]:
        print(f"suite: {problem}")
    if not results:
        print("no case was evaluated")
        sys.exit(3)
    sys.exit(1 if failed or suite else 0)


def apply_mutation(expected, kind):
    """Negative controls: inject one wrong expectation."""
    expected = copy.deepcopy(expected)
    if kind == "wrong-fee":
        for item in expected["activity"]:
            for rows in item.get("row_sets") or []:
                for row in rows:
                    if isinstance(row.get("fee"), int) and row["fee"] > 0:
                        row["fee"] += 1
                        return expected
    elif kind == "wrong-input-count":
        for item in expected["activity"]:
            for constraint in item.get("constraints", []):
                if constraint["name"] == "owned_input_count" and constraint["value"] > 0:
                    constraint["value"] += 1
                    return expected
    elif kind == "omitted-event":
        for account in expected["accounts"].values():
            if account["ledger"]:
                account["ledger"].pop(0)
                return expected
    raise SystemExit(f"mutation {kind}: nothing to mutate")


# ----------------------------------------------------------------- gate -----

NEGATIVE_CONTROLS = ["wrong-fee", "wrong-input-count", "omitted-event"]


def run_compare(expected, observed, mutate=None):
    command = [
        sys.executable,
        os.path.abspath(__file__),
        "compare",
        "--expected",
        expected,
        "--observed",
        observed,
    ]
    if mutate:
        command += ["--mutate", mutate]
    return subprocess.run(command, capture_output=True, text=True).returncode


def gate(args):
    out = args.out_dir
    cases = load(os.path.join(out, "cases.json"))
    required = cases["required_cases"]
    matrix = {}
    suite = {}
    for name in sorted(os.listdir(out)):
        if not (name.startswith("report-") and name.endswith(".json")):
            continue
        report = load(os.path.join(out, name))
        checkpoint = report["checkpoint"]
        for case, variants in report["evaluated"].items():
            for variant in variants:
                failed = bool(report["failures"].get(case, {}).get(variant))
                cell = matrix.setdefault(case, {}).setdefault(variant, [])
                cell.append(f"{checkpoint}:{'fail' if failed else 'pass'}")
        if report["suite_failures"]:
            suite[checkpoint] = report["suite_failures"]
    controls = {}
    expected = os.path.join(out, "expected-final.json")
    observed = os.path.join(out, "observed-final.json")
    if os.path.exists(expected) and os.path.exists(observed):
        for control in NEGATIVE_CONTROLS:
            controls[control] = run_compare(expected, observed, control)
        wrong_owner = os.path.join(out, "expected-final-wrong-ownership.json")
        if os.path.exists(wrong_owner):
            controls["wrong-ownership"] = run_compare(wrong_owner, observed)
    missing = [c for c in required if c not in matrix]
    controls_ok = bool(controls) and all(code != 0 for code in controls.values())
    case_status = {}
    for case in required:
        cells = matrix.get(case, {})
        if not cells:
            case_status[case] = "not run"
        elif any("fail" in c for cell in cells.values() for c in cell):
            case_status[case] = "fail"
        else:
            case_status[case] = "pass"
    summary = {
        "cases": case_status,
        "matrix": matrix,
        "missing_cases": missing,
        "negative_controls": {k: ("fails as required" if v != 0 else "PASSED (bad)") for k, v in controls.items()},
        "suite_failures": suite,
    }
    dump(os.path.join(out, "results.json"), summary)
    for case in required:
        cells = matrix.get(case, {})
        print(
            f"{case}: {case_status[case]:8} "
            + " ".join(f"{v}={'/'.join(c)}" for v, c in sorted(cells.items()))
        )
    for control, code in controls.items():
        print(f"negative control {control}: exit {code}")
    for checkpoint, problems in suite.items():
        print(f"suite failures at {checkpoint}: {len(problems)}")
        for problem in problems[:10]:
            print(f"    {problem}")
    ok = not missing and controls_ok and all(s == "pass" for s in case_status.values()) and not suite
    sys.exit(0 if ok else 1)


# ------------------------------------------------------------- manifest -----


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 16), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git(repo, *args):
    try:
        return subprocess.run(
            ["git", "-C", repo, *args], capture_output=True, text=True, check=True
        ).stdout.strip()
    except subprocess.CalledProcessError:
        return None


def manifest(args):
    rpc = Rpc(args.rpc)
    out = args.out_dir
    cases = load(os.path.join(out, "cases.json"))
    ownership = load(os.path.join(out, "ownership.json"))
    transactions = {}
    for record in cases["txs"]:
        txid = record["txid"]
        try:
            raw = rpc("getrawtransaction", txid, 0)
        except RpcError:
            raw = (record.get("links") or {}).get("raw_hex")
        if raw is None:
            continue
        decoded = rpc("decoderawtransaction", raw)
        prevouts = {}
        for vin in decoded["vin"]:
            if "txid" in vin:
                prevouts[f"{vin['txid']}:{vin['vout']}"] = rpc(
                    "getrawtransaction", vin["txid"], 0
                )
        transactions[txid] = {"raw": raw, "prevout_txs": prevouts}
    lock = os.path.join(args.repo, "rust", "Cargo.toml")
    wallet_libraries = None
    with open(lock) as handle:
        for line in handle:
            if line.startswith("zakura-client-sqlite") and "rev" in line:
                wallet_libraries = line.split('rev = "')[1].split('"')[0]
    chain_text = os.path.join(args.repo, "rust", "tests", "transparent_history_cases", "chain.rs")
    images = [
        line.split('"')[1]
        for line in open(chain_text)
        if "@sha256:" in line and '"' in line
    ]
    files = sorted(
        f
        for f in os.listdir(out)
        if f.endswith(".json") and f not in ("manifest.json",)
    )
    value = {
        "network": "regtest",
        "pool_activation": "Overwinter..NU6.2 at height 1; NU6.3 inactive",
        "checkpoints": cases["checkpoints"],
        "scenarios": sorted(cases["cases"]),
        "ownership": ownership,
        "transactions": transactions,
        "pins": {
            "vizor": git(args.repo, "rev-parse", "HEAD"),
            "vizor_dirty": bool(git(args.repo, "status", "--porcelain", "--untracked-files=no")),
            "wallet_libraries": wallet_libraries,
            "images": images,
            "oracle_sha256": sha256_file(os.path.abspath(__file__)),
        },
        "checksums": {f: sha256_file(os.path.join(out, f)) for f in files},
    }
    dump(os.path.join(out, "manifest.json"), value)
    print(f"manifest: {len(transactions)} transactions, {len(files)} checksummed files")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("derive")
    p.add_argument("--rpc", required=True)
    p.add_argument("--ownership", required=True)
    p.add_argument("--cases", required=True)
    p.add_argument("--checkpoint", required=True)
    p.add_argument("--profile", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--mutate-ownership", action="store_true")
    p.add_argument("--ui-out", help="also write app-layer (fresh restore) expectations")
    p.set_defaults(func=derive)
    p = sub.add_parser("reprofile")
    p.add_argument("--expected", required=True)
    p.add_argument("--cases", required=True)
    p.add_argument("--out", required=True)
    p.set_defaults(func=reprofile)
    p = sub.add_parser("compare")
    p.add_argument("--expected", required=True)
    p.add_argument("--observed", required=True)
    p.add_argument("--report")
    p.add_argument("--mutate", choices=NEGATIVE_CONTROLS)
    p.set_defaults(func=compare)
    p = sub.add_parser("gate")
    p.add_argument("--out-dir", required=True)
    p.set_defaults(func=gate)
    p = sub.add_parser("manifest")
    p.add_argument("--rpc", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--repo", required=True)
    p.set_defaults(func=manifest)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
