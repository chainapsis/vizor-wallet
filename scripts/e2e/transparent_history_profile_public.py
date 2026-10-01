"""Public-mode expectation profile for the transparent history suite.

Public mode is production today: transparent discovery through lightwalletd
(UTXO streams, address txid history, full transactions). This module is the
only mode-specific material: it maps mode-independent chain facts and authored
case intent to

  * the owned-ledger / coverage checks (`account_checks`),
  * the activity expectations per variant (`activity`), split into exact
    post-enrichment rows and honesty constraints for incomplete evidence,
  * the allowed lightwalletd requests (`request_policy`).

A `private` profile is a sibling module with the same three functions.

Expectations encode the qualification spec (wallet-libraries
docs/transparent-pir-history-qualification.md), not current Vizor behaviour.
Field vocabulary (tx_kind, display_pool, fee_state) is Vizor's public history
API; the values are chosen from the spec's required result for each case.
"""

# Variants that hold a retained reference database (built or observed the tx).
RETAINED = ("R", "O")

ALLOWED_METHODS = [
    "GetLatestBlock",
    "GetBlock",
    "GetBlockRange",
    "GetTreeState",
    "GetLatestTreeState",
    "GetSubtreeRoots",
    "GetLightdInfo",
    "GetAddressUtxos",
    "GetAddressUtxosStream",
    "GetTaddressTxids",
    "GetTransaction",
    "SendTransaction",
]

ADDRESS_METHODS = [
    "GetAddressUtxos",
    "GetAddressUtxosStream",
    "GetTaddressTxids",
    "GetTaddressTransactions",
    "GetTaddressBalance",
    "GetTaddressBalanceStream",
]

# Checkpoint -> account-level assertions.
ACCOUNT_ASSERTS = {
    "final": ["ledger", "utxos", "balance", "coverage"],
    "pending": ["ledger", "utxos"],
    "pre_reorg": ["ledger", "utxos"],
}


def variant_kind(cases, variant):
    return cases.get("variant_kinds", {}).get(variant, "complete")


def status_fields(facts):
    if facts["status"] == "mined":
        return {
            "mined_height": facts["mined_height"],
            "expired_unmined": False,
            "timestamp_source": "block",
            "block_time": facts["block_time"],
        }
    return {
        "mined_height": 0,
        "expired_unmined": facts.get("expired", False),
        "block_time": 0,
    }


def common(facts, effect, extra):
    row = {"account_balance_delta": effect["delta"]}
    row.update(status_fields(facts))
    row.update(extra)
    if facts["status"] != "mined" and facts.get("expired"):
        # Never mined and past expiry: no financial effect happened, and the
        # spec leaves the presentation of the movement to the existing
        # local/status paths. Only status, kind, amount and fee are asserted.
        row.pop("account_balance_delta", None)
    return row


def final_flags():
    return {"details_complete": True, "provisional": False}


def receive_rows(facts, effect, pool, amount):
    kind = "received" if facts["status"] == "mined" or facts.get("expired") else "receiving"
    return [
        common(
            facts,
            effect,
            dict(
                tx_kind=kind,
                display_amount=amount,
                display_pool=pool,
                fee_state="not_applicable",
                fee=0,
                **final_flags(),
            ),
        )
    ]


def sent_row(facts, effect, amount, pool, fee=None):
    return common(
        facts,
        effect,
        dict(
            tx_kind="sent",
            display_amount=amount,
            display_pool=pool,
            fee_state="known",
            fee=facts["fee"] if fee is None else fee,
            **final_flags(),
        ),
    )


def external_payment(facts, account, attribution):
    return sum(o["value"] for o in facts["outputs"] if o["owner"] != account) + (
        attribution.get("external_shielded_out", 0)
        if attribution.get("shielded_owner") == account
        else 0
    )


def real_outputs(facts, account, attribution):
    outputs = [[o["address"], o["value"]] for o in facts["outputs"] if o["owner"] != account]
    if attribution.get("external_shielded_out"):
        outputs.append([None, attribution["external_shielded_out"]])
    return outputs


def expectations(intent, facts, effect, record, account, context):
    """Post-enrichment, complete-coverage expectation for one (tx, account).

    Returns (row_sets, constraints). `row_sets` lists acceptable row sets;
    None means only the constraints apply.
    """
    attribution = record.get("attribution", {})
    fee = facts.get("fee")
    delta = effect["delta"]
    owned_ext = [o for o in effect["owned_outputs"] if o["owner_scope"] == "external"]
    constraints = [{"name": "no_zero_known_fee"}]
    if record["builder"] == "S" and effect["owned_input_count"]:
        constraints.append({"name": "owned_input_count", "value": effect["owned_input_count"]})

    if not effect["involved"]:
        return [[]], [{"name": "absent"}]

    if intent in (
        "t_receive",
        "coinbase_receive",
        "funding_t",
        "tex_return",
        "pending_receive",
        "reorged_receive",
    ) or (intent in ("cross_account_t", "cross_account_from_shielded") and not effect["spent"]):
        amount = sum(o["value"] for o in effect["owned_outputs"])
        return [receive_rows(facts, effect, "transparent", amount)], constraints

    if intent in ("funding_shielded", "gift_card_claim"):
        return [receive_rows(facts, effect, "shielded", effect["shielded_net"])], constraints

    if intent in (
        "t_send",
        "t_send_multi",
        "shielded_to_external_t",
        "swap_deposit",
        "expired_send",
        "conflicting_spend",
        "cross_account_t",
        "cross_account_from_shielded",
    ):
        payment = external_payment(facts, account, attribution)
        constraints.append(
            {"name": "detail_outputs_real", "outputs": real_outputs(facts, account, attribution)}
        )
        constraints.append({"name": "kinds_at_most_once"})
        return [[sent_row(facts, effect, payment, "transparent")]], constraints

    if intent == "gift_card_create":
        payment = attribution.get("external_shielded_out", 0)
        constraints.append({"name": "kinds_at_most_once"})
        return [[sent_row(facts, effect, payment, "shielded")]], constraints

    if intent in ("shield", "pending_shield", "conflicted_shield"):
        row = common(
            facts,
            effect,
            dict(
                tx_kind="shielded",
                display_amount=effect["shielded_net"],
                display_pool="shielded",
                fee_state="known",
                fee=fee,
                **final_flags(),
            ),
        )
        if facts["status"] != "mined":
            # A shield the reference wallet built but the chain never mined:
            # existing local/status paths own the state.
            row["timestamp_source"] = "created"
        return [[row]], constraints

    if intent in ("self_transfer", "unshield_self"):
        amount = sum(o["value"] for o in owned_ext)
        sent = sent_row(facts, effect, amount, "transparent")
        received = common(
            facts,
            effect,
            dict(tx_kind="received", display_amount=amount, display_pool="transparent"),
        )
        constraints += [
            {"name": "kinds_at_most_once"},
            {"name": "delta_is", "values": [delta]},
            {"name": "amounts_in", "values": [amount]},
        ]
        return [[sent, received], [sent]], constraints

    if intent == "mixed_pool":
        payment = external_payment(facts, account, attribution)
        sent = sent_row(facts, effect, payment, ["transparent", "mixed"])
        own_shielded = effect["shielded_net"]
        received = common(
            facts,
            effect,
            dict(tx_kind="received", display_amount=own_shielded, display_pool="shielded"),
        )
        constraints += [
            {"name": "kinds_at_most_once"},
            {"name": "delta_is", "values": [delta]},
            {"name": "detail_outputs_real", "outputs": real_outputs(facts, account, attribution)},
        ]
        return [[sent, received], [sent]], constraints

    if intent == "shared_funding":
        payment = external_payment(facts, account, attribution)
        return None, constraints + [
            {"name": "row_present"},
            {"name": "row_count_le", "value": 1},
            {"name": "delta_is", "values": [delta]},
            {"name": "fee_state_in", "values": ["known", "unknown"]},
            {"name": "known_fee_is_whole", "values": [fee]},
            {
                "name": "amount_not_in",
                "values": sorted({payment, abs(delta) - fee} - {abs(delta)}),
                "why": "payment or fee share attributed from a jointly funded transaction",
            },
            {"name": "amount_le", "value": abs(delta)},
        ]

    if intent in ("tex_leg1", "tex_leg2"):
        links = record.get("links") or {}
        other = context["facts"].get(links.get("other_leg"), {})
        other_effect = context["effects"].get(f"{links.get('other_leg')}:{account}", {})
        both_fee = fee + (other.get("fee") or 0)
        both_delta = delta + other_effect.get("delta", 0)
        if intent == "tex_leg1":
            # Visible individually, or folded into leg 2 (supported grouping:
            # the ephemeral output is owned and spent by leg 2).
            return [[], [common(facts, effect, dict(account_balance_delta=delta))]], constraints + [
                {"name": "delta_is", "values": [delta]},
                {"name": "row_count_le", "value": 1},
            ]
        payment = external_payment(facts, account, attribution)
        grouped = sent_row(facts, effect, payment, "transparent", fee=[fee, both_fee])
        grouped["account_balance_delta"] = [delta, both_delta]
        return [[grouped]], constraints + [{"name": "kinds_at_most_once"}]

    raise SystemExit(f"public profile: no expectation for intent {intent}")


def knows(record, facts, variant, kind):
    """Whether a variant can learn this tx through public sync paths."""
    if facts["status"] == "mined":
        return True
    return variant in RETAINED and record["builder"] == "V" and kind == "complete"


def activity(context):
    cases = context["cases"]
    checkpoint = context["checkpoint"]
    items = []
    # A case whose variant has incomplete evidence (H13) asserts honesty over
    # every transaction in the wallet; other cases assert their own txs.
    incomplete = {
        (case_id, variant)
        for case_id, case in cases["cases"].items()
        for variant in case["checkpoints"].get(checkpoint, [])
        if variant_kind(cases, variant) != "complete"
    }
    for record in cases["txs"]:
        case = cases["cases"][record["case"]]
        targets = [
            (record["case"], v)
            for v in case["checkpoints"].get(checkpoint, [])
            if variant_kind(cases, v) == "complete"
        ] + sorted(incomplete)
        facts = context["facts"][record["txid"]]
        for case_id, variant in targets:
            kind = variant_kind(cases, variant)
            for account in context["alice_accounts"]:
                effect = context["effects"][f"{record['txid']}:{account}"]
                item = {
                    "case": case_id,
                    "txid": record["txid"],
                    "intent": record["intent"],
                    "account": account,
                    "variant": variant,
                    "fee": facts.get("fee"),
                }
                if not knows(record, facts, variant, kind):
                    item["row_sets"] = None
                    item["constraints"] = [{"name": "absent_or_unconfirmed"}]
                    items.append(item)
                    continue
                row_sets, constraints = expectations(
                    record["intent"], facts, effect, record, account, context
                )
                if facts["status"] != "mined" and variant in RETAINED:
                    # Unmined rows the reference wallet built date from creation.
                    for rows in row_sets or []:
                        for row in rows:
                            row["timestamp_source"] = "created"
                if kind == "complete":
                    item["row_sets"] = row_sets
                    item["constraints"] = constraints
                else:
                    # Incomplete evidence (held enrichment, faults): visible
                    # partial facts only. Whatever claims to be final must be
                    # true; no known fee may be wrong or zero; a debit the
                    # wallet recorded must keep a row.
                    finals = [row for rows in (row_sets or []) for row in rows]
                    item["row_sets"] = None
                    item["constraints"] = [
                        {"name": "honest_if_final", "final_rows": finals},
                        {"name": "no_zero_known_fee"},
                        {"name": "known_fee_is_whole", "values": sorted(
                            {f for r in finals for f in (r["fee"] if isinstance(r.get("fee"), list) else [r.get("fee")]) if f}
                        ) or [facts.get("fee")]},
                    ]
                    if effect["spent"] and effect["involved"]:
                        item["constraints"].append({"name": "row_present_if_known_spend"})
                items.append(item)
        # H04: retained versus restored over the V-built transactions.
    items.extend(retained_vs_fresh(context))
    return items


def retained_vs_fresh(context):
    cases = context["cases"]
    checkpoint = context["checkpoint"]
    h04 = cases["cases"].get("H04")
    if not h04 or checkpoint not in h04["checkpoints"]:
        return []
    sources = set(h04.get("source_cases", []))
    items = []
    for record in cases["txs"]:
        if record["case"] not in sources or record["builder"] != "V":
            continue
        facts = context["facts"][record["txid"]]
        if facts["status"] != "mined":
            continue
        for variant in h04["checkpoints"][checkpoint]:
            for account in context["alice_accounts"]:
                effect = context["effects"][f"{record['txid']}:{account}"]
                if not effect["involved"] or not effect["spent"]:
                    continue
                retained = variant in RETAINED
                fees = [facts.get("fee")]
                other = (record.get("links") or {}).get("other_leg")
                if other:
                    # H10 permits grouping a TEX operation: leg 1 may fold
                    # into leg 2, whose fee may then be the combined fee.
                    fees.append(facts.get("fee") + context["facts"][other].get("fee", 0))
                constraints = [
                    # Retained: the local creation fact survives.
                    # Restored: nothing local is invented.
                    {"name": "created_time", "present": retained},
                    {"name": "known_fee_is_whole", "values": fees},
                ]
                if record["intent"] != "tex_leg1":
                    constraints.append({"name": "row_present"})
                if retained:
                    constraints.append({"name": "fee_state_in", "values": ["known"]})
                items.append(
                    {
                        "case": "H04",
                        "txid": record["txid"],
                        "intent": record["intent"],
                        "account": account,
                        "variant": variant,
                        "fee": facts.get("fee"),
                        "row_sets": None,
                        "constraints": constraints,
                    }
                )
    return items


def account_checks(context):
    cases = context["cases"]
    checkpoint = context["checkpoint"]
    variants = set()
    for case in cases["cases"].values():
        variants.update(case["checkpoints"].get(checkpoint, []))
    checks = []
    for variant in sorted(variants):
        kind = variant_kind(cases, variant)
        for account in context["alice_accounts"]:
            if kind == "fault":
                checks.append(
                    {
                        "variant": variant,
                        "account": account,
                        "case": "H13",
                        "assert": ["no_synchronized_claim", "no_spendable_claim"],
                    }
                )
            elif kind == "complete" and checkpoint in ACCOUNT_ASSERTS:
                checks.append(
                    {
                        "variant": variant,
                        "account": account,
                        "assert": ACCOUNT_ASSERTS[checkpoint],
                        "authority": ["current"],
                    }
                )
    # H04: the reopened copy must equal the reference database exactly.
    h04 = cases["cases"].get("H04")
    if h04 and checkpoint in h04["checkpoints"] and {"R", "O"} <= set(h04["checkpoints"][checkpoint]):
        for account in context["alice_accounts"]:
            checks.append(
                {
                    "variant": "O",
                    "account": account,
                    "case": "H04",
                    "assert": ["variants_equal"],
                    "other": "R",
                }
            )
    return checks


def request_policy(context, alice_addresses, related_txids):
    v_built = sorted(r["txid"] for r in context["cases"]["txs"] if r["builder"] == "V")
    return {
        "allowed_methods": ALLOWED_METHODS,
        "address_methods": ADDRESS_METHODS,
        "allowed_addresses": alice_addresses,
        "allowed_txids": related_txids,
        # Only the reference wallet (and its reopened copy, which resubmits
        # unmined unexpired transactions it created) may broadcast.
        "send_txids": {"R": v_built, "O": v_built},
    }


# ------------------------------------------------------------------ UI -----
# Presentation the spec requires for a fresh restore in the app (variant N,
# which also runs the mempool observer). Values are oracle facts; the labels
# are Vizor's product copy for each spec state.

TITLES = {
    "sent": "Sent",
    "received": "Received",
    "receiving": "Receiving",
    "shielded": "Shielded",
    "unknown": "Transaction",
}
POOL_LABELS = {"transparent": "Transparent", "shielded": "Shielded", "mixed": "Mixed"}


def _first(value):
    return value[0] if isinstance(value, list) else value


def ui_rows(context):
    rows = []
    for record in context["cases"]["txs"]:
        facts = context["facts"][record["txid"]]
        app_sees_mempool = (
            record["intent"] == "pending_receive" and facts["status"] == "mempool"
        )
        if facts["status"] != "mined" and not app_sees_mempool:
            continue
        for account in context["alice_accounts"]:
            effect = context["effects"][f"{record['txid']}:{account}"]
            if not effect["involved"]:
                continue
            row_sets, _ = expectations(
                record["intent"], facts, effect, record, account, context
            )
            internal = bytes.fromhex(record["txid"])[::-1].hex()
            base = {
                "case": record["case"],
                "intent": record["intent"],
                "account": account,
                "txid": internal,
            }
            if not row_sets or not any(row_sets):
                # Constraint-only expectation (e.g. shared funding): a tappable
                # row must exist; its amount is checked by the Rust layer.
                if effect["spent"] or effect["delta"]:
                    rows.append(dict(base, role=None, optional=False, fee_known=None))
                continue
            preferred = max(row_sets, key=len)
            for row in preferred:
                kind = row.get("tx_kind")
                if not isinstance(kind, str):
                    continue
                pending = facts["status"] != "mined"
                failed = bool(row.get("expired_unmined"))
                pool = _first(row.get("display_pool"))
                fee = _first(row.get("fee"))
                in_every_set = all(
                    any(r.get("tx_kind") == kind for r in rows_) for rows_ in row_sets
                )
                rows.append(
                    dict(
                        base,
                        role="received" if kind == "receiving" else kind,
                        kind=kind,
                        optional=not in_every_set,
                        title=TITLES.get(kind, "Transaction"),
                        pending=pending,
                        failed=failed,
                        amount_zats=row["display_amount"],
                        sign="-"
                        if kind == "sent"
                        else ("+" if kind in ("received", "receiving") else ""),
                        pool_label=POOL_LABELS.get(pool)
                        if kind in ("sent", "received", "receiving")
                        else None,
                        status="Failed"
                        if failed
                        else ("In progress" if pending else "Completed"),
                        block_time=facts["block_time"],
                        fee_known=fee if row.get("fee_state") == "known" else None,
                    )
                )
    return rows
