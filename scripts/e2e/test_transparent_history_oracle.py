#!/usr/bin/env python3
"""Self-tests for the transparent history oracle and its profiles.

Synthetic chain facts only: no zcashd, Docker or Vizor. They pin how the
private profile derives its expectations from the public one, the private
request policy, and the oracle constraint the private profile adds.

    python3 scripts/e2e/test_transparent_history_oracle.py
"""

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import transparent_history_oracle as oracle  # noqa: E402
import transparent_history_profile_private as private  # noqa: E402
import transparent_history_profile_public as public  # noqa: E402

ZEC = 100_000_000
FEE = 10_000
SCRIPT = {"A0": "76a914" + "a0" * 20 + "88ac", "A1": "76a914" + "a1" * 20 + "88ac"}


def io(index, value, owner=None, scope="external"):
    return {
        "index": index,
        "txid": f"{index:064x}",
        "value": value,
        "script": SCRIPT.get(owner, "76a914" + "bb" * 20 + "88ac"),
        "address": f"t-{owner or 'other'}-{index}",
        "owner": owner,
        "owner_scope": scope if owner else None,
    }


def facts(txid, inputs=(), outputs=(), orchard=0, shielded=False, fee=FEE, status="mined"):
    return {
        "txid": txid,
        "known_to_chain": True,
        "inputs": list(inputs),
        "outputs": list(outputs),
        "sapling_value_balance": 0,
        "orchard_value_balance": orchard,
        "sapling_spends": 0,
        "sapling_outputs": 0,
        "orchard_actions": 2 if shielded else 0,
        "has_shielded": shielded,
        "fee": fee,
        "status": status,
        "mined_height": 10 if status == "mined" else 0,
        "block_hash": "00" * 32 if status == "mined" else None,
        "block_time": 1_700_000_000 if status == "mined" else 0,
        "expiry_height": 0,
        "expired": False,
    }


def record(case, txid, builder, intent, attribution=None):
    return {
        "case": case,
        "txid": txid,
        "builder": builder,
        "intent": intent,
        "attribution": attribution or {},
        "links": None,
    }


# (record, facts) per transaction. Values are self-consistent: fee = inputs -
# outputs + orchard value balance.
TXS = [
    (
        record("H03", "aa" * 32, "Z", "t_receive"),
        facts("aa" * 32, outputs=[io(0, ZEC, "A0")], orchard=ZEC + FEE, shielded=True),
    ),
    (
        record("H01", "bb" * 32, "S", "t_send"),
        facts(
            "bb" * 32,
            inputs=[io(0, 3 * ZEC, "A0")],
            outputs=[io(0, ZEC, None), io(1, 2 * ZEC - FEE, "A0", "internal")],
        ),
    ),
    (
        record("H06", "cc" * 32, "S", "self_transfer"),
        facts(
            "cc" * 32,
            inputs=[io(0, 2 * ZEC, "A0")],
            outputs=[io(0, ZEC, "A0"), io(1, ZEC - FEE, "A0", "internal")],
        ),
    ),
    (
        record("H07", "dd" * 32, "V", "shield", {"shielded_owner": "A0"}),
        facts(
            "dd" * 32,
            inputs=[io(0, 2 * ZEC, "A0")],
            orchard=-(2 * ZEC - FEE),
            shielded=True,
        ),
    ),
    (
        record("H08", "ee" * 32, "V", "shielded_to_external_t", {"shielded_owner": "A0"}),
        facts("ee" * 32, outputs=[io(0, ZEC, None)], orchard=ZEC + FEE, shielded=True),
    ),
    (
        record("H06", "ff" * 32, "V", "cross_account_from_shielded", {"shielded_owner": "A0"}),
        facts("ff" * 32, outputs=[io(0, ZEC, "A1")], orchard=ZEC + FEE, shielded=True),
    ),
    (
        record("H11", "11" * 32, "V", "gift_card_claim", {"shielded_net": {"A1": ZEC}}),
        facts("11" * 32, orchard=FEE, shielded=True),
    ),
    (
        record("H12", "22" * 32, "Z", "pending_receive"),
        facts(
            "22" * 32,
            outputs=[io(0, ZEC, "A0")],
            orchard=ZEC + FEE,
            shielded=True,
            status="mempool",
        ),
    ),
]

CASES = {
    "required_cases": ["H01", "H03", "H06", "H07", "H08", "H11", "H12", "H13"],
    "variant_kinds": {"N_pre": "pre_enrichment", "N_lag": "fault", "N_pir_fail": "fault"},
    "cases": {
        case: {"id": case, "checkpoints": {"final": ["R", "N", "O"]}}
        for case in ["H01", "H03", "H06", "H07", "H08", "H11", "H12"]
    }
    | {"H13": {"id": "H13", "checkpoints": {"final_pre": ["N_pre"], "h13_lag": ["N_lag"]}}},
    "txs": [r for r, _ in TXS],
}


def context(checkpoint="final"):
    all_facts = {r["txid"]: f for r, f in TXS}
    effects = {
        f"{r['txid']}:{account}": oracle.account_effect(all_facts[r["txid"]], account, r["attribution"])
        for r, _ in TXS
        for account in ("A0", "A1")
    }
    return {
        "checkpoint": checkpoint,
        "cases": CASES,
        "facts": all_facts,
        "effects": effects,
        "accounts": {},
        "alice_accounts": ["A0", "A1"],
    }


def item(items, txid, account, variant):
    found = [
        i
        for i in items
        if i["txid"] == txid and i["account"] == account and i["variant"] == variant
    ]
    assert len(found) == 1, (txid[:4], account, variant, len(found))
    return found[0]


def names(entry):
    return {c["name"]: c for c in entry["constraints"]}


class PrivateActivity(unittest.TestCase):
    def setUp(self):
        self.context = context()
        self.public = public.activity(self.context)
        self.private = private.activity(self.context)

    def test_transparent_receives_stay_exact(self):
        for variant in ("R", "N"):
            self.assertEqual(
                item(self.private, "aa" * 32, "A0", variant),
                item(self.public, "aa" * 32, "A0", variant),
            )

    def test_a_fully_owned_transparent_send_keeps_exact_amount_and_fee(self):
        for variant in ("R", "N", "O"):
            got = item(self.private, "bb" * 32, "A0", variant)
            want = item(self.public, "bb" * 32, "A0", variant)
            (row,) = got["row_sets"][0]
            self.assertFalse(row["details_complete"])
            self.assertNotIn("provisional", row)
            for field in ("tx_kind", "display_amount", "fee", "fee_state", "account_balance_delta"):
                self.assertEqual(row[field], want["row_sets"][0][0][field])
            self.assertEqual(row["display_amount"], ZEC)
            self.assertEqual(row["fee"], FEE)

    def test_the_reference_wallet_keeps_what_it_built(self):
        for variant in ("R", "O"):
            self.assertEqual(
                item(self.private, "dd" * 32, "A0", variant),
                item(self.public, "dd" * 32, "A0", variant),
            )

    def test_a_restored_shield_is_honestly_incomplete_with_a_known_fee(self):
        got = item(self.private, "dd" * 32, "A0", "N")
        self.assertIsNone(got["row_sets"])
        constraints = names(got)
        self.assertEqual(constraints["fee_state_in"]["values"], ["known"])
        self.assertEqual(constraints["delta_is"]["values"], [-FEE])
        self.assertEqual(constraints["known_fee_is_whole"]["values"], [FEE])
        self.assertIn("row_present", constraints)
        self.assertIn(2 * ZEC - FEE, constraints["amount_in_or_le"]["values"])
        self.assertEqual(constraints["amount_in_or_le"]["value"], FEE)
        finals = constraints["honest_if_final"]["final_rows"]
        self.assertEqual([r["tx_kind"] for r in finals], ["shielded"])

    def test_a_shielded_only_spend_has_an_unknown_fee(self):
        constraints = names(item(self.private, "ee" * 32, "A0", "N"))
        self.assertEqual(constraints["fee_state_in"]["values"], ["unknown"])
        self.assertEqual(constraints["delta_is"]["values"], [-(ZEC + FEE)])

    def test_another_accounts_receive_may_supply_the_fee(self):
        constraints = names(item(self.private, "ff" * 32, "A0", "N"))
        self.assertEqual(constraints["fee_state_in"]["values"], ["known", "unknown"])
        # The receiving account's row is an exact transparent receive.
        self.assertEqual(
            item(self.private, "ff" * 32, "A1", "N"), item(self.public, "ff" * 32, "A1", "N")
        )

    def test_a_self_transfer_infers_no_gross_payment(self):
        constraints = names(item(self.private, "cc" * 32, "A0", "N"))
        self.assertEqual(constraints["delta_is"]["values"], [-FEE])
        self.assertNotIn(2 * ZEC, constraints["amount_in_or_le"]["values"])
        self.assertIn(ZEC, constraints["amount_in_or_le"]["values"])

    def test_the_gift_card_claim_was_not_built_by_the_reference_wallet(self):
        got = item(self.private, "11" * 32, "A1", "R")
        self.assertIsNone(got["row_sets"])
        self.assertNotIn("fee_state_in", names(got))

    def test_unmined_and_incomplete_variants_keep_the_public_constraints(self):
        self.assertEqual(
            item(self.private, "22" * 32, "A0", "N"), item(self.public, "22" * 32, "A0", "N")
        )
        pre = context("final_pre")
        got, want = private.activity(pre), public.activity(pre)
        self.assertTrue(got)
        self.assertEqual(got, want)


class PrivatePolicy(unittest.TestCase):
    def test_no_public_lookup_is_allowed(self):
        policy = private.request_policy(context(), ["t-a0"], ["aa" * 32])
        self.assertNotIn("GetTransaction", policy["allowed_methods"])
        for method in policy["address_methods"]:
            self.assertNotIn(method, policy["allowed_methods"])
        self.assertEqual(policy["allowed_addresses"], [])
        self.assertEqual(policy["allowed_txids"], [])
        self.assertEqual(policy["send_txids"]["R"], sorted(["dd" * 32, "ee" * 32, "ff" * 32, "11" * 32]))

    def test_faults_assert_no_spendable_claim_only(self):
        checks = private.account_checks(context("h13_lag"))
        self.assertTrue(checks)
        for check in checks:
            self.assertEqual(check["assert"], ["no_spendable_claim"])

    def test_a_public_lookup_fails_the_comparison(self):
        ctx = context()
        expected = {
            "checkpoint": "final",
            "cases": CASES["cases"],
            "tx_case": {r["txid"]: r["case"] for r in CASES["txs"]},
            "activity": [],
            "account_checks": [],
            "accounts": {},
            "requests": private.request_policy(ctx, ["t-a0"], ["aa" * 32]),
        }
        observed = {
            "views": [],
            "requests": {
                "N": [
                    {"method": "GetBlockRange", "subjects": [], "fault": None},
                    {"method": "GetTransaction", "subjects": ["aa" * 32, "aa" * 32], "fault": None},
                    {"method": "GetTaddressTxids", "subjects": ["t-a0"], "fault": None},
                ]
            },
        }
        _, suite, _ = oracle.compare_views(expected, observed)
        self.assertEqual(
            suite,
            [
                "requests N: method GetTransaction outside the profile",
                "requests N: method GetTaddressTxids outside the profile",
            ],
        )

    def test_there_are_no_app_layer_expectations(self):
        with self.assertRaises(SystemExit):
            private.ui_rows(context())


class AmountConstraint(unittest.TestCase):
    def problems(self, amount):
        entry = {
            "txid": "cc" * 32,
            "fee": FEE,
            "constraints": [{"name": "amount_in_or_le", "values": [ZEC], "value": FEE}],
        }
        row = {"display_amount": amount}
        return oracle.check_constraints(entry, [row], {"ledger": []}, {})

    def test_a_real_amount_or_at_most_the_movement_passes(self):
        self.assertEqual(self.problems(ZEC), [])
        self.assertEqual(self.problems(FEE), [])
        self.assertEqual(self.problems(0), [])

    def test_an_invented_amount_fails(self):
        self.assertEqual(len(self.problems(2 * ZEC)), 1)


class GateStatusTest(unittest.TestCase):
    def test_a_checkpoint_named_fail_does_not_fail_the_case(self):
        cells = {"N_cut": ["h13_cut:pass"], "N_utxo_fail": ["h13_utxo_fail:pass"]}
        self.assertEqual(oracle.cells_status(cells), "pass")

    def test_a_failed_checkpoint_fails_the_case(self):
        cells = {"R": ["pending:pass", "final:fail"]}
        self.assertEqual(oracle.cells_status(cells), "fail")
        self.assertEqual(oracle.cells_status({}), "not run")


PAYEE = "tmPayee"
OWN = "uregtest1own"


def detail_row(kind, outputs):
    return {
        "tx_kind": kind,
        "detail": {"outputs": [[address, amount, "transparent"] for address, amount in outputs]},
    }


def detail_outputs_real(rows, real):
    item = {"constraints": [{"name": "detail_outputs_real", "outputs": real}]}
    return oracle.check_constraints(item, rows, {}, {})


class DetailOutputsRealTest(unittest.TestCase):
    """V9: only a sent row's detail lists payments to others."""

    REAL = [[PAYEE, 130_000_000]]

    def test_a_received_row_may_list_the_accounts_own_receipt(self):
        rows = [
            detail_row("sent", [(PAYEE, 130_000_000)]),
            detail_row("received", [(OWN, 70_000_000)]),
        ]
        self.assertEqual(detail_outputs_real(rows, self.REAL), [])

    def test_a_sent_row_listing_an_invented_output_fails(self):
        rows = [detail_row("sent", [(PAYEE, 130_000_000), (OWN, 70_000_000)])]
        problems = detail_outputs_real(rows, self.REAL)
        self.assertEqual(len(problems), 1)
        self.assertIn("70000000 is not a real output", problems[0])


MINED = {"txid": "aa", "index": 0, "value": 70_000_000, "spent_by": None}
REORGED = {"txid": "bb", "index": 0, "value": 99_990_000}


def ledger_entry(txid, index, value, mined_height, spenders=()):
    return {
        "txid": txid,
        "index": index,
        "value": value,
        "receive_mined_height": mined_height,
        "mined_spenders": [],
        "all_spenders": list(spenders),
    }


def account(mempool_receives=(), mempool_spends=()):
    return {
        "ledger": [MINED],
        "utxos": [MINED],
        "transparent_balance": MINED["value"],
        "mempool": {"receives": list(mempool_receives), "spends": list(mempool_spends)},
    }


def balance_problems(exp, view_ledger, transparent):
    check = {"variant": "R", "account": "A0", "assert": ["balance"], "authority": ["current"]}
    expected = {"accounts": {"A0": exp}}
    view = {
        "ledger": view_ledger,
        "balance": {"transparent": transparent, "transparent_authority": "current"},
    }
    return oracle.account_problems(check, view, expected, {}, [])


class MempoolAwareBalanceTest(unittest.TestCase):
    """Gap 5b: expected pending state comes from the chain plus the mempool."""

    def test_a_recorded_receive_still_in_the_mempool_counts(self):
        # H12 R: a receive reorged out of the chain is back in the mempool,
        # unmined and unexpired; the wallet that saw it mined still counts it.
        exp = account(mempool_receives=[REORGED])
        ledger = [ledger_entry("aa", 0, 70_000_000, 200), ledger_entry("bb", 0, 99_990_000, None)]
        self.assertEqual(balance_problems(exp, ledger, 169_990_000), [])

    def test_an_unmined_receive_the_mempool_lacks_does_not_count(self):
        exp = account()
        ledger = [ledger_entry("aa", 0, 70_000_000, 200), ledger_entry("bb", 0, 99_990_000, None)]
        problems = balance_problems(exp, ledger, 169_990_000)
        self.assertEqual(len(problems), 1)
        self.assertIn("!= chain and mempool 70000000", problems[0][0])

    def test_a_pending_receive_the_wallet_never_saw_is_not_required(self):
        exp = account(mempool_receives=[REORGED])
        ledger = [ledger_entry("aa", 0, 70_000_000, 200)]
        self.assertEqual(balance_problems(exp, ledger, 70_000_000), [])

    def test_a_recorded_mempool_spend_removes_the_mined_output(self):
        exp = account(mempool_spends=[{"txid": "aa", "index": 0, "spent_by": "cc"}])
        ledger = [ledger_entry("aa", 0, 70_000_000, 200, spenders=["cc"])]
        self.assertEqual(balance_problems(exp, ledger, 0), [])
        self.assertEqual(len(balance_problems(exp, ledger, 70_000_000)), 1)

    def test_an_overstated_balance_still_fails(self):
        # Gap 5a stays visible: an output a mined conflicting spend consumed
        # is not balance, mempool or not.
        exp = account(mempool_receives=[REORGED])
        ledger = [ledger_entry("aa", 0, 70_000_000, 200), ledger_entry("bb", 0, 99_990_000, None)]
        self.assertEqual(len(balance_problems(exp, ledger, 279_990_000)), 1)


if __name__ == "__main__":
    unittest.main()
