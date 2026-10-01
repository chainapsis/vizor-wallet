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


if __name__ == "__main__":
    unittest.main()
