#!/usr/bin/env python3
"""Unit tests for the transparent history suite's oracle.

Run: python3 -m unittest scripts/e2e/test_transparent_history_oracle.py
"""
import importlib.util
import unittest
from pathlib import Path

ORACLE_PATH = Path(__file__).with_name("transparent_history_oracle.py")
SPEC = importlib.util.spec_from_file_location("transparent_history_oracle", ORACLE_PATH)
assert SPEC is not None and SPEC.loader is not None
ORACLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ORACLE)

PAYEE = "tmPayee"
OWN = "uregtest1own"


def row(kind, outputs):
    return {
        "tx_kind": kind,
        "detail": {"outputs": [[address, amount, "transparent"] for address, amount in outputs]},
    }


def detail_outputs_real(rows, real):
    item = {"constraints": [{"name": "detail_outputs_real", "outputs": real}]}
    return ORACLE.check_constraints(item, rows, {}, {})


class DetailOutputsRealTest(unittest.TestCase):
    """V9: only a sent row's detail lists payments to others."""

    REAL = [[PAYEE, 130_000_000]]

    def test_a_received_row_may_list_the_accounts_own_receipt(self):
        rows = [row("sent", [(PAYEE, 130_000_000)]), row("received", [(OWN, 70_000_000)])]
        self.assertEqual(detail_outputs_real(rows, self.REAL), [])

    def test_a_sent_row_listing_an_invented_output_fails(self):
        rows = [row("sent", [(PAYEE, 130_000_000), (OWN, 70_000_000)])]
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
    return ORACLE.account_problems(check, view, expected, {}, [])


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
