"""Private-mode expectation profile for the transparent history suite.

Private mode is `PrivateRequired`: transparent recovery through the
transparent PIR service, and no public transparent lookup at all. Regtest has
no Enhance PIR or status service, so the private payload, status and history
lanes stay unavailable (`EnhancementPolicy.private` is mainnet-only) and the
lookup gate withholds the public ones: no `GetTransaction`, no address method.
What a wallet knows of a transaction it did not build is therefore what the
shards carry (owned receives and spends, each with the v11 metadata: exact
whole fee, complete transparent input count, shielded-components bit) plus
what scanning finds of its own shielded notes.

The harness publishes the shards itself, from zcashd, so this qualifies
Vizor's private mode against a correct publisher, not the production one.

This module post-processes the public profile's expectations; it adds no
chain facts. Per (tx, account, variant), for variants with complete evidence:

* the reference wallet's own transactions (R and O, built by R) keep the
  public expectation: R stored them when it built them;
* exact: transparent receives (TPIR has every owned output) keep the public
  rows;
* exact amount and fee, details incomplete: the account spent, the
  transaction has no shielded components, and the account owns every input,
  so the metadata gives the aggregate payment and the whole fee; the public
  row with `details_complete` false (recipient outputs are not recovered);
* honestly incomplete (only payload or txid PIR could fill): everything else
  the account took part in. A row is present unless the public profile allows
  folding it (TEX leg 1); its movement is exact; any final row is a true one;
  a known fee is the whole fee and never zero; the amount is a real owned
  amount, the sole funder's real payment, or at most the movement; the fee is
  known when the account owns a transparent script in it, unknown when its
  part is shielded only and no other Alice account owns a script in it.

Incomplete-evidence variants (N_pre, and the faults N_lag and N_pir_fail)
keep the public honesty constraints. Fault variants assert no spendable claim
from incomplete evidence; private sync reports success by design and states
transparent authority separately, so there is no synchronized-claim check.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import transparent_history_profile_public as public  # noqa: E402

RETAINED = public.RETAINED

# Block and tree data for scanning, and broadcasts of the wallet's own
# transactions. No GetTransaction and no address method: under
# PrivateRequired nothing reveals an address, txid or outpoint.
ALLOWED_METHODS = [
    "GetLatestBlock",
    "GetBlock",
    "GetBlockRange",
    "GetTreeState",
    "GetLatestTreeState",
    "GetSubtreeRoots",
    "GetLightdInfo",
    "SendTransaction",
]

# Intents whose rows TPIR recovers exactly: receives of owned outputs.
EXACT_RECEIVES = (
    "t_receive",
    "coinbase_receive",
    "funding_t",
    "tex_return",
    "pending_receive",
    "reorged_receive",
)

# Public constraints that still hold for an honestly incomplete row; the rest
# (amount and fee-state rules) are replaced.
KEPT_CONSTRAINTS = (
    "no_zero_known_fee",
    "owned_input_count",
    "kinds_at_most_once",
    "row_count_le",
    "amount_not_in",
    "detail_outputs_real",
    "delta_is",
)

variant_kind = public.variant_kind


def built_by_reference(record):
    """Whether the reference wallet R built this transaction. The gift-card
    claim is V-built by the card's own claim wallet, not by R."""
    return record["builder"] == "V" and record["intent"] != "gift_card_claim"


def owns_script(effect):
    return bool(effect["owned_inputs"] or effect["owned_outputs"])


def category(record, facts, effect):
    """`exact`, `aggregate` or `incomplete` for a mined transaction the
    account took part in and the variant did not build."""
    intent = record["intent"]
    if intent in EXACT_RECEIVES or (
        intent in ("cross_account_t", "cross_account_from_shielded") and not effect["spent"]
    ):
        return "exact"
    if (
        effect["spent"]
        and intent != "self_transfer"
        and not facts["has_shielded"]
        and effect["owned_input_count"]
        and effect["owned_input_count"] == len(facts["inputs"])
    ):
        return "aggregate"
    return "incomplete"


def honest_amounts(facts, effect, account, attribution):
    """Amounts a row may show without inventing one: owned outputs, singly
    and summed, the owned shielded movement, and, when the account funded
    every input, its real external payment."""
    owned = effect["owned_outputs"]
    values = {o["value"] for o in owned}
    if owned:
        values.add(sum(o["value"] for o in owned))
    external = [o["value"] for o in owned if o["owner_scope"] == "external"]
    if external:
        values.add(sum(external))
    if effect["shielded_net"]:
        values.add(abs(effect["shielded_net"]))
    if effect["owned_input_count"] and effect["owned_input_count"] == len(facts["inputs"]):
        values.add(public.external_payment(facts, account, attribution))
    return sorted(v for v in values if v > 0)


def other_account_owns_script(context, txid, account):
    return any(
        owns_script(context["effects"][f"{txid}:{other}"])
        for other in context["alice_accounts"]
        if other != account
    )


def incomplete(item, record, facts, effect, context):
    """Constraints for an honestly incomplete row (see the module docs)."""
    account = item["account"]
    attribution = record.get("attribution", {})
    finals = [row for rows in (item["row_sets"] or []) for row in rows]
    folds = any(rows == [] for rows in (item["row_sets"] or []))
    fees = [facts["fee"]] if facts.get("fee") is not None else []
    other = (record.get("links") or {}).get("other_leg")
    if fees and other and context["facts"].get(other, {}).get("fee") is not None:
        fees.append(facts["fee"] + context["facts"][other]["fee"])
    delta = effect["delta"]
    constraints = [c for c in item["constraints"] if c["name"] in KEPT_CONSTRAINTS]
    if not any(c["name"] == "delta_is" for c in constraints):
        constraints.append({"name": "delta_is", "values": [delta]})
    if not any(c["name"] == "no_zero_known_fee" for c in constraints):
        constraints.append({"name": "no_zero_known_fee"})
    if not folds:
        constraints.append({"name": "row_present"})
    constraints += [
        {"name": "honest_if_final", "final_rows": finals},
        {"name": "known_fee_is_whole", "values": fees},
        {
            "name": "amount_in_or_le",
            "values": honest_amounts(facts, effect, account, attribution),
            "value": abs(delta),
        },
    ]
    if effect["spent"]:
        if owns_script(effect):
            states = ["known"]
        elif other_account_owns_script(context, record["txid"], account):
            # Another Alice account's recovered event carries the whole fee.
            states = ["known", "unknown"]
        else:
            states = ["unknown"]
        constraints.append({"name": "fee_state_in", "values": states})
    return dict(item, row_sets=None, constraints=constraints)


def aggregate(item):
    """The public rows, with recipient details incomplete and provisional
    left to the wallet: amount, movement and fee stay exact."""
    row_sets = []
    for rows in item["row_sets"] or []:
        changed = []
        for row in rows:
            row = dict(row, details_complete=False)
            row.pop("provisional", None)
            changed.append(row)
        row_sets.append(changed)
    return dict(item, row_sets=row_sets)


def activity(context):
    cases = context["cases"]
    records = {r["txid"]: r for r in cases["txs"]}
    items = []
    for item in public.activity(context):
        if item["case"] == "H04":
            # Retained versus restored: creation facts and whole fees only,
            # which hold in either mode.
            items.append(item)
            continue
        record = records[item["txid"]]
        facts = context["facts"][item["txid"]]
        effect = context["effects"][f"{item['txid']}:{item['account']}"]
        kind = variant_kind(cases, item["variant"])
        retained = item["variant"] in RETAINED and built_by_reference(record)
        unknown = item["row_sets"] is None and any(
            c["name"] == "absent_or_unconfirmed" for c in item["constraints"]
        )
        if kind != "complete" or retained or unknown or not effect["involved"]:
            # Public honesty constraints, the reference wallet's own
            # transactions, unknown unmined ones, and uninvolved accounts.
            items.append(item)
            continue
        if item["row_sets"] is None and record["intent"] != "shared_funding":
            raise SystemExit(
                f"private profile: no rows for {record['intent']} {item['txid'][:12]}"
            )
        which = category(record, facts, effect)
        if which == "exact":
            items.append(item)
        elif which == "aggregate":
            items.append(aggregate(item))
        else:
            items.append(incomplete(item, record, facts, effect, context))
    return items


def account_checks(context):
    checks = []
    for check in public.account_checks(context):
        if "no_synchronized_claim" in check["assert"]:
            check = dict(check)
            check["assert"] = ["no_spendable_claim"]
        if "balance" in check["assert"]:
            # The transparent balance is the recovered, confirmed ledger. A
            # receive the wallet holds only as unmined (H12 R's reorged-away
            # receive, back in the mempool) needs a status lane to count as
            # pending, and regtest has none: it does not count.
            check = dict(check, pending_receives=False)
        checks.append(check)
    return checks


def request_policy(context, alice_addresses, related_txids):
    policy = public.request_policy(context, alice_addresses, related_txids)
    policy.update(allowed_methods=ALLOWED_METHODS, allowed_addresses=[], allowed_txids=[])
    return policy


def ui_rows(context):
    raise SystemExit(
        "private profile: no app-layer expectations; run the Rust layer only "
        "(the runner refuses --flutter with --profile private)"
    )
