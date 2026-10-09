"""Run one exact ignored Rust test against its original case-local Zakura owner."""
from __future__ import annotations

import os
import re
import threading
import time

import e2e_runtime as runtime
from funder_build import ProducedRegtestFunder
from native_rust_case_storage import RustCaseStorage
from native_worker_lifecycle import NativeWorkerCase


RUST_CASES = {
    "rust.receive.sync": ("regtest_receive_sync", "create_wallet_receives_funds_and_syncs_balance"),
    "rust.send.basic": ("regtest_send", "funded_wallet_can_send_to_second_wallet"),
    "rust.send.second-account": ("regtest_send", "imported_second_account_can_send_using_its_own_seed"),
    "rust.import.bip39-passphrase": ("regtest_import", "bip39_passphrase_import_recovers_funds_sent_to_independently_derived_address"),
    "rust.import.historical-birthday": ("regtest_import", "import_wallet_with_historical_birthday_recovers_existing_funds"),
    "rust.import.future-birthday": ("regtest_import", "import_wallet_with_future_birthday_does_not_rescan_old_receive"),
    "rust.import.receive-after-sync": ("regtest_import", "import_wallet_then_receive_new_funds_after_sync_updates_correctly"),
    "rust.import.deterministic-reimport": ("regtest_import", "same_mnemonic_imported_into_fresh_db_matches_original_ua_and_balance"),
    "rust.multi-account.orphaned-range": ("regtest_multi_account", "sync_start_rescues_wallet_stuck_by_orphaned_historical_scan_range"),
    "rust.multi-account.deleted-range": ("regtest_multi_account", "sync_completes_when_deleted_account_left_scanned_range_below_birthday"),
    "rust.multi-account.late-add-history-future": ("regtest_multi_account", "adding_second_account_after_tip_sync_recovers_historical_and_future_funds"),
    "rust.multi-account.tip-birthday-history": ("regtest_multi_account", "late_added_account_with_tip_birthday_still_recovers_historical_funds"),
    "rust.multi-account.two-before-sync": ("regtest_multi_account", "two_new_accounts_added_before_single_sync_are_both_recovered"),
    "rust.multi-account.preserve-history": ("regtest_multi_account", "existing_account_history_is_unchanged_when_new_account_is_added"),
    "rust.multi-account.isolated-balances": ("regtest_multi_account", "multi_account_sync_keeps_balances_isolated_per_account"),
    "rust.multi-account.idempotent-sync": ("regtest_multi_account", "repeated_sync_is_idempotent_for_multi_account_wallet"),
}


def verify_test_output(lines, test):
    """Exit 0 with zero tests, an ignored test or a different test is not PASS."""
    output = "".join(lines)
    if (len(re.findall(r"^running 1 test$", output, re.MULTILINE)) != 1
        or len(re.findall(r"^test " + re.escape(test) + r" \.\.\. ok$", output, re.MULTILINE)) != 1
        or len(re.findall(r"^test result: ok\. 1 passed; 0 failed; 0 ignored; 0 measured; [0-9]+ filtered out; finished in [0-9.]+s$",
                          output, re.MULTILINE)) != 1):
        raise runtime.RunnerError("original Rust child did not prove the exact selected test passed")


def execute_native_rust_case(session, *, artifact, scenario, cancel_event=None):
    if (not isinstance(session, NativeWorkerCase) or not isinstance(session.storage, RustCaseStorage)
        or not isinstance(artifact, ProducedRegtestFunder) or session._finished
        or session._front is None or session._control is None
        or RUST_CASES.get(scenario.id) != (scenario.target, scenario.test)
        or scenario.profile != "zakura-direct-height1"):
        raise runtime.RunnerError("expected an original prepared Rust case and built exact test")
    session.verify_owned()
    session.storage.verify_owned()
    binary = artifact.test_binary(scenario.target)
    cancel = cancel_event if cancel_event is not None else threading.Event()
    deadline = time.monotonic() + scenario.timeout_seconds
    if cancel.is_set():
        raise runtime.Cancelled()
    lines = []
    process = session.case.start_process([str(binary), scenario.test, "--exact", "--ignored",
        "--show-output", "--test-threads=1", "--color", "never"],
        env={**os.environ, "VIZOR_E2E_RUST_TEMP_ROOT": str(session.storage.path)},
        raw_lines=lines, max_output_bytes=8*1024*1024)
    while process.process.poll() is None:
        if cancel.is_set():
            raise runtime.Cancelled()
        if time.monotonic() >= deadline:
            raise runtime.RunnerError("original Rust E2E deadline expired", 124)
        session.verify_owned()
        session.storage.verify_owned()
        session._front.assert_running()
        session._control.pump(deadline=deadline, cancel_event=cancel)
    code = session.case.wait_process(process, timeout=max(0.001, deadline-time.monotonic()), cancel_event=cancel)
    if code != 0:
        raise runtime.RunnerError("original Rust test reported failing assertions", code)
    verify_test_output(lines, scenario.test)
    artifact.verify_unchanged()
    session._front.assert_running()
    return {"scenario_id": scenario.id, "namespace": session.case.workspace.namespace,
            "test_pid": process.process.pid, "test_exit_code": code,
            "assertions_passed": True, "wallet_cleanup_pending": True}
